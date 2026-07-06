defmodule JidoCode.Runtime.SnapshotStore do
  @moduledoc """
  Storage boundary for repository runtime snapshots.

  The default backend stores snapshots as product-owned control-plane
  checkpoints. An ETS backend is available for tests and failure injection
  without changing runtime snapshot semantics.
  """

  require Logger

  alias JidoCode.ExecutionRuntime.RecordStore
  alias JidoCode.Runtime.Snapshot

  @ets_table :jido_code_runtime_snapshot_store
  @record_store_backend :record_store
  @ets_backend :ets

  @type backend :: :record_store | :ets

  @spec save(Snapshot.t() | map(), keyword()) :: :ok | {:error, term()}
  def save(snapshot_or_status, opts \\ [])

  def save(%Snapshot{} = snapshot, opts) do
    case backend(opts) do
      @record_store_backend -> save_record_store(snapshot, opts)
      @ets_backend -> save_ets(snapshot)
      other -> unavailable(other, :save, :unsupported_backend)
    end
  end

  def save(status, opts) when is_map(status) do
    with {:ok, snapshot} <- Snapshot.from_status(status) do
      save(snapshot, opts)
    end
  end

  def save(_snapshot_or_status, _opts), do: {:error, %{type: :invalid_runtime_snapshot}}

  @spec load(String.t(), keyword()) :: {:ok, Snapshot.t()} | :error | {:error, term()}
  def load(managed_repo_id, opts \\ [])

  def load(managed_repo_id, opts) when is_binary(managed_repo_id) do
    case backend(opts) do
      @record_store_backend -> load_record_store(managed_repo_id, opts)
      @ets_backend -> load_ets(managed_repo_id)
      other -> unavailable(other, :load, :unsupported_backend)
    end
  end

  def load(_managed_repo_id, _opts), do: {:error, %{type: :invalid_managed_repo_id}}

  @spec delete(String.t(), keyword()) :: :ok | {:error, term()}
  def delete(managed_repo_id, opts \\ [])

  def delete(managed_repo_id, opts) when is_binary(managed_repo_id) do
    case backend(opts) do
      @record_store_backend -> delete_record_store(managed_repo_id, opts)
      @ets_backend -> delete_ets(managed_repo_id)
      other -> unavailable(other, :delete, :unsupported_backend)
    end
  end

  def delete(_managed_repo_id, _opts), do: {:error, %{type: :invalid_managed_repo_id}}

  @spec checkpoint_id(String.t()) :: String.t()
  def checkpoint_id(managed_repo_id), do: Snapshot.checkpoint_id(managed_repo_id)

  defp save_record_store(%Snapshot{} = snapshot, opts) do
    attrs = %{
      checkpoint_id: checkpoint_id(snapshot.managed_repo_id),
      managed_repo_id: snapshot.managed_repo_id,
      sandbox_session_id: nil,
      sprites_checkpoint_id: checkpoint_id(snapshot.managed_repo_id),
      name: "Repository runtime snapshot #{snapshot.managed_repo_id}",
      exec_session_sequence: 0,
      runner_state_snapshot: Snapshot.to_record(snapshot),
      metadata: %{
        "kind" => Snapshot.kind(),
        "managed_repo_id" => snapshot.managed_repo_id,
        "version" => Snapshot.version(),
        "deleted" => false
      }
    }

    case RecordStore.create_checkpoint(attrs, record_store_opts(opts)) do
      {:ok, _checkpoint} ->
        :ok

      {:error, reason} ->
        Logger.warning("Repository runtime snapshot save failed for #{snapshot.managed_repo_id}: #{inspect(reason)}")
        unavailable(@record_store_backend, :save, reason)
    end
  rescue
    error ->
      Logger.warning(
        "Repository runtime snapshot save failed for #{snapshot.managed_repo_id}: #{Exception.message(error)}"
      )

      unavailable(@record_store_backend, :save, error)
  end

  defp load_record_store(managed_repo_id, opts) do
    case RecordStore.list_checkpoints(%{id: checkpoint_id(managed_repo_id)}, record_store_opts(opts)) do
      {:ok, [checkpoint | _rest]} ->
        if deleted_checkpoint?(checkpoint) do
          :error
        else
          checkpoint
          |> Map.get(:runner_state_snapshot, %{})
          |> Snapshot.from_record()
        end

      {:ok, []} ->
        :error

      {:error, reason} ->
        Logger.warning("Repository runtime snapshot load failed for #{managed_repo_id}: #{inspect(reason)}")
        unavailable(@record_store_backend, :load, reason)
    end
  rescue
    error ->
      Logger.warning("Repository runtime snapshot load failed for #{managed_repo_id}: #{Exception.message(error)}")
      unavailable(@record_store_backend, :load, error)
  end

  defp delete_record_store(managed_repo_id, opts) do
    attrs = %{
      checkpoint_id: checkpoint_id(managed_repo_id),
      managed_repo_id: managed_repo_id,
      sandbox_session_id: nil,
      sprites_checkpoint_id: checkpoint_id(managed_repo_id),
      name: "Repository runtime snapshot #{managed_repo_id}",
      exec_session_sequence: 0,
      runner_state_snapshot: %{},
      metadata: %{
        "kind" => Snapshot.kind(),
        "managed_repo_id" => managed_repo_id,
        "version" => Snapshot.version(),
        "deleted" => true
      }
    }

    case RecordStore.create_checkpoint(attrs, record_store_opts(opts)) do
      {:ok, _checkpoint} ->
        :ok

      {:error, reason} ->
        Logger.warning("Repository runtime snapshot delete failed for #{managed_repo_id}: #{inspect(reason)}")
        unavailable(@record_store_backend, :delete, reason)
    end
  rescue
    error ->
      Logger.warning("Repository runtime snapshot delete failed for #{managed_repo_id}: #{Exception.message(error)}")
      unavailable(@record_store_backend, :delete, error)
  end

  defp save_ets(%Snapshot{} = snapshot) do
    table = ensure_ets_table()
    true = :ets.insert(table, {snapshot.managed_repo_id, Snapshot.to_record(snapshot), false})
    :ok
  end

  defp load_ets(managed_repo_id) do
    table = ensure_ets_table()

    case :ets.lookup(table, managed_repo_id) do
      [{^managed_repo_id, _record, true}] -> :error
      [{^managed_repo_id, record, false}] -> Snapshot.from_record(record)
      [] -> :error
    end
  end

  defp delete_ets(managed_repo_id) do
    table = ensure_ets_table()
    true = :ets.insert(table, {managed_repo_id, %{}, true})
    :ok
  end

  defp ensure_ets_table do
    case :ets.whereis(@ets_table) do
      :undefined ->
        :ets.new(@ets_table, [:named_table, :public, :set, read_concurrency: true, write_concurrency: true])

      table ->
        table
    end
  rescue
    ArgumentError ->
      @ets_table
  end

  defp deleted_checkpoint?(%{metadata: metadata}) when is_map(metadata) do
    Map.get(metadata, "deleted") == true or Map.get(metadata, :deleted) == true
  end

  defp deleted_checkpoint?(_checkpoint), do: false

  defp backend(opts) do
    Keyword.get(opts, :backend) ||
      Application.get_env(:jido_code, :repository_runtime_snapshot_store, @record_store_backend)
  end

  defp record_store_opts(opts) do
    opts
    |> Keyword.drop([:backend])
  end

  defp unavailable(backend, operation, reason) do
    {:error,
     %{
       type: :runtime_snapshot_store_unavailable,
       backend: backend,
       operation: operation,
       reason: reason
     }}
  end
end
