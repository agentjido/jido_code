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
  alias JidoCode.ContextBudget
  alias JidoCode.Conversations.ContextMemory
  alias JidoCode.Conversations.LongTermProvenance
  alias JidoCode.Conversations.RuntimeReadiness
  alias JidoCode.Conversations.WorkflowRouter
  alias JidoCode.LLMSelection
  alias JidoCode.MemoryGraph.WorkflowService, as: MemoryWorkflowService
  alias JidoCode.SourceCodeGraph.WorkflowService, as: SemanticWorkflowService

  @prompt_memory_capture_text_limit 500
  @prompt_memory_default_ttl_ms 86_400_000

  @type runtime_spec :: %{
          conversation_id: String.t(),
          managed_repo_id: String.t(),
          work_item_id: String.t(),
          child_work_id: String.t(),
          turn_id: String.t(),
          command_id: String.t() | nil,
          instruction: String.t(),
          command_type: String.t() | nil,
          actor: map() | nil,
          objective: String.t() | nil,
          source: String.t() | nil,
          scope: atom() | String.t() | nil,
          attachment_mode: atom() | String.t() | nil,
          status: atom() | String.t() | nil,
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
      _ = LongTermProvenance.capture_turn_started(runtime_spec, request, readiness)
      _ = capture_prompt_memory_turn_inputs(runtime_spec, request)

      progress_context_management = record_context_observation(request, runtime_spec, :progress)
      emit.(runtime_progress_event(request) |> maybe_put_context_management(progress_context_management))

      case maybe_request_clarification(request) do
        {:awaiting_input, payload} ->
          _ =
            LongTermProvenance.capture_clarification_request(
              runtime_spec,
              request,
              readiness,
              Map.get(payload, "prompt")
            )

          {:awaiting_input, payload}

        :ok ->
          case invoke(request, runtime_spec, readiness) do
            {:ok, result} ->
              summary = result_summary(result, request.workflow)
              _ = LongTermProvenance.capture_turn_completed(runtime_spec, request, readiness, summary)
              _ = capture_prompt_memory_turn_completed(runtime_spec, request, summary)

              completed_context_management = record_context_observation(request, runtime_spec, :completed)

              emit.(
                %{
                  "kind" => "delta",
                  "text" => summary,
                  "workflow" => Atom.to_string(request.workflow),
                  "context_source" => context_source_name(request.context_source),
                  "context_budget" => ContextBudget.summary(request.context_budget)
                }
                |> maybe_put_context_management(completed_context_management)
              )

              {:completed,
               %{
                 "kind" => "completed",
                 "result" => %{
                   "summary" => summary,
                   "workflow" => Atom.to_string(request.workflow),
                   "context_source" => context_source_name(request.context_source),
                   "instruction" => request.user_instruction,
                   "llm_selection" => llm_selection_payload(request.llm_selection),
                   "context_budget" => ContextBudget.summary(request.context_budget),
                   "context_management" => completed_context_management,
                   "prompt_memory" => prompt_memory_event(request.prompt_memory)
                 }
               }}

            {:error, %{} = typed_error} ->
              _ =
                LongTermProvenance.capture_turn_failed(
                  runtime_spec,
                  request,
                  readiness,
                  Map.get(typed_error, "detail") || Map.get(typed_error, :detail)
                )

              {:failed, %{"kind" => "failed", "error" => normalize_error(typed_error)}}

            {:error, reason, %{} = detail} ->
              _ =
                LongTermProvenance.capture_turn_failed(
                  runtime_spec,
                  request,
                  readiness,
                  Map.get(detail, :detail) || Map.get(detail, "detail") || inspect(reason)
                )

              {:failed, %{"kind" => "failed", "error" => normalize_error(Map.put_new(detail, :reason, reason))}}

            {:error, reason} ->
              _ = LongTermProvenance.capture_turn_failed(runtime_spec, request, readiness, inspect(reason))
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
        prompt_memory_scope = prompt_memory_scope(runtime_spec, managed_repo_id, work_item_id, workflow)
        prompt_memory = retrieve_prompt_memory(prompt_memory_scope, workflow)

        runtime_instruction =
          bounded_instruction(
            runtime_spec,
            workflow,
            managed_repo_id,
            work_item_id,
            readiness.workspace_path,
            shared_context,
            referenced_files,
            clarification_resume,
            prompt_memory,
            readiness.llm_selection
          )

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
           prompt_memory: prompt_memory,
           llm_selection: readiness.llm_selection,
           context_budget: runtime_instruction.context_budget,
           instruction: runtime_instruction.text
         }}
      end
    end
  end

  defp maybe_request_clarification(
         %{
           routing: %{ambiguous?: true} = routing,
           context_source: context_source
         } = request
       ) do
    {:awaiting_input,
     %{
       "kind" => "needs_input",
       "prompt" => workflow_clarification_prompt(),
       "workflow" => "clarify",
       "context_source" => context_source_name(context_source),
       "context_budget" => ContextBudget.summary(request.context_budget),
       "prompt_memory" => prompt_memory_event(request.prompt_memory),
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
         "context_budget" => ContextBudget.summary(request.context_budget),
         "prompt_memory" => prompt_memory_event(request.prompt_memory),
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
       when workflow in [:plan, :execute, :refactor, :review, :explain] do
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
       when workflow in [:plan, :execute, :refactor, :review, :explain] do
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

        :refactor ->
          MemoryWorkflowService.refactor(
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

      {:error, reason, _}
      when reason in [:memory_graph_write_failed, :memory_graph_query_failed, :memory_graph_timeout] ->
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
       when workflow in [:plan, :execute, :refactor, :review, :explain] do
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

      :refactor ->
        AgentWorkspace.refactor_work(
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

      {:error, reason, _} = _error
      when reason in [:source_code_graph_analysis_failed, :source_code_graph_store_failed] ->
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
               llm_selection: readiness.llm_selection
             ) do
          {:error, :source_code_graph_disabled, _} ->
            log_semantic_degradation(managed_repo_id, :disabled)

            AgentWorkspace.plan_work(managed_repo_id, work_item_id, instruction,
              workspace_path: workspace_path,
              actor: actor,
              llm_selection: readiness.llm_selection
            )

          {:error, :source_code_graph_not_ready, _} ->
            log_semantic_degradation(managed_repo_id, :not_ready)

            AgentWorkspace.plan_work(managed_repo_id, work_item_id, instruction,
              workspace_path: workspace_path,
              actor: actor,
              llm_selection: readiness.llm_selection
            )

          {:error, reason, _} = _error
          when reason in [:source_code_graph_analysis_failed, :source_code_graph_store_failed] ->
            log_semantic_degradation(managed_repo_id, {:analysis_failed, reason})

            AgentWorkspace.plan_work(managed_repo_id, work_item_id, instruction,
              workspace_path: workspace_path,
              actor: actor,
              llm_selection: readiness.llm_selection
            )

          result ->
            result
        end

      :review ->
        case SemanticWorkflowService.review(managed_repo_id, work_item_id, instruction,
               semantic: semantic_opts,
               workspace_path: workspace_path,
               actor: actor,
               llm_selection: readiness.llm_selection
             ) do
          {:error, :source_code_graph_disabled, _} ->
            log_semantic_degradation(managed_repo_id, :disabled)

            AgentWorkspace.review_work(managed_repo_id, work_item_id, instruction,
              workspace_path: workspace_path,
              actor: actor,
              llm_selection: readiness.llm_selection
            )

          {:error, :source_code_graph_not_ready, _} ->
            log_semantic_degradation(managed_repo_id, :not_ready)

            AgentWorkspace.review_work(managed_repo_id, work_item_id, instruction,
              workspace_path: workspace_path,
              actor: actor,
              llm_selection: readiness.llm_selection
            )

          {:error, reason, _} = _error
          when reason in [:source_code_graph_analysis_failed, :source_code_graph_store_failed] ->
            log_semantic_degradation(managed_repo_id, {:analysis_failed, reason})

            AgentWorkspace.review_work(managed_repo_id, work_item_id, instruction,
              workspace_path: workspace_path,
              actor: actor,
              llm_selection: readiness.llm_selection
            )

          result ->
            result
        end

      :explain ->
        case SemanticWorkflowService.explain(managed_repo_id, work_item_id, instruction,
               semantic: semantic_opts,
               workspace_path: workspace_path,
               actor: actor,
               llm_selection: readiness.llm_selection
             ) do
          {:error, :source_code_graph_disabled, _} ->
            log_semantic_degradation(managed_repo_id, :disabled)

            AgentWorkspace.explain_work(managed_repo_id, work_item_id, instruction,
              workspace_path: workspace_path,
              actor: actor,
              llm_selection: readiness.llm_selection
            )

          {:error, :source_code_graph_not_ready, _} ->
            log_semantic_degradation(managed_repo_id, :not_ready)

            AgentWorkspace.explain_work(managed_repo_id, work_item_id, instruction,
              workspace_path: workspace_path,
              actor: actor,
              llm_selection: readiness.llm_selection
            )

          {:error, reason, _} = _error
          when reason in [:source_code_graph_analysis_failed, :source_code_graph_store_failed] ->
            log_semantic_degradation(managed_repo_id, {:analysis_failed, reason})

            AgentWorkspace.explain_work(managed_repo_id, work_item_id, instruction,
              workspace_path: workspace_path,
              actor: actor,
              llm_selection: readiness.llm_selection
            )

          result ->
            result
        end

      _workflow ->
        # Execute and refactor use workspace dispatch with optional semantic context.
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
         clarification_resume,
         prompt_memory,
         llm_selection
       ) do
    accepted_tool_results =
      shared_context
      |> Map.get("accepted_tool_results", [])
      |> normalize_list_of_maps()
      |> Enum.take(-3)

    compaction_summaries =
      active_compaction_summaries(managed_repo_id, work_item_id, workflow, shared_context)

    policy =
      runtime_spec
      |> runtime_context_budget_opts(shared_context)
      |> Keyword.put(:llm_selection, llm_selection)
      |> ContextBudget.policy()

    sections = [
      ContextBudget.section(
        :system_prompt,
        "Repository conversation objective: #{normalize_optional_string(map_get(runtime_spec, :objective)) || "Coordinate managed repository work."}",
        retention: :required
      ),
      ContextBudget.section(:workflow, "Workflow: #{workflow_name(workflow)}", retention: :important),
      ContextBudget.section(
        :current_request,
        "Current request: #{normalize_optional_string(map_get(runtime_spec, :instruction)) || "Continue the repository conversation."}",
        retention: :required
      ),
      ContextBudget.section(
        :repository_scope,
        [
          "- managed_repo_id: #{managed_repo_id}",
          "- work_item_id: #{work_item_id}",
          "- workspace_path: #{workspace_path}",
          "- source: #{normalize_optional_string(map_get(runtime_spec, :source)) || "conversation"}"
        ],
        retention: :required
      ),
      ContextBudget.section(:referenced_files, referenced_files, retention: :useful),
      ContextBudget.section(:accepted_tool_results, accepted_result_lines(accepted_tool_results), retention: :useful),
      ContextBudget.section(:compaction_summary, compaction_summary_lines(compaction_summaries),
        retention: :useful,
        metadata: %{
          kind: :compaction_summary,
          summary_count: length(compaction_summaries),
          summary_ids: Enum.map(compaction_summaries, &Map.get(&1, "id"))
        }
      ),
      ContextBudget.section(:clarification_context, clarification_lines(clarification_resume), retention: :important),
      ContextBudget.section(:prompt_memory, prompt_memory_lines(prompt_memory, accepted_tool_results),
        retention: :useful,
        metadata: prompt_memory_event(prompt_memory)
      ),
      ContextBudget.section(
        :guidance,
        [
          "- Stay within the current repository and governed work item unless the conversation explicitly changes scope.",
          "- Treat referenced files and accepted tool results as bounded context, and confirm details against the current source before making claims."
        ],
        retention: :important
      )
    ]

    packed = ContextBudget.pack(sections, policy: policy)

    %{
      text: packed.text,
      context_budget: packed
    }
  end

  defp active_compaction_summaries(managed_repo_id, work_item_id, workflow, shared_context) do
    active_summary_ids =
      shared_context
      |> Map.get("active_compaction_summary_ids", [])
      |> normalize_string_list()

    summaries =
      AgentWorkspace.context_compaction_summaries(managed_repo_id, work_item_id,
        workflow: workflow,
        limit: 6
      )

    case active_summary_ids do
      [] ->
        summaries

      summary_ids ->
        active_summaries = Enum.filter(summaries, &(Map.get(&1, "id") in summary_ids))

        if active_summaries == [], do: summaries, else: active_summaries
    end
  end

  defp compaction_summary_lines([]), do: []

  defp compaction_summary_lines(summaries) when is_list(summaries) do
    Enum.map(summaries, fn summary ->
      summary_text = Map.get(summary, "summary_text", "")
      summary_id = Map.get(summary, "id", "unknown-summary")
      workflow = Map.get(summary, "workflow", "unknown-workflow")
      specialist_role = Map.get(summary, "specialist_role", "unknown-specialist")
      span_count = summary |> Map.get("source_span_ids", []) |> length()

      "- #{summary_id} (#{workflow}/#{specialist_role}, #{span_count} span(s)): #{summary_text}"
    end)
  end

  defp runtime_progress_event(request) do
    if request.routing.ambiguous? do
      %{
        "kind" => "progress",
        "summary" =>
          "Requesting clarification before choosing whether to plan, implement, refactor, review, or explain this repository work.",
        "workflow" => "clarify",
        "context_source" => context_source_name(request.context_source),
        "referenced_files" => request.referenced_files,
        "context_budget" => ContextBudget.summary(request.context_budget),
        "prompt_memory" => prompt_memory_event(request.prompt_memory),
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
        "llm_selection" => llm_selection_payload(request.llm_selection),
        "context_budget" => ContextBudget.summary(request.context_budget),
        "prompt_memory" => prompt_memory_event(request.prompt_memory)
      }
    end
  end

  defp record_context_observation(%{work_item_id: nil}, _runtime_spec, _state), do: :ok

  defp record_context_observation(request, runtime_spec, state) do
    case AgentWorkspace.record_context_observation(
           request.managed_repo_id,
           request.work_item_id,
           %{
             workflow: request.workflow,
             specialist_role: request.workflow,
             conversation_id: normalize_optional_string(map_get(runtime_spec, :conversation_id)),
             turn_id: normalize_optional_string(map_get(runtime_spec, :turn_id)),
             source: "conversation_runtime",
             context_budget: ContextBudget.summary(request.context_budget),
             diagnostics: %{
               state: state,
               context_source: context_source_name(request.context_source)
             }
           }
         ) do
      {:ok, summary} -> summary
      {:error, reason} -> %{"state" => "degraded", "diagnostics" => [%{"reason" => inspect(reason)}]}
    end
  end

  defp maybe_put_context_management(event, %{} = context_management) do
    Map.put(event, "context_management", context_management)
  end

  defp maybe_put_context_management(event, _context_management), do: event

  defp runtime_context_budget_opts(runtime_spec, shared_context) do
    conversation_budget =
      runtime_spec
      |> map_get(:conversation_metadata)
      |> normalize_map()
      |> Map.get("context_budget")

    shared_budget = Map.get(shared_context, "context_budget")

    []
    |> Keyword.merge(context_budget_keyword(conversation_budget))
    |> Keyword.merge(context_budget_keyword(shared_budget))
  end

  defp context_budget_keyword(%{} = budget) do
    budget
    |> Enum.flat_map(fn {key, value} ->
      case context_budget_key(key) do
        nil -> []
        atom -> [{atom, value}]
      end
    end)
  end

  defp context_budget_keyword(_budget), do: []

  defp context_budget_key(key) when is_atom(key), do: key

  defp context_budget_key(key) when is_binary(key) do
    key
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> nil
  end

  defp context_budget_key(_key), do: nil

  defp prompt_memory_scope(runtime_spec, managed_repo_id, work_item_id, workflow) do
    %{
      managed_repo_id: managed_repo_id,
      work_item_id: normalize_optional_string(work_item_id),
      conversation_id: normalize_optional_string(map_get(runtime_spec, :conversation_id)),
      turn_id: normalize_optional_string(map_get(runtime_spec, :turn_id)),
      workflow: workflow,
      source: normalize_optional_string(map_get(runtime_spec, :source)) || "conversation_runtime"
    }
  end

  defp retrieve_prompt_memory(scope, workflow) do
    case ContextMemory.retrieve(scope, query: prompt_memory_query(workflow)) do
      {:ok, prompt_memory} ->
        prompt_memory

      {:error, reason} ->
        %{
          state: :degraded,
          namespace: nil,
          items: [],
          instruction_lines: [],
          diagnostics: %{reason: inspect(reason)},
          metadata: %{}
        }
    end
  end

  defp prompt_memory_query(workflow) do
    %{
      kinds: prompt_memory_kinds(workflow),
      tags_any: ["prompt-memory"],
      order: :desc,
      extensions: %{workflow: workflow_name(workflow)}
    }
  end

  defp prompt_memory_kinds(workflow) when workflow in [:execute, :refactor, :review] do
    [
      :active_constraint,
      :accepted_tool_result,
      :clarification_answer,
      :plan_summary,
      :next_step,
      :stable_preference,
      :workflow_preference
    ]
  end

  defp prompt_memory_kinds(_workflow), do: ContextMemory.supported_kinds()

  defp prompt_memory_lines(prompt_memory, accepted_tool_results) do
    lines = ContextMemory.instruction_lines(prompt_memory)

    if accepted_tool_results == [] do
      lines
    else
      Enum.reject(lines, &String.starts_with?(&1, "- accepted_tool_result:"))
    end
  end

  defp prompt_memory_event(%{state: state} = prompt_memory) do
    metadata = normalize_map(map_get(prompt_memory, :metadata))
    diagnostics = normalize_map(map_get(prompt_memory, :diagnostics))

    %{}
    |> Map.put("state", normalize_optional_string(state) || "unknown")
    |> maybe_put("namespace", normalize_optional_string(map_get(prompt_memory, :namespace)))
    |> Map.put("item_count", prompt_memory_item_count(prompt_memory, metadata))
    |> maybe_put("provider", normalize_optional_string(Map.get(metadata, "provider")))
    |> maybe_put("diagnostics", prompt_memory_diagnostics(diagnostics))
  end

  defp prompt_memory_event(_prompt_memory), do: %{"state" => "unavailable", "item_count" => 0}

  defp prompt_memory_item_count(prompt_memory, metadata) do
    case Map.get(metadata, "total_count") do
      count when is_integer(count) ->
        count

      _other ->
        case map_get(prompt_memory, :items) do
          items when is_list(items) -> length(items)
          _other -> 0
        end
    end
  end

  defp prompt_memory_diagnostics(diagnostics) when diagnostics == %{}, do: nil
  defp prompt_memory_diagnostics(diagnostics), do: diagnostics

  defp workflow_name(workflow) when is_atom(workflow), do: Atom.to_string(workflow)
  defp workflow_name(workflow) when is_binary(workflow), do: workflow
  defp workflow_name(_workflow), do: "clarify"

  defp capture_prompt_memory_turn_inputs(runtime_spec, request) do
    scope = prompt_memory_scope(runtime_spec, request.managed_repo_id, request.work_item_id, request.workflow)
    base_metadata = prompt_memory_capture_metadata(scope, "turn_input")

    prompt_memory_input_records(request, base_metadata)
    |> remember_prompt_memory_records(scope)
  end

  defp capture_prompt_memory_turn_completed(runtime_spec, request, summary) do
    scope = prompt_memory_scope(runtime_spec, request.managed_repo_id, request.work_item_id, request.workflow)

    kind =
      case request.workflow do
        :plan -> :plan_summary
        _workflow -> :next_step
      end

    %{
      kind: kind,
      text: bounded_prompt_memory_text(summary),
      metadata: prompt_memory_capture_metadata(scope, "turn_completed"),
      tags: ["runtime-completion", workflow_name(request.workflow)]
    }
    |> then(fn record ->
      if record.text do
        remember_prompt_memory_records([record], scope)
      else
        :ok
      end
    end)
  end

  defp prompt_memory_input_records(request, base_metadata) do
    []
    |> Kernel.++(clarification_prompt_memory_records(request.clarification_resume, base_metadata))
    |> Kernel.++(accepted_tool_result_prompt_memory_records(request.shared_context, base_metadata))
    |> Kernel.++(active_constraint_prompt_memory_records(request.shared_context, base_metadata))
  end

  defp clarification_prompt_memory_records(%{} = clarification_resume, base_metadata)
       when map_size(clarification_resume) > 0 do
    text =
      []
      |> maybe_append_line("prompt", normalize_optional_string(Map.get(clarification_resume, "prompt")))
      |> maybe_append_line("response", normalize_optional_string(Map.get(clarification_resume, "response")))
      |> Enum.join(" ")
      |> bounded_prompt_memory_text()

    if text do
      [
        %{
          kind: :clarification_answer,
          text: text,
          metadata:
            Map.merge(base_metadata, %{
              "capture_event" => "clarification_resume",
              "clarification_prompt" => bounded_prompt_memory_text(Map.get(clarification_resume, "prompt"))
            }),
          tags: ["clarification-resume"]
        }
      ]
    else
      []
    end
  end

  defp clarification_prompt_memory_records(_clarification_resume, _base_metadata), do: []

  defp accepted_tool_result_prompt_memory_records(shared_context, base_metadata) do
    shared_context
    |> Map.get("accepted_tool_results", [])
    |> normalize_list_of_maps()
    |> Enum.take(-3)
    |> Enum.flat_map(fn result ->
      case accepted_result_line(result) |> bounded_prompt_memory_text() do
        nil ->
          []

        text ->
          [
            %{
              kind: :accepted_tool_result,
              text: text,
              metadata:
                Map.merge(base_metadata, %{
                  "capture_event" => "accepted_tool_result",
                  "child_work_id" => normalize_optional_string(Map.get(result, "child_work_id")),
                  "accepted_workflow" => normalize_optional_string(Map.get(result, "workflow"))
                }),
              tags: ["accepted-tool-result"]
            }
          ]
      end
    end)
  end

  defp active_constraint_prompt_memory_records(shared_context, base_metadata) do
    shared_context
    |> active_constraint_values()
    |> Enum.flat_map(fn value ->
      case bounded_prompt_memory_text(value) do
        nil ->
          []

        text ->
          [
            %{
              kind: :active_constraint,
              text: text,
              metadata: Map.put(base_metadata, "capture_event", "active_constraint"),
              tags: ["active-constraint"]
            }
          ]
      end
    end)
  end

  defp active_constraint_values(shared_context) do
    []
    |> Kernel.++(constraint_values(Map.get(shared_context, "active_constraints")))
    |> Kernel.++(constraint_values(Map.get(shared_context, "accepted_constraints")))
    |> Kernel.++(constraint_values(Map.get(shared_context, "constraints")))
    |> Enum.uniq()
  end

  defp constraint_values(values) when is_list(values) do
    values
    |> Enum.flat_map(fn
      value when is_binary(value) ->
        [value]

      %{} = value ->
        [
          Map.get(value, "summary"),
          Map.get(value, "constraint"),
          Map.get(value, "text"),
          Map.get(value, "detail")
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.take(1)

      _other ->
        []
    end)
  end

  defp constraint_values(value) when is_binary(value), do: [value]
  defp constraint_values(_value), do: []

  defp remember_prompt_memory_records(records, scope) do
    Enum.each(records, fn record ->
      _ = ContextMemory.remember(scope, record)
    end)

    :ok
  end

  defp prompt_memory_capture_metadata(scope, capture_event) do
    namespace_metadata =
      case ContextMemory.namespaces(scope) do
        {:ok, %{primary: primary, previous: previous}} ->
          %{
            "prompt_memory_namespace" => primary,
            "previous_prompt_memory_namespaces" => previous
          }

        {:error, _reason} ->
          %{}
      end

    namespace_metadata
    |> Map.merge(%{
      "capture_event" => capture_event,
      "retention_policy" => "short_term_prompt_context",
      "ttl_ms" => prompt_memory_ttl_ms()
    })
  end

  defp prompt_memory_ttl_ms do
    case Application.get_env(:jido_code, :conversation_context_memory, []) do
      config when is_list(config) ->
        case Keyword.get(config, :ttl_ms) do
          ttl_ms when is_integer(ttl_ms) and ttl_ms > 0 -> ttl_ms
          _other -> @prompt_memory_default_ttl_ms
        end

      _other ->
        @prompt_memory_default_ttl_ms
    end
  end

  defp bounded_prompt_memory_text(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil -> nil
      text -> String.slice(text, 0, @prompt_memory_capture_text_limit)
    end
  end

  defp result_summary(result, workflow) do
    case workflow do
      :plan -> Map.get(result, :plan) || Map.get(result, "plan")
      :execute -> Map.get(result, :changes) || Map.get(result, "changes")
      :refactor -> Map.get(result, :refactoring) || Map.get(result, "refactoring")
      :review -> Map.get(result, :feedback) || Map.get(result, "feedback")
      :explain -> Map.get(result, :explanation) || Map.get(result, "explanation")
    end
    |> normalize_summary()
  end

  defp clarification_phrase?(instruction, workflow) do
    text = (instruction || "") |> String.downcase()

    contains_any?(text, ["clarify", "needs input", "which file", "what file"]) or
      (workflow in [:execute, :refactor, :review] and contains_any?(text, ["file", "module", "function"]))
  end

  defp clarification_prompt(:execute),
    do: "Which file or module should I change first?"

  defp clarification_prompt(:refactor),
    do: "Which file, module, or behavior-preserving structure should I refactor first?"

  defp clarification_prompt(:review),
    do: "Which file, module, or diff should I review first?"

  defp clarification_prompt(_workflow),
    do: "Which file or module should I inspect first?"

  defp workflow_clarification_prompt do
    "Do you want me to plan, implement, refactor, review, or explain this request?"
  end

  defp select_context_source(nil), do: :workflow_clarification

  defp select_context_source(workflow) when workflow in [:execute, :refactor] do
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
    |> Enum.map(&accepted_result_line/1)
    |> Enum.reject(&is_nil/1)
  end

  defp accepted_result_line(result) do
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
