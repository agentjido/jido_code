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
  4. **default** - Allow if no patterns match (fail-open for compatibility)

  ## Examples

      iex> perms = %JidoCode.Extensibility.Permissions{allow: ["Read:*", "Write:*"], deny: ["*delete*"]}
      iex> JidoCode.Extensibility.Permissions.check_permission(perms, "Read", "file.txt")
      :allow

      iex> perms = %JidoCode.Extensibility.Permissions{deny: ["*delete*"]}
      iex> JidoCode.Extensibility.Permissions.check_permission(perms, "Edit", "delete_file")
      :deny

      iex> perms = %JidoCode.Extensibility.Permissions{ask: ["run_command:*"]}
      iex> JidoCode.Extensibility.Permissions.check_permission(perms, "run_command", "make")
      :ask

  ## Glob Patterns

  The system uses Unix-style glob patterns:
  - `*` - Matches any sequence of characters
  - `?` - Matches any single character

  """

  defstruct allow: [], deny: [], ask: []

  @type t :: %__MODULE__{
          allow: [String.t()],
          deny: [String.t()],
          ask: [String.t()]
        }

  @type decision :: :allow | :deny | :ask

  @type category :: String.t() | atom()
  @type action :: String.t() | atom()

  @doc """
  Checks if a permission is granted based on configured patterns.

  Patterns are evaluated in priority order: deny > ask > allow > (default: allow)

  ## Parameters

  - `permissions` - The Permissions struct to check against
  - `category` - The category of the action (e.g., "Read", "Edit", "run_command")
  - `action` - The specific action to check (e.g., "file.txt", "delete", "make")

  ## Returns

  - `:allow` - The action is permitted
  - `:deny` - The action is blocked
  - `:ask` - User confirmation is required

  ## Examples

      iex> perms = %JidoCode.Extensibility.Permissions{allow: ["Read:*"], deny: ["*delete*"]}
      iex> JidoCode.Extensibility.Permissions.check_permission(perms, "Read", "file.txt")
      :allow

      iex> perms = %JidoCode.Extensibility.Permissions{deny: ["*delete*"]}
      iex> JidoCode.Extensibility.Permissions.check_permission(perms, "Edit", "delete_file")
      :deny

      iex> perms = %JidoCode.Extensibility.Permissions{ask: ["run_command:*"]}
      iex> JidoCode.Extensibility.Permissions.check_permission(perms, "run_command", "make")
      :ask

      iex> perms = %JidoCode.Extensibility.Permissions{}
      iex> JidoCode.Extensibility.Permissions.check_permission(perms, "Any", "action")
      :allow

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

      # Default: allow (fail-open for backward compatibility)
      true ->
        :allow
    end
  end

  @doc """
  Parses a permissions configuration from a JSON-like map.

  ## Parameters

  - `json` - Map with string keys containing "allow", "deny", "ask" arrays

  ## Returns

  - `{:ok, %Permissions{}}` - Successfully parsed
  - `{:error, reason}` - Validation failed

  ## Examples

      iex> JidoCode.Extensibility.Permissions.from_json(%{"allow" => ["Read:*"], "deny" => ["*delete*"]})
      {:ok, %JidoCode.Extensibility.Permissions{allow: ["Read:*"], deny: ["*delete*"], ask: []}}

      iex> JidoCode.Extensibility.Permissions.from_json(%{"allow" => ["Read:*"], "ask" => ["run_command:*"]})
      {:ok, %JidoCode.Extensibility.Permissions{allow: ["Read:*"], deny: [], ask: ["run_command:*"]}}

      iex> JidoCode.Extensibility.Permissions.from_json(%{"allow" => "not_a_list"})
      {:error, "allow must be a list of strings"}

      iex> JidoCode.Extensibility.Permissions.from_json(%{"allow" => [123]})
      {:error, "permission patterns must be non-empty strings"}

  """
  @spec from_json(map()) :: {:ok, t()} | {:error, String.t()}
  def from_json(json) when is_map(json) do
    with :ok <- validate_field_list(json, "allow"),
         :ok <- validate_field_list(json, "deny"),
         :ok <- validate_field_list(json, "ask"),
         :ok <- validate_patterns(json, "allow"),
         :ok <- validate_patterns(json, "deny"),
         :ok <- validate_patterns(json, "ask") do
      permissions = %__MODULE__{
        allow: Map.get(json, "allow", []),
        deny: Map.get(json, "deny", []),
        ask: Map.get(json, "ask", [])
      }

      {:ok, permissions}
    end
  end

  @doc """
  Returns default safe permission configuration.

  The defaults follow a secure-by-default approach:
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
      ]
    }
  end

  # Private Functions

  @doc false
  defp format_target(category, action) do
    cat = to_string(category)
    act = to_string(action)
    "#{cat}:#{act}"
  end

  @doc false
  defp matches_any?(_target, []), do: false
  defp matches_any?(_target, nil), do: false

  defp matches_any?(target, [pattern | rest]) do
    case glob_match?(target, pattern) do
      true -> true
      false -> matches_any?(target, rest)
    end
  end

  @doc false
  # Simple glob pattern matching
  # Supports: * (matches any sequence), ? (matches single char)
  # For permission patterns, we mostly need * wildcard matching
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
      {:ok, regex} -> Regex.match?(regex, target)
      _error -> false
    end
  end

  @doc false
  defp validate_field_list(json, key) do
    value = Map.get(json, key)

    case value do
      nil -> :ok
      list when is_list(list) -> :ok
      _ -> {:error, "#{key} must be a list of strings"}
    end
  end

  @doc false
  defp validate_patterns(json, key) do
    list = Map.get(json, key, [])

    case validate_patterns_list(list) do
      :ok -> :ok
      {:error, _} = error -> error
    end
  end

  defp validate_patterns_list([]), do: :ok

  defp validate_patterns_list([pattern | rest]) when is_binary(pattern) do
    if String.trim(pattern) == "" do
      {:error, "#{key_from_context()} patterns must be non-empty strings"}
    else
      validate_patterns_list(rest)
    end
  end

  defp validate_patterns_list([_ | _]) do
    {:error, "#{key_from_context()} patterns must be non-empty strings"}
  end

  defp key_from_context do
    # This is a simplified version - in a real scenario we'd pass the key through
    "permission"
  end
end
