defmodule JidoCode.ControlPlane.FakeStore do
  @moduledoc """
  Deterministic in-memory control-plane store for unit tests.

  This implementation honors the product-level store behaviour without opening
  RocksDB. It enforces subject and identity conflicts, optimistic updated-at
  checks, authorization context, and append-event capture.
  """

  use GenServer

  @behaviour JidoCode.ControlPlane.Store

  alias JidoCode.ControlPlane.Store
  alias JidoCode.ControlPlane.Store.{Outcome, Request}

  alias JidoCode.ControlPlane.Store.Errors.{
    ConflictError,
    NotFoundError,
    UnauthorizedError,
    ValidationError
  }

  defstruct records: %{}, identities: %{}, events: []

  @type state :: %__MODULE__{
          records: %{String.t() => map()},
          identities: %{term() => String.t()},
          events: [map()]
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec seed(GenServer.server(), [map()]) :: :ok
  def seed(server, records) when is_list(records) do
    GenServer.call(server, {:seed, records})
  end

  @spec events(GenServer.server()) :: [map()]
  def events(server), do: GenServer.call(server, :events)

  @spec snapshot(GenServer.server()) :: state()
  def snapshot(server), do: GenServer.call(server, :snapshot)

  @impl Store
  def create(%Request{} = request), do: call_store(request, :create)

  @impl Store
  def update(%Request{} = request), do: call_store(request, :update)

  @impl Store
  def upsert(%Request{} = request), do: call_store(request, :upsert)

  @impl Store
  def delete(%Request{} = request), do: call_store(request, :delete)

  @impl Store
  def get(%Request{} = request), do: call_store(request, :get)

  @impl Store
  def list(%Request{} = request), do: call_store(request, :list)

  @impl Store
  def append_event(%Request{} = request), do: call_store(request, :append_event)

  @impl Store
  def query(%Request{} = request), do: call_store(request, :query)

  @impl true
  def init(opts) do
    state = %__MODULE__{}

    records = Keyword.get(opts, :records, [])
    {:ok, seed_state(state, records)}
  end

  @impl true
  def handle_call({:seed, records}, _from, state) do
    {:reply, :ok, seed_state(state, records)}
  end

  def handle_call(:events, _from, state) do
    {:reply, Enum.reverse(state.events), state}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:operation, operation, request}, _from, state) do
    {reply, next_state} = apply_operation(operation, Request.put_operation(request, operation), state)
    {:reply, reply, next_state}
  end

  defp call_store(%Request{store: nil}, operation) do
    {:error,
     ValidationError.exception(
       stage: operation,
       field: :store,
       reason: :missing_store,
       errors: [%{field: :store, reason: :missing}]
     )}
  end

  defp call_store(%Request{store: store} = request, operation) do
    GenServer.call(store, {:operation, operation, request})
  end

  defp apply_operation(operation, request, state) do
    case ensure_authorized(request) do
      :ok -> do_apply_operation(operation, request, state)
      {:error, error} -> {{:error, error}, state}
    end
  end

  defp do_apply_operation(:create, request, state) do
    with :ok <- validate_write_request(request),
         :ok <- assert_subject_available(state, request),
         :ok <- assert_identity_available(state, request) do
      entry = entry_from_request(request)
      next_state = put_entry(state, entry)

      {{:ok, write_outcome(request, entry, :created)}, next_state}
    else
      {:error, error} -> {{:error, error}, state}
    end
  end

  defp do_apply_operation(:update, request, state) do
    with :ok <- validate_write_request(request),
         {:ok, existing} <- fetch_entry(state, request),
         :ok <- assert_expected_updated_at(existing, request),
         :ok <- assert_identity_available(state, request),
         next_state <- delete_entry(state, existing),
         entry <- entry_from_request(request),
         next_state <- put_entry(next_state, entry) do
      {{:ok, write_outcome(request, entry, :updated)}, next_state}
    else
      {:error, error} -> {{:error, error}, state}
    end
  end

  defp do_apply_operation(:upsert, request, state) do
    with :ok <- validate_write_request(request),
         :ok <- assert_identity_available(state, request) do
      existing = find_existing_upsert_entry(state, request)
      next_state = if existing, do: delete_entry(state, existing), else: state
      entry = entry_from_request(request)
      next_state = put_entry(next_state, entry)
      status = if existing, do: :updated, else: :created

      {{:ok, write_outcome(request, entry, status)}, next_state}
    else
      {:error, error} -> {{:error, error}, state}
    end
  end

  defp do_apply_operation(:delete, request, state) do
    with :ok <- validate_subject_request(request),
         {:ok, existing} <- fetch_entry(state, request) do
      next_state = delete_entry(state, existing)

      {{:ok,
        %Outcome{
          operation: :delete,
          status: :deleted,
          record_type: existing.record_type,
          subject_iri: existing.subject_iri,
          deleted_subject_iris: [existing.subject_iri],
          metadata: request.metadata
        }}, next_state}
    else
      {:error, error} -> {{:error, error}, state}
    end
  end

  defp do_apply_operation(:get, request, state) do
    with {:ok, entry} <- fetch_entry(state, request) do
      {{:ok,
        %Outcome{
          operation: :get,
          status: :found,
          record_type: entry.record_type,
          subject_iri: entry.subject_iri,
          record: entry.record,
          projection: projection(entry),
          metadata: request.metadata
        }}, state}
    else
      {:error, error} -> {{:error, error}, state}
    end
  end

  defp do_apply_operation(:list, request, state) do
    entries = filter_entries(state.records, request)
    {paged_entries, page} = paginate(entries, request)

    {{:ok,
      %Outcome{
        operation: :list,
        status: :listed,
        record_type: request.record_type,
        records: Enum.map(paged_entries, & &1.record),
        projections: Enum.map(paged_entries, &projection/1),
        metadata: Map.merge(request.metadata, page)
      }}, state}
  end

  defp do_apply_operation(:append_event, request, state) do
    with :ok <- validate_event_request(request) do
      event_iri = request.subject_iri || map_get(request.event, :event_iri) || map_get(request.event, :id)
      event = Map.merge(request.event || %{}, %{event_iri: event_iri, record_type: request.record_type})
      next_state = %{state | events: [event | state.events]}

      {{:ok,
        %Outcome{
          operation: :append_event,
          status: :appended,
          record_type: request.record_type,
          subject_iri: event_iri,
          event_iri: event_iri,
          metadata: request.metadata
        }}, next_state}
    else
      {:error, error} -> {{:error, error}, state}
    end
  end

  defp do_apply_operation(:query, request, state) do
    entries = filter_entries(state.records, request)
    {paged_entries, page} = paginate(entries, request)

    {{:ok,
      %Outcome{
        operation: :query,
        status: :query_succeeded,
        record_type: request.record_type,
        records: Enum.map(paged_entries, & &1.record),
        projections: Enum.map(paged_entries, &projection/1),
        metadata: Map.merge(request.metadata, page)
      }}, state}
  end

  defp ensure_authorized(%Request{authorization: %{allowed?: true}}), do: :ok

  defp ensure_authorized(%Request{} = request) do
    {:error,
     UnauthorizedError.exception(
       operation: request.operation,
       record_type: request.record_type,
       actor: request.actor,
       reason: request.authorization && request.authorization.reason
     )}
  end

  defp validate_write_request(%Request{} = request) do
    cond do
      is_nil(request.record_type) ->
        validation_error(request.operation, :record_type, :missing)

      not present_string?(request.subject_iri) ->
        validation_error(request.operation, :subject_iri, :missing)

      not is_map(request.record) ->
        validation_error(request.operation, :record, :invalid)

      true ->
        :ok
    end
  end

  defp validate_subject_request(%Request{} = request) do
    if present_string?(request.subject_iri) or not is_nil(request.identity) do
      :ok
    else
      validation_error(request.operation, :subject_iri, :missing)
    end
  end

  defp validate_event_request(%Request{} = request) do
    cond do
      is_nil(request.record_type) ->
        validation_error(request.operation, :record_type, :missing)

      not is_map(request.event) ->
        validation_error(request.operation, :event, :invalid)

      not present_string?(request.subject_iri || map_get(request.event, :event_iri) || map_get(request.event, :id)) ->
        validation_error(request.operation, :event_iri, :missing)

      true ->
        :ok
    end
  end

  defp validation_error(stage, field, reason) do
    {:error,
     ValidationError.exception(
       stage: stage,
       field: field,
       reason: reason,
       errors: [%{field: field, reason: reason}]
     )}
  end

  defp assert_subject_available(%{records: records}, %Request{} = request) do
    case Map.fetch(records, request.subject_iri) do
      :error ->
        :ok

      {:ok, existing} ->
        {:error,
         ConflictError.exception(
           record_type: request.record_type,
           identity: :subject_iri,
           subject_iri: request.subject_iri,
           conflicting_subject_iri: existing.subject_iri
         )}
    end
  end

  defp assert_identity_available(%{identities: identities}, %Request{} = request) do
    identity_key = identity_key(request)

    case identity_key && Map.fetch(identities, identity_key) do
      nil ->
        :ok

      :error ->
        :ok

      {:ok, subject_iri} when subject_iri == request.subject_iri ->
        :ok

      {:ok, subject_iri} ->
        {:error,
         ConflictError.exception(
           record_type: request.record_type,
           identity: identity_name(request.identity),
           subject_iri: request.subject_iri,
           conflicting_subject_iri: subject_iri
         )}
    end
  end

  defp assert_expected_updated_at(_entry, %Request{expected_updated_at: nil}), do: :ok

  defp assert_expected_updated_at(entry, %Request{} = request) do
    if map_get(entry.record, :updated_at) == request.expected_updated_at do
      :ok
    else
      {:error,
       ConflictError.exception(
         record_type: request.record_type,
         identity: :expected_updated_at,
         subject_iri: request.subject_iri,
         conflicting_subject_iri: request.subject_iri
       )}
    end
  end

  defp fetch_entry(%{records: records} = state, %Request{} = request) do
    subject_iri = request.subject_iri || subject_for_identity(state, request)

    case subject_iri && Map.fetch(records, subject_iri) do
      {:ok, entry} ->
        {:ok, entry}

      _other ->
        {:error, NotFoundError.exception(record_type: request.record_type, subject_iri: subject_iri)}
    end
  end

  defp subject_for_identity(%{identities: identities}, request) do
    identity_key = identity_key(request)
    identity_key && Map.get(identities, identity_key)
  end

  defp find_existing_upsert_entry(state, request) do
    with nil <- Map.get(state.records, request.subject_iri),
         subject_iri when is_binary(subject_iri) <- subject_for_identity(state, request) do
      Map.get(state.records, subject_iri)
    else
      entry -> entry
    end
  end

  defp entry_from_request(%Request{} = request) do
    %{
      record_type: request.record_type,
      subject_iri: request.subject_iri,
      record: request.record,
      identity_key: identity_key(request),
      correlation_id: request.correlation_id,
      metadata: request.metadata
    }
  end

  defp put_entry(state, entry) do
    state
    |> put_in([Access.key(:records), entry.subject_iri], entry)
    |> put_identity(entry)
  end

  defp put_identity(state, %{identity_key: nil}), do: state

  defp put_identity(state, entry) do
    put_in(state, [Access.key(:identities), entry.identity_key], entry.subject_iri)
  end

  defp delete_entry(state, entry) do
    identities =
      if entry.identity_key do
        Map.delete(state.identities, entry.identity_key)
      else
        state.identities
      end

    %{state | records: Map.delete(state.records, entry.subject_iri), identities: identities}
  end

  defp write_outcome(request, entry, status) do
    %Outcome{
      operation: request.operation,
      status: status,
      record_type: entry.record_type,
      subject_iri: entry.subject_iri,
      record: entry.record,
      projection: projection(entry),
      written_subject_iris: [entry.subject_iri],
      metadata: request.metadata
    }
  end

  defp projection(entry) do
    %{
      record_type: entry.record_type,
      subject_iri: entry.subject_iri,
      record: entry.record
    }
  end

  defp filter_entries(records, request) do
    query = request.query || %{}
    record_type = request.record_type || map_get(query, :record_type)
    managed_repo_id = map_get(query, :managed_repo_id)

    records
    |> Map.values()
    |> Enum.filter(fn entry -> is_nil(record_type) or entry.record_type == record_type end)
    |> Enum.filter(fn entry ->
      is_nil(managed_repo_id) or map_get(entry.record, :managed_repo_id) == managed_repo_id
    end)
    |> Enum.sort_by(& &1.subject_iri)
  end

  defp paginate(entries, request) do
    query = request.query || %{}
    limit = query |> map_get(:limit, 50) |> clamp_integer(50, 1, 500)
    offset = query |> map_get(:offset, 0) |> clamp_integer(0, 0, 1_000_000)
    total_count = length(entries)
    page = entries |> Enum.drop(offset) |> Enum.take(limit)
    next_offset = if offset + length(page) < total_count, do: offset + length(page), else: nil

    {page, %{limit: limit, offset: offset, total_count: total_count, next_offset: next_offset}}
  end

  defp seed_state(state, records) do
    Enum.reduce(records, state, fn attrs, acc ->
      request =
        attrs
        |> Request.new()
        |> Request.put_operation(:seed)

      entry = entry_from_request(request)
      put_entry(acc, entry)
    end)
  end

  defp identity_key(%Request{identity: nil}), do: nil

  defp identity_key(%Request{} = request) do
    identity = request.identity || %{}

    {
      request.record_type,
      identity_name(identity),
      map_get(identity, :value) || map_get(identity, :values) || Map.delete(identity, :identity)
    }
  end

  defp identity_name(nil), do: nil
  defp identity_name(identity), do: map_get(identity, :identity, :identity)

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp clamp_integer(value, _default, min, max) when is_integer(value), do: value |> max(min) |> min(max)
  defp clamp_integer(_value, default, _min, _max), do: default

  defp map_get(map, key, default \\ nil)

  defp map_get(nil, _key, default), do: default
  defp map_get(map, key, default) when is_map(map), do: Map.get(map, key) || Map.get(map, Atom.to_string(key), default)
end
