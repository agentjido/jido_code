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
  alias JidoCode.Conversations.RuntimeReadiness
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
           RuntimeReadiness.resolve(runtime_spec[:managed_repo_id] || runtime_spec["managed_repo_id"]),
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
                   "instruction" => request.user_instruction
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
           ),
         {:ok, work_item_id} <-
           required_string(
             runtime_spec[:work_item_id] || runtime_spec["work_item_id"],
             "conversation_runtime_work_item_unavailable",
             "Work item scope is missing for real conversation runtime."
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
      child_work_result = normalize_map(map_get(runtime_spec, :child_work_result))

      workflow =
        prior_workflow(turn_payload, child_work_result) ||
          infer_workflow(instruction, objective, map_get(runtime_spec, :conversation_metadata))

      referenced_files =
        shared_context
        |> Map.get("referenced_files", [])
        |> normalize_string_list()
        |> Kernel.++(referenced_files_from_map(turn_payload))
        |> Kernel.++(referenced_files_from_text(instruction))
        |> Enum.uniq()

      clarification_resume = normalize_map(Map.get(turn_payload, "clarification_resume"))

      context_source = select_context_source(workflow)

      {:ok,
       %{
         managed_repo_id: managed_repo_id,
         work_item_id: work_item_id,
         user_instruction: instruction || "Continue the repository conversation.",
         workflow: workflow,
         context_source: context_source,
         source: normalize_optional_string(map_get(runtime_spec, :source)),
         objective: objective,
         referenced_files: referenced_files,
         shared_context: shared_context,
         clarification_resume: clarification_resume,
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

  defp maybe_request_clarification(%{
         user_instruction: instruction,
         clarification_resume: clarification_resume,
         referenced_files: referenced_files,
         workflow: workflow
       } = request) do
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
          actor: map_get(runtime_spec, :actor)
        )

      :review ->
        SemanticWorkflowService.review(
          request.managed_repo_id,
          request.work_item_id,
          request.instruction,
          semantic: semantic_opts,
          workspace_path: readiness.workspace_path,
          actor: map_get(runtime_spec, :actor)
        )

      :explain ->
        SemanticWorkflowService.explain(
          request.managed_repo_id,
          request.work_item_id,
          request.instruction,
          semantic: semantic_opts,
          workspace_path: readiness.workspace_path,
          actor: map_get(runtime_spec, :actor)
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
        invoke_workspace(request, readiness, actor,
          source_code_graph: [workspace_path: readiness.workspace_path, prepare: :load_if_missing]
        )

      _other ->
        invoke_workspace(request, readiness, actor, [])
    end
  end

  defp invoke_memory_workflow(%{workflow: workflow} = request, readiness, actor)
       when workflow in [:plan, :execute, :review, :explain] do
    memory_opts = [workspace_path: readiness.workspace_path, prepare: :recover_if_needed]

    case workflow do
      :plan ->
        MemoryWorkflowService.plan(
          request.managed_repo_id,
          request.work_item_id,
          request.instruction,
          memory: memory_opts,
          workspace_path: readiness.workspace_path,
          actor: actor
        )

      :execute ->
        MemoryWorkflowService.execute(
          request.managed_repo_id,
          request.work_item_id,
          request.instruction,
          memory: memory_opts,
          workspace_path: readiness.workspace_path,
          actor: actor
        )

      :review ->
        MemoryWorkflowService.review(
          request.managed_repo_id,
          request.work_item_id,
          request.instruction,
          memory: memory_opts,
          workspace_path: readiness.workspace_path,
          actor: actor
        )

      :explain ->
        MemoryWorkflowService.explain(
          request.managed_repo_id,
          request.work_item_id,
          request.instruction,
          memory: memory_opts,
          workspace_path: readiness.workspace_path,
          actor: actor
        )
    end
  end

  defp invoke_workspace(%{workflow: workflow} = request, readiness, actor, extra_opts)
       when workflow in [:plan, :execute, :review, :explain] do
    opts =
      [workspace_path: readiness.workspace_path, actor: actor]
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
    accepted_tool_results =
      shared_context
      |> Map.get("accepted_tool_results", [])
      |> normalize_list_of_maps()
      |> Enum.take(-3)

    [
      "Repository conversation objective: #{normalize_optional_string(map_get(runtime_spec, :objective)) || "Coordinate managed repository work."}",
      "Workflow: #{Atom.to_string(workflow)}",
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
    %{
      "kind" => "progress",
      "summary" =>
        "Routing the repository conversation through the #{Atom.to_string(request.workflow)} specialist using #{context_source_label(request.context_source)}.",
      "workflow" => Atom.to_string(request.workflow),
      "context_source" => context_source_name(request.context_source),
      "referenced_files" => request.referenced_files
    }
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

  defp prior_workflow(turn_payload, child_work_result) do
    turn_workflow =
      turn_payload
      |> Map.get("conversation_runtime")
      |> normalize_map()
      |> Map.get("workflow")

    child_work_workflow =
      child_work_result
      |> Map.get("latest_progress")
      |> normalize_map()
      |> Map.get("workflow") ||
        child_work_result
        |> Map.get("needs_input")
        |> normalize_map()
        |> Map.get("workflow")

    normalize_workflow(turn_workflow || child_work_workflow)
  end

  defp infer_workflow(instruction, objective, conversation_metadata) do
    text =
      [instruction, objective, conversation_metadata && map_get(conversation_metadata, "last_work_action")]
      |> Enum.map(&normalize_optional_string/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")
      |> String.downcase()

    cond do
      contains_any?(text, ["plan", "approach", "break down", "step-by-step", "roadmap", "outline"]) ->
        :plan

      contains_any?(text, ["review", "audit", "critique", "risk", "regression", "security"]) ->
        :review

      contains_any?(text, ["implement", "change", "fix", "update", "edit", "refactor", "write", "add", "remove", "patch"]) ->
        :execute

      true ->
        :explain
    end
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
  defp context_source_label(_other), do: "AgentWorkspace"

  defp context_source_name(context_source), do: Atom.to_string(context_source)

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

  defp normalize_workflow(value) when value in [:plan, :execute, :review, :explain], do: value

  defp normalize_workflow(value) when is_binary(value) do
    case String.trim(value) do
      "plan" -> :plan
      "execute" -> :execute
      "review" -> :review
      "explain" -> :explain
      _other -> nil
    end
  end

  defp normalize_workflow(_value), do: nil

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
  defp normalize_optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_optional_string()
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
