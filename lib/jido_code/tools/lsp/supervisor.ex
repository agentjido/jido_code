defmodule JidoCode.Tools.LSP.Supervisor do
  @moduledoc """
  Supervisor for LSP client processes.

  Manages per-project Expert LSP clients. Each project gets its own client
  to ensure proper isolation and correct workspace configuration.

  ## Usage

  The supervisor is started as part of the application supervision tree.
  Clients are started on-demand when LSP operations are requested.

      # Get or start a client for a project
      {:ok, client} = LSP.Supervisor.get_or_start_client("/path/to/project")

      # The client can then be used for LSP requests
      {:ok, result} = LSP.Client.request(client, "textDocument/hover", params)
  """

  use DynamicSupervisor

  alias JidoCode.Tools.LSP.Client

  @doc """
  Starts the LSP supervisor.
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Gets an existing client for the project or starts a new one.

  Returns `{:ok, pid}` if successful, or `{:error, reason}` if the client
  cannot be started (e.g., Expert is not available).

  ## Parameters

    * `project_root` - The absolute path to the project root directory

  ## Returns

    * `{:ok, pid}` - The client process ID
    * `{:error, :expert_not_available}` - Expert is not installed
    * `{:error, reason}` - Other startup error
  """
  @spec get_or_start_client(String.t()) :: {:ok, pid()} | {:error, term()}
  def get_or_start_client(project_root) when is_binary(project_root) do
    client_name = client_name(project_root)

    case Process.whereis(client_name) do
      nil ->
        start_client(project_root, client_name)

      pid when is_pid(pid) ->
        {:ok, pid}
    end
  end

  @doc """
  Stops the client for a specific project.

  ## Parameters

    * `project_root` - The project root directory
  """
  @spec stop_client(String.t()) :: :ok
  def stop_client(project_root) when is_binary(project_root) do
    client_name = client_name(project_root)

    case Process.whereis(client_name) do
      nil ->
        :ok

      pid when is_pid(pid) ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  @doc """
  Checks if a client exists for the given project.
  """
  @spec client_exists?(String.t()) :: boolean()
  def client_exists?(project_root) when is_binary(project_root) do
    client_name = client_name(project_root)
    Process.whereis(client_name) != nil
  end

  @doc """
  Checks if Expert is available on the system.
  """
  @spec expert_available?() :: boolean()
  defdelegate expert_available?, to: Client

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp start_client(project_root, client_name) do
    if Client.expert_available?() do
      child_spec = {
        Client,
        project_root: project_root, name: client_name
      }

      case DynamicSupervisor.start_child(__MODULE__, child_spec) do
        {:ok, pid} ->
          {:ok, pid}

        {:error, {:already_started, pid}} ->
          {:ok, pid}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :expert_not_available}
    end
  end

  # Generate a unique name for the client based on project root
  defp client_name(project_root) do
    # Use a hash of the project root to create a unique atom
    hash = :erlang.phash2(project_root, 1_000_000)
    :"lsp_client_#{hash}"
  end
end
