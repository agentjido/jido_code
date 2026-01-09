defmodule JidoCode.Extensibility.Permissions do
  @moduledoc """
  Permission configuration for extensibility components.

  Permission matching follows glob patterns with three outcomes:
  - `:allow` - Permit the action
  - `:deny` - Block the action (highest priority)
  - `:ask` - Prompt user for approval

  ## Fields

  - `:allow` - List of allowed patterns (lowest priority)
  - `:deny` - List of denied patterns (highest priority)
  - `:ask` - List of patterns requiring user confirmation (medium priority)
  - `:default_mode` - Default permission mode when no patterns match (:allow or :deny)

  ## Permission Format

  Permissions use a `category:action` format:
  - `*` - Matches everything
  - `Edit:*` - Matches all Edit tool operations
  - `run_command:git*` - Matches git commands
  - `*:delete` - Matches delete operations in any category

  ## Priority Order

  Patterns are evaluated in the following order:
  1. **deny** (highest) - Block if any deny pattern matches
  2. **ask** - Prompt if any ask pattern matches
  3. **allow** - Permit if any allow pattern matches
  4. **default** - Use `default_mode` (:deny for security, :allow for compatibility)

  ## Default Mode

  The `default_mode` field controls behavior when no patterns match:
  - `:deny` - Secure by default (recommended for production)
  - `:allow` - Permissive by default (for backward compatibility)

  ## Examples

      iex> perms = %JidoCode.Extensibility.Permissions{allow: ["Read:*", "Write:*"], deny: ["*delete*"], default_mode: :deny}
      iex> JidoCode.Extensibility.Permissions.check_permission(perms, "Read", "file.txt")
      :allow

      iex> perms = %JidoCode.Extensibility.Permissions{deny: ["*delete*"], default_mode: :deny}
      iex> JidoCode.Extensibility.Permissions.check_permission(perms, "Edit", "delete_file")
      :deny

      iex> perms = %JidoCode.Extensibility.Permissions{ask: ["run_command:*"], default_mode: :deny}
      iex> JidoCode.Extensibility.Permissions.check_permission(perms, "run_command", "make")
      :ask

      iex> perms = %JidoCode.Extensibility.Permissions{default_mode: :deny}
      iex> JidoCode.Extensibility.Permissions.check_permission(perms, "Any", "action")
      :deny

  ## Glob Patterns

  The system uses Unix-style glob patterns:
  - `*` - Matches any sequence of characters
  - `?` - Matches any single character

  """

  alias JidoCode.Extensibility.Error

  # Module attributes for validation constants
  @valid_default_modes [:allow, :deny]

  defstruct allow: [], deny: [], ask: [], default_mode: :deny

  @typedoc """
  Permission struct with pattern lists and default mode.

  ## Fields

  - `:allow` - List of allowed patterns (lowest priority)
  - `:deny` - List of denied patterns (highest priority)
  - `:ask` - List of patterns requiring user confirmation (medium priority)
  - `:default_mode` - Default behavior when no patterns match (:allow or :deny)
  """
  @type t :: %__MODULE__{
          allow: [String.t()],
          deny: [String.t()],
          ask: [String.t()],
          default_mode: default_mode()
        }

  @typedoc """
  Permission decision: :allow | :deny | :ask
  """
  @type decision :: :allow | :deny | :ask

  @typedoc """
  Permission default mode: :allow | :deny
  """
  @type default_mode :: :allow | :deny

  @typedoc """
  Permission category (e.g., "Read", "Edit", "run_command")
  """
  @type category :: String.t() | atom()

  @typedoc """
  Permission action (e.g., "file.txt", "delete", "make")
  """
  @type action :: String.t() | atom()

  @doc """
  Checks if a permission is granted based on configured patterns.

  Patterns are evaluated in priority order: deny > ask > allow > default_mode

  ## Parameters

  - `permissions` - The Permissions struct to check against
  - `category` - The category of the action (e.g., "Read", "Edit", "run_command")
  - `action` - The specific action to check (e.g., "file.txt", "delete", "make")

  ## Returns

  - `:allow` - The action is permitted
  - `:deny` - The action is blocked
  - `:ask` - User confirmation is required

  ## Examples

      iex> perms = %JidoCode.Extensibility.Permissions{allow: ["Read:*"], deny: ["*delete*"], default_mode: :deny}
      iex> JidoCode.Extensibility.Permissions.check_permission(perms, "Read", "file.txt")
      :allow

      iex> perms = %JidoCode.Extensibility.Permissions{deny: ["*delete*"], default_mode: :deny}
      iex> JidoCode.Extensibility.Permissions.check_permission(perms, "Edit", "delete_file")
      :deny

      iex> perms = %JidoCode.Extensibility.Permissions{ask: ["run_command:*"], default_mode: :deny}
      iex> JidoCode.Extensibility.Permissions.check_permission(perms, "run_command", "make")
      :ask

      iex> perms = %JidoCode.Extensibility.Permissions{default_mode: :deny}
      iex> JidoCode.Extensibility.Permissions.check_permission(perms, "Any", "action")
      :deny

  """
  @spec check_permission(t(), category(), action()) :: decision()
  def check_permission(%__MODULE__{} = permissions, category, action) do
    target = format_target(category, action)

    cond do
      matches_any?(target, permissions.deny) ->
        :deny

      matches_any?(target, permissions.ask) ->
        :ask

      matches_any?(target, permissions.allow) ->
        :allow

      # Default: use configured default_mode (deny for security)
      true ->
        permissions.default_mode
    end
  end

  @doc """
  Parses a permissions configuration from a JSON-like map.

  ## Parameters

  - `json` - Map with string keys containing "allow", "deny", "ask", "default_mode"

  ## Returns

  - `{:ok, %Permissions{}}` - Successfully parsed
  - `{:error, %Error{}}` - Validation failed with structured error

  ## Examples

      iex> JidoCode.Extensibility.Permissions.from_json(%{"allow" => ["Read:*"], "deny" => ["*delete*"]})
      {:ok, %JidoCode.Extensibility.Permissions{allow: ["Read:*"], deny: ["*delete*"], ask: [], default_mode: :deny}}

      iex> JidoCode.Extensibility.Permissions.from_json(%{"allow" => ["Read:*"], "ask" => ["run_command:*"]})
      {:ok, %JidoCode.Extensibility.Permissions{allow: ["Read:*"], deny: [], ask: ["run_command:*"], default_mode: :deny}}

      iex> JidoCode.Extensibility.Permissions.from_json(%{"allow" => "not_a_list"})
      {:error, %JidoCode.Extensibility.Error{code: :field_list_invalid, message: "allow must be a list of strings", details: %{field: "allow"}}}

      iex> JidoCode.Extensibility.Permissions.from_json(%{"allow" => [123]})
      {:error, %JidoCode.Extensibility.Error{code: :pattern_invalid, message: "allow patterns must be non-empty strings", details: %{reason: "allow patterns must be non-empty strings"}}}

      iex> JidoCode.Extensibility.Permissions.from_json(%{"default_mode" => "deny"})
      {:ok, %JidoCode.Extensibility.Permissions{allow: [], deny: [], ask: [], default_mode: :deny}}

  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Error.t()}
  def from_json(json) when is_map(json) do
    with :ok <- validate_field_list(json, "allow"),
         :ok <- validate_field_list(json, "deny"),
         :ok <- validate_field_list(json, "ask"),
         :ok <- validate_patterns(json, "allow"),
         :ok <- validate_patterns(json, "deny"),
         :ok <- validate_patterns(json, "ask"),
         {:ok, default_mode} <- parse_default_mode(json) do
      permissions = %__MODULE__{
        allow: Map.get(json, "allow", []),
        deny: Map.get(json, "deny", []),
        ask: Map.get(json, "ask", []),
        default_mode: default_mode
      }

      {:ok, permissions}
    end
  end

  @doc """
  Returns default safe permission configuration.

  The defaults follow a secure-by-default approach:
  - **default_mode**: `:deny` (secure by default)
  - **Allow**: Common safe tools (Read, Write, Edit, ListDirectory, Grep)
  - **Allow**: Safe version control commands (git, mix)
  - **Deny**: Dangerous operations (delete, remove, shutdown, format)
  - **Ask**: Potentially risky operations (run_command, web_fetch, web_search)

  ## Examples

      iex> perms = JidoCode.Extensibility.Permissions.defaults()
      iex> perms.allow |> Enum.member?("Read:*")
      true

      iex> perms = JidoCode.Extensibility.Permissions.defaults()
      iex> perms.deny |> Enum.member?("*delete*")
      true

      iex> perms = JidoCode.Extensibility.Permissions.defaults()
      iex> perms.ask |> Enum.member?("web_fetch:*")
      true

      iex> perms = JidoCode.Extensibility.Permissions.defaults()
      iex> perms.default_mode
      :deny

  """
  @spec defaults() :: t()
  def defaults do
    %__MODULE__{
      allow: [
        # Common file operations (safe)
        "Read:*",
        "Write:*",
        "Edit:*",
        "ListDirectory:*",
        "FileInfo:*",
        "Grep:*",
        "FindFiles:*",
        # Safe version control (allow git and mix commands)
        "run_command:git*",
        "run_command:mix*",
        # Livebook operations
        "livebook_edit:*",
        # Todo list management
        "todo_write:*"
      ],
      deny: [
        # Dangerous deletion operations
        "*delete*",
        "*remove*",
        "*rm *",
        "*rmdir*",
        # System destruction
        "*shutdown*",
        "*reboot*",
        "*poweroff*",
        # Disk operations
        "*format*",
        "*mkfs*",
        # Network manipulation
        "*iptables*",
        "*ifconfig*",
        # User management
        "*useradd*",
        "*userdel*",
        "*passwd*"
      ],
      ask: [
        # Web operations
        "web_fetch:*",
        "web_search:*",
        # Task spawning
        "spawn_task:*",
        # File creation in system directories
        "Write:/etc/*",
        "Write:/usr/*",
        "Write:/bin/*",
        "Write:/sbin/*"
      ],
      default_mode: :deny
    }
  end

  # Private Functions

  @doc false
  @spec format_target(category(), action()) :: String.t()
  defp format_target(category, action) do
    cat = to_string(category)
    act = to_string(action)
    "#{cat}:#{act}"
  end

  @doc false
  @spec matches_any?(String.t(), [String.t()]) :: boolean()
  defp matches_any?(_target, []), do: false
  defp matches_any?(_target, nil), do: false

  defp matches_any?(target, [pattern | rest]) do
    case glob_match?(target, pattern) do
      true -> true
      false -> matches_any?(target, rest)
    end
  end

  @doc false
  # Simple glob pattern matching with regex compilation error handling
  # Supports: * (matches any sequence), ? (matches single char)
  # For permission patterns, we mostly need * wildcard matching
  @spec glob_match?(String.t(), String.t()) :: boolean()
  defp glob_match?(target, pattern) when is_binary(target) and is_binary(pattern) do
    # Convert glob pattern to regex
    regex_pattern =
      pattern
      # Escape special regex characters first (except * and ?)
      |> String.replace(~r/([.|\(\)\[\]{}^$+\\])/, "\\\\\\1")
      # Convert glob wildcards to regex
      |> String.replace("*", ".*")
      |> String.replace("?", ".")
      # Anchor the pattern
      |> then(fn p -> "^" <> p <> "$" end)

    case Regex.compile(regex_pattern) do
      {:ok, regex} ->
        Regex.match?(regex, target)

      {:error, reason} ->
        # Log the invalid pattern but don't crash
        require Logger
        Logger.warning(
          "Invalid permission pattern: #{pattern} - #{inspect(reason)}. Returning false for match."
        )

        false
    end
  end

  @doc false
  @spec validate_field_list(map(), String.t()) :: :ok | {:error, Error.t()}
  defp validate_field_list(json, key) do
    value = Map.get(json, key)

    case value do
      nil -> :ok
      list when is_list(list) -> :ok
      _ -> {:error, Error.field_list_invalid(key)}
    end
  end

  @doc false
  @spec validate_patterns(map(), String.t()) :: :ok | {:error, Error.t()}
  defp validate_patterns(json, key) do
    list = Map.get(json, key, [])

    case validate_patterns_list(list, key) do
      :ok -> :ok
      {:error, _} = error -> error
    end
  end

  @doc false
  @spec validate_patterns_list([String.t()], String.t()) :: :ok | {:error, Error.t()}
  defp validate_patterns_list([], _key), do: :ok

  defp validate_patterns_list([pattern | rest], key) when is_binary(pattern) do
    if String.trim(pattern) == "" do
      {:error, Error.pattern_invalid("#{key} patterns must be non-empty strings")}
    else
      validate_patterns_list(rest, key)
    end
  end

  defp validate_patterns_list([_ | _], key) do
    {:error, Error.pattern_invalid("#{key} patterns must be non-empty strings")}
  end

  @doc false
  @spec parse_default_mode(map()) :: {:ok, default_mode()} | {:error, Error.t()}
  defp parse_default_mode(json) do
    case Map.get(json, "default_mode") do
      nil ->
        # Default to :deny for security
        {:ok, :deny}

      mode when is_binary(mode) ->
        case String.to_existing_atom(mode) do
          atom when atom in @valid_default_modes -> {:ok, atom}
          _ -> {:error, Error.permissions_invalid("default_mode must be one of: allow, deny")}
        end

      mode when is_atom(mode) ->
        if mode in @valid_default_modes do
          {:ok, mode}
        else
          {:error, Error.permissions_invalid("default_mode must be one of: allow, deny")}
        end

      _ ->
        {:error, Error.permissions_invalid("default_mode must be one of: allow, deny")}
    end
  end
end
