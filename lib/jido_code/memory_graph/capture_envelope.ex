defmodule JidoCode.MemoryGraph.CaptureEnvelope do
  # covers: architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
  # covers: architecture.memory_capture_plane.memory_capture_requires_explicit_repo_work_and_actor_context
  # covers: architecture.memory_graph.memory_graph_links_to_source_code_entities_by_stable_iri
  # covers: architecture.source_code_graph_pod.code_entities_use_stable_iris_for_cross_graph_links
  @moduledoc false

  alias JidoCode.{MemoryGraph, SourceCodeGraph}

  @workflow_provenance_kinds ~w(work_session agent_run tool_invocation prompt_turn plan patch review)a

  @kind_paths %{
    work_session: "work_session",
    agent_run: "agent_run",
    tool_invocation: "tool_invocation",
    prompt_turn: "prompt_turn",
    plan: "plan",
    patch: "patch",
    review: "review"
  }

  @kind_class_names %{
    work_session: "WorkSession",
    agent_run: "AgentRun",
    tool_invocation: "ToolInvocation",
    prompt_turn: "PromptTurn",
    plan: "Plan",
    patch: "Patch",
    review: "Review"
  }

  @type graph_context :: map()
  @type normalized_envelope :: map()

  @spec provenance_kinds() :: [atom()]
  def provenance_kinds, do: @workflow_provenance_kinds

  @spec workflow_provenance_kind?(atom() | String.t() | nil) :: boolean()
  def workflow_provenance_kind?(kind) when is_atom(kind), do: kind in @workflow_provenance_kinds

  def workflow_provenance_kind?(kind) when is_binary(kind) do
    case normalize_kind(kind) do
      {:ok, normalized} -> normalized in @workflow_provenance_kinds
      _other -> false
    end
  end

  def workflow_provenance_kind?(_kind), do: false

  @spec work_session(keyword() | map()) :: map()
  def work_session(attrs), do: build(:work_session, attrs)

  @spec agent_run(keyword() | map()) :: map()
  def agent_run(attrs), do: build(:agent_run, attrs)

  @spec tool_invocation(keyword() | map()) :: map()
  def tool_invocation(attrs), do: build(:tool_invocation, attrs)

  @spec prompt_turn(keyword() | map()) :: map()
  def prompt_turn(attrs), do: build(:prompt_turn, attrs)

  @spec plan(keyword() | map()) :: map()
  def plan(attrs), do: build(:plan, attrs)

  @spec patch(keyword() | map()) :: map()
  def patch(attrs), do: build(:patch, attrs)

  @spec review(keyword() | map()) :: map()
  def review(attrs), do: build(:review, attrs)

  @spec normalize(map(), graph_context()) :: {:ok, normalized_envelope()} | {:error, atom(), map()}
  def normalize(capture, graph_context) when is_map(capture) and is_map(graph_context) do
    with {:ok, kind} <- normalize_kind(Map.get(capture, :kind) || Map.get(capture, "kind")),
         true <- kind in @workflow_provenance_kinds or
                   {:error, :memory_capture_plane_not_ready, unsupported_capture_diagnostics(capture, graph_context)},
         {:ok, managed_repo_id} <- required_string(graph_context.managed_repo_id, :managed_repo_id),
         {:ok, workspace_path} <- required_string(graph_context.workspace_path, :workspace_path),
         {:ok, actor_id} <- actor_id(capture),
         {:ok, revision} <- revision(graph_context, capture),
         {:ok, session_id} <- session_id(kind, capture, managed_repo_id, revision),
         {:ok, started_at} <- normalize_datetime(Map.get(capture, :started_at) || Map.get(capture, "started_at")),
         {:ok, ended_at} <- optional_datetime(Map.get(capture, :ended_at) || Map.get(capture, "ended_at")) do
      id =
        Map.get(capture, :id) ||
          Map.get(capture, "id") ||
          default_resource_id(kind, session_id, capture, managed_repo_id, revision)

      metadata = normalize_map(Map.get(capture, :metadata) || Map.get(capture, "metadata") || %{})
      workflow = normalize_optional_string(Map.get(capture, :workflow) || Map.get(capture, "workflow"))
      work_item_id = normalize_optional_string(Map.get(capture, :work_item_id) || Map.get(capture, "work_item_id"))
      goal = normalize_optional_string(Map.get(capture, :goal) || Map.get(capture, "goal"))
      outcome = normalize_optional_string(Map.get(capture, :outcome) || Map.get(capture, "outcome"))
      content = normalize_optional_string(Map.get(capture, :content) || Map.get(capture, "content"))
      agent_name = normalize_optional_string(Map.get(capture, :agent_name) || Map.get(capture, "agent_name"))
      tool_name = normalize_optional_string(Map.get(capture, :tool_name) || Map.get(capture, "tool_name"))
      branch_name = normalize_optional_string(Map.get(capture, :branch_name) || Map.get(capture, "branch_name"))
      model_name = normalize_optional_string(Map.get(capture, :model) || Map.get(capture, "model"))
      toolchain_name = normalize_optional_string(Map.get(capture, :toolchain) || Map.get(capture, "toolchain"))

      source_code_anchors = source_code_anchors(capture, managed_repo_id)

      {:ok,
       %{
         kind: kind,
         graph_name: MemoryGraph.workflow_provenance_graph_name(),
         named_graph_iri: MemoryGraph.workflow_provenance_named_graph_iri(),
         managed_repo_id: managed_repo_id,
         workspace_path: workspace_path,
         revision: revision,
         actor_id: actor_id,
         workflow: workflow,
         work_item_id: work_item_id,
         goal: goal,
         outcome: outcome,
         content: content,
         metadata: metadata,
         started_at: started_at,
         ended_at: ended_at,
         resource_id: id,
         resource_iri: resource_iri(kind, graph_context, id),
         resource_class_iri: resource_class_iri(kind),
         session_id: session_id,
         session_iri: resource_iri(:work_session, graph_context, session_id),
         actor_iri: actor_iri(graph_context, actor_id),
         revision_iri: revision_iri(graph_context, revision),
         parent_agent_run_iri:
           optional_related_resource_iri(
             :agent_run,
             Map.get(capture, :agent_run_id) || Map.get(capture, "agent_run_id"),
             graph_context
           ),
         patch_iri:
           optional_related_resource_iri(
             :patch,
             Map.get(capture, :patch_id) || Map.get(capture, "patch_id"),
             graph_context
           ),
         branch_name: branch_name,
         model_name: model_name,
         toolchain_name: toolchain_name,
         label: label(kind, workflow, agent_name, tool_name),
         source_code_anchors: source_code_anchors
       }}
    end
  end

  defp build(kind, attrs) when is_list(attrs), do: build(kind, Map.new(attrs))
  defp build(kind, attrs) when is_map(attrs), do: Map.put(attrs, :kind, kind)

  defp normalize_kind(kind) when kind in @workflow_provenance_kinds, do: {:ok, kind}

  defp normalize_kind(kind) when is_binary(kind) do
    case String.trim(kind) do
      "work_session" -> {:ok, :work_session}
      "agent_run" -> {:ok, :agent_run}
      "tool_invocation" -> {:ok, :tool_invocation}
      "prompt_turn" -> {:ok, :prompt_turn}
      "plan" -> {:ok, :plan}
      "patch" -> {:ok, :patch}
      "review" -> {:ok, :review}
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

  defp session_id(:work_session, capture, managed_repo_id, revision) do
    session_id =
      Map.get(capture, :session_id) ||
        Map.get(capture, "session_id") ||
        Map.get(capture, :id) ||
        Map.get(capture, "id") ||
        "session-#{stable_suffix({managed_repo_id, revision, capture})}"

    required_string(session_id, :session_id)
  end

  defp session_id(_kind, capture, _managed_repo_id, _revision) do
    capture
    |> Map.get(:session_id, Map.get(capture, "session_id"))
    |> required_string(:session_id)
  end

  defp default_resource_id(kind, session_id, capture, managed_repo_id, revision) do
    case kind do
      :work_session ->
        session_id

      _other ->
        payload_hash =
          stable_suffix({
            kind,
            session_id,
            managed_repo_id,
            revision,
            Map.take(capture, [:content, :goal, :outcome, :workflow, :work_item_id, :agent_name, :tool_name])
          })

        "#{Atom.to_string(kind)}-#{payload_hash}"
    end
  end

  defp required_string(value, field) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, :invalid_memory_capture, %{field: field, reason: :missing}}
      normalized -> {:ok, normalized}
    end
  end

  defp required_string(_value, field), do: {:error, :invalid_memory_capture, %{field: field, reason: :missing}}

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_datetime(nil), do: {:ok, DateTime.utc_now() |> DateTime.truncate(:second)}
  defp normalize_datetime(%DateTime{} = value), do: {:ok, DateTime.truncate(value, :second)}

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, DateTime.truncate(datetime, :second)}
      _other -> {:error, :invalid_memory_capture, %{field: :started_at, reason: :invalid_datetime}}
    end
  end

  defp normalize_datetime(_value),
    do: {:error, :invalid_memory_capture, %{field: :started_at, reason: :invalid_datetime}}

  defp optional_datetime(nil), do: {:ok, nil}
  defp optional_datetime(value), do: normalize_datetime(value)

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

  defp optional_iri(nil), do: nil

  defp optional_iri(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      iri -> RDF.iri(iri)
    end
  end

  defp optional_iri(_value), do: nil

  defp optional_related_resource_iri(_kind, nil, _graph_context), do: nil

  defp optional_related_resource_iri(kind, resource_id, graph_context) do
    resource_iri(kind, graph_context, resource_id)
  end

  defp resource_iri(kind, graph_context, resource_id) do
    RDF.iri(
      "#{MemoryGraph.workflow_provenance_base_iri(graph_context.managed_repo_id)}#{Map.fetch!(@kind_paths, kind)}/#{uri_encode(resource_id)}"
    )
  end

  defp actor_iri(graph_context, actor_id) do
    RDF.iri(
      "#{MemoryGraph.workflow_provenance_base_iri(graph_context.managed_repo_id)}actor/#{uri_encode(actor_id)}"
    )
  end

  defp revision_iri(graph_context, revision) do
    RDF.iri(
      "#{MemoryGraph.workflow_provenance_base_iri(graph_context.managed_repo_id)}revision/#{uri_encode(revision)}"
    )
  end

  defp resource_class_iri(kind) do
    RDF.iri("https://jido.run/ontology/memory##{Map.fetch!(@kind_class_names, kind)}")
  end

  defp label(kind, workflow, agent_name, tool_name) do
    case kind do
      :work_session -> workflow || "work session"
      :agent_run -> agent_name || workflow || "agent run"
      :tool_invocation -> tool_name || "tool invocation"
      :prompt_turn -> workflow || "prompt turn"
      :plan -> "plan artifact"
      :patch -> "patch artifact"
      :review -> "review activity"
    end
  end

  defp unsupported_capture_diagnostics(capture, graph_context) do
    %{
      state: :capture_plane_not_ready,
      graph_name: graph_context.selected_graph_name,
      named_graph_iri: graph_context.selected_named_graph_iri,
      capture_ready?: false,
      current_revision: graph_context.revision_metadata.current_revision,
      requested_revision: graph_context.revision_metadata.requested_revision,
      capture: capture
    }
  end

  defp stable_suffix(term) do
    term
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end

  defp uri_encode(value) when is_binary(value), do: URI.encode(value)
  defp uri_encode(value), do: value |> to_string() |> uri_encode()

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
