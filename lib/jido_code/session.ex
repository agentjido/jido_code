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
end
