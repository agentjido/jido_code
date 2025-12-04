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
end
