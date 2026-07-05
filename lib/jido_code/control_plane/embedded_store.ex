defmodule JidoCode.ControlPlane.EmbeddedStore do
  @moduledoc """
  Store behaviour adapter backed by the supervised embedded TripleStore.

  This module bridges the product-level store contract to the lower-level
  command/query boundary introduced in Phase 2.
  """

  @behaviour JidoCode.ControlPlane.Store

  alias JidoCode.ControlPlane.Codecs.Registry
  alias JidoCode.ControlPlane.Store
  alias JidoCode.ControlPlane.Store.{Outcome, Request}

  alias JidoCode.ControlPlane.Store.Errors.{
    ConflictError,
    NotFoundError,
    UnauthorizedError,
    UnavailableError,
    ValidationError
  }

  alias JidoCode.ControlPlane.{StoreCommand, StoreQuery, Validation}

  @impl Store
  def create(%Request{} = request) do
    with :ok <- ensure_authorized(request),
         {:ok, encoded} <- encode_request_record(request),
         :ok <- validate_request_record(request),
         {:ok, outcome} <-
           StoreCommand.execute(
             StoreCommand.insert(
               graph_name: encoded.graph_name,
               subject_iri: encoded.subject_iri,
               triples: encoded.triples,
               actor: request.actor,
               correlation_id: request.correlation_id
             ),
             request.store
           ) do
      {:ok, write_outcome(:create, :created, request, encoded, outcome)}
    else
      error -> normalize_error(error, request)
    end
  end

  @impl Store
  def update(%Request{} = request) do
    with :ok <- ensure_authorized(request),
         {:ok, encoded} <- encode_request_record(request),
         :ok <- validate_request_record(request),
         {:ok, outcome} <-
           StoreCommand.execute(
             StoreCommand.replace_subject(
               graph_name: encoded.graph_name,
               subject_iri: encoded.subject_iri,
               triples: encoded.triples,
               expected_updated_at: request.expected_updated_at,
               actor: request.actor,
               correlation_id: request.correlation_id
             ),
             request.store
           ) do
      {:ok, write_outcome(:update, :updated, request, encoded, outcome)}
    else
      error -> normalize_error(error, request)
    end
  end

  @impl Store
  def upsert(%Request{} = request) do
    with :ok <- ensure_authorized(request),
         {:ok, encoded} <- encode_request_record(request),
         :ok <- validate_request_record(request),
         {:ok, identity} <- identity_for_command(encoded),
         {:ok, outcome} <-
           StoreCommand.execute(
             StoreCommand.upsert_by_identity(
               graph_name: encoded.graph_name,
               subject_iri: encoded.subject_iri,
               identity: identity,
               triples: encoded.triples,
               expected_updated_at: request.expected_updated_at,
               actor: request.actor,
               correlation_id: request.correlation_id
             ),
             request.store
           ) do
      status = if Map.get(outcome, :deleted_triple_count, 0) > 0, do: :updated, else: :created
      {:ok, write_outcome(:upsert, status, request, encoded, outcome)}
    else
      error -> normalize_error(error, request)
    end
  end

  @impl Store
  def delete(%Request{} = request) do
    with :ok <- ensure_authorized(request),
         {:ok, subject_iri} <- subject_iri_for_request(request),
         {:ok, graph_name} <- graph_name_for(request.record_type),
         {:ok, outcome} <-
           StoreCommand.execute(
             StoreCommand.delete_subject(
               graph_name: graph_name,
               subject_iri: subject_iri,
               actor: request.actor,
               correlation_id: request.correlation_id
             ),
             request.store
           ) do
      if Map.get(outcome, :deleted_triple_count, 0) == 0 do
        {:error, NotFoundError.exception(record_type: request.record_type, subject_iri: subject_iri)}
      else
        {:ok,
         %Outcome{
           operation: :delete,
           status: :deleted,
           record_type: request.record_type,
           subject_iri: subject_iri,
           deleted_subject_iris: [subject_iri],
           metadata: request.metadata
         }}
      end
    else
      error -> normalize_error(error, request)
    end
  end

  @impl Store
  def get(%Request{} = request) do
    with :ok <- ensure_authorized(request),
         {:ok, projection} <- get_projection(request) do
      case projection do
        nil ->
          {:error, NotFoundError.exception(record_type: request.record_type, subject_iri: request.subject_iri)}

        projection ->
          {:ok,
           %Outcome{
             operation: :get,
             status: :found,
             record_type: request.record_type,
             subject_iri: projection.subject_iri,
             projection: projection,
             metadata: request.metadata
           }}
      end
    else
      error -> normalize_error(error, request)
    end
  end

  @impl Store
  def list(%Request{} = request) do
    with :ok <- ensure_authorized(request),
         {:ok, result} <- StoreQuery.list_by_class(request.record_type, query_opts(request)) do
      {:ok,
       %Outcome{
         operation: :list,
         status: :listed,
         record_type: request.record_type,
         projections: result.results,
         metadata:
           Map.merge(request.metadata, %{
             total_count: result.total_count,
             limit: result.limit,
             offset: result.offset,
             next_offset: result.next_offset
           })
       }}
    else
      error -> normalize_error(error, request)
    end
  end

  @impl Store
  def append_event(%Request{} = request) do
    event_request = %{request | record: request.event || request.record}

    with :ok <- ensure_authorized(event_request),
         {:ok, encoded} <- encode_request_record(event_request),
         :ok <- validate_request_record(event_request),
         {:ok, outcome} <-
           StoreCommand.execute(
             StoreCommand.append_event(
               graph_name: encoded.graph_name,
               subject_iri: encoded.subject_iri,
               triples: encoded.triples,
               actor: request.actor,
               correlation_id: request.correlation_id
             ),
             request.store
           ) do
      {:ok,
       %Outcome{
         operation: :append_event,
         status: :appended,
         record_type: request.record_type,
         subject_iri: encoded.subject_iri,
         event_iri: Map.get(outcome, :event_iri),
         metadata: request.metadata
       }}
    else
      error -> normalize_error(error, request)
    end
  end

  @impl Store
  def query(%Request{} = request), do: list(%{request | operation: :query})

  defp encode_request_record(%Request{record_type: record_type, record: record}) when is_map(record) do
    Registry.encode(record_type, record)
  end

  defp encode_request_record(request), do: {:error, {:invalid_record, request.record_type}}

  defp validate_request_record(%Request{} = request) do
    Validation.validate(request.record_type, request.record)
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

  defp get_projection(%Request{identity: identity} = request) when is_map(identity) do
    StoreQuery.lookup_by_identity(request.record_type, identity, query_opts(request))
  end

  defp get_projection(%Request{} = request) do
    with {:ok, identity} <- identity_from_subject(request) do
      StoreQuery.get_by_id(request.record_type, identity, query_opts(request))
    end
  end

  defp identity_from_subject(%{record: record}) when is_map(record), do: {:ok, record}

  defp identity_from_subject(%{subject_iri: subject_iri}) when is_binary(subject_iri) do
    {:ok, Path.basename(subject_iri)}
  end

  defp identity_from_subject(_request), do: {:error, :missing_subject_identity}

  defp subject_iri_for_request(%Request{subject_iri: subject_iri}) when is_binary(subject_iri), do: {:ok, subject_iri}

  defp subject_iri_for_request(%Request{} = request) do
    with {:ok, encoded} <- encode_request_record(request), do: {:ok, encoded.subject_iri}
  end

  defp graph_name_for(record_type) do
    case JidoCode.ControlPlane.GraphTopology.graph_for_record(record_type) do
      {:ok, graph_name} -> {:ok, graph_name}
      {:error, reason} -> {:error, reason}
    end
  end

  defp identity_for_command(%{identity_queries: [identity | _rest]} = encoded) do
    case identity do
      %{predicate: predicate, value: value} when not is_nil(value) ->
        {:ok,
         %{
           identity: identity.identity,
           predicate_iri: control_iri(predicate),
           value: value,
           class_iri: Map.get(identity, :class_iri) || Map.get(encoded, :class_iri)
         }}

      _other ->
        {:error, :missing_identity}
    end
  end

  defp identity_for_command(_encoded), do: {:error, :missing_identity}

  defp write_outcome(operation, status, request, encoded, command_outcome) do
    %Outcome{
      operation: operation,
      status: status,
      record_type: request.record_type,
      subject_iri: encoded.subject_iri,
      record: request.record,
      projection: %{subject_iri: encoded.subject_iri, record_type: request.record_type},
      written_subject_iris: Map.get(command_outcome, :written_subject_iris, [encoded.subject_iri]),
      metadata: request.metadata
    }
  end

  defp query_opts(%Request{} = request) do
    query = request.query || %{}

    [
      server: request.store,
      limit: map_get(query, :limit, 50),
      offset: map_get(query, :offset, 0)
    ]
  end

  defp normalize_error(:ok, _request), do: {:error, UnavailableError.exception(stage: :unknown, reason: :unexpected_ok)}
  defp normalize_error({:error, %_{} = error}, _request), do: {:error, error}

  defp normalize_error({:error, {:conflict, identity, conflicting_subject_iri}}, request) do
    {:error,
     ConflictError.exception(
       record_type: request.record_type,
       identity: identity,
       subject_iri: request.subject_iri,
       conflicting_subject_iri: conflicting_subject_iri
     )}
  end

  defp normalize_error({:error, {:stale_write, subject_iri}}, request) do
    {:error,
     ConflictError.exception(
       record_type: request.record_type,
       identity: :expected_updated_at,
       subject_iri: subject_iri,
       conflicting_subject_iri: subject_iri
     )}
  end

  defp normalize_error({:error, :control_plane_invalid_query, diagnostics}, _request) do
    {:error, ValidationError.exception(stage: diagnostics.stage, reason: diagnostics.reason, errors: [diagnostics])}
  end

  defp normalize_error({:error, reason}, request) do
    {:error,
     ValidationError.exception(
       stage: request.operation || :store_request,
       reason: reason,
       errors: [%{field: :record, reason: reason}]
     )}
  end

  defp normalize_error(other, request) do
    {:error, UnavailableError.exception(stage: request.operation || :store_request, reason: other)}
  end

  defp map_get(map, key, default), do: Map.get(map, key) || Map.get(map, Atom.to_string(key), default)
  defp control_iri(local), do: RDF.iri(JidoCode.ControlPlane.SemanticIdentity.ontology_namespace() <> local)
end
