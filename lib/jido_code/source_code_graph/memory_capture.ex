defmodule JidoCode.SourceCodeGraph.MemoryCapture do
  # covers: architecture.memory_capture_plane.durable_memories_are_inserted_through_explicit_classification_and_adoption
  # covers: architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
  # covers: architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
  # covers: architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records
  # covers: architecture.factory_control_plane.semantic_repository_insights_rejoin_control_plane
  @moduledoc false

  alias JidoCode.AgentWorkspace
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.{CaptureEnvelope, DurableMemoryEnvelope}
  alias JidoCode.SourceCodeGraph.Finding

  @spec record(map(), keyword()) :: {:ok, map()} | {:error, term()} | {:error, atom(), map()}
  def record(projection_or_finding, opts \\ []) do
    with {:ok, finding} <- ensure_finding(projection_or_finding, opts),
         {:ok, workspace_path} <- normalize_workspace_path(Keyword.get(opts, :workspace_path)),
         {:ok, memory_kind} <- normalize_memory_kind(Keyword.get(opts, :memory_kind)),
         {:ok, classification_reason} <- required_string(Keyword.get(opts, :classification_reason)),
         actor_id when is_binary(actor_id) <- required_actor_id(opts),
         revision when is_binary(revision) <- revision(finding),
         session_id <- session_id(opts, finding, memory_kind),
         :ok <- ensure_memory_graph_ready(finding.managed_repo_id, workspace_path, revision, opts),
         :ok <-
           ensure_workflow_session(
             finding.managed_repo_id,
             workspace_path,
             session_id,
             actor_id,
             revision,
             memory_kind,
             finding,
             opts
           ),
         capture <-
           build_memory_capture(
             finding,
             memory_kind,
             actor_id,
             revision,
             session_id,
             classification_reason,
             opts
           ),
         {:ok, record_result} <-
           AgentWorkspace.record_memory_graph(
             finding.managed_repo_id,
             workspace_path,
             capture,
             [revision: revision] ++ opts
           ) do
      {:ok,
       %{
         finding: finding,
         memory_kind: memory_kind,
         session_id: session_id,
         capture: capture,
         record: record_result
       }}
    else
      {:error, reason, detail} -> {:error, reason, detail}
      {:error, reason} -> {:error, reason}
      _other -> {:error, :memory_capture_failed}
    end
  end

  defp ensure_finding(%{kind: :semantic_finding} = finding, _opts), do: {:ok, finding}
  defp ensure_finding(projection, opts), do: Finding.from_projection(projection, opts)

  defp normalize_workspace_path(path) when is_binary(path) do
    case String.trim(path) do
      "" -> {:error, :missing_workspace_path}
      normalized -> {:ok, normalized}
    end
  end

  defp normalize_workspace_path(_path), do: {:error, :missing_workspace_path}

  defp normalize_memory_kind(kind) when is_atom(kind) do
    if kind in DurableMemoryEnvelope.memory_kinds() do
      {:ok, kind}
    else
      {:error, :invalid_memory_kind}
    end
  end

  defp normalize_memory_kind(kind) when is_binary(kind) do
    case String.trim(kind) do
      value
      when value in ~w(fact decision lesson_learned invariant convention known_issue open_question pattern anti_pattern) ->
        {:ok, String.to_atom(value)}

      _other ->
        {:error, :invalid_memory_kind}
    end
  end

  defp normalize_memory_kind(_kind), do: {:error, :invalid_memory_kind}

  defp required_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, :missing_classification_reason}
      normalized -> {:ok, normalized}
    end
  end

  defp required_string(_value), do: {:error, :missing_classification_reason}

  defp required_actor_id(opts) do
    case normalize_optional_string(Keyword.get(opts, :actor_id)) do
      nil ->
        case Keyword.get(opts, :actor) do
          %{} = actor -> actor["id"] || actor[:id]
          _other -> nil
        end

      actor_id ->
        actor_id
    end
  end

  defp revision(finding) do
    graph = Map.get(finding, :graph, %{})
    graph[:imported_revision] || graph["imported_revision"] || graph[:current_revision] || graph["current_revision"]
  end

  defp session_id(opts, finding, memory_kind) do
    Keyword.get(opts, :session_id) ||
      Enum.join(
        ["memory", Atom.to_string(memory_kind), finding.digest, Keyword.get(opts, :work_item_id)]
        |> Enum.reject(&is_nil/1),
        "-"
      )
  end

  defp ensure_memory_graph_ready(managed_repo_id, workspace_path, revision, opts) do
    case AgentWorkspace.memory_graph_status(managed_repo_id, workspace_path, revision: revision) do
      {:ok, %{ready?: true, stale?: false}} ->
        :ok

      _other ->
        case AgentWorkspace.refresh_memory_graph(managed_repo_id, workspace_path, [revision: revision] ++ opts) do
          {:ok, _result} -> :ok
          _other -> {:error, :memory_graph_not_ready}
        end
    end
  end

  defp ensure_workflow_session(
         managed_repo_id,
         workspace_path,
         session_id,
         actor_id,
         revision,
         memory_kind,
         finding,
         opts
       ) do
    capture =
      CaptureEnvelope.work_session(
        session_id: session_id,
        actor_id: actor_id,
        workflow: Keyword.get(opts, :workflow, :memory_capture),
        work_item_id: Keyword.get(opts, :work_item_id),
        goal: "Capture durable #{memory_kind} memory",
        outcome: finding.summary,
        revision: revision,
        anchors: anchors_from_finding(finding, opts)
      )

    case AgentWorkspace.record_memory_graph(
           managed_repo_id,
           workspace_path,
           capture,
           graph_name: MemoryGraph.workflow_provenance_graph_name(),
           revision: revision
         ) do
      {:ok, _result} -> :ok
      {:error, _reason, _detail} -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp build_memory_capture(
         finding,
         memory_kind,
         actor_id,
         revision,
         session_id,
         classification_reason,
         opts
       ) do
    DurableMemoryEnvelope.build(memory_kind, %{
      session_id: session_id,
      actor_id: actor_id,
      revision: revision,
      workflow: Keyword.get(opts, :workflow, :memory_capture),
      work_item_id: Keyword.get(opts, :work_item_id),
      content: Keyword.get(opts, :content, finding.summary || "Durable memory capture"),
      anchors: anchors_from_finding(finding, opts),
      tags: Keyword.get(opts, :tags, [finding.category]),
      classification: %{
        source: Keyword.get(opts, :classification_source, "semantic_workflow"),
        reason: classification_reason,
        label: Keyword.get(opts, :classification_label, "semantic durable memory")
      },
      governed_context: governed_context(opts),
      related_memory_ids: Keyword.get(opts, :related_memory_ids, []),
      alternative_considered_ids: Keyword.get(opts, :alternative_considered_ids, []),
      consequence_memory_ids: Keyword.get(opts, :consequence_memory_ids, []),
      supersedes_memory_id: Keyword.get(opts, :supersedes_memory_id),
      decision_status: Keyword.get(opts, :decision_status),
      confidence: Keyword.get(opts, :confidence),
      rationale: Keyword.get(opts, :rationale),
      context: Keyword.get(opts, :context),
      supported_by: supported_by(finding, opts),
      evidence_artifacts: evidence_artifacts(opts),
      confidence_source: Keyword.get(opts, :confidence_source)
    })
  end

  defp anchors_from_finding(finding, opts) do
    query = normalize_map(Keyword.get(opts, :query, %{}))
    requested_query = normalize_map(Map.get(finding.provenance, :query, %{}))

    module_name =
      query["module_name"] ||
        requested_query["module_name"] ||
        first_payload_value(finding, "module_name")

    function_iri =
      query["function_iri"] ||
        requested_query["function_iri"] ||
        first_payload_value(finding, "function_iri")

    subject_iri =
      query["subject_iri"] ||
        requested_query["subject_iri"] ||
        first_payload_value(finding, "subject_iri")

    anchors = %{}
    anchors = if is_binary(module_name), do: Map.put(anchors, :module_name, module_name), else: anchors
    anchors = if is_binary(function_iri), do: Map.put(anchors, :function_iri, function_iri), else: anchors
    if is_binary(subject_iri), do: Map.put(anchors, :subject_iri, subject_iri), else: anchors
  end

  defp first_payload_value(finding, key) when key in ["module_name", "function_iri", "subject_iri"] do
    atom_key =
      case key do
        "module_name" -> :module_name
        "function_iri" -> :function_iri
        "subject_iri" -> :subject_iri
      end

    finding
    |> get_in([:payload, :items])
    |> List.wrap()
    |> List.first()
    |> case do
      %{} = first_item -> Map.get(first_item, key) || Map.get(first_item, atom_key)
      _other -> nil
    end
  end

  defp governed_context(opts) do
    opts
    |> Keyword.take([:observation_id, :assessment_id, :work_item_id, :evidence_id, :decision_id, :run_id])
    |> Enum.into(%{})
  end

  defp supported_by(finding, opts) do
    base = [%{id: finding.digest, label: finding.summary}]

    case Keyword.get(opts, :supported_by) do
      nil -> base
      list when is_list(list) -> base ++ list
      other -> base ++ [other]
    end
  end

  defp evidence_artifacts(opts) do
    case Keyword.get(opts, :evidence_artifacts) do
      nil -> []
      list when is_list(list) -> list
      other -> [other]
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

      Map.put(acc, normalized_key, nested_value)
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(_value), do: nil
end
