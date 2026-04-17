defmodule JidoCode.Conversations.Runtime do
  # covers: architecture.conversation_orchestration.real_llm_turn_execution_replaces_surface_simulation
  # covers: architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary
  # covers: architecture.conversation_orchestration.llm_readiness_and_failure_states_are_explicit
  # covers: architecture.conversation_orchestration.real_runtime_cutover_has_no_compatibility_mode
  @moduledoc """
  Product-owned real execution boundary for conversation child work.

  The LiveView never assembles prompts or calls the specialist runtime
  directly. This boundary resolves readiness, shapes the conversation request,
  and routes it through the existing `AgentWorkspace` surface.
  """

  alias JidoCode.AgentWorkspace
  alias JidoCode.Conversations.WorkflowRouter
  alias JidoCode.Conversations.RuntimeReadiness
  alias JidoCode.LLMSelection
  alias JidoCode.MemoryGraph.WorkflowService, as: MemoryWorkflowService
  alias JidoCode.SourceCodeGraph.WorkflowService, as: SemanticWorkflowService

  @type runtime_spec :: %{
          conversation_id: String.t(),
          managed_repo_id: String.t(),
          work_item_id: String.t(),
          child_work_id: String.t(),
          turn_id: String.t(),
          instruction: String.t(),
          command_type: String.t() | nil,
          actor: map() | nil,
          objective: String.t() | nil,
          source: String.t() | nil,
          source_metadata: map() | nil,
          conversation_metadata: map() | nil,
          shared_context: map() | nil,
          turn_payload: map() | nil,
          child_work_result: map() | nil
        }

  @type runtime_event :: map()
  @type runtime_outcome ::
          {:completed, runtime_event()} | {:failed, runtime_event()} | {:awaiting_input, runtime_event()}

  @spec run(runtime_spec(), (runtime_event() -> term())) :: runtime_outcome()
  def run(runtime_spec, emit) when is_map(runtime_spec) and is_function(emit, 1) do
    emit.(%{
      "kind" => "progress",
      "summary" => "Checking repository conversation runtime readiness."
    })

    with {:ok, readiness} <-
           RuntimeReadiness.resolve(
             runtime_spec[:managed_repo_id] || runtime_spec["managed_repo_id"],
             conversation_metadata: normalize_map(map_get(runtime_spec, :conversation_metadata))
           ),
         {:ok, request} <- build_request(runtime_spec, readiness) do
      emit.(runtime_progress_event(request))

      case maybe_request_clarification(request) do
        {:awaiting_input, payload} ->
          {:awaiting_input, payload}

        :ok ->
          case invoke(request, runtime_spec, readiness) do
            {:ok, result} ->
              summary = result_summary(result, request.workflow)

              emit.(%{
                "kind" => "delta",
                "text" => summary,
                "workflow" => Atom.to_string(request.workflow),
                "context_source" => context_source_name(request.context_source)
              })

              {:completed,
               %{
                 "kind" => "completed",
                 "result" => %{
                   "summary" => summary,
                   "workflow" => Atom.to_string(request.workflow),
                   "context_source" => context_source_name(request.context_source),
                   "instruction" => request.user_instruction,
                   "llm_selection" => llm_selection_payload(request.llm_selection)
                 }
               }}

            {:error, %{} = typed_error} ->
              {:failed, %{"kind" => "failed", "error" => normalize_error(typed_error)}}

            {:error, reason, %{} = detail} ->
              {:failed, %{"kind" => "failed", "error" => normalize_error(Map.put_new(detail, :reason, reason))}}

            {:error, reason} ->
              {:failed, %{"kind" => "failed", "error" => runtime_error(reason)}}
          end
      end
    else
      {:error, %{} = typed_error} ->
        {:failed, %{"kind" => "failed", "error" => normalize_error(typed_error)}}

      {:error, reason} ->
        {:failed, %{"kind" => "failed", "error" => runtime_error(reason)}}
    end
  end

  defp build_request(runtime_spec, readiness) do
    with {:ok, managed_repo_id} <-
           required_string(
             runtime_spec[:managed_repo_id] || runtime_spec["managed_repo_id"],
             "conversation_runtime_repo_scope_invalid",
             "Managed repository scope is missing for real conversation runtime."
           ) do
      instruction =
        runtime_spec
        |> map_get(:instruction)
        |> normalize_optional_string()

      objective =
        runtime_spec
        |> map_get(:objective)
        |> normalize_optional_string()

      shared_context = normalize_map(map_get(runtime_spec, :shared_context))
      turn_payload = normalize_map(map_get(runtime_spec, :turn_payload))

      routing =
        WorkflowRouter.resolve(%{
          command_type: map_get(runtime_spec, :command_type),
          payload: turn_payload,
          objective: objective,
          conversation_metadata: normalize_map(map_get(runtime_spec, :conversation_metadata)),
          source_metadata: normalize_map(map_get(runtime_spec, :source_metadata)),
          shared_context: shared_context
        })

      workflow = routing.workflow
      work_item_id = normalize_optional_string(runtime_spec[:work_item_id] || runtime_spec["work_item_id"])

      referenced_files =
        shared_context
        |> Map.get("referenced_files", [])
        |> normalize_string_list()
        |> Kernel.++(referenced_files_from_map(turn_payload))
        |> Kernel.++(referenced_files_from_text(instruction))
        |> Enum.uniq()

      clarification_resume = normalize_map(Map.get(turn_payload, "clarification_resume"))

      context_source = select_context_source(workflow)

      with {:ok, work_item_id} <- require_work_item_for_request(work_item_id, routing) do
        {:ok,
         %{
           managed_repo_id: managed_repo_id,
           work_item_id: work_item_id,
           user_instruction: instruction || "Continue the repository conversation.",
           workflow: workflow,
           routing: routing,
           context_source: context_source,
           source: normalize_optional_string(map_get(runtime_spec, :source)),
           objective: objective,
           referenced_files: referenced_files,
           shared_context: shared_context,
           clarification_resume: clarification_resume,
           llm_selection: readiness.llm_selection,
           instruction:
             bounded_instruction(
               runtime_spec,
               workflow,
               managed_repo_id,
               work_item_id,
               readiness.workspace_path,
               shared_context,
               referenced_files,
               clarification_resume
             )
         }}
      end
    end
  end

  defp maybe_request_clarification(%{
         routing: %{ambiguous?: true} = routing,
         context_source: context_source
       }) do
    {:awaiting_input,
     %{
       "kind" => "needs_input",
       "prompt" => workflow_clarification_prompt(),
       "workflow" => "clarify",
       "context_source" => context_source_name(context_source),
       "required_context" => %{
         "workflow_choices" => Enum.map(WorkflowRouter.workflows(), &Atom.to_string/1)
       },
       "routing" => WorkflowRouter.metadata(routing)
     }}
  end

  defp maybe_request_clarification(
         %{
           user_instruction: instruction,
           clarification_resume: clarification_resume,
           referenced_files: referenced_files,
           workflow: workflow
         } = request
       ) do
    needs_file_clarification? =
      clarification_resume == %{} and
        referenced_files == [] and clarification_phrase?(instruction, workflow)

    if needs_file_clarification? do
      {:awaiting_input,
       %{
         "kind" => "needs_input",
         "prompt" => clarification_prompt(workflow),
         "workflow" => Atom.to_string(workflow),
         "context_source" => context_source_name(request.context_source),
         "required_context" => %{"referenced_files" => referenced_files}
       }}
    else
      :ok
    end
  end

  defp maybe_request_clarification(_request), do: :ok

  defp invoke(%{workflow: workflow, context_source: :semantic_workflow} = request, runtime_spec, readiness)
       when workflow in [:plan, :review, :explain] do
    semantic_opts = [workspace_path: readiness.workspace_path, prepare: :load_if_missing]

    case workflow do
      :plan ->
        SemanticWorkflowService.plan(
          request.managed_repo_id,
          request.work_item_id,
          request.instruction,
          semantic: semantic_opts,
          workspace_path: readiness.workspace_path,
          actor: map_get(runtime_spec, :actor),
          llm_selection: readiness.llm_selection
        )

      :review ->
        SemanticWorkflowService.review(
          request.managed_repo_id,
          request.work_item_id,
          request.instruction,
          semantic: semantic_opts,
          workspace_path: readiness.workspace_path,
          actor: map_get(runtime_spec, :actor),
          llm_selection: readiness.llm_selection
        )

      :explain ->
        SemanticWorkflowService.explain(
          request.managed_repo_id,
          request.work_item_id,
          request.instruction,
          semantic: semantic_opts,
          workspace_path: readiness.workspace_path,
          actor: map_get(runtime_spec, :actor),
          llm_selection: readiness.llm_selection
        )
    end
  end

  defp invoke(%{workflow: workflow} = request, runtime_spec, readiness)
       when workflow in [:plan, :execute, :review, :explain] do
    actor = map_get(runtime_spec, :actor)

    case select_context_source(workflow) do
      :memory_workflow ->
        invoke_memory_workflow(request, readiness, actor)

      :workspace_with_semantic ->
        invoke_workspace_with_semantic_fallback(request, readiness, actor)

      :semantic_workflow ->
        invoke_semantic_workflow_with_fallback(request, readiness, actor)

      _other ->
        invoke_workspace(request, readiness, actor, [])
    end
  end

  defp invoke_memory_workflow(%{workflow: workflow} = request, readiness, actor)
       when workflow in [:plan, :execute, :review, :explain] do
    memory_opts = [workspace_path: readiness.workspace_path, prepare: :recover_if_needed]

    result =
      case workflow do
        :plan ->
          MemoryWorkflowService.plan(
            request.managed_repo_id,
            request.work_item_id,
            request.instruction,
            memory: memory_opts,
            workspace_path: readiness.workspace_path,
            actor: actor,
            llm_selection: readiness.llm_selection
          )

        :execute ->
          MemoryWorkflowService.execute(
            request.managed_repo_id,
            request.work_item_id,
            request.instruction,
            memory: memory_opts,
            workspace_path: readiness.workspace_path,
            actor: actor,
            llm_selection: readiness.llm_selection
          )

        :review ->
          MemoryWorkflowService.review(
            request.managed_repo_id,
            request.work_item_id,
            request.instruction,
            memory: memory_opts,
            workspace_path: readiness.workspace_path,
            actor: actor,
            llm_selection: readiness.llm_selection
          )

        :explain ->
          MemoryWorkflowService.explain(
            request.managed_repo_id,
            request.work_item_id,
            request.instruction,
            memory: memory_opts,
            workspace_path: readiness.workspace_path,
            actor: actor,
            llm_selection: readiness.llm_selection
          )
      end

    handle_memory_workflow_result(result, request, readiness, actor)
  end

  defp handle_memory_workflow_result(result, request, readiness, actor) do
    case result do
      {:error, :memory_graph_disabled, _} ->
        log_memory_degradation(request.managed_repo_id, :disabled)
        fallback_to_workspace(request, readiness, actor)

      {:error, :memory_graph_not_ready, _} ->
        log_memory_degradation(request.managed_repo_id, :not_ready)
        fallback_to_workspace_with_semantic(request, readiness, actor)

      {:error, reason, _} when reason in [:memory_graph_write_failed, :memory_graph_query_failed, :memory_graph_timeout] ->
        log_memory_degradation(request.managed_repo_id, {:operation_failed, reason})
        fallback_to_workspace_with_semantic(request, readiness, actor)

      result ->
        result
    end
  end

  defp fallback_to_workspace(request, readiness, actor) do
    invoke_workspace(request, readiness, actor, [])
  end

  defp fallback_to_workspace_with_semantic(request, readiness, actor) do
    if semantic_enabled?() do
      invoke_workspace_with_semantic_fallback(request, readiness, actor)
    else
      invoke_workspace(request, readiness, actor, [])
    end
  end

  defp log_memory_degradation(managed_repo_id, reason) do
    require Logger

    Logger.warning("""
    Memory graph degraded for repo #{managed_repo_id}: #{inspect(reason)}
    Falling back from memory workflow to workspace mode.
    """)
  end

  defp invoke_workspace(%{workflow: workflow} = request, readiness, actor, extra_opts)
       when workflow in [:plan, :execute, :review, :explain] do
    opts =
      [workspace_path: readiness.workspace_path, actor: actor, llm_selection: readiness.llm_selection]
      |> Keyword.merge(List.wrap(extra_opts))

    case workflow do
      :plan ->
        AgentWorkspace.plan_work(
          request.managed_repo_id,
          request.work_item_id,
          request.instruction,
          opts
        )

      :execute ->
        AgentWorkspace.execute_work(
          request.managed_repo_id,
          request.work_item_id,
          request.instruction,
          opts
        )

      :review ->
        AgentWorkspace.review_work(
          request.managed_repo_id,
          request.work_item_id,
          request.instruction,
          opts
        )

      :explain ->
        AgentWorkspace.explain_work(
          request.managed_repo_id,
          request.work_item_id,
          request.instruction,
          opts
        )
    end
  end

  # Invokes workspace with semantic context, falling back to plain workspace on failure
  defp invoke_workspace_with_semantic_fallback(request, readiness, actor) do
    semantic_opts = [workspace_path: readiness.workspace_path, prepare: :load_if_missing]

    case invoke_workspace(request, readiness, actor, source_code_graph: semantic_opts) do
      {:error, :source_code_graph_disabled, _} ->
        # Feature is disabled, fall back to plain workspace
        log_semantic_degradation(request.managed_repo_id, :disabled)
        invoke_workspace(request, readiness, actor, [])

      {:error, :source_code_graph_not_ready, _} ->
        # Graph not loaded, fall back to plain workspace
        log_semantic_degradation(request.managed_repo_id, :not_ready)
        invoke_workspace(request, readiness, actor, [])

      {:error, reason, _} = _error when reason in [:source_code_graph_analysis_failed, :source_code_graph_store_failed] ->
        # Semantic analysis failed, fall back to plain workspace
        log_semantic_degradation(request.managed_repo_id, {:analysis_failed, reason})
        invoke_workspace(request, readiness, actor, [])

      result ->
        result
    end
  end

  # Invokes semantic workflow with fallback to workspace on failure
  defp invoke_semantic_workflow_with_fallback(request, readiness, actor) do
    managed_repo_id = request.managed_repo_id
    work_item_id = request.work_item_id
    instruction = request.instruction
    workspace_path = readiness.workspace_path

    semantic_opts = [workspace_path: workspace_path, prepare: :load_if_missing]

    case request.workflow do
      :plan ->
        case SemanticWorkflowService.plan(managed_repo_id, work_item_id, instruction,
               semantic: semantic_opts,
               workspace_path: workspace_path,
               actor: actor,
               llm_selection: readiness.llm_selection) do
          {:error, :source_code_graph_disabled, _} ->
            log_semantic_degradation(managed_repo_id, :disabled)
            AgentWorkspace.plan_work(managed_repo_id, work_item_id, instruction,
              workspace_path: workspace_path,
              actor: actor,
              llm_selection: readiness.llm_selection)

          {:error, :source_code_graph_not_ready, _} ->
            log_semantic_degradation(managed_repo_id, :not_ready)
            AgentWorkspace.plan_work(managed_repo_id, work_item_id, instruction,
              workspace_path: workspace_path,
              actor: actor,
              llm_selection: readiness.llm_selection)

          {:error, reason, _} = _error when reason in [:source_code_graph_analysis_failed, :source_code_graph_store_failed] ->
            log_semantic_degradation(managed_repo_id, {:analysis_failed, reason})
            AgentWorkspace.plan_work(managed_repo_id, work_item_id, instruction,
              workspace_path: workspace_path,
              actor: actor,
              llm_selection: readiness.llm_selection)

          result ->
            result
        end

      :review ->
        case SemanticWorkflowService.review(managed_repo_id, work_item_id, instruction,
               semantic: semantic_opts,
               workspace_path: workspace_path,
               actor: actor,
               llm_selection: readiness.llm_selection) do
          {:error, :source_code_graph_disabled, _} ->
            log_semantic_degradation(managed_repo_id, :disabled)
            AgentWorkspace.review_work(managed_repo_id, work_item_id, instruction,
              workspace_path: workspace_path,
              actor: actor,
              llm_selection: readiness.llm_selection)

          {:error, :source_code_graph_not_ready, _} ->
            log_semantic_degradation(managed_repo_id, :not_ready)
            AgentWorkspace.review_work(managed_repo_id, work_item_id, instruction,
              workspace_path: workspace_path,
              actor: actor,
              llm_selection: readiness.llm_selection)

          {:error, reason, _} = _error when reason in [:source_code_graph_analysis_failed, :source_code_graph_store_failed] ->
            log_semantic_degradation(managed_repo_id, {:analysis_failed, reason})
            AgentWorkspace.review_work(managed_repo_id, work_item_id, instruction,
              workspace_path: workspace_path,
              actor: actor,
              llm_selection: readiness.llm_selection)

          result ->
            result
        end

      :explain ->
        case SemanticWorkflowService.explain(managed_repo_id, work_item_id, instruction,
               semantic: semantic_opts,
               workspace_path: workspace_path,
               actor: actor,
               llm_selection: readiness.llm_selection) do
          {:error, :source_code_graph_disabled, _} ->
            log_semantic_degradation(managed_repo_id, :disabled)
            AgentWorkspace.explain_work(managed_repo_id, work_item_id, instruction,
              workspace_path: workspace_path,
              actor: actor,
              llm_selection: readiness.llm_selection)

          {:error, :source_code_graph_not_ready, _} ->
            log_semantic_degradation(managed_repo_id, :not_ready)
            AgentWorkspace.explain_work(managed_repo_id, work_item_id, instruction,
              workspace_path: workspace_path,
              actor: actor,
              llm_selection: readiness.llm_selection)

          {:error, reason, _} = _error when reason in [:source_code_graph_analysis_failed, :source_code_graph_store_failed] ->
            log_semantic_degradation(managed_repo_id, {:analysis_failed, reason})
            AgentWorkspace.explain_work(managed_repo_id, work_item_id, instruction,
              workspace_path: workspace_path,
              actor: actor,
              llm_selection: readiness.llm_selection)

          result ->
            result
        end

      _workflow ->
        # For execute workflow, use workspace with semantic fallback
        invoke_workspace_with_semantic_fallback(request, readiness, actor)
    end
  end

  defp log_semantic_degradation(managed_repo_id, reason) do
    require Logger

    Logger.warning("""
    Source code graph degraded for repo #{managed_repo_id}: #{inspect(reason)}
    Falling back to non-semantic workspace mode.
    """)
  end

  defp bounded_instruction(
         runtime_spec,
         workflow,
         managed_repo_id,
         work_item_id,
         workspace_path,
         shared_context,
         referenced_files,
         clarification_resume
       ) do
    workflow_name = if(is_atom(workflow), do: Atom.to_string(workflow), else: "clarify")

    accepted_tool_results =
      shared_context
      |> Map.get("accepted_tool_results", [])
      |> normalize_list_of_maps()
      |> Enum.take(-3)

    [
      "Repository conversation objective: #{normalize_optional_string(map_get(runtime_spec, :objective)) || "Coordinate managed repository work."}",
      "Workflow: #{workflow_name}",
      "Current request: #{normalize_optional_string(map_get(runtime_spec, :instruction)) || "Continue the repository conversation."}",
      "Repository scope:",
      "- managed_repo_id: #{managed_repo_id}",
      "- work_item_id: #{work_item_id}",
      "- workspace_path: #{workspace_path}",
      "- source: #{normalize_optional_string(map_get(runtime_spec, :source)) || "conversation"}"
    ]
    |> maybe_append_section("Referenced files", referenced_files)
    |> maybe_append_section("Accepted tool results", accepted_result_lines(accepted_tool_results))
    |> maybe_append_section("Clarification context", clarification_lines(clarification_resume))
    |> Kernel.++([
      "Guidance:",
      "- Stay within the current repository and governed work item unless the conversation explicitly changes scope.",
      "- Treat referenced files and accepted tool results as bounded context, and confirm details against the current source before making claims."
    ])
    |> Enum.join("\n")
  end

  defp runtime_progress_event(request) do
    if request.routing.ambiguous? do
      %{
        "kind" => "progress",
        "summary" =>
          "Requesting clarification before choosing whether to plan, implement, review, or explain this repository work.",
        "workflow" => "clarify",
        "context_source" => context_source_name(request.context_source),
        "referenced_files" => request.referenced_files,
        "routing" => WorkflowRouter.metadata(request.routing)
      }
    else
      %{
        "kind" => "progress",
        "summary" =>
          "Routing the repository conversation through the #{Atom.to_string(request.workflow)} specialist using #{context_source_label(request.context_source)}#{runtime_llm_summary(request.llm_selection)}.",
        "workflow" => Atom.to_string(request.workflow),
        "context_source" => context_source_name(request.context_source),
        "referenced_files" => request.referenced_files,
        "llm_selection" => llm_selection_payload(request.llm_selection)
      }
    end
  end

  defp result_summary(result, workflow) do
    case workflow do
      :plan -> Map.get(result, :plan) || Map.get(result, "plan")
      :execute -> Map.get(result, :changes) || Map.get(result, "changes")
      :review -> Map.get(result, :feedback) || Map.get(result, "feedback")
      :explain -> Map.get(result, :explanation) || Map.get(result, "explanation")
    end
    |> normalize_summary()
  end

  defp clarification_phrase?(instruction, workflow) do
    text = (instruction || "") |> String.downcase()

    contains_any?(text, ["clarify", "needs input", "which file", "what file"]) or
      (workflow in [:execute, :review] and contains_any?(text, ["file", "module", "function"]))
  end

  defp clarification_prompt(:execute),
    do: "Which file or module should I change first?"

  defp clarification_prompt(:review),
    do: "Which file, module, or diff should I review first?"

  defp clarification_prompt(_workflow),
    do: "Which file or module should I inspect first?"

  defp workflow_clarification_prompt do
    "Do you want me to plan, implement, review, or explain this request?"
  end

  defp select_context_source(nil), do: :workflow_clarification

  defp select_context_source(:execute) do
    cond do
      memory_enabled?() -> :memory_workflow
      semantic_enabled?() -> :workspace_with_semantic
      true -> :workspace
    end
  end

  defp select_context_source(workflow) when workflow in [:plan, :review, :explain] do
    cond do
      semantic_enabled?() -> :semantic_workflow
      memory_enabled?() -> :memory_workflow
      true -> :workspace
    end
  end

  defp semantic_enabled?, do: Application.get_env(:jido_code, :source_code_graph_enabled, false)
  defp memory_enabled?, do: Application.get_env(:jido_code, :memory_graph_enabled, false)

  defp context_source_label(:semantic_workflow), do: "the semantic workflow boundary"
  defp context_source_label(:memory_workflow), do: "the memory workflow boundary"
  defp context_source_label(:workspace_with_semantic), do: "AgentWorkspace with explicit semantic graph context"
  defp context_source_label(:workflow_clarification), do: "workflow clarification"
  defp context_source_label(_other), do: "AgentWorkspace"

  defp context_source_name(context_source), do: Atom.to_string(context_source)

  defp runtime_llm_summary(llm_selection) do
    case llm_selection do
      %{model_spec: model_spec} when is_binary(model_spec) -> " with #{model_spec}"
      _other -> ""
    end
  end

  defp llm_selection_payload(llm_selection) do
    llm_selection
    |> LLMSelection.summary()
    |> case do
      nil -> nil
      summary -> normalize_map(summary)
    end
  end

  defp accepted_result_lines(results) do
    results
    |> Enum.map(fn result ->
      summary =
        result
        |> Map.get("result", %{})
        |> normalize_map()
        |> case do
          %{"summary" => summary} -> summary
          %{"reason" => reason} -> reason
          %{} = payload when payload != %{} -> inspect(payload)
          _other -> nil
        end

      child_work_id = normalize_optional_string(Map.get(result, "child_work_id"))
      workflow = normalize_optional_string(Map.get(result, "workflow"))

      [workflow, child_work_id, summary]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" | ")
      |> normalize_optional_string()
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp clarification_lines(%{} = clarification_resume) do
    []
    |> maybe_append_line("prompt", normalize_optional_string(Map.get(clarification_resume, "prompt")))
    |> maybe_append_line("response", normalize_optional_string(Map.get(clarification_resume, "response")))
  end

  defp clarification_lines(_clarification_resume), do: []

  defp referenced_files_from_map(value) when is_map(value) do
    []
    |> Kernel.++(normalize_string_list(Map.get(value, "referenced_files")))
    |> Kernel.++(normalize_string_list(Map.get(value, "files")))
    |> Kernel.++(List.wrap(normalize_optional_string(Map.get(value, "file"))))
    |> Kernel.++(List.wrap(normalize_optional_string(Map.get(value, "path"))))
  end

  defp referenced_files_from_map(_value), do: []

  defp referenced_files_from_text(value) when is_binary(value) do
    ~r/(?:^|[\s(])([A-Za-z0-9_\/\.-]+\.(?:ex|exs|heex|md|json|yaml|yml|js|ts|tsx|css))(?:[:]\d+)?/
    |> Regex.scan(value, capture: :all_but_first)
    |> Enum.map(fn [match] -> String.trim(match) end)
  end

  defp referenced_files_from_text(_value), do: []

  defp contains_any?(text, phrases) when is_binary(text) and is_list(phrases) do
    Enum.any?(phrases, &String.contains?(text, &1))
  end

  defp contains_any?(_text, _phrases), do: false

  defp maybe_append_section(lines, _title, []), do: lines

  defp maybe_append_section(lines, title, entries) when is_list(entries) do
    lines ++ [title <> ":"] ++ Enum.map(entries, &"- #{&1}")
  end

  defp maybe_append_line(lines, _label, nil), do: lines
  defp maybe_append_line(lines, label, value), do: lines ++ ["- #{label}: #{value}"]

  defp normalize_list_of_maps(value) when is_list(value) do
    Enum.map(value, &normalize_map/1)
  end

  defp normalize_list_of_maps(_value), do: []

  defp normalize_string_list(value) when is_list(value) do
    value
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_string_list(_value), do: []

  defp required_string(value, error_type, detail) do
    case normalize_optional_string(value) do
      nil ->
        {:error,
         %{
           "error_type" => error_type,
           "detail" => detail,
           "remediation" => "Retry the conversation turn after repository scope is repaired."
         }}

      normalized ->
        {:ok, normalized}
    end
  end

  defp require_work_item_for_request(work_item_id, %{ambiguous?: true}), do: {:ok, work_item_id}

  defp require_work_item_for_request(work_item_id, _routing) do
    required_string(
      work_item_id,
      "conversation_runtime_work_item_unavailable",
      "Work item scope is missing for real conversation runtime."
    )
  end

  defp normalize_summary(value) when is_binary(value) do
    case String.trim(value) do
      "" -> "The repository conversation completed without a textual summary."
      trimmed -> trimmed
    end
  end

  defp normalize_summary(value), do: inspect(value)

  defp map_get(map, key) when is_map(map) and is_atom(key) do
    string_key = Atom.to_string(key)
    Map.get(map, key) || Map.get(map, string_key)
  end

  defp map_get(map, key) when is_map(map) and is_binary(key) do
    atom_key =
      try do
        String.to_existing_atom(key)
      rescue
        ArgumentError -> nil
      end

    Map.get(map, key) || (atom_key && Map.get(map, atom_key))
  end

  defp map_get(_map, _key), do: nil

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      Map.put(acc, normalized_key, normalize_nested_value(nested_value))
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil

  defp normalize_error(error) when is_map(error) do
    %{}
    |> maybe_put("error_type", string_value(Map.get(error, "error_type") || Map.get(error, :error_type)))
    |> maybe_put("detail", string_value(Map.get(error, "detail") || Map.get(error, :detail)))
    |> maybe_put(
      "remediation",
      string_value(Map.get(error, "remediation") || Map.get(error, :remediation))
    )
  end

  defp runtime_error(reason) do
    %{
      "error_type" => "conversation_runtime_execution_failed",
      "detail" => "Real conversation execution failed (#{inspect(reason)}).",
      "remediation" => "Retry the turn after runtime services recover."
    }
  end

  defp string_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp string_value(value) when is_atom(value), do: value |> Atom.to_string() |> string_value()
  defp string_value(_value), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
