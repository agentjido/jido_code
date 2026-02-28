defmodule JidoCode.Forge.InfraClient.Behaviour do
  @moduledoc """
  Behaviour defining the interface for infrastructure client implementations.

  An infra client provides an isolated execution environment (container, VM, or local sandbox)
  where Forge runners execute commands and manage files.

  ## Progress Reporting

  The `create/1` callback receives a spec map that may include an `:on_progress` key —
  a function `(stage, metadata) -> :ok` called during long-running provisioning to report
  progress. Stages: `:ssh_key`, `:server_creating`, `:server_booting`, `:ssh_waiting`,
  `:ssh_connected`, `:session_starting`. Fast-provisioning implementations (like local
  sandboxes) may ignore this key.
  """

  @type client :: term()
  @type infra_id :: String.t()
  @type spec :: map()
  @type command :: String.t()
  @type path :: String.t()
  @type content :: binary()
  @type env_map :: %{String.t() => String.t()}
  @type handle :: term()
  @type opts :: keyword()

  @doc """
  Create a new infrastructure environment from the given specification.

  The spec map may include an `:on_progress` key with a function `(stage, metadata) -> :ok`
  for reporting provisioning progress.

  Returns the client state and a unique infrastructure identifier.
  """
  @callback create(spec()) :: {:ok, client(), infra_id()} | {:error, term()}

  @doc """
  Execute a command synchronously in the environment.

  Returns the output and exit code.
  """
  @callback exec(client(), command(), opts()) :: {String.t(), non_neg_integer()}

  @doc """
  Spawn an asynchronous command in the environment.

  Returns a handle for monitoring or interacting with the process.
  """
  @callback spawn(client(), command(), args :: [String.t()], opts()) ::
              {:ok, handle()} | {:error, term()}

  @doc """
  Write content to a file in the environment.
  """
  @callback write_file(client(), path(), content()) :: :ok | {:error, term()}

  @doc """
  Read content from a file in the environment.
  """
  @callback read_file(client(), path()) :: {:ok, content()} | {:error, term()}

  @doc """
  Inject environment variables into the environment.

  These should be available to all subsequent commands.
  """
  @callback inject_env(client(), env_map()) :: :ok | {:error, term()}

  @doc """
  Destroy the environment and clean up resources.
  """
  @callback destroy(client(), infra_id()) :: :ok | {:error, term()}

  @doc """
  Returns the implementation module for this client type.
  """
  @callback impl_module() :: module()
end
