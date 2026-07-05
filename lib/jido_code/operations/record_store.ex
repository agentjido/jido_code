defmodule JidoCode.Operations.RecordStore do
  @moduledoc """
  Store-backed operations records for ingress, synthesis, and work projections.
  """

  alias JidoCode.ControlPlane.Codecs.Registry
  alias JidoCode.ControlPlane.ProductStore
  alias JidoCode.ControlPlane.Store.ActorContext
  alias JidoCode.ControlPlane.Store.Errors.NotFoundError

  alias JidoCode.Operations.{
    Assessment,
    Event,
    ExternalObject,
    Intake,
    Observation,
    WorkItem
  }

  @control_plane_ns JidoCode.ControlPlane.SemanticIdentity.ontology_namespace()
  @unscoped_repo_id "unscoped"

  @record_modules %{
    intake: Intake,
    external_object: ExternalObject,
    observation: Observation,
    event: Event,
    assessment: Assessment,
    work_item: WorkItem
  }

  @id_fields %{
    intake: :intake_id,
    external_object: :external_object_id,
    observation: :observation_id,
    event: :event_id,
    assessment: :assessment_id,
    work_item: :work_item_id
  }

  @repo_scoped [:intake, :observation, :event, :assessment, :work_item]
  @datetime_fields %{
    intake: :received_at,
    observation: :observed_at,
    event: :occurred_at,
    assessment: :assessed_at,
    work_item: :opened_at
  }
  @map_fields [
    :payload,
    :source_metadata,
    :requested_by,
    :captured_by,
    :inputs,
    :assessment_metadata,
    :initiating_actor,
    :work_metadata,
    :metadata
  ]
  @top_level_key_aliases %{
    "id" => :id,
    "managed_repo_id" => :managed_repo_id,
    "managedRepoId" => :managed_repo_id,
    "intake_id" => :intake_id,
    "intakeId" => :intake_id,
    "external_object_id" => :external_object_id,
    "externalObjectId" => :external_object_id,
    "observation_id" => :observation_id,
    "observationId" => :observation_id,
    "event_id" => :event_id,
    "eventId" => :event_id,
    "assessment_id" => :assessment_id,
    "assessmentId" => :assessment_id,
    "work_item_id" => :work_item_id,
    "workItemId" => :work_item_id,
    "provider" => :provider,
    "provider_host" => :provider_host,
    "providerHost" => :provider_host,
    "object_type" => :object_type,
    "objectType" => :object_type,
    "external_id" => :external_id,
    "externalId" => :external_id,
    "canonical_key" => :canonical_key,
    "canonicalKey" => :canonical_key,
    "canonical_reference" => :canonical_reference,
    "canonicalReference" => :canonical_reference,
    "title" => :title,
    "url" => :url,
    "status" => :status,
    "recordStatus" => :status,
    "channel" => :channel,
    "intent" => :intent,
    "source" => :source,
    "category" => :category,
    "summary" => :summary,
    "correlation_key" => :correlation_key,
    "correlationKey" => :correlation_key,
    "priority" => :priority,
    "urgency" => :urgency,
    "recommended_action" => :recommended_action,
    "recommendedAction" => :recommended_action,
    "rationale" => :rationale,
    "dedup_key" => :dedup_key,
    "dedupKey" => :dedup_key,
    "payload" => :payload,
    "payloadJson" => :payload,
    "source_metadata" => :source_metadata,
    "sourceMetadataJson" => :source_metadata,
    "requested_by" => :requested_by,
    "requestedByJson" => :requested_by,
    "captured_by" => :captured_by,
    "capturedByJson" => :captured_by,
    "inputs" => :inputs,
    "inputsJson" => :inputs,
    "assessment_metadata" => :assessment_metadata,
    "assessmentMetadataJson" => :assessment_metadata,
    "initiating_actor" => :initiating_actor,
    "initiatingActorJson" => :initiating_actor,
    "work_metadata" => :work_metadata,
    "workMetadataJson" => :work_metadata,
    "audit_log" => :audit_log,
    "auditLogJson" => :audit_log,
    "metadata" => :metadata,
    "metadataJson" => :metadata,
    "received_at" => :received_at,
    "receivedAt" => :received_at,
    "observed_at" => :observed_at,
    "observedAt" => :observed_at,
    "occurred_at" => :occurred_at,
    "occurredAt" => :occurred_at,
    "assessed_at" => :assessed_at,
    "assessedAt" => :assessed_at,
    "opened_at" => :opened_at,
    "openedAt" => :opened_at,
    "last_assessed_at" => :last_assessed_at,
    "lastAssessedAt" => :last_assessed_at,
    "inserted_at" => :inserted_at,
    "insertedAt" => :inserted_at,
    "updated_at" => :updated_at,
    "updatedAt" => :updated_at
  }
  @known_atoms %{
    "github" => :github,
    "github_issue" => :github_issue,
    "github_pull_request" => :github_pull_request,
    "github_repository" => :github_repository,
    "open" => :open,
    "in_progress" => :in_progress,
    "blocked" => :blocked,
    "closed" => :closed,
    "completed" => :completed,
    "cancelled" => :cancelled,
    "suppressed" => :suppressed,
    "critical" => :critical,
    "high" => :high,
    "medium" => :medium,
    "low" => :low
  }

  @spec create(atom(), map(), keyword()) :: {:ok, struct()} | {:error, term()}
  def create(record_type, attrs, opts \\ []) when is_atom(record_type) and is_map(attrs) do
    with {:ok, record} <- record(record_type, attrs),
         {:ok, %{record: saved_record}} <-
           ProductStore.dispatch(:create, record_type, Keyword.merge([record: record], store_opts(opts))) do
      {:ok, to_struct(record_type, saved_record)}
    end
  end

  @spec upsert_external_object(map(), keyword()) :: {:ok, ExternalObject.t()} | {:error, term()}
  def upsert_external_object(attrs, opts \\ []) when is_map(attrs) do
    with canonical_key <- map_get(attrs, :canonical_key),
         {:ok, existing} <- get_external_object_by_canonical_key(canonical_key, opts),
         attrs <- maybe_preserve_id(attrs, existing, :external_object_id),
         {:ok, record} <- record(:external_object, attrs),
         {:ok, %{record: saved_record}} <-
           ProductStore.dispatch(:upsert, :external_object, Keyword.merge([record: record], store_opts(opts))) do
      {:ok, to_struct(:external_object, saved_record)}
    end
  end

  @spec update_work_item(WorkItem.t(), map(), keyword()) :: {:ok, WorkItem.t()} | {:error, term()}
  def update_work_item(%WorkItem{} = work_item, attrs, opts \\ []) when is_map(attrs) do
    with {:ok, record} <- record(:work_item, merge_work_item(work_item, attrs)),
         {:ok, %{record: saved_record}} <-
           ProductStore.dispatch(:update, :work_item, Keyword.merge([record: record], store_opts(opts))) do
      {:ok, to_struct(:work_item, saved_record)}
    end
  end

  @spec get(atom(), String.t(), keyword()) :: {:ok, struct() | nil} | {:error, term()}
  def get(record_type, id, opts \\ []) when is_atom(record_type) and is_binary(id) do
    with {:ok, records} <- list(record_type, %{}, opts) do
      {:ok, Enum.find(records, &(Map.get(&1, :id) == id))}
    end
  end

  @spec get_external_object_by_canonical_key(String.t() | nil, keyword()) ::
          {:ok, ExternalObject.t() | nil} | {:error, term()}
  def get_external_object_by_canonical_key(canonical_key, opts \\ [])

  def get_external_object_by_canonical_key(nil, _opts), do: {:ok, nil}

  def get_external_object_by_canonical_key(canonical_key, opts) when is_binary(canonical_key) do
    request_opts =
      Keyword.merge(
        [
          identity: %{
            identity: :unique_canonical_key,
            predicate_iri: RDF.iri(@control_plane_ns <> "canonicalKey"),
            value: canonical_key
          }
        ],
        store_opts(opts)
      )

    case ProductStore.dispatch(:get, :external_object, request_opts) do
      {:ok, %{projection: projection}} -> decode_projection(:external_object, projection)
      {:error, %NotFoundError{}} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec list(atom(), map(), keyword()) :: {:ok, [struct()]} | {:error, term()}
  def list(record_type, filters \\ %{}, opts \\ []) when is_atom(record_type) and is_map(filters) do
    case ProductStore.dispatch(
           :list,
           record_type,
           Keyword.merge([query: %{limit: 500, offset: 0}], store_opts(opts))
         ) do
      {:ok, %{projections: projections}} ->
        records =
          projections
          |> Enum.map(&decode_projection(record_type, &1))
          |> Enum.flat_map(fn
            {:ok, record} -> [record]
            {:error, _reason} -> []
          end)
          |> Enum.filter(&matches_filters?(&1, filters))

        {:ok, records}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec list_by_repo(atom(), String.t(), keyword()) :: {:ok, [struct()]} | {:error, term()}
  def list_by_repo(record_type, managed_repo_id, opts \\ []) when is_binary(managed_repo_id) do
    list(record_type, %{managed_repo_id: managed_repo_id}, opts)
  end

  @spec list_work_by_managed_repo(String.t(), keyword()) :: {:ok, [WorkItem.t()]} | {:error, term()}
  def list_work_by_managed_repo(managed_repo_id, opts \\ []) when is_binary(managed_repo_id) do
    list(:work_item, %{managed_repo_id: managed_repo_id}, opts)
  end

  @spec list_work_by_external_object(String.t(), keyword()) :: {:ok, [WorkItem.t()]} | {:error, term()}
  def list_work_by_external_object(external_object_id, opts \\ []) when is_binary(external_object_id) do
    list(:work_item, %{external_object_id: external_object_id}, opts)
  end

  @spec list_work_by_status(atom() | String.t(), keyword()) :: {:ok, [WorkItem.t()]} | {:error, term()}
  def list_work_by_status(status, opts \\ []) do
    list(:work_item, %{status: normalize_atom(status)}, opts)
  end

  @spec list_work_by_priority(atom() | String.t(), keyword()) :: {:ok, [WorkItem.t()]} | {:error, term()}
  def list_work_by_priority(priority, opts \\ []) do
    list(:work_item, %{priority: normalize_atom(priority)}, opts)
  end

  @spec repository_monitoring_summary(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def repository_monitoring_summary(managed_repo_id, opts \\ [])

  def repository_monitoring_summary(managed_repo_id, opts) when is_binary(managed_repo_id) do
    case list_work_by_managed_repo(managed_repo_id, opts) do
      {:ok, work_items} ->
        {:ok,
         %{
           managed_repo_id: managed_repo_id,
           status: :ready,
           degraded?: false,
           stale?: false,
           empty?: work_items == [],
           work_item_count: length(work_items),
           open_work_count: Enum.count(work_items, &(&1.status == :open)),
           status_counts: count_by(work_items, :status),
           priority_counts: count_by(work_items, :priority),
           work_items: work_items
         }}

      {:error, reason} ->
        {:ok,
         %{
           managed_repo_id: managed_repo_id,
           status: :degraded,
           degraded?: true,
           stale?: false,
           empty?: true,
           work_item_count: 0,
           open_work_count: 0,
           status_counts: %{},
           priority_counts: %{},
           work_items: [],
           error: reason
         }}
    end
  end

  def repository_monitoring_summary(_managed_repo_id, _opts),
    do: {:error, :invalid_managed_repo_id}

  def to_struct(record_type, record) when is_atom(record_type) and is_map(record) do
    struct!(Map.fetch!(@record_modules, record_type), struct_attrs(record_type, record))
    |> Map.put(:__metadata__, %{control_plane_record: record})
  end

  defp record(record_type, attrs) do
    with {:ok, id_field} <- id_field(record_type) do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      id = normalize_optional_string(map_get(attrs, id_field) || map_get(attrs, :id)) || Ecto.UUID.generate()

      record =
        attrs
        |> normalize_record_map()
        |> Map.put(id_field, id)
        |> Map.put_new(:inserted_at, now)
        |> Map.put(:updated_at, now)
        |> put_datetime(record_type, now)
        |> put_default_provider_host(record_type)
        |> put_repo_scope(record_type)
        |> put_default_metadata()

      {:ok, record}
    end
  end

  defp id_field(record_type) do
    case Map.fetch(@id_fields, record_type) do
      {:ok, id_field} -> {:ok, id_field}
      :error -> {:error, :unknown_operations_record_type}
    end
  end

  defp put_datetime(record, :work_item, now) do
    record
    |> Map.put_new(:opened_at, now)
    |> Map.put_new(:last_assessed_at, map_get(record, :opened_at) || now)
  end

  defp put_datetime(record, record_type, now) do
    case Map.fetch(@datetime_fields, record_type) do
      {:ok, datetime_field} -> Map.put_new(record, datetime_field, now)
      :error -> record
    end
  end

  defp put_default_provider_host(record, :external_object), do: Map.put_new(record, :provider_host, "github.com")
  defp put_default_provider_host(record, _record_type), do: record

  defp put_repo_scope(record, record_type) when record_type in @repo_scoped do
    case normalize_optional_string(map_get(record, :managed_repo_id)) do
      nil -> Map.put(record, :managed_repo_id, @unscoped_repo_id)
      managed_repo_id -> Map.put(record, :managed_repo_id, managed_repo_id)
    end
  end

  defp put_repo_scope(record, _record_type), do: record
  defp put_default_metadata(record), do: Map.put_new(record, :metadata, %{})

  defp maybe_preserve_id(attrs, nil, _id_field), do: attrs
  defp maybe_preserve_id(attrs, existing, id_field), do: Map.put(attrs, id_field, existing.id)

  defp merge_work_item(%WorkItem{} = work_item, attrs) do
    work_item
    |> Map.from_struct()
    |> Map.take([
      :id,
      :managed_repo_id,
      :assessment_id,
      :event_id,
      :external_object_id,
      :observation_id,
      :intake_id,
      :category,
      :status,
      :priority,
      :recommended_action,
      :summary,
      :dedup_key,
      :initiating_actor,
      :work_metadata,
      :audit_log,
      :opened_at,
      :last_assessed_at,
      :inserted_at
    ])
    |> Map.merge(attrs)
    |> Map.put(:work_item_id, work_item.id)
  end

  defp decode_projection(record_type, projection) do
    with {:ok, record} <- Registry.decode(record_type, projection) do
      {:ok, to_struct(record_type, record)}
    end
  end

  defp struct_attrs(:intake, record) do
    %{
      id: map_get(record, :intake_id),
      managed_repo_id: public_managed_repo_id(map_get(record, :managed_repo_id)),
      channel: map_get(record, :channel),
      intent: map_get(record, :intent),
      payload: decode_json_map(map_get(record, :payload, %{})),
      source_metadata: decode_json_map(map_get(record, :source_metadata, %{})),
      requested_by: decode_json_map(map_get(record, :requested_by, %{})),
      received_at: normalize_datetime(map_get(record, :received_at)),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
  end

  defp struct_attrs(:external_object, record) do
    %{
      id: map_get(record, :external_object_id),
      managed_repo_id: public_managed_repo_id(map_get(record, :managed_repo_id)),
      provider: normalize_atom(map_get(record, :provider)),
      object_type: normalize_atom(map_get(record, :object_type)),
      external_id: map_get(record, :external_id),
      canonical_key: map_get(record, :canonical_key),
      canonical_reference: map_get(record, :canonical_reference),
      title: map_get(record, :title),
      url: map_get(record, :url),
      status: map_get(record, :status),
      payload: decode_json_map(map_get(record, :payload, %{})),
      source_metadata: decode_json_map(map_get(record, :source_metadata, %{})),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
  end

  defp struct_attrs(:observation, record) do
    %{
      id: map_get(record, :observation_id),
      managed_repo_id: public_managed_repo_id(map_get(record, :managed_repo_id)),
      external_object_id: map_get(record, :external_object_id),
      source: map_get(record, :source),
      category: map_get(record, :category),
      summary: map_get(record, :summary),
      payload: decode_json_map(map_get(record, :payload, %{})),
      source_metadata: decode_json_map(map_get(record, :source_metadata, %{})),
      captured_by: decode_json_map(map_get(record, :captured_by, %{})),
      observed_at: normalize_datetime(map_get(record, :observed_at)),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
  end

  defp struct_attrs(:event, record) do
    %{
      id: map_get(record, :event_id),
      managed_repo_id: public_managed_repo_id(map_get(record, :managed_repo_id)),
      external_object_id: map_get(record, :external_object_id),
      observation_id: map_get(record, :observation_id),
      intake_id: map_get(record, :intake_id),
      category: map_get(record, :category),
      summary: map_get(record, :summary),
      correlation_key: map_get(record, :correlation_key),
      payload: decode_json_map(map_get(record, :payload, %{})),
      source_metadata: decode_json_map(map_get(record, :source_metadata, %{})),
      occurred_at: normalize_datetime(map_get(record, :occurred_at)),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
  end

  defp struct_attrs(:assessment, record) do
    %{
      id: map_get(record, :assessment_id),
      managed_repo_id: public_managed_repo_id(map_get(record, :managed_repo_id)),
      event_id: map_get(record, :event_id),
      external_object_id: map_get(record, :external_object_id),
      category: map_get(record, :category),
      summary: map_get(record, :summary),
      priority: normalize_atom(map_get(record, :priority)),
      urgency: normalize_atom(map_get(record, :urgency)),
      recommended_action: map_get(record, :recommended_action),
      rationale: map_get(record, :rationale),
      inputs: decode_json_map(map_get(record, :inputs, %{})),
      assessment_metadata: decode_json_map(map_get(record, :assessment_metadata, %{})),
      assessed_at: normalize_datetime(map_get(record, :assessed_at)),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
  end

  defp struct_attrs(:work_item, record) do
    %{
      id: map_get(record, :work_item_id),
      managed_repo_id: public_managed_repo_id(map_get(record, :managed_repo_id)),
      assessment_id: map_get(record, :assessment_id),
      event_id: map_get(record, :event_id),
      external_object_id: map_get(record, :external_object_id),
      observation_id: map_get(record, :observation_id),
      intake_id: map_get(record, :intake_id),
      category: map_get(record, :category),
      status: normalize_atom(map_get(record, :status)),
      priority: normalize_atom(map_get(record, :priority)),
      recommended_action: map_get(record, :recommended_action),
      summary: map_get(record, :summary),
      dedup_key: map_get(record, :dedup_key),
      initiating_actor: decode_json_map(map_get(record, :initiating_actor, %{})),
      work_metadata: decode_json_map(map_get(record, :work_metadata, %{})),
      audit_log: decode_json_list(map_get(record, :audit_log, [])),
      opened_at: normalize_datetime(map_get(record, :opened_at)),
      last_assessed_at: normalize_datetime(map_get(record, :last_assessed_at)),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
  end

  defp matches_filters?(record, filters) do
    Enum.all?(filters, fn {key, expected} ->
      actual = Map.get(record, key) || Map.get(record, to_string(key))

      case expected do
        expected_values when is_list(expected_values) -> actual in expected_values
        expected_value -> actual == expected_value
      end
    end)
  end

  defp normalize_record_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key = normalize_key(key)
      normalized_value = normalize_record_value(normalized_key, nested_value)
      Map.put(acc, normalized_key, normalized_value)
    end)
  end

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    Map.get(@top_level_key_aliases, key) ||
      Map.get(@top_level_key_aliases, Macro.underscore(key)) ||
      key
  end

  defp normalize_key(key), do: key |> to_string() |> normalize_key()

  defp normalize_record_value(key, value) when key in @map_fields and is_map(value), do: normalize_map(value)
  defp normalize_record_value(:audit_log, value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_record_value(_key, %DateTime{} = value), do: DateTime.truncate(value, :microsecond)
  defp normalize_record_value(_key, %NaiveDateTime{} = value), do: value
  defp normalize_record_value(_key, %_{} = value), do: value
  defp normalize_record_value(_key, value) when is_map(value), do: normalize_map(value)
  defp normalize_record_value(_key, value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_record_value(_key, value), do: value

  defp normalize_nested_value(%DateTime{} = value),
    do: value |> DateTime.truncate(:microsecond) |> DateTime.to_iso8601()

  defp normalize_nested_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp normalize_nested_value(%_{} = value), do: inspect(value)
  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp normalize_map(%_{}), do: %{}

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      Map.put(acc, to_string(key), normalize_nested_value(nested_value))
    end)
  end

  defp normalize_map(_value), do: %{}

  defp decode_json_map(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _other -> %{}
    end
  end

  defp decode_json_map(value) when is_map(value), do: normalize_map(value)
  defp decode_json_map(_value), do: %{}

  defp decode_json_list(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_list(decoded) -> decoded
      _other -> []
    end
  end

  defp decode_json_list(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp decode_json_list(_value), do: []

  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :microsecond)

  defp normalize_datetime(%NaiveDateTime{} = datetime) do
    case DateTime.from_naive(datetime, "Etc/UTC") do
      {:ok, parsed_datetime} -> normalize_datetime(parsed_datetime)
      _other -> nil
    end
  end

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> normalize_datetime(datetime)
      _other -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_atom(nil), do: nil
  defp normalize_atom(value) when is_atom(value), do: value

  defp normalize_atom(value) when is_binary(value) do
    normalized_value = value |> String.trim() |> String.downcase()

    case normalized_value do
      "" -> nil
      value -> Map.get(@known_atoms, value, value)
    end
  end

  defp count_by(records, field) do
    records
    |> Enum.map(&Map.get(&1, field))
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
  end

  defp public_managed_repo_id(@unscoped_repo_id), do: nil
  defp public_managed_repo_id(value), do: normalize_optional_string(value)

  defp map_get(map, key, default \\ nil)
  defp map_get(map, key, default) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  defp map_get(_map, _key, default), do: default

  defp store_opts(opts) do
    case Keyword.get(opts, :actor) do
      %ActorContext{} -> opts
      nil -> opts
      _legacy_actor -> Keyword.delete(opts, :actor)
    end
  end
end
