defmodule JidoCode.MemoryGraph.DurableMemoryEnvelope do
  # covers: architecture.memory_capture_plane.durable_memories_are_inserted_through_explicit_classification_and_adoption
  # covers: architecture.memory_capture_plane.memory_capture_requires_explicit_repo_work_and_actor_context
  # covers: architecture.memory_capture_plane.transient_llm_output_is_not_inserted_as_memory_without_adoption
  # covers: architecture.memory_graph.memory_graph_links_to_source_code_entities_by_stable_iri
  # covers: architecture.memory_ontology.coding_memory_types_extend_core_memory_model
  # covers: architecture.memory_ontology.memories_anchor_to_code_entities_and_symbols
  # covers: architecture.memory_ontology.decision_structure_supports_supersession_and_consequence
  @moduledoc false

  alias JidoCode.{MemoryGraph, SourceCodeGraph}
  alias JidoCode.MemoryGraph.GovernedReference

  @memory_kinds ~w(fact decision lesson_learned invariant convention known_issue open_question pattern anti_pattern)a

  @kind_paths %{
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

  @kind_class_names %{
    fact: "Fact",
    decision: "Decision",
    lesson_learned: "LessonLearned",
    invariant: "Invariant",
    convention: "Convention",
    known_issue: "KnownIssue",
    open_question: "OpenQuestion",
    pattern: "Pattern",
    anti_pattern: "AntiPattern"
  }

  @decision_statuses %{
    proposed: "proposed",
    accepted: "accepted",
    superseded: "superseded",
    rejected: "rejected"
  }

  @type graph_context :: map()
  @type normalized_envelope :: map()

  @spec memory_kinds() :: [atom()]
  def memory_kinds, do: @memory_kinds

  @spec supported_kind?(atom() | String.t() | nil) :: boolean()
  def supported_kind?(kind) when is_atom(kind), do: kind in @memory_kinds

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

  for kind <- @memory_kinds do
    @spec unquote(kind)(keyword() | map()) :: map()
    def unquote(kind)(attrs), do: build(unquote(kind), attrs)
  end

  @spec normalize(map(), graph_context()) :: {:ok, normalized_envelope()} | {:error, atom(), map()}
  def normalize(capture, graph_context) when is_map(capture) and is_map(graph_context) do
    with {:ok, kind} <- normalize_kind(Map.get(capture, :kind) || Map.get(capture, "kind")),
         {:ok, classification} <- classification(capture),
         {:ok, managed_repo_id} <- required_string(graph_context.managed_repo_id, :managed_repo_id),
         {:ok, workspace_path} <- required_string(graph_context.workspace_path, :workspace_path),
         {:ok, actor_id} <- actor_id(capture),
         {:ok, revision} <- revision(graph_context, capture),
         {:ok, session_id} <- session_id(capture),
         {:ok, content} <- required_string(Map.get(capture, :content) || Map.get(capture, "content"), :content),
         {:ok, timestamp} <- normalize_datetime(Map.get(capture, :timestamp) || Map.get(capture, "timestamp")),
         {:ok, confidence} <- maybe_confidence(kind, capture),
         {:ok, rationale} <- maybe_required_text(kind, capture, :rationale),
         {:ok, lesson_context} <- maybe_required_text(kind, capture, :context) do
      resource_id =
        Map.get(capture, :id) ||
          Map.get(capture, "id") ||
          default_resource_id(kind, session_id, revision, content, classification)

      related_memory_ids =
        normalize_string_list(Map.get(capture, :related_memory_ids) || Map.get(capture, "related_memory_ids"))

      alternative_considered_ids =
        normalize_string_list(
          Map.get(capture, :alternative_considered_ids) || Map.get(capture, "alternative_considered_ids")
        )

      consequence_memory_ids =
        normalize_string_list(Map.get(capture, :consequence_memory_ids) || Map.get(capture, "consequence_memory_ids"))

      supersedes_memory_id =
        normalize_optional_string(Map.get(capture, :supersedes_memory_id) || Map.get(capture, "supersedes_memory_id"))

      decision_status =
        normalize_decision_status(Map.get(capture, :decision_status) || Map.get(capture, "decision_status"))

      tags = normalize_string_list(Map.get(capture, :tags) || Map.get(capture, "tags"))
      workflow = normalize_optional_string(Map.get(capture, :workflow) || Map.get(capture, "workflow"))
      work_item_id = normalize_optional_string(Map.get(capture, :work_item_id) || Map.get(capture, "work_item_id"))
      source_code_anchors = source_code_anchors(capture, managed_repo_id)

      with {:ok, governed_references} <- governed_references(capture, managed_repo_id) do
        governed_artifacts = governed_artifacts(governed_references)
        supported_by_artifacts = supported_by_artifacts(capture, managed_repo_id)
        confidence_source = confidence_source_artifact(capture, managed_repo_id)
        evidence_artifacts = evidence_artifacts(capture, managed_repo_id)

        {:ok,
         %{
           kind: kind,
           graph_name: MemoryGraph.memory_graph_name(),
           named_graph_iri: MemoryGraph.memory_named_graph_iri(),
           managed_repo_id: managed_repo_id,
           workspace_path: workspace_path,
           revision: revision,
           actor_id: actor_id,
           resource_id: resource_id,
           resource_iri: resource_iri(kind, graph_context, resource_id),
           resource_class_iri: resource_class_iri(kind),
           session_id: session_id,
           session_iri: session_iri(graph_context, session_id),
           actor_iri: actor_iri(graph_context, actor_id),
           revision_iri: revision_iri(graph_context, revision),
           workflow: workflow,
           work_item_id: work_item_id,
           content: content,
           timestamp: timestamp,
           confidence: confidence,
           rationale: rationale,
           lesson_context: lesson_context,
           classification: classification,
           source_code_anchors: source_code_anchors,
           tags: tags,
           related_memory_iris: Enum.map(related_memory_ids, &existing_memory_iri(graph_context, &1)),
           alternative_considered_iris: Enum.map(alternative_considered_ids, &existing_memory_iri(graph_context, &1)),
           consequence_memory_iris: Enum.map(consequence_memory_ids, &existing_memory_iri(graph_context, &1)),
           supersedes_iri: supersedes_memory_id && existing_memory_iri(graph_context, supersedes_memory_id),
           decision_status_iri: decision_status && decision_status_iri(decision_status),
           observed_at_revision_iri: revision_iri(graph_context, revision),
           valid_for_revision_iri: revision_iri(graph_context, revision),
           governed_references: governed_references,
           governed_artifacts: governed_artifacts,
           supported_by_artifacts: supported_by_artifacts,
           confidence_source: confidence_source,
           evidence_artifacts: evidence_artifacts
         }}
      end
    end
  end

  defp normalize_kind(kind) when kind in @memory_kinds, do: {:ok, kind}

  defp normalize_kind(kind) when is_binary(kind) do
    case String.trim(kind) do
      "fact" -> {:ok, :fact}
      "decision" -> {:ok, :decision}
      "lesson_learned" -> {:ok, :lesson_learned}
      "invariant" -> {:ok, :invariant}
      "convention" -> {:ok, :convention}
      "known_issue" -> {:ok, :known_issue}
      "open_question" -> {:ok, :open_question}
      "pattern" -> {:ok, :pattern}
      "anti_pattern" -> {:ok, :anti_pattern}
      _other -> {:error, :invalid_memory_capture, %{field: :kind, reason: :unsupported_kind}}
    end
  end

  defp normalize_kind(_kind), do: {:error, :invalid_memory_capture, %{field: :kind, reason: :missing}}

  defp classification(capture) do
    classification =
      Map.get(capture, :classification) ||
        Map.get(capture, "classification") ||
        Map.get(capture, :adoption) ||
        Map.get(capture, "adoption") ||
        %{}

    normalized = normalize_map(classification)

    source =
      normalize_optional_string(
        normalized["source"] || normalized["adopted_via"] || normalized["adoption_source"] ||
          normalized["classification_source"]
      )

    reason =
      normalize_optional_string(
        normalized["reason"] || normalized["adoption_reason"] || normalized["classification_reason"]
      )

    case {source, reason} do
      {source, reason} when is_binary(source) and is_binary(reason) ->
        {:ok,
         %{
           source: source,
           reason: reason,
           label:
             normalize_optional_string(normalized["label"]) ||
               "#{source} durable memory adoption"
         }}

      _other ->
        {:error, :invalid_memory_capture, %{field: :classification, reason: :missing}}
    end
  end

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

  defp maybe_confidence(:fact, capture) do
    case normalize_decimal(Map.get(capture, :confidence) || Map.get(capture, "confidence")) do
      nil -> {:error, :invalid_memory_capture, %{field: :confidence, reason: :missing}}
      value -> {:ok, value}
    end
  end

  defp maybe_confidence(_kind, capture) do
    {:ok, normalize_decimal(Map.get(capture, :confidence) || Map.get(capture, "confidence"))}
  end

  defp maybe_required_text(:decision, capture, :rationale) do
    case normalize_optional_string(Map.get(capture, :rationale) || Map.get(capture, "rationale")) do
      nil -> {:error, :invalid_memory_capture, %{field: :rationale, reason: :missing}}
      value -> {:ok, value}
    end
  end

  defp maybe_required_text(:lesson_learned, capture, :context) do
    case normalize_optional_string(Map.get(capture, :context) || Map.get(capture, "context")) do
      nil -> {:error, :invalid_memory_capture, %{field: :context, reason: :missing}}
      value -> {:ok, value}
    end
  end

  defp maybe_required_text(_kind, capture, field) do
    {:ok, normalize_optional_string(Map.get(capture, field) || Map.get(capture, Atom.to_string(field)))}
  end

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

  defp source_code_anchors(capture, managed_repo_id) do
    anchors = normalize_map(Map.get(capture, :anchors) || Map.get(capture, "anchors") || %{})

    module_iri =
      case normalize_optional_string(anchors["module_iri"] || anchors["moduleIRI"]) do
        nil ->
          case normalize_optional_string(anchors["module_name"] || anchors["moduleName"]) do
            nil -> nil
            module_name -> RDF.iri("#{SourceCodeGraph.base_iri(managed_repo_id)}#{module_name}")
          end

        iri ->
          RDF.iri(iri)
      end

    [
      about_repository: optional_iri(anchors["repository_iri"]),
      about_file: optional_iri(anchors["file_iri"]),
      about_module: module_iri,
      about_function: optional_iri(anchors["function_iri"]),
      about_test: optional_iri(anchors["test_iri"]),
      about_config: optional_iri(anchors["config_iri"]),
      affects_symbol: optional_iri(anchors["subject_iri"]) || module_iri
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp governed_references(capture, managed_repo_id) do
    GovernedReference.normalize_context(managed_repo_id, governed_reference_input(capture))
  end

  defp governed_artifacts(governed_references) when is_list(governed_references) do
    Enum.map(governed_references, fn reference ->
      %{
        kind: reference.kind,
        id: reference.id,
        iri: RDF.iri(reference.iri),
        label: reference.label
      }
    end)
  end

  defp supported_by_artifacts(capture, managed_repo_id) do
    capture
    |> Map.get(:supported_by, Map.get(capture, "supported_by"))
    |> normalize_artifact_list(managed_repo_id, "supported")
  end

  defp evidence_artifacts(capture, managed_repo_id) do
    capture
    |> Map.get(:evidence_artifacts, Map.get(capture, "evidence_artifacts"))
    |> normalize_artifact_list(managed_repo_id, "evidence")
  end

  defp confidence_source_artifact(capture, managed_repo_id) do
    capture
    |> Map.get(:confidence_source, Map.get(capture, "confidence_source"))
    |> normalize_artifact(managed_repo_id, "confidence")
  end

  defp normalize_artifact_list(nil, _managed_repo_id, _prefix), do: []

  defp normalize_artifact_list(list, managed_repo_id, prefix) when is_list(list) do
    Enum.flat_map(list, fn item ->
      case normalize_artifact(item, managed_repo_id, prefix) do
        nil -> []
        artifact -> [artifact]
      end
    end)
  end

  defp normalize_artifact_list(value, managed_repo_id, prefix),
    do: List.wrap(normalize_artifact(value, managed_repo_id, prefix)) |> Enum.reject(&is_nil/1)

  defp normalize_artifact(nil, _managed_repo_id, _prefix), do: nil

  defp normalize_artifact(value, managed_repo_id, prefix) when is_binary(value) do
    artifact("#{prefix}/#{value}", value, managed_repo_id)
  end

  defp normalize_artifact(value, managed_repo_id, prefix) when is_map(value) do
    normalized = normalize_map(value)
    id = normalized["id"] || normalized["iri"] || normalized["value"]
    label = normalized["label"] || normalized["summary"] || id

    case normalize_optional_string(id) do
      nil -> nil
      artifact_id -> artifact("#{prefix}/#{artifact_id}", label, managed_repo_id)
    end
  end

  defp normalize_artifact(_value, _managed_repo_id, _prefix), do: nil

  defp governed_reference_input(capture) do
    Map.get(capture, :governed_references) ||
      Map.get(capture, "governed_references") ||
      Map.get(capture, :governed_context) ||
      Map.get(capture, "governed_context")
  end

  defp artifact(path, label, managed_repo_id) do
    %{
      iri: RDF.iri("#{MemoryGraph.base_iri(managed_repo_id)}artifact/#{URI.encode(path)}"),
      label: label
    }
  end

  defp optional_iri(nil), do: nil

  defp optional_iri(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      iri -> RDF.iri(iri)
    end
  end

  defp optional_iri(_value), do: nil

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

  defp resource_iri(kind, graph_context, resource_id) do
    RDF.iri(
      "#{MemoryGraph.base_iri(graph_context.managed_repo_id)}#{Map.fetch!(@kind_paths, kind)}/#{URI.encode(resource_id)}"
    )
  end

  defp existing_memory_iri(graph_context, memory_id) do
    RDF.iri("#{MemoryGraph.base_iri(graph_context.managed_repo_id)}memory/#{URI.encode(memory_id)}")
  end

  defp resource_class_iri(kind) do
    RDF.iri("https://jido.run/ontology/memory##{Map.fetch!(@kind_class_names, kind)}")
  end

  defp decision_status_iri(status) when is_binary(status) do
    RDF.iri("https://jido.run/ontology/memory##{status}")
  end

  defp default_resource_id(kind, session_id, revision, content, classification) do
    {kind, session_id, revision, content, classification}
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

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_string_list(value) when is_binary(value), do: [String.trim(value)]
  defp normalize_string_list(_value), do: []

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
