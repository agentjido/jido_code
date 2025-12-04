defmodule JidoCode.Session do
  @moduledoc """
  Represents a work session in JidoCode.

  A session encapsulates all context for working on a specific project:
  - Project directory and sandbox boundary
  - LLM configuration (provider, model, parameters)
  - Conversation history and task list (via Session.State)
  - Creation and update timestamps

  Sessions are managed by the SessionRegistry and supervised by SessionSupervisor.
  Each session runs in isolation with its own Manager process for security enforcement.

  ## Example

      iex> session = %JidoCode.Session{
      ...>   id: "550e8400-e29b-41d4-a716-446655440000",
      ...>   name: "my-project",
      ...>   project_path: "/home/user/projects/my-project",
      ...>   config: %{
      ...>     provider: "anthropic",
      ...>     model: "claude-3-5-sonnet-20241022",
      ...>     temperature: 0.7,
      ...>     max_tokens: 4096
      ...>   },
      ...>   created_at: ~U[2024-01-15 10:00:00Z],
      ...>   updated_at: ~U[2024-01-15 10:00:00Z]
      ...> }
      %JidoCode.Session{...}

  ## Fields

  - `id` - RFC 4122 UUID v4 uniquely identifying the session
  - `name` - Display name shown in tabs (defaults to folder name)
  - `project_path` - Absolute path to the project directory
  - `config` - LLM configuration map with provider, model, temperature, max_tokens
  - `created_at` - UTC timestamp when session was created
  - `updated_at` - UTC timestamp of last modification
  """

  @typedoc """
  LLM configuration for a session.

  - `provider` - Provider name (e.g., "anthropic", "openai", "ollama")
  - `model` - Model identifier (e.g., "claude-3-5-sonnet-20241022")
  - `temperature` - Sampling temperature (0.0 to 2.0)
  - `max_tokens` - Maximum tokens in response
  """
  @type config :: %{
          provider: String.t(),
          model: String.t(),
          temperature: float(),
          max_tokens: pos_integer()
        }

  @typedoc """
  A work session representing an isolated project context.
  """
  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          project_path: String.t(),
          config: config(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :name,
    :project_path,
    :config,
    :created_at,
    :updated_at
  ]

  # Default LLM configuration when Settings doesn't provide one
  @default_config %{
    provider: "anthropic",
    model: "claude-3-5-sonnet-20241022",
    temperature: 0.7,
    max_tokens: 4096
  }

  @doc """
  Creates a new session with the given options.

  ## Options

  - `:project_path` (required) - Absolute path to the project directory
  - `:name` (optional) - Display name for the session, defaults to folder name
  - `:config` (optional) - LLM configuration map, defaults to global settings

  ## Returns

  - `{:ok, session}` - Successfully created session
  - `{:error, :missing_project_path}` - project_path option not provided
  - `{:error, :path_not_found}` - project_path does not exist
  - `{:error, :path_not_directory}` - project_path is not a directory

  ## Examples

      iex> {:ok, session} = JidoCode.Session.new(project_path: "/home/user/my-project")
      iex> session.name
      "my-project"

      iex> {:ok, session} = JidoCode.Session.new(
      ...>   project_path: "/home/user/my-project",
      ...>   name: "Custom Name"
      ...> )
      iex> session.name
      "Custom Name"

      iex> JidoCode.Session.new(project_path: "/nonexistent/path")
      {:error, :path_not_found}
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, atom()}
  def new(opts) when is_list(opts) do
    with {:ok, project_path} <- fetch_project_path(opts),
         :ok <- validate_path_exists(project_path),
         :ok <- validate_path_is_directory(project_path) do
      now = DateTime.utc_now()

      session = %__MODULE__{
        id: generate_id(),
        name: opts[:name] || Path.basename(project_path),
        project_path: project_path,
        config: opts[:config] || load_default_config(),
        created_at: now,
        updated_at: now
      }

      {:ok, session}
    end
  end

  # Fetch and validate project_path from options
  defp fetch_project_path(opts) do
    case Keyword.fetch(opts, :project_path) do
      {:ok, path} when is_binary(path) -> {:ok, path}
      {:ok, _} -> {:error, :invalid_project_path}
      :error -> {:error, :missing_project_path}
    end
  end

  # Validate that the path exists
  defp validate_path_exists(path) do
    if File.exists?(path) do
      :ok
    else
      {:error, :path_not_found}
    end
  end

  # Validate that the path is a directory
  defp validate_path_is_directory(path) do
    if File.dir?(path) do
      :ok
    else
      {:error, :path_not_directory}
    end
  end

  # Load default config from Settings or use fallback defaults
  defp load_default_config do
    settings =
      case JidoCode.Settings.load() do
        {:ok, s} -> s
        _ -> %{}
      end

    %{
      provider: settings["provider"] || @default_config.provider,
      model: settings["model"] || @default_config.model,
      temperature: settings["temperature"] || @default_config.temperature,
      max_tokens: settings["max_tokens"] || @default_config.max_tokens
    }
  end

  @doc """
  Generates an RFC 4122 compliant UUID v4 (random).

  The UUID is generated using cryptographically secure random bytes with:
  - Version bits set to 4 (random UUID)
  - Variant bits set to 2 (RFC 4122)
  - Formatted as standard UUID string (8-4-4-4-12)

  ## Examples

      iex> id = JidoCode.Session.generate_id()
      iex> Regex.match?(~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/, id)
      true
  """
  @spec generate_id() :: String.t()
  def generate_id do
    <<u0::48, _::4, u1::12, _::2, u2::62>> = :crypto.strong_rand_bytes(16)

    <<u0::48, 4::4, u1::12, 2::2, u2::62>>
    |> Base.encode16(case: :lower)
    |> format_uuid()
  end

  # Format hex string as UUID (8-4-4-4-12)
  defp format_uuid(hex) do
    <<a::binary-8, b::binary-4, c::binary-4, d::binary-4, e::binary-12>> = hex
    "#{a}-#{b}-#{c}-#{d}-#{e}"
  end

  # Maximum allowed length for session name
  @max_name_length 50

  @doc """
  Validates a session struct, checking all fields for correctness.

  Returns `{:ok, session}` if all validations pass, or `{:error, reasons}`
  with a list of all validation failures.

  ## Validation Rules

  - `id` - Must be a non-empty string
  - `name` - Must be a non-empty string, max #{@max_name_length} characters
  - `project_path` - Must be an absolute path to an existing directory
  - `config.provider` - Must be a non-empty string
  - `config.model` - Must be a non-empty string
  - `config.temperature` - Must be a float between 0.0 and 2.0
  - `config.max_tokens` - Must be a positive integer
  - `created_at` - Must be a DateTime
  - `updated_at` - Must be a DateTime

  ## Examples

      iex> {:ok, session} = JidoCode.Session.new(project_path: "/tmp")
      iex> JidoCode.Session.validate(session)
      {:ok, session}

      iex> session = %JidoCode.Session{id: "", name: "test"}
      iex> {:error, reasons} = JidoCode.Session.validate(session)
      iex> :invalid_id in reasons
      true
  """
  @spec validate(t()) :: {:ok, t()} | {:error, [atom()]}
  def validate(%__MODULE__{} = session) do
    errors =
      []
      |> validate_id(session.id)
      |> validate_name(session.name)
      |> validate_session_project_path(session.project_path)
      |> validate_config(session.config)
      |> validate_timestamps(session.created_at, session.updated_at)

    case errors do
      [] -> {:ok, session}
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  # Validate id is a non-empty string
  defp validate_id(errors, id) when is_binary(id) and byte_size(id) > 0, do: errors
  defp validate_id(errors, _), do: [:invalid_id | errors]

  # Validate name is a non-empty string with max length
  defp validate_name(errors, name) when is_binary(name) and byte_size(name) > 0 do
    if String.length(name) <= @max_name_length do
      errors
    else
      [:name_too_long | errors]
    end
  end

  defp validate_name(errors, _), do: [:invalid_name | errors]

  # Validate project_path is absolute and exists as directory
  defp validate_session_project_path(errors, path) when is_binary(path) do
    cond do
      not String.starts_with?(path, "/") ->
        [:path_not_absolute | errors]

      not File.exists?(path) ->
        [:path_not_found | errors]

      not File.dir?(path) ->
        [:path_not_directory | errors]

      true ->
        errors
    end
  end

  defp validate_session_project_path(errors, _), do: [:invalid_project_path | errors]

  # Validate config map
  defp validate_config(errors, config) when is_map(config) do
    errors
    |> validate_provider(config[:provider] || config["provider"])
    |> validate_model(config[:model] || config["model"])
    |> validate_temperature(config[:temperature] || config["temperature"])
    |> validate_max_tokens(config[:max_tokens] || config["max_tokens"])
  end

  defp validate_config(errors, _), do: [:invalid_config | errors]

  # Validate provider is non-empty string
  defp validate_provider(errors, provider) when is_binary(provider) and byte_size(provider) > 0,
    do: errors

  defp validate_provider(errors, _), do: [:invalid_provider | errors]

  # Validate model is non-empty string
  defp validate_model(errors, model) when is_binary(model) and byte_size(model) > 0, do: errors
  defp validate_model(errors, _), do: [:invalid_model | errors]

  # Validate temperature is float between 0.0 and 2.0
  defp validate_temperature(errors, temp) when is_float(temp) and temp >= 0.0 and temp <= 2.0,
    do: errors

  defp validate_temperature(errors, temp) when is_integer(temp) and temp >= 0 and temp <= 2,
    do: errors

  defp validate_temperature(errors, _), do: [:invalid_temperature | errors]

  # Validate max_tokens is positive integer
  defp validate_max_tokens(errors, tokens) when is_integer(tokens) and tokens > 0, do: errors
  defp validate_max_tokens(errors, _), do: [:invalid_max_tokens | errors]

  # Validate timestamps are DateTime structs
  defp validate_timestamps(errors, %DateTime{}, %DateTime{}), do: errors

  defp validate_timestamps(errors, created_at, updated_at) do
    errors
    |> then(fn e -> if match?(%DateTime{}, created_at), do: e, else: [:invalid_created_at | e] end)
    |> then(fn e -> if match?(%DateTime{}, updated_at), do: e, else: [:invalid_updated_at | e] end)
  end

  @doc """
  Updates the LLM configuration for a session.

  Merges the new config values with the existing config, allowing partial updates.
  Only known config keys (provider, model, temperature, max_tokens) are merged.
  The `updated_at` timestamp is set to the current UTC time.

  ## Parameters

  - `session` - The session to update
  - `new_config` - A map with config values to merge (atom or string keys)

  ## Returns

  - `{:ok, updated_session}` - Successfully updated session
  - `{:error, :invalid_config}` - new_config is not a map
  - `{:error, :invalid_provider}` - provider is empty or not a string
  - `{:error, :invalid_model}` - model is empty or not a string
  - `{:error, :invalid_temperature}` - temperature not in range 0.0-2.0
  - `{:error, :invalid_max_tokens}` - max_tokens not a positive integer

  ## Examples

      iex> {:ok, session} = JidoCode.Session.new(project_path: "/tmp")
      iex> {:ok, updated} = JidoCode.Session.update_config(session, %{temperature: 0.5})
      iex> updated.config.temperature
      0.5

      iex> {:ok, session} = JidoCode.Session.new(project_path: "/tmp")
      iex> {:ok, updated} = JidoCode.Session.update_config(session, %{provider: "openai", model: "gpt-4"})
      iex> {updated.config.provider, updated.config.model}
      {"openai", "gpt-4"}
  """
  @spec update_config(t(), map()) :: {:ok, t()} | {:error, atom()}
  def update_config(%__MODULE__{} = session, new_config) when is_map(new_config) do
    merged_config = merge_config(session.config, new_config)

    case validate_config_only(merged_config) do
      :ok ->
        updated_session = %{session | config: merged_config, updated_at: DateTime.utc_now()}
        {:ok, updated_session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def update_config(%__MODULE__{}, _), do: {:error, :invalid_config}

  # Merge new config values with existing config, supporting both atom and string keys
  defp merge_config(existing, new_config) do
    %{
      provider: new_config[:provider] || new_config["provider"] || existing[:provider] || existing["provider"],
      model: new_config[:model] || new_config["model"] || existing[:model] || existing["model"],
      temperature: new_config[:temperature] || new_config["temperature"] || existing[:temperature] || existing["temperature"],
      max_tokens: new_config[:max_tokens] || new_config["max_tokens"] || existing[:max_tokens] || existing["max_tokens"]
    }
  end

  # Validate config and return first error (not accumulating like validate/1)
  defp validate_config_only(config) do
    cond do
      not valid_provider?(config[:provider]) -> {:error, :invalid_provider}
      not valid_model?(config[:model]) -> {:error, :invalid_model}
      not valid_temperature?(config[:temperature]) -> {:error, :invalid_temperature}
      not valid_max_tokens?(config[:max_tokens]) -> {:error, :invalid_max_tokens}
      true -> :ok
    end
  end

  defp valid_provider?(p), do: is_binary(p) and byte_size(p) > 0
  defp valid_model?(m), do: is_binary(m) and byte_size(m) > 0
  defp valid_temperature?(t), do: (is_float(t) and t >= 0.0 and t <= 2.0) or (is_integer(t) and t >= 0 and t <= 2)
  defp valid_max_tokens?(t), do: is_integer(t) and t > 0

  @doc """
  Renames a session.

  Updates the session name after validating the new name meets requirements.
  The `updated_at` timestamp is set to the current UTC time.

  ## Parameters

  - `session` - The session to rename
  - `new_name` - The new name for the session

  ## Returns

  - `{:ok, updated_session}` - Successfully renamed session
  - `{:error, :invalid_name}` - new_name is empty or not a string
  - `{:error, :name_too_long}` - new_name exceeds #{@max_name_length} characters

  ## Examples

      iex> {:ok, session} = JidoCode.Session.new(project_path: "/tmp")
      iex> {:ok, renamed} = JidoCode.Session.rename(session, "My Project")
      iex> renamed.name
      "My Project"

      iex> {:ok, session} = JidoCode.Session.new(project_path: "/tmp")
      iex> JidoCode.Session.rename(session, "")
      {:error, :invalid_name}
  """
  @spec rename(t(), String.t()) :: {:ok, t()} | {:error, atom()}
  def rename(%__MODULE__{} = session, new_name) when is_binary(new_name) do
    cond do
      byte_size(new_name) == 0 ->
        {:error, :invalid_name}

      String.length(new_name) > @max_name_length ->
        {:error, :name_too_long}

      true ->
        updated_session = %{session | name: new_name, updated_at: DateTime.utc_now()}
        {:ok, updated_session}
    end
  end

  def rename(%__MODULE__{}, _), do: {:error, :invalid_name}
end
