defmodule JidoCode.Memory.Supervisor do
  @moduledoc """
  Supervisor for the JidoCode memory subsystem.

  This supervisor manages the lifecycle of all memory-related processes,
  ensuring proper startup order and restart behavior.

  ## Supervision Tree

  ```
  JidoCode.Memory.Supervisor (:one_for_one)
       │
       └── JidoCode.Memory.LongTerm.StoreManager
            • Manages session-isolated memory stores
            • Handles store lifecycle (open, close, cleanup)
  ```

  ## Restart Strategy

  Uses `:one_for_one` strategy - if the StoreManager crashes, only it restarts.
  This is appropriate since:
  - StoreManager is stateful but can recover by reopening stores on demand
  - Future children (e.g., caching, indexing) can fail independently

  ## Configuration

  The supervisor accepts the following options which are passed to StoreManager:

  - `:base_path` - Base directory for memory stores (default: `~/.jido_code/memory_stores`)
  - `:config` - Additional store configuration options

  ## Example

      # Started automatically by the application
      # Or manually for testing:
      {:ok, pid} = JidoCode.Memory.Supervisor.start_link()

      # With custom options:
      {:ok, pid} = JidoCode.Memory.Supervisor.start_link(
        base_path: "/tmp/test_memory_stores"
      )

  """

  use Supervisor

  alias JidoCode.Memory.LongTerm.StoreManager

  # =============================================================================
  # Client API
  # =============================================================================

  @doc """
  Starts the Memory Supervisor.

  ## Options

  - `:name` - Supervisor name (default: `#{__MODULE__}`)
  - `:store_name` - StoreManager process name (default: `StoreManager`)
  - `:base_path` - Base directory for memory stores
  - `:config` - Additional store configuration

  ## Examples

      {:ok, pid} = JidoCode.Memory.Supervisor.start_link()
      {:ok, pid} = JidoCode.Memory.Supervisor.start_link(base_path: "/tmp/stores")

      # For testing with isolated instances:
      {:ok, pid} = JidoCode.Memory.Supervisor.start_link(
        name: :my_supervisor,
        store_name: :my_store_manager,
        base_path: "/tmp/test_stores"
      )

  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    {sup_opts, child_opts} = Keyword.split(opts, [:name])
    name = Keyword.get(sup_opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, child_opts, name: name)
  end

  # =============================================================================
  # Supervisor Callbacks
  # =============================================================================

  @impl true
  def init(opts) do
    # Extract store_name option and pass as :name to StoreManager
    {store_name, store_opts} = Keyword.pop(opts, :store_name, StoreManager)
    store_opts = Keyword.put(store_opts, :name, store_name)

    children = [
      {StoreManager, store_opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
