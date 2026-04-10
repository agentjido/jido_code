defmodule JidoCode.MemoryGraph.DurableMemoryUpdateEnvelope do
  # covers: architecture.memory_capture_plane.validation_and_invalidation_follow_revision_and_test_evidence
  # covers: architecture.memory_capture_plane.memory_capture_requires_explicit_repo_work_and_actor_context
  # covers: architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
  # covers: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  # covers: architecture.memory_ontology.change_and_revision_provenance_is_explicit
  # covers: architecture.memory_ontology.decision_structure_supports_supersession_and_consequence
  # covers: architecture.memory_ontology.freshness_evidence_and_validation_metadata_are_explicit
  @moduledoc false

  alias JidoCode.MemoryGraph

  @update_kinds ~w(memory_validation memory_invalidation decision_supersession)a

  @memory_kind_paths %{
    fact: "fact",
    decision: "decision",
    lesson_learned: "lesson_learned",
    invariant: "invariant",
    convention: "convention",
    known_issue: "known_issue",
    open_question: "open_question",
    pattern: "pattern",
    anti_pattern: "anti_pattern"
  }

  @decision_statuses %{
    proposed: "proposed",
    accepted: "accepted",
    superseded: "superseded",
    rejected: "rejected"
  }

  @type graph_context :: map()
  @type normalized_envelope :: map()

  @spec update_kinds() :: [atom()]
  def update_kinds, do: @update_kinds

  @spec supported_kind?(atom() | String.t() | nil) :: boolean()
  def supported_kind?(kind) when is_atom(kind), do: kind in @update_kinds

  def supported_kind?(kind) when is_binary(kind) do
    case normalize_kind(kind) do
      {:ok, _kind} -> true
      _other -> false
    end
  end

  def supported_kind?(_kind), do: false

  @spec build(atom(), keyword() | map()) :: map()
  def build(kind, attrs) when is_list(attrs), do: build(kind, Map.new(attrs))
  def build(kind, attrs) when is_map(attrs), do: Map.put(attrs, :kind, kind)

  def memory_validation(attrs), do: build(:memory_validation, attrs)
  def memory_invalidation(attrs), do: build(:memory_invalidation, attrs)
  def decision_supersession(attrs), do: build(:decision_supersession, attrs)

  @spec normalize(map(), graph_context()) :: {:ok, normalized_envelope()} | {:error, atom(), map()}
  def normalize(capture, graph_context) when is_map(capture) and is_map(graph_context) do
    with {:ok, kind} <- normalize_kind(Map.get(capture, :kind) || Map.get(capture, "kind")),
         {:ok, managed_repo_id} <- required_string(graph_context.managed_repo_id, :managed_repo_id),
         {:ok, workspace_path} <- required_string(graph_context.workspace_path, :workspace_path),
         {:ok, actor_id} <- actor_id(capture),
         {:ok, revision} <- revision(graph_context, capture),
         {:ok, session_id} <- session_id(capture),
         {:ok, timestamp} <- normalize_datetime(Map.get(capture, :timestamp) || Map.get(capture, "timestamp")),
         {:ok, memory_iri} <- memory_target_iri(capture, graph_context),
         {:ok, stale_reason} <- stale_reason(kind, capture),
         {:ok, decision_status} <- decision_status(kind, capture),
         {:ok, superseded_status} <- superseded_status(kind, capture),
         {:ok, superseded_memory_iri} <- superseded_memory_iri(kind, capture, graph_context),
         {:ok, freshness_score} <- freshness_score(kind, capture) do
      test_run = test_run(capture, managed_repo_id)
      supported_by_artifacts = supported_by_artifacts(capture, managed_repo_id)
      evidence_artifacts = evidence_artifacts(capture, managed_repo_id)
      confidence_source = confidence_source_artifact(capture, managed_repo_id)

      update_id =
        default_update_id(
          kind,
          session_id,
          revision,
          memory_iri,
          superseded_memory_iri,
          timestamp
        )

      {:ok,
       %{
         kind: kind,
         graph_name: MemoryGraph.memory_graph_name(),
         named_graph_iri: MemoryGraph.memory_named_graph_iri(),
         managed_repo_id: managed_repo_id,
         workspace_path: workspace_path,
         actor_id: actor_id,
         revision: revision,
         session_id: session_id,
         timestamp: timestamp,
         memory_iri: memory_iri,
         superseded_memory_iri: superseded_memory_iri,
         update_id: update_id,
         update_iri: update_iri(graph_context, update_id),
         session_iri: session_iri(graph_context, session_id),
         actor_iri: actor_iri(graph_context, actor_id),
         revision_iri: revision_iri(graph_context, revision),
         valid_for_revision_iri: revision_iri(graph_context, revision),
         invalidated_by_revision_iri: revision_iri(graph_context, revision),
         freshness_score: freshness_score,
         stale_reason: stale_reason,
         decision_status_iri: decision_status && decision_status_iri(decision_status),
         superseded_status_iri: superseded_status && decision_status_iri(superseded_status),
         test_run: test_run,
         supported_by_artifacts: supported_by_artifacts,
         evidence_artifacts: evidence_artifacts,
         confidence_source: confidence_source
       }}
    end
  end

  defp normalize_kind(kind) when kind in @update_kinds, do: {:ok, kind}

  defp normalize_kind(kind) when is_binary(kind) do
    case String.trim(kind) do
      "memory_validation" -> {:ok, :memory_validation}
      "memory_invalidation" -> {:ok, :memory_invalidation}
      "decision_supersession" -> {:ok, :decision_supersession}
      _other -> {:error, :invalid_memory_capture, %{field: :kind, reason: :unsupported_kind}}
    end
  end

  defp normalize_kind(_kind), do: {:error, :invalid_memory_capture, %{field: :kind, reason: :missing}}

  defp actor_id(capture) do
    capture
    |> Map.get(:actor_id, Map.get(capture, "actor_id"))
    |> required_string(:actor_id)
  end

  defp revision(graph_context, capture) do
    capture_revision = Map.get(capture, :revision) || Map.get(capture, "revision")

    graph_revision =
      get_in(graph_context, [:revision_metadata, :current_revision]) ||
        get_in(graph_context, [:revision_metadata, :requested_revision])

    required_string(capture_revision || graph_revision, :revision)
  end

  defp session_id(capture) do
    capture
    |> Map.get(:session_id, Map.get(capture, "session_id"))
    |> required_string(:session_id)
  end

  defp memory_target_iri(capture, graph_context) do
    case explicit_memory_iri(capture, [:memory_iri, "memory_iri", :resource_iri, "resource_iri"]) do
      {:ok, iri} ->
        {:ok, iri}

      :error ->
        memory_id =
          normalize_optional_string(
            Map.get(capture, :memory_id) ||
              Map.get(capture, "memory_id") ||
              Map.get(capture, :resource_id) ||
              Map.get(capture, "resource_id")
          )

        case memory_id do
          nil ->
            {:error, :invalid_memory_capture, %{field: :memory_iri, reason: :missing}}

          id ->
            kind =
              normalize_optional_memory_kind(
                Map.get(capture, :memory_kind) ||
                  Map.get(capture, "memory_kind") ||
                  Map.get(capture, :resource_kind) ||
                  Map.get(capture, "resource_kind")
              )

            {:ok, memory_iri(graph_context, id, kind)}
        end
    end
  end

  defp superseded_memory_iri(:decision_supersession, capture, graph_context) do
    case explicit_memory_iri(capture, [
           :superseded_memory_iri,
           "superseded_memory_iri",
           :superseded_resource_iri,
           "superseded_resource_iri"
         ]) do
      {:ok, iri} ->
        {:ok, iri}

      :error ->
        superseded_memory_id =
          normalize_optional_string(
            Map.get(capture, :superseded_memory_id) ||
              Map.get(capture, "superseded_memory_id") ||
              Map.get(capture, :superseded_resource_id) ||
              Map.get(capture, "superseded_resource_id")
          )

        case superseded_memory_id do
          nil ->
            {:error, :invalid_memory_capture, %{field: :superseded_memory_iri, reason: :missing}}

          id ->
            kind =
              normalize_optional_memory_kind(
                Map.get(capture, :superseded_memory_kind) ||
                  Map.get(capture, "superseded_memory_kind") ||
                  :decision
              )

            {:ok, memory_iri(graph_context, id, kind)}
        end
    end
  end

  defp superseded_memory_iri(_kind, _capture, _graph_context), do: {:ok, nil}

  defp stale_reason(:memory_invalidation, capture) do
    capture
    |> Map.get(
      :stale_reason,
      Map.get(capture, "stale_reason") || Map.get(capture, :reason) || Map.get(capture, "reason")
    )
    |> normalize_required_reason(:stale_reason)
  end

  defp stale_reason(:decision_supersession, capture) do
    {:ok,
     normalize_optional_string(Map.get(capture, :stale_reason) || Map.get(capture, "stale_reason")) ||
       "superseded"}
  end

  defp stale_reason(_kind, _capture), do: {:ok, nil}

  defp decision_status(:decision_supersession, capture) do
    case normalize_decision_status(
           Map.get(capture, :decision_status) || Map.get(capture, "decision_status") || :accepted
         ) do
      nil -> {:error, :invalid_memory_capture, %{field: :decision_status, reason: :invalid}}
      status -> {:ok, status}
    end
  end

  defp decision_status(_kind, _capture), do: {:ok, nil}

  defp superseded_status(:decision_supersession, capture) do
    case normalize_decision_status(
           Map.get(capture, :superseded_decision_status) ||
             Map.get(capture, "superseded_decision_status") ||
             :superseded
         ) do
      nil -> {:error, :invalid_memory_capture, %{field: :superseded_decision_status, reason: :invalid}}
      status -> {:ok, status}
    end
  end

  defp superseded_status(_kind, _capture), do: {:ok, nil}

  defp freshness_score(:memory_validation, capture) do
    score =
      normalize_decimal(Map.get(capture, :freshness_score) || Map.get(capture, "freshness_score") || 1.0)

    if is_nil(score) do
      {:error, :invalid_memory_capture, %{field: :freshness_score, reason: :invalid}}
    else
      {:ok, score}
    end
  end

  defp freshness_score(:memory_invalidation, capture) do
    score =
      normalize_decimal(Map.get(capture, :freshness_score) || Map.get(capture, "freshness_score") || 0.0)

    if is_nil(score) do
      {:error, :invalid_memory_capture, %{field: :freshness_score, reason: :invalid}}
    else
      {:ok, score}
    end
  end

  defp freshness_score(:decision_supersession, capture) do
    score =
      normalize_decimal(Map.get(capture, :freshness_score) || Map.get(capture, "freshness_score") || 1.0)

    if is_nil(score) do
      {:error, :invalid_memory_capture, %{field: :freshness_score, reason: :invalid}}
    else
      {:ok, score}
    end
  end

  defp normalize_datetime(nil), do: {:ok, DateTime.utc_now() |> DateTime.truncate(:second)}
  defp normalize_datetime(%DateTime{} = value), do: {:ok, DateTime.truncate(value, :second)}

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, DateTime.truncate(datetime, :second)}
      _other -> {:error, :invalid_memory_capture, %{field: :timestamp, reason: :invalid_datetime}}
    end
  end

  defp normalize_datetime(_value),
    do: {:error, :invalid_memory_capture, %{field: :timestamp, reason: :invalid_datetime}}

  defp test_run(capture, managed_repo_id) do
    case normalize_artifact(
           Map.get(capture, :test_run) || Map.get(capture, "test_run"),
           managed_repo_id,
           "test_run",
           :workflow
         ) do
      nil -> nil
      artifact -> Map.put(artifact, :class, :test_run)
    end
  end

  defp supported_by_artifacts(capture, managed_repo_id) do
    capture
    |> Map.get(:supported_by, Map.get(capture, "supported_by"))
    |> normalize_artifact_list(managed_repo_id, "supported", :memory)
  end

  defp evidence_artifacts(capture, managed_repo_id) do
    capture
    |> Map.get(:evidence_artifacts, Map.get(capture, "evidence_artifacts"))
    |> normalize_artifact_list(managed_repo_id, "evidence", :memory)
  end

  defp confidence_source_artifact(capture, managed_repo_id) do
    capture
    |> Map.get(:confidence_source, Map.get(capture, "confidence_source"))
    |> normalize_artifact(managed_repo_id, "confidence", :memory)
  end

  defp normalize_artifact_list(nil, _managed_repo_id, _prefix, _space), do: []

  defp normalize_artifact_list(list, managed_repo_id, prefix, space) when is_list(list) do
    Enum.flat_map(list, fn item ->
      case normalize_artifact(item, managed_repo_id, prefix, space) do
        nil -> []
        artifact -> [artifact]
      end
    end)
  end

  defp normalize_artifact_list(value, managed_repo_id, prefix, space),
    do: List.wrap(normalize_artifact(value, managed_repo_id, prefix, space)) |> Enum.reject(&is_nil/1)

  defp normalize_artifact(nil, _managed_repo_id, _prefix, _space), do: nil

  defp normalize_artifact(value, managed_repo_id, prefix, space) when is_binary(value) do
    artifact("#{prefix}/#{value}", value, managed_repo_id, space)
  end

  defp normalize_artifact(value, managed_repo_id, prefix, space) when is_map(value) do
    normalized = normalize_map(value)
    id = normalized["id"] || normalized["iri"] || normalized["value"]
    label = normalized["label"] || normalized["summary"] || id

    case normalize_optional_string(id) do
      nil -> nil
      artifact_id -> artifact("#{prefix}/#{artifact_id}", label, managed_repo_id, space)
    end
  end

  defp normalize_artifact(_value, _managed_repo_id, _prefix, _space), do: nil

  defp artifact(path, label, managed_repo_id, :memory) do
    %{
      iri: RDF.iri("#{MemoryGraph.base_iri(managed_repo_id)}artifact/#{URI.encode(path)}"),
      label: label
    }
  end

  defp artifact(path, label, managed_repo_id, :workflow) do
    %{
      iri: RDF.iri("#{MemoryGraph.workflow_provenance_base_iri(managed_repo_id)}#{URI.encode(path)}"),
      label: label
    }
  end

  defp explicit_memory_iri(capture, keys) do
    keys
    |> Enum.find_value(fn key -> normalize_optional_string(Map.get(capture, key)) end)
    |> case do
      nil -> :error
      iri -> {:ok, RDF.iri(iri)}
    end
  end

  defp memory_iri(graph_context, memory_id, nil) do
    RDF.iri("#{MemoryGraph.base_iri(graph_context.managed_repo_id)}memory/#{URI.encode(memory_id)}")
  end

  defp memory_iri(graph_context, memory_id, memory_kind) do
    RDF.iri(
      "#{MemoryGraph.base_iri(graph_context.managed_repo_id)}#{Map.fetch!(@memory_kind_paths, memory_kind)}/#{URI.encode(memory_id)}"
    )
  end

  defp normalize_optional_memory_kind(value) when is_atom(value) do
    if Map.has_key?(@memory_kind_paths, value), do: value, else: nil
  end

  defp normalize_optional_memory_kind(value) when is_binary(value) do
    case String.trim(value) do
      "fact" -> :fact
      "decision" -> :decision
      "lesson_learned" -> :lesson_learned
      "invariant" -> :invariant
      "convention" -> :convention
      "known_issue" -> :known_issue
      "open_question" -> :open_question
      "pattern" -> :pattern
      "anti_pattern" -> :anti_pattern
      _other -> nil
    end
  end

  defp normalize_optional_memory_kind(_value), do: nil

  defp normalize_decision_status(value) when is_atom(value), do: Map.get(@decision_statuses, value)

  defp normalize_decision_status(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed in Map.values(@decision_statuses), do: trimmed, else: nil
  end

  defp normalize_decision_status(_value), do: nil

  defp normalize_decimal(nil), do: nil
  defp normalize_decimal(value) when is_float(value), do: value
  defp normalize_decimal(value) when is_integer(value), do: value / 1

  defp normalize_decimal(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {parsed, ""} -> parsed
      _other -> nil
    end
  end

  defp normalize_decimal(_value), do: nil

  defp normalize_required_reason(value, _field) when is_atom(value), do: {:ok, Atom.to_string(value)}

  defp normalize_required_reason(value, field) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, :invalid_memory_capture, %{field: field, reason: :missing}}
      normalized -> {:ok, normalized}
    end
  end

  defp normalize_required_reason(_value, field),
    do: {:error, :invalid_memory_capture, %{field: field, reason: :missing}}

  defp session_iri(graph_context, session_id) do
    RDF.iri(
      "#{MemoryGraph.workflow_provenance_base_iri(graph_context.managed_repo_id)}work_session/#{URI.encode(session_id)}"
    )
  end

  defp actor_iri(graph_context, actor_id) do
    RDF.iri("#{MemoryGraph.workflow_provenance_base_iri(graph_context.managed_repo_id)}actor/#{URI.encode(actor_id)}")
  end

  defp revision_iri(graph_context, revision) do
    RDF.iri(
      "#{MemoryGraph.workflow_provenance_base_iri(graph_context.managed_repo_id)}revision/#{URI.encode(revision)}"
    )
  end

  defp update_iri(graph_context, update_id) do
    RDF.iri("#{MemoryGraph.base_iri(graph_context.managed_repo_id)}artifact/update/#{URI.encode(update_id)}")
  end

  defp decision_status_iri(status) when is_binary(status) do
    RDF.iri("https://jido.run/ontology/memory##{status}")
  end

  defp default_update_id(kind, session_id, revision, memory_iri, superseded_memory_iri, timestamp) do
    {kind, session_id, revision, to_string(memory_iri), to_string(superseded_memory_iri), timestamp}
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end

  defp required_string(value, field) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, :invalid_memory_capture, %{field: field, reason: :missing}}
      normalized -> {:ok, normalized}
    end
  end

  defp required_string(_value, field), do: {:error, :invalid_memory_capture, %{field: field, reason: :missing}}

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      Map.put(acc, normalized_key, nested_value)
    end)
  end

  defp normalize_map(_value), do: %{}
end
