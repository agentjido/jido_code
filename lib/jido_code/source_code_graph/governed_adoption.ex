defmodule JidoCode.SourceCodeGraph.GovernedAdoption do
  # covers: architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records
  # covers: architecture.factory_control_plane.semantic_repository_insights_rejoin_control_plane
  # covers: architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
  # covers: architecture.memory_capture_plane.workflow_provenance_and_memory_are_written_to_distinct_named_graphs
  # covers: architecture.memory_capture_plane.transient_llm_output_is_not_inserted_as_memory_without_adoption
  @moduledoc """
  Explicit governed adoption flows for semantic source-code graph findings.

  This boundary makes semantic findings influence factory behavior only through
  durable control-plane records such as Assessment, WorkItem, and Evidence.
  """

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.Actor
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.{CaptureEnvelope, GovernedReference}
  alias JidoCode.Operations.{RecordStore, WorkItem, WorkSynthesis}
  alias JidoCode.SourceCodeGraph.{Finding, Materialization, MemoryCapture, ProductFeedback}

  @adoption_actor Actor.factory_system_actor(%{
                    "id" => "system:source-code-graph-governed-adoption",
                    "email" => "source-code-graph-governed-adoption@system.local"
                  })

  @spec adopt_work_item(map(), keyword()) ::
          {:ok,
           %{
             finding: map(),
             observation: map(),
             event: map(),
             assessment: map(),
             work_item: WorkItem.t() | nil,
             action: atom()
           }}
          | {:error, term()}
  def adopt_work_item(projection_or_finding, opts \\ []) do
    with {:ok, finding} <- ensure_finding(projection_or_finding, opts),
         {:ok, %{observation: observation, event: event, assessment: assessment}} <-
           Materialization.materialize_assessment(finding, opts),
         {:ok, %{work_item: work_item, action: action}} <-
           WorkSynthesis.from_assessment(assessment, observation: observation, event: event),
         {:ok, adopted_work_item} <- preserve_work_item_metadata(work_item, finding, action, opts) do
      _ =
        capture_governed_adoption_provenance(
          :plan,
          finding,
          %{
            observation_id: observation.id,
            assessment_id: assessment.id,
            work_item_id: adopted_work_item && adopted_work_item.id,
            content: finding.summary,
            outcome: Atom.to_string(action)
          },
          opts
        )

      {:ok,
       %{
         finding: finding,
         observation: observation,
         event: event,
         assessment: assessment,
         work_item: adopted_work_item,
         action: action
       }}
    end
  end

  @spec review_support(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def review_support(projection_or_finding, opts \\ []) do
    with {:ok, finding} <- ensure_finding(projection_or_finding, opts),
         {:ok, evidence_input} <- Materialization.evidence_input(finding, opts) do
      _ =
        capture_governed_adoption_provenance(
          :review,
          finding,
          %{
            work_item_id: Keyword.get(opts, :work_item_id),
            run_id: Keyword.get(opts, :run_id),
            content: finding.summary,
            outcome: "review_support"
          },
          opts
        )

      {:ok,
       %{
         finding: finding,
         summary: finding.summary,
         evidence_input: evidence_input,
         review_metadata: %{
           "graph" => normalize_map(finding.graph),
           "provenance" => normalize_map(finding.provenance),
           "freshness" => normalize_map(ProductFeedback.for_graph(finding.graph))
         }
       }}
    end
  end

  @spec adopt_evidence(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def adopt_evidence(projection_or_finding, opts \\ []) do
    with {:ok, evidence} <- Materialization.materialize_evidence(projection_or_finding, opts),
         {:ok, finding} <- ensure_finding(projection_or_finding, opts) do
      _ =
        capture_governed_adoption_provenance(
          :review,
          finding,
          %{
            work_item_id: evidence.work_item_id,
            run_id: evidence.run_id,
            evidence_id: evidence.id,
            content: finding.summary,
            outcome: "evidence_adopted"
          },
          opts
        )

      {:ok, evidence}
    end
  end

  @spec adopt_memory(map(), keyword()) :: {:ok, map()} | {:error, term()} | {:error, atom(), map()}
  def adopt_memory(projection_or_finding, opts \\ []) do
    MemoryCapture.record(
      projection_or_finding,
      [
        classification_source: "governed_adoption",
        workflow: :governed_adoption,
        work_item_id: Keyword.get(opts, :work_item_id),
        observation_id: Keyword.get(opts, :observation_id),
        assessment_id: Keyword.get(opts, :assessment_id),
        evidence_id: Keyword.get(opts, :evidence_id),
        decision_id: Keyword.get(opts, :decision_id),
        run_id: Keyword.get(opts, :run_id)
      ] ++ opts
    )
  end

  defp ensure_finding(%{kind: :semantic_finding} = finding, _opts), do: {:ok, finding}
  defp ensure_finding(projection, opts), do: Finding.from_projection(projection, opts)

  defp capture_governed_adoption_provenance(_kind, _finding, _details, opts)
       when not is_list(opts),
       do: :ok

  defp capture_governed_adoption_provenance(kind, finding, details, opts) do
    workspace_path = Keyword.get(opts, :workspace_path)
    revision = provenance_revision(finding)

    with true <- MemoryGraph.capability_enabled?(opts),
         {:ok, workspace_path} <- normalize_workspace_path(workspace_path),
         revision when is_binary(revision) <- revision,
         actor_id when is_binary(actor_id) <- actor_id(opts),
         :ok <- ensure_workflow_provenance_ready(finding.managed_repo_id, workspace_path, revision, opts),
         capture when is_map(capture) <- governed_capture(kind, finding, details, actor_id, revision, opts),
         {:ok, _result} <-
           AgentWorkspace.record_memory_graph(
             finding.managed_repo_id,
             workspace_path,
             capture,
             [graph_name: MemoryGraph.workflow_provenance_graph_name(), revision: revision] ++ opts
           ) do
      :ok
    else
      _other -> :ok
    end
  end

  defp governed_capture(kind, finding, details, actor_id, revision, opts) do
    session_id = provenance_session_id(kind, finding, details)
    anchors = anchors_from_finding(finding, opts)

    base = [
      session_id: session_id,
      actor_id: actor_id,
      workflow: :governed_adoption,
      work_item_id: details.work_item_id,
      content: details.content,
      outcome: details.outcome,
      revision: revision,
      governed_references: governed_references(details, opts),
      anchors: anchors
    ]

    case kind do
      :plan ->
        CaptureEnvelope.plan(base)

      :review ->
        CaptureEnvelope.review(base ++ [started_at: DateTime.utc_now(), ended_at: DateTime.utc_now()])
    end
  end

  defp ensure_workflow_provenance_ready(managed_repo_id, workspace_path, revision, opts) do
    case AgentWorkspace.memory_graph_status(
           managed_repo_id,
           workspace_path,
           graph_name: MemoryGraph.workflow_provenance_graph_name(),
           revision: revision
         ) do
      {:ok, %{ready?: true, stale?: false}} ->
        :ok

      {:ok, _status} ->
        case AgentWorkspace.recover_memory_graph(
               managed_repo_id,
               workspace_path,
               [graph_name: MemoryGraph.workflow_provenance_graph_name(), revision: revision] ++ opts
             ) do
          {:ok, %{graph_status: %{ready?: true, stale?: false}}} -> :ok
          _other -> {:error, :memory_graph_not_ready}
        end

      _other ->
        {:error, :memory_graph_not_ready}
    end
  end

  defp normalize_workspace_path(path) when is_binary(path) do
    case String.trim(path) do
      "" -> {:error, :missing_workspace_path}
      normalized -> {:ok, normalized}
    end
  end

  defp normalize_workspace_path(_path), do: {:error, :missing_workspace_path}

  defp governed_references(details, opts) do
    observation_id = Map.get(details, :observation_id)
    assessment_id = Map.get(details, :assessment_id)
    work_item_id = Map.get(details, :work_item_id)
    run_id = Map.get(details, :run_id)
    evidence_id = Map.get(details, :evidence_id)

    explicit =
      [
        observation_id && %{kind: :observation, id: observation_id},
        assessment_id && %{kind: :assessment, id: assessment_id},
        work_item_id && %{kind: :work_item, id: work_item_id},
        run_id && %{kind: :run, id: run_id},
        evidence_id && %{kind: :evidence, id: evidence_id},
        Keyword.get(opts, :observation_id) && %{kind: :observation, id: Keyword.get(opts, :observation_id)},
        Keyword.get(opts, :assessment_id) && %{kind: :assessment, id: Keyword.get(opts, :assessment_id)},
        Keyword.get(opts, :evidence_id) && %{kind: :evidence, id: Keyword.get(opts, :evidence_id)},
        Keyword.get(opts, :decision_id) && %{kind: :decision, id: Keyword.get(opts, :decision_id)}
      ]
      |> Enum.reject(&is_nil/1)

    inherited =
      opts
      |> Keyword.get(:governed_references)
      |> GovernedReference.explicit_many()

    (explicit ++ inherited)
    |> Enum.uniq_by(fn reference -> {reference.kind, reference.id} end)
  end

  defp provenance_revision(finding) do
    graph = Map.get(finding, :graph, %{})
    graph[:imported_revision] || graph["imported_revision"] || graph[:current_revision] || graph["current_revision"]
  end

  defp provenance_session_id(kind, finding, details) do
    prefix =
      case kind do
        :plan -> "governed-plan"
        :review -> "governed-review"
      end

    [
      prefix,
      finding.digest,
      details.work_item_id || details.run_id || "session"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("-")
  end

  defp actor_id(opts) do
    case actor(opts) do
      %{} = actor -> actor["id"] || actor[:id]
      _other -> nil
    end
  end

  defp anchors_from_finding(finding, opts) do
    query = normalize_map(Keyword.get(opts, :query, %{}))
    requested_query = normalize_map(Map.get(finding.provenance, :query, %{}))

    module_name =
      query["module_name"] ||
        requested_query["module_name"] ||
        first_payload_value(finding, "module_name")

    subject_iri =
      query["subject_iri"] ||
        requested_query["subject_iri"] ||
        first_payload_value(finding, "subject_iri")

    anchors = %{}
    anchors = if is_binary(module_name), do: Map.put(anchors, :module_name, module_name), else: anchors
    if is_binary(subject_iri), do: Map.put(anchors, :subject_iri, subject_iri), else: anchors
  end

  defp first_payload_value(finding, key) when key in ["module_name", "subject_iri"] do
    atom_key =
      case key do
        "module_name" -> :module_name
        "subject_iri" -> :subject_iri
      end

    finding
    |> get_in([:payload, :items])
    |> List.wrap()
    |> List.first()
    |> case do
      %{} = first_item ->
        Map.get(first_item, key) || Map.get(first_item, atom_key)

      _other ->
        nil
    end
  end

  defp preserve_work_item_metadata(nil, _finding, _action, _opts), do: {:ok, nil}

  defp preserve_work_item_metadata(%WorkItem{} = work_item, finding, action, _opts) do
    metadata =
      work_item.work_metadata
      |> normalize_map()
      |> Map.put(
        "semantic_finding",
        %{
          "digest" => finding.digest,
          "summary" => finding.summary,
          "category" => finding.category,
          "recommended_action" => finding.recommended_action,
          "adoption_action" => Atom.to_string(action),
          "graph" => normalize_map(finding.graph),
          "freshness" => normalize_map(ProductFeedback.for_graph(finding.graph)),
          "provenance" => normalize_map(finding.provenance),
          "payload" => normalize_map(finding.payload)
        }
      )

    RecordStore.update_work_item(work_item, %{work_metadata: metadata})
  end

  defp actor(opts) do
    opts
    |> Keyword.get(:actor)
    |> Actor.effective_actor()
    |> case do
      nil -> @adoption_actor
      actor -> actor
    end
  end

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      normalized_value =
        cond do
          is_boolean(nested_value) or is_nil(nested_value) -> nested_value
          is_map(nested_value) -> normalize_map(nested_value)
          is_list(nested_value) -> Enum.map(nested_value, &normalize_nested_value/1)
          is_atom(nested_value) -> Atom.to_string(nested_value)
          true -> nested_value
        end

      Map.put(acc, normalized_key, normalized_value)
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(value) when is_boolean(value) or is_nil(value), do: value
  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_nested_value(value), do: value
end
