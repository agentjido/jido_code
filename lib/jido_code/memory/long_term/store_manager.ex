defmodule JidoCode.Memory.LongTerm.StoreManager do
  @moduledoc """
  Session-isolated triple store lifecycle management.

  The StoreManager is a GenServer that manages the lifecycle of session-specific
  TripleStore instances for long-term memory persistence. Each session gets its
  own isolated RDF triple store backed by RocksDB.

  ## Architecture

  ```
  StoreManager (GenServer)
       │
       ├── stores: %{session_id => %{store: store_ref, metadata: %{...}}}
       │
       └── base_path: ~/.jido_code/memory_stores/
            ├── session_abc123/   (RocksDB instance)
            ├── session_def456/   (RocksDB instance)
            └── session_ghi789/   (RocksDB instance)
  ```

  ## Store Backend

  Uses the TripleStore library backed by RocksDB for persistent RDF storage.
  Each session gets its own TripleStore instance with:
  - SPARQL 1.1 Query and Update support
  - Ontology loaded on first open
  - Persistent storage across restarts

  ## Example Usage

      # Get or create a store for a session
      {:ok, store} = StoreManager.get_or_create("session-123")

      # Get an existing store (fails if not open)
      {:ok, store} = StoreManager.get("session-123")
      {:error, :not_found} = StoreManager.get("unknown-session")

      # Check store health
      {:ok, :healthy} = StoreManager.health("session-123")

      # Close a specific session's store
      :ok = StoreManager.close("session-123")

      # Close all open stores
      :ok = StoreManager.close_all()

      # List open session IDs
      ["session-123", "session-456"] = StoreManager.list_open()

  ## Configuration

  The StoreManager can be configured with:
  - `base_path` - Directory for store files (default: `~/.jido_code/memory_stores`)
  - `name` - GenServer name for registration (default: `__MODULE__`)

  """

  use GenServer

  require Logger

  alias JidoCode.Memory.LongTerm.OntologyLoader
  alias JidoCode.Memory.Types

  # =============================================================================
  # Types
  # =============================================================================

  @typedoc """
  Reference to an open TripleStore instance.
  """
  @type store_ref :: TripleStore.store()

  @typedoc """
  Metadata tracked for each open store.
  """
  @type store_metadata :: %{
          opened_at: DateTime.t(),
          last_accessed: DateTime.t(),
          ontology_loaded: boolean()
        }

  @typedoc """
  Entry for a store in the stores map.
  """
  @type store_entry :: %{
          store: store_ref(),
          metadata: store_metadata()
        }

  @typedoc """
  StoreManager state.

  - `stores` - Map of session_id to store entry (store ref + metadata)
  - `base_path` - Base directory for persistent storage
  - `config` - Store configuration options
  """
  @type state :: %{
          stores: %{String.t() => store_entry()},
          base_path: String.t(),
          config: map()
        }

  # =============================================================================
  # Constants
  # =============================================================================

  @default_base_path "~/.jido_code/memory_stores"
  @default_config %{
    create_if_missing: true
  }

  # =============================================================================
  # Client API
  # =============================================================================

  @doc """
  Starts the StoreManager GenServer.

  ## Options

  - `:base_path` - Base directory for store files (default: `~/.jido_code/memory_stores`)
  - `:name` - GenServer name (default: `#{__MODULE__}`)
  - `:config` - Additional configuration options

  ## Examples

      {:ok, pid} = StoreManager.start_link()
      {:ok, pid} = StoreManager.start_link(base_path: "/tmp/stores")

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets or creates a store for the given session.

  If a store already exists for the session, returns the existing reference.
  If not, opens a new TripleStore and loads the ontology.

  ## Examples

      {:ok, store} = StoreManager.get_or_create("session-123")

  """
  @spec get_or_create(String.t(), GenServer.server()) :: {:ok, store_ref()} | {:error, term()}
  def get_or_create(session_id, server \\ __MODULE__) do
    GenServer.call(server, {:get_or_create, session_id})
  end

  @doc """
  Gets an existing store for the given session.

  Returns `{:error, :not_found}` if no store is open for the session.
  Unlike `get_or_create/1`, this does not create a new store.

  ## Examples

      {:ok, store} = StoreManager.get("session-123")
      {:error, :not_found} = StoreManager.get("unknown-session")

  """
  @spec get(String.t(), GenServer.server()) :: {:ok, store_ref()} | {:error, :not_found}
  def get(session_id, server \\ __MODULE__) do
    GenServer.call(server, {:get, session_id})
  end

  @doc """
  Gets store metadata for the given session.

  Returns metadata including open time, last access time, and ontology status.

  ## Examples

      {:ok, %{opened_at: ~U[...], last_accessed: ~U[...], ontology_loaded: true}} =
        StoreManager.get_metadata("session-123")

  """
  @spec get_metadata(String.t(), GenServer.server()) ::
          {:ok, store_metadata()} | {:error, :not_found}
  def get_metadata(session_id, server \\ __MODULE__) do
    GenServer.call(server, {:get_metadata, session_id})
  end

  @doc """
  Checks the health of a session's store.

  Returns `{:ok, :healthy}` if the store is operational.

  ## Examples

      {:ok, :healthy} = StoreManager.health("session-123")
      {:error, :not_found} = StoreManager.health("unknown-session")

  """
  @spec health(String.t(), GenServer.server()) ::
          {:ok, :healthy} | {:error, :not_found | :unhealthy | term()}
  def health(session_id, server \\ __MODULE__) do
    GenServer.call(server, {:health, session_id})
  end

  @doc """
  Closes the store for the given session.

  If the session has no open store, returns `:ok` without error.

  ## Examples

      :ok = StoreManager.close("session-123")

  """
  @spec close(String.t(), GenServer.server()) :: :ok | {:error, term()}
  def close(session_id, server \\ __MODULE__) do
    GenServer.call(server, {:close, session_id})
  end

  @doc """
  Closes all open stores.

  Used during shutdown to ensure clean cleanup.

  ## Examples

      :ok = StoreManager.close_all()

  """
  @spec close_all(GenServer.server()) :: :ok
  def close_all(server \\ __MODULE__) do
    GenServer.call(server, :close_all)
  end

  @doc """
  Lists all currently open session IDs.

  ## Examples

      ["session-123", "session-456"] = StoreManager.list_open()

  """
  @spec list_open(GenServer.server()) :: [String.t()]
  def list_open(server \\ __MODULE__) do
    GenServer.call(server, :list_open)
  end

  @doc """
  Checks if a store is open for the given session.

  ## Examples

      true = StoreManager.open?("session-123")
      false = StoreManager.open?("unknown-session")

  """
  @spec open?(String.t(), GenServer.server()) :: boolean()
  def open?(session_id, server \\ __MODULE__) do
    GenServer.call(server, {:open?, session_id})
  end

  @doc """
  Returns the base path for store files.

  ## Examples

      "/home/user/.jido_code/memory_stores" = StoreManager.base_path()

  """
  @spec base_path(GenServer.server()) :: String.t()
  def base_path(server \\ __MODULE__) do
    GenServer.call(server, :base_path)
  end

  # =============================================================================
  # GenServer Callbacks
  # =============================================================================

  @impl true
  def init(opts) do
    base_path = Keyword.get(opts, :base_path, @default_base_path)
    config = Keyword.get(opts, :config, @default_config)

    expanded_path = expand_path(base_path)

    # Ensure base directory exists
    case ensure_directory(expanded_path) do
      :ok ->
        state = %{
          stores: %{},
          base_path: expanded_path,
          config: config
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, {:failed_to_create_base_path, reason}}
    end
  end

  @impl true
  def handle_call({:get_or_create, session_id}, _from, state) do
    # Validate session ID to prevent atom exhaustion and path traversal attacks
    if not Types.valid_session_id?(session_id) do
      {:reply, {:error, :invalid_session_id}, state}
    else
      case Map.get(state.stores, session_id) do
        nil ->
          case open_store(session_id, state) do
            {:ok, store_ref, metadata} ->
              entry = %{store: store_ref, metadata: metadata}
              new_stores = Map.put(state.stores, session_id, entry)
              {:reply, {:ok, store_ref}, %{state | stores: new_stores}}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end

        %{store: store_ref} = entry ->
          # Update last accessed time
          updated_metadata = %{entry.metadata | last_accessed: DateTime.utc_now()}
          updated_entry = %{entry | metadata: updated_metadata}
          new_stores = Map.put(state.stores, session_id, updated_entry)
          {:reply, {:ok, store_ref}, %{state | stores: new_stores}}
      end
    end
  end

  @impl true
  def handle_call({:get, session_id}, _from, state) do
    case Map.get(state.stores, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{store: store_ref} = entry ->
        # Update last accessed time
        updated_metadata = %{entry.metadata | last_accessed: DateTime.utc_now()}
        updated_entry = %{entry | metadata: updated_metadata}
        new_stores = Map.put(state.stores, session_id, updated_entry)
        {:reply, {:ok, store_ref}, %{state | stores: new_stores}}
    end
  end

  @impl true
  def handle_call({:get_metadata, session_id}, _from, state) do
    case Map.get(state.stores, session_id) do
      nil -> {:reply, {:error, :not_found}, state}
      %{metadata: metadata} -> {:reply, {:ok, metadata}, state}
    end
  end

  @impl true
  def handle_call({:health, session_id}, _from, state) do
    case Map.get(state.stores, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{store: store_ref} ->
        case TripleStore.health(store_ref) do
          {:ok, %{status: :healthy}} -> {:reply, {:ok, :healthy}, state}
          {:ok, %{status: status}} -> {:reply, {:error, {:unhealthy, status}}, state}
          {:ok, :healthy} -> {:reply, {:ok, :healthy}, state}
          {:ok, status} when is_map(status) -> {:reply, {:ok, :healthy}, state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:close, session_id}, _from, state) do
    case Map.get(state.stores, session_id) do
      nil ->
        {:reply, :ok, state}

      %{store: store_ref} ->
        close_store(store_ref)
        new_stores = Map.delete(state.stores, session_id)
        {:reply, :ok, %{state | stores: new_stores}}
    end
  end

  @impl true
  def handle_call(:close_all, _from, state) do
    Enum.each(state.stores, fn {_session_id, %{store: store_ref}} ->
      close_store(store_ref)
    end)

    {:reply, :ok, %{state | stores: %{}}}
  end

  @impl true
  def handle_call(:list_open, _from, state) do
    session_ids = Map.keys(state.stores)
    {:reply, session_ids, state}
  end

  @impl true
  def handle_call({:open?, session_id}, _from, state) do
    {:reply, Map.has_key?(state.stores, session_id), state}
  end

  @impl true
  def handle_call(:base_path, _from, state) do
    {:reply, state.base_path, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("StoreManager received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("StoreManager terminating: #{inspect(reason)}")

    Enum.each(state.stores, fn {_session_id, %{store: store_ref}} ->
      close_store(store_ref)
    end)

    :ok
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  @doc false
  @spec store_path(String.t(), String.t()) :: String.t()
  def store_path(base_path, session_id) do
    Path.join(base_path, "session_" <> session_id)
  end

  defp expand_path(path) do
    path
    |> Path.expand()
  end

  defp ensure_directory(path) do
    case File.mkdir_p(path) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp open_store(session_id, state) do
    # Create session-specific directory for the TripleStore
    session_path = store_path(state.base_path, session_id)

    # Verify path containment - ensure resolved path is within base_path
    # This is a defense-in-depth measure (session_id is already validated)
    resolved_path = Path.expand(session_path)
    base_expanded = Path.expand(state.base_path)

    if not String.starts_with?(resolved_path, base_expanded <> "/") and
         resolved_path != base_expanded do
      {:error, :path_traversal_detected}
    else
      # Open TripleStore with RocksDB backend
      case TripleStore.open(session_path, create_if_missing: true) do
        {:ok, store} ->
          # Ensure ontology is loaded
          case ensure_ontology_loaded(store) do
            :ok ->
              now = DateTime.utc_now()

              metadata = %{
                opened_at: now,
                last_accessed: now,
                ontology_loaded: true
              }

              Logger.debug("Opened TripleStore for session #{session_id} at #{session_path}")
              {:ok, store, metadata}

            {:error, reason} ->
              # Close the store if ontology loading fails
              TripleStore.close(store)
              {:error, {:ontology_load_failed, reason}}
          end

        {:error, reason} ->
          Logger.error("Failed to open TripleStore for session #{session_id}: #{inspect(reason)}")
          {:error, {:store_open_failed, reason}}
      end
    end
  end

  defp ensure_ontology_loaded(store) do
    if OntologyLoader.ontology_loaded?(store) do
      :ok
    else
      case OntologyLoader.load_ontology(store) do
        {:ok, _count} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp close_store(store_ref) do
    case TripleStore.close(store_ref) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Error closing TripleStore: #{inspect(reason)}")
        :ok
    end
  end
end
