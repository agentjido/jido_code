defmodule JidoCode.MemoryGraph.HelperQueries do
  # covers: architecture.memory_graph_product_adoption.product_owned_memory_service_boundary
  # covers: architecture.memory_graph_product_adoption.memory_and_provenance_views_can_cross_link_to_source_code
  @moduledoc false

  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.GovernedReference

  @memory_kind_classes %{
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

  @provenance_kind_classes %{
    work_session: "WorkSession",
    agent_run: "AgentRun",
    tool_invocation: "ToolInvocation",
    prompt_turn: "PromptTurn",
    plan: "Plan",
    patch: "Patch",
    review: "Review"
  }

  @spec memories(String.t(), map()) :: String.t()
  def memories(managed_repo_id, params \\ %{}) when is_binary(managed_repo_id) do
    limit = positive_limit(params[:limit], 25)
    base_iri = MemoryGraph.base_iri(managed_repo_id)

    kind_values =
      params
      |> Map.get(:kinds)
      |> normalize_kind_values(@memory_kind_classes)

    kind_filter =
      if kind_values == [] do
        """
          VALUES ?kind {
            #{Enum.map_join(Map.values(@memory_kind_classes), "\n        ", &"jido:#{&1}")}
          }
        """
      else
        """
          VALUES ?kind {
            #{Enum.map_join(kind_values, "\n        ", &"jido:#{&1}")}
          }
        """
      end

    content_filter =
      case normalized_string(params[:content_contains]) do
        nil ->
          ""

        search ->
          """
            FILTER(CONTAINS(LCASE(STR(?content)), LCASE("#{escape_string(search)}")))
          """
      end

    anchor_filter =
      case normalized_string(params[:module_name]) do
        nil ->
          ""

        module_name ->
          module_iri = "#{MemoryGraph.source_code_base_iri(managed_repo_id)}#{module_name}"

          """
            FILTER(BOUND(?module) && STR(?module) = "#{escape_string(module_iri)}")
          """
      end

    governed_filter =
      governed_filter(
        managed_repo_id,
        Map.get(params, :governed_references, params[:artifact_paths]),
        "memory"
      )

    """
    SELECT ?memory ?kind ?content ?timestamp ?confidence ?decisionStatus ?freshnessScore ?lastValidatedAt ?staleReason ?module ?function ?subject ?governedRecord ?governedKind ?governedLabel ?conversationId ?turnId ?commandId ?conversationEvent ?clarificationState ?conversationScope ?conversationAttachmentMode ?conversationStatus ?conversationSource ?supportedArtifact ?supportedArtifactLabel ?supportedArtifactComment
    WHERE {
    #{kind_filter}
      ?memory a ?kind ;
              jido:content ?content ;
              jido:timestamp ?timestamp .
      OPTIONAL { ?memory jido:confidence ?confidence . }
      OPTIONAL { ?memory jido:decisionStatus ?decisionStatus . }
      OPTIONAL { ?memory jido:freshnessScore ?freshnessScore . }
      OPTIONAL { ?memory jido:lastValidatedAt ?lastValidatedAt . }
      OPTIONAL { ?memory jido:staleReason ?staleReason . }
      OPTIONAL { ?memory jido:aboutModule ?module . }
      OPTIONAL { ?memory jido:aboutFunction ?function . }
      OPTIONAL { ?memory jido:affectsSymbol ?subject . }
      OPTIONAL { ?memory jido:conversationId ?conversationId . }
      OPTIONAL { ?memory jido:conversationTurnId ?turnId . }
      OPTIONAL { ?memory jido:conversationCommandId ?commandId . }
      OPTIONAL { ?memory jido:conversationEvent ?conversationEvent . }
      OPTIONAL { ?memory jido:clarificationState ?clarificationState . }
      OPTIONAL { ?memory jido:conversationScope ?conversationScope . }
      OPTIONAL { ?memory jido:conversationAttachmentMode ?conversationAttachmentMode . }
      OPTIONAL { ?memory jido:conversationStatus ?conversationStatus . }
      OPTIONAL { ?memory jido:conversationSource ?conversationSource . }
      OPTIONAL {
        ?memory jido:supportedBy ?supportedArtifact .
        OPTIONAL { ?supportedArtifact rdfs:label ?supportedArtifactLabel . }
        OPTIONAL { ?supportedArtifact rdfs:comment ?supportedArtifactComment . }
      }
      OPTIONAL {
        VALUES (?governedPredicate ?governedKind) {
          (jido:aboutManagedRepo "managed_repo")
          (jido:aboutObservation "observation")
          (jido:aboutAssessment "assessment")
          (jido:aboutWorkItem "work_item")
          (jido:aboutRun "run")
          (jido:aboutEvidence "evidence")
          (jido:aboutChangeRequest "change_request")
          (jido:aboutDecision "decision")
        }
        ?memory ?governedPredicate ?governedRecord .
        OPTIONAL { ?governedRecord <https://jido.run/ontology/control-plane#recordLabel> ?governedRecordLabel . }
        OPTIONAL { ?governedRecord rdfs:label ?governedRecordRdfsLabel . }
        BIND(COALESCE(?governedRecordLabel, ?governedRecordRdfsLabel) AS ?governedLabel)
      }
    #{governed_filter}
      FILTER(STRSTARTS(STR(?memory), "#{base_iri}"))
    #{content_filter}
    #{anchor_filter}
    }
    ORDER BY DESC(?timestamp) ?memory
    LIMIT #{limit}
    """
  end

  @spec provenance(String.t(), map()) :: String.t()
  def provenance(managed_repo_id, params \\ %{}) when is_binary(managed_repo_id) do
    limit = positive_limit(params[:limit], 25)
    base_iri = MemoryGraph.workflow_provenance_base_iri(managed_repo_id)

    kind_values =
      params
      |> Map.get(:kinds)
      |> normalize_kind_values(@provenance_kind_classes)

    kind_filter =
      if kind_values == [] do
        """
          VALUES ?kind {
            #{Enum.map_join(Map.values(@provenance_kind_classes), "\n        ", &"jido:#{&1}")}
          }
        """
      else
        """
          VALUES ?kind {
            #{Enum.map_join(kind_values, "\n        ", &"jido:#{&1}")}
          }
        """
      end

    label_filter =
      case normalized_string(params[:label_contains]) do
        nil ->
          ""

        search ->
          """
            FILTER(CONTAINS(LCASE(STR(COALESCE(?label, ?content, ""))), LCASE("#{escape_string(search)}")))
          """
      end

    governed_filter =
      governed_filter(
        managed_repo_id,
        Map.get(params, :governed_references, params[:artifact_paths]),
        "resource"
      )

    conversation_filter =
      case normalized_string(params[:conversation_id]) do
        nil ->
          ""

        conversation_id ->
          """
            FILTER(BOUND(?conversationId) && STR(?conversationId) = "#{escape_string(conversation_id)}")
          """
      end

    turn_filter =
      case normalized_string(params[:turn_id]) do
        nil ->
          ""

        turn_id ->
          """
            FILTER(BOUND(?turnId) && STR(?turnId) = "#{escape_string(turn_id)}")
          """
      end

    conversation_event_filter =
      case normalized_string(params[:conversation_event]) do
        nil ->
          ""

        conversation_event ->
          """
            FILTER(BOUND(?conversationEvent) && STR(?conversationEvent) = "#{escape_string(conversation_event)}")
          """
      end

    conversation_origin_filter =
      if Map.get(params, :conversation_origin?, false) do
        """
          FILTER(BOUND(?conversationId))
        """
      else
        ""
      end

    """
    SELECT ?resource ?kind ?label ?content ?startedAt ?endedAt ?session ?module ?function ?subject ?revision ?governedRecord ?governedKind ?governedLabel ?conversationId ?turnId ?commandId ?conversationEvent ?clarificationState ?conversationScope ?conversationAttachmentMode ?conversationStatus ?conversationSource
    WHERE {
    #{kind_filter}
      ?resource a ?kind .
      OPTIONAL { ?resource rdfs:label ?label . }
      OPTIONAL { ?resource rdfs:comment ?content . }
      OPTIONAL { ?resource prov:startedAtTime ?startedAt . }
      OPTIONAL { ?resource prov:endedAtTime ?endedAt . }
      OPTIONAL { ?resource prov:wasInformedBy ?session . }
      OPTIONAL { ?resource jido:aboutModule ?module . }
      OPTIONAL { ?resource jido:aboutFunction ?function . }
      OPTIONAL { ?resource jido:affectsSymbol ?subject . }
      OPTIONAL { ?resource jido:validForRevision ?revision . }
      OPTIONAL { ?resource jido:conversationId ?conversationId . }
      OPTIONAL { ?resource jido:conversationTurnId ?turnId . }
      OPTIONAL { ?resource jido:conversationCommandId ?commandId . }
      OPTIONAL { ?resource jido:conversationEvent ?conversationEvent . }
      OPTIONAL { ?resource jido:clarificationState ?clarificationState . }
      OPTIONAL { ?resource jido:conversationScope ?conversationScope . }
      OPTIONAL { ?resource jido:conversationAttachmentMode ?conversationAttachmentMode . }
      OPTIONAL { ?resource jido:conversationStatus ?conversationStatus . }
      OPTIONAL { ?resource jido:conversationSource ?conversationSource . }
      OPTIONAL {
        VALUES (?governedPredicate ?governedKind) {
          (jido:aboutManagedRepo "managed_repo")
          (jido:aboutObservation "observation")
          (jido:aboutAssessment "assessment")
          (jido:aboutWorkItem "work_item")
          (jido:aboutRun "run")
          (jido:aboutEvidence "evidence")
          (jido:aboutChangeRequest "change_request")
          (jido:aboutDecision "decision")
        }
        ?resource ?governedPredicate ?governedRecord .
        OPTIONAL { ?governedRecord <https://jido.run/ontology/control-plane#recordLabel> ?governedRecordLabel . }
        OPTIONAL { ?governedRecord rdfs:label ?governedRecordRdfsLabel . }
        BIND(COALESCE(?governedRecordLabel, ?governedRecordRdfsLabel) AS ?governedLabel)
      }
    #{governed_filter}
      FILTER(STRSTARTS(STR(?resource), "#{base_iri}"))
    #{label_filter}
    #{conversation_filter}
    #{turn_filter}
    #{conversation_event_filter}
    #{conversation_origin_filter}
    }
    ORDER BY DESC(?startedAt) ?resource
    LIMIT #{limit}
    """
  end

  @spec cross_links(String.t(), String.t()) :: String.t()
  def cross_links(managed_repo_id, resource_iri) when is_binary(managed_repo_id) and is_binary(resource_iri) do
    base_iri = MemoryGraph.base_iri(managed_repo_id)
    workflow_base_iri = MemoryGraph.workflow_provenance_base_iri(managed_repo_id)

    """
    SELECT ?repository ?file ?module ?function ?test ?config ?subject ?governedRecord ?governedKind ?governedLabel ?artifact ?artifactLabel ?related
    WHERE {
      BIND(<#{escape_string(resource_iri)}> AS ?resource)
      OPTIONAL { ?resource jido:aboutRepository ?repository . }
      OPTIONAL { ?resource jido:aboutFile ?file . }
      OPTIONAL { ?resource jido:aboutModule ?module . }
      OPTIONAL { ?resource jido:aboutFunction ?function . }
      OPTIONAL { ?resource jido:aboutTest ?test . }
      OPTIONAL { ?resource jido:aboutConfig ?config . }
      OPTIONAL { ?resource jido:affectsSymbol ?subject . }
      OPTIONAL {
        VALUES (?governedPredicate ?governedKind) {
          (jido:aboutManagedRepo "managed_repo")
          (jido:aboutObservation "observation")
          (jido:aboutAssessment "assessment")
          (jido:aboutWorkItem "work_item")
          (jido:aboutRun "run")
          (jido:aboutEvidence "evidence")
          (jido:aboutChangeRequest "change_request")
          (jido:aboutDecision "decision")
        }
        ?resource ?governedPredicate ?governedRecord .
        OPTIONAL { ?governedRecord rdfs:label ?governedLabel . }
      }
      OPTIONAL {
        ?resource jido:supportedBy ?artifact .
        OPTIONAL { ?artifact rdfs:label ?artifactLabel . }
      }
      OPTIONAL { ?resource jido:relatedTo ?related . }
      FILTER(
        STRSTARTS(STR(?resource), "#{base_iri}") ||
        STRSTARTS(STR(?resource), "#{workflow_base_iri}")
      )
    }
    """
  end

  defp normalize_kind_values(nil, _class_map), do: []

  defp normalize_kind_values(values, class_map) when is_list(values) do
    values
    |> Enum.map(&normalize_kind_value(&1, class_map))
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_kind_values(value, class_map), do: normalize_kind_values([value], class_map)

  defp normalize_kind_value(value, class_map) when is_atom(value), do: Map.get(class_map, value)

  defp normalize_kind_value(value, class_map) when is_binary(value) do
    case value |> String.trim() |> String.replace("-", "_") do
      "fact" -> Map.get(class_map, :fact)
      "decision" -> Map.get(class_map, :decision)
      "lesson_learned" -> Map.get(class_map, :lesson_learned)
      "invariant" -> Map.get(class_map, :invariant)
      "convention" -> Map.get(class_map, :convention)
      "known_issue" -> Map.get(class_map, :known_issue)
      "open_question" -> Map.get(class_map, :open_question)
      "pattern" -> Map.get(class_map, :pattern)
      "anti_pattern" -> Map.get(class_map, :anti_pattern)
      "work_session" -> Map.get(class_map, :work_session)
      "agent_run" -> Map.get(class_map, :agent_run)
      "tool_invocation" -> Map.get(class_map, :tool_invocation)
      "prompt_turn" -> Map.get(class_map, :prompt_turn)
      "plan" -> Map.get(class_map, :plan)
      "patch" -> Map.get(class_map, :patch)
      "review" -> Map.get(class_map, :review)
      _other -> nil
    end
  end

  defp normalize_kind_value(_value, _class_map), do: nil

  defp normalized_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalized_string(_value), do: nil

  defp governed_filter(_managed_repo_id, nil, _resource_var), do: ""

  defp governed_filter(managed_repo_id, artifact_paths, resource_var) do
    normalized_paths =
      artifact_paths
      |> List.wrap()
      |> Enum.map(&normalized_string/1)
      |> Enum.reject(&is_nil/1)

    typed_values =
      normalized_paths
      |> Enum.flat_map(fn path ->
        case GovernedReference.from_artifact_path(managed_repo_id, path) do
          {:ok, reference} ->
            [
              {predicate_local(reference.kind), escape_string(reference.iri)}
            ]

          _other ->
            []
        end
      end)

    legacy_values =
      normalized_paths
      |> Enum.map(&MemoryGraph.artifact_iri(managed_repo_id, &1))
      |> Enum.map(&to_string/1)

    clauses =
      []
      |> maybe_add_typed_filter(resource_var, typed_values)
      |> maybe_add_legacy_filter(resource_var, legacy_values)

    case clauses do
      [] -> ""
      clauses -> Enum.map_join(clauses, "\n        UNION\n", &("        " <> &1))
    end
  end

  defp maybe_add_typed_filter(clauses, _resource_var, []), do: clauses

  defp maybe_add_typed_filter(clauses, resource_var, typed_values) do
    clauses ++
      [
        """
        {
          VALUES (?governedPredicate ?governedRecord) {
            #{Enum.map_join(typed_values, "\n            ", fn {predicate, iri} -> "(jido:#{predicate} <#{iri}>)" end)}
          }
          ?#{resource_var} ?governedPredicate ?governedRecord .
        }
        """
      ]
  end

  defp maybe_add_legacy_filter(clauses, _resource_var, []), do: clauses

  defp maybe_add_legacy_filter(clauses, resource_var, legacy_values) do
    clauses ++
      [
        """
        {
          VALUES ?artifact {
            #{Enum.map_join(legacy_values, "\n            ", &"<#{escape_string(&1)}>")}
          }
          ?#{resource_var} jido:supportedBy ?artifact .
        }
        """
      ]
  end

  defp predicate_local(kind) do
    case kind do
      :managed_repo -> "aboutManagedRepo"
      :event -> "aboutEvent"
      :observation -> "aboutObservation"
      :assessment -> "aboutAssessment"
      :work_item -> "aboutWorkItem"
      :run -> "aboutRun"
      :evidence -> "aboutEvidence"
      :change_request -> "aboutChangeRequest"
      :decision -> "aboutDecision"
    end
  end

  defp positive_limit(nil, default), do: default
  defp positive_limit(value, _default) when is_integer(value) and value > 0, do: value

  defp positive_limit(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _other -> default
    end
  end

  defp positive_limit(_value, default), do: default

  defp escape_string(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end
end
