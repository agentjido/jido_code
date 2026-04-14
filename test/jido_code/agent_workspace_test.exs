defmodule JidoCode.AgentWorkspaceTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.agent_os_integration.workspace_context
  # covers: architecture.agent_os_integration.product_work_entrypoints_route_to_workspace
  # covers: architecture.agent_os_integration.pod_cleanup_on_completion
  # covers: architecture.agent_os_integration.multiple_pods_parallel_execution
  # covers: architecture.agent_os_integration.kernel_snapshots_restore_resumable_runtime_state
  # covers: architecture.agent_os_integration.missing_kernel_runtime_recovers_from_snapshot
  # covers: architecture.agent_os_integration.repository_work_queue_is_bounded
  # covers: architecture.agent_os_integration.eager_collaboration_state_is_seeded_before_specialist_work
  # covers: architecture.policy_layers.runtime_policy_governs_runtime_capability
  # covers: architecture.policy_layers.runtime_capacity_limits_fail_closed
  # covers: architecture.policy_layers.runtime_entrypoints_seed_explicit_collaboration_context
  # covers: architecture.policy_layers.memory_operator_actions_remain_policy_bound
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.stale_queries_and_failures_remain_bounded
  # covers: architecture.source_code_graph_pod.workspace_binding_is_explicit_and_product_owned
  # covers: architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
  # covers: architecture.memory_capture_plane.workflow_provenance_and_memory_are_written_to_distinct_named_graphs
  # covers: architecture.agent_os_integration.memory_graph_product_actions_stay_workspace_bound
  # covers: architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
  # covers: architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentOS.Manager
  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Operations.Ingress
  alias JidoCode.Projects.Project

  describe "kernel lifecycle" do
    test "ensure_kernel creates or returns existing kernel" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"

      assert {:ok, kernel_name} = AgentWorkspace.ensure_kernel(managed_repo_id)
      assert is_atom(kernel_name)

      # Calling again should return the same kernel
      assert {:ok, ^kernel_name} = AgentWorkspace.ensure_kernel(managed_repo_id)
    end

    test "kernel_status returns nil for non-existent kernel" do
      refute AgentWorkspace.kernel_status("nonexistent-repo-#{System.unique_integer()}")
    end

    test "list_kernels returns list of kernel names" do
      kernels = AgentWorkspace.list_kernels()
      assert is_list(kernels)
    end

    test "shutdown_kernel is idempotent" do
      managed_repo_id = "temp-repo-#{System.unique_integer()}"

      # Should not error even if kernel doesn't exist
      assert :ok = AgentWorkspace.shutdown_kernel(managed_repo_id)
    end

    test "ensure_kernel restores persisted work pods after a restart" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, initial_result} =
               AgentWorkspace.plan_work(
                 managed_repo_id,
                 work_item_id,
                 "Persist planning state",
                 workspace_path: workspace_path
               )

      assert initial_result.plan =~ "deterministic planner response"
      assert work_item_id in AgentWorkspace.active_work_items(managed_repo_id)

      assert :ok = AgentWorkspace.shutdown_kernel(managed_repo_id)
      refute Manager.kernel_exists?(managed_repo_id)

      assert {:ok, _kernel_name} = AgentWorkspace.ensure_kernel(managed_repo_id)
      assert work_item_id in AgentWorkspace.active_work_items(managed_repo_id)

      pod_status = Manager.pod_status(managed_repo_id, "coding-pod-#{work_item_id}")
      assert get_in(pod_status, [:metadata, :last_plan, :plan]) =~ "deterministic planner response"
    end

    test "ensure_kernel recovers after an unexpected kernel crash" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, _pod_name} =
               AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)

      old_pid =
        managed_repo_id
        |> Manager.kernel_status()
        |> Map.fetch!(:supervisor_pid)

      Process.exit(old_pid, :kill)
      Process.sleep(200)

      assert {:ok, _kernel_name} = AgentWorkspace.ensure_kernel(managed_repo_id)

      new_pid =
        managed_repo_id
        |> Manager.kernel_status()
        |> Map.fetch!(:supervisor_pid)

      assert is_pid(new_pid)
      refute new_pid == old_pid
      assert work_item_id in AgentWorkspace.active_work_items(managed_repo_id)
    end
  end

  describe "pod lifecycle" do
    test "ensure_coding_pod returns ok with pod name" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, pod_name} =
               AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)

      assert is_atom(pod_name)
    end

    test "complete_work stops the work item and removes it from active work" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, _pod_name} =
               AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)

      assert work_item_id in AgentWorkspace.active_work_items(managed_repo_id)

      assert :ok = AgentWorkspace.complete_work(managed_repo_id, work_item_id)
      refute work_item_id in AgentWorkspace.active_work_items(managed_repo_id)
    end

    test "active_work_items returns active coding work items" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, _pod_name} =
               AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)

      items = AgentWorkspace.active_work_items(managed_repo_id)
      assert work_item_id in items
    end

    test "enforces a bounded concurrent work queue for new work items" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()
      work_item_1 = "work-#{System.unique_integer()}"
      work_item_2 = "work-#{System.unique_integer()}"
      previous_limit = Application.get_env(:jido_code, :agent_workspace_max_concurrent_work_items)

      Application.put_env(:jido_code, :agent_workspace_max_concurrent_work_items, 1)

      on_exit(fn ->
        if is_nil(previous_limit) do
          Application.delete_env(:jido_code, :agent_workspace_max_concurrent_work_items)
        else
          Application.put_env(:jido_code, :agent_workspace_max_concurrent_work_items, previous_limit)
        end

        File.rm_rf!(workspace_path)
      end)

      assert {:ok, _pod_name} =
               AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_1, workspace_path)

      assert {:error, {:work_queue_full, %{limit: 1, active_work_items: [^work_item_1]}}} =
               AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_2, workspace_path)
    end
  end

  describe "work execution" do
    test "plan_work returns ok with plan map" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, result} =
               AgentWorkspace.plan_work(
                 managed_repo_id,
                 work_item_id,
                 "Implement feature",
                 workspace_path: workspace_path
               )

      assert is_map(result)
      assert Map.has_key?(result, :plan)
      assert result.plan =~ "deterministic planner response"
    end

    test "execute_work returns ok with changes map" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, result} =
               AgentWorkspace.execute_work(
                 managed_repo_id,
                 work_item_id,
                 "Implement function",
                 workspace_path: workspace_path
               )

      assert is_map(result)
      assert Map.has_key?(result, :changes)
      assert result.changes =~ "deterministic coder response"
    end

    test "execute_work injects bounded memory context into the coder request" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()
      previous = Application.get_env(:jido_code, :memory_graph_enabled, false)

      Application.put_env(:jido_code, :memory_graph_enabled, true)

      on_exit(fn ->
        Application.put_env(:jido_code, :memory_graph_enabled, previous)
        File.rm_rf!(workspace_path)
      end)

      memory_graph = %{
        workflow: :execute,
        graph: %{
          ready?: true,
          stale?: false,
          state: :ready,
          current_revision: "rev-45-execute"
        },
        freshness: %{
          state: :ready,
          label: "Memory graph ready"
        },
        policy: %{
          intent: :implementation_constraints,
          follow_up_intent: :work_item,
          memory_kinds: [:decision, :invariant, :convention, :known_issue, :pattern],
          provenance_kinds: [:plan, :review, :patch]
        },
        selection: %{
          governed_references: [
            %{kind: :run, id: "run-45", iri: "https://example.test/run-45", label: "Run 45"}
          ],
          memory_resources: ["https://example.test/memory#decision-45"],
          provenance_resources: ["https://example.test/workflow_provenance#plan-45"],
          related_resources: [
            "https://example.test/memory#decision-45",
            "https://example.test/workflow_provenance#plan-45"
          ],
          selected_items: %{
            memories: [
              %{
                memory_kind: "Decision",
                content: "Keep greet/1 behavior stable."
              }
            ],
            provenance: [
              %{
                provenance_kind: "Plan",
                content: "Refactor through a helper and preserve nil handling."
              }
            ]
          }
        }
      }

      assert {:ok, result} =
               AgentWorkspace.execute_work(
                 managed_repo_id,
                 work_item_id,
                 "Implement function with bounded memory context",
                 workspace_path: workspace_path,
                 memory_graph: memory_graph
               )

      assert result.workflow_provenance.workflow == :execute
      assert result.memory_context.workflow == :execute
      assert result.memory_context.graph["ready?"] == true
      assert result.memory_context.policy["intent"] == "implementation_constraints"

      assert result.memory_context.selection["governed_references"] == [
               %{
                 "kind" => "run",
                 "id" => "run-45",
                 "iri" => "https://example.test/run-45",
                 "label" => "Run 45"
               }
             ]

      assert result.changes =~ "Memory context:"
      assert result.changes =~ "workflow: :execute"
      assert result.changes =~ "\"intent\" => \"implementation_constraints\""
      assert result.changes =~ "Keep greet/1 behavior stable."
    end

    test "review_work returns ok with feedback map" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, result} =
               AgentWorkspace.review_work(
                 managed_repo_id,
                 work_item_id,
                 "Review code",
                 workspace_path: workspace_path
               )

      assert is_map(result)
      assert Map.has_key?(result, :feedback)
      assert result.feedback =~ "deterministic reviewer response"
    end

    test "full_workflow returns ok with plan, changes, and feedback" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      assert {:ok, result} =
               AgentWorkspace.full_workflow(
                 managed_repo_id,
                 work_item_id,
                 "Full workflow",
                 workspace_path: workspace_path
               )

      assert Map.has_key?(result, :plan)
      assert Map.has_key?(result, :changes)
      assert Map.has_key?(result, :feedback)
    end

    test "work entrypoints emit workflow provenance in the workflow_provenance graph" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()
      plan_work_item_id = "plan-#{System.unique_integer()}"
      coding_work_item_id = "code-#{System.unique_integer()}"
      review_work_item_id = "review-#{System.unique_integer()}"
      explain_work_item_id = "explain-#{System.unique_integer()}"
      previous = Application.get_env(:jido_code, :memory_graph_enabled, false)

      Application.put_env(:jido_code, :memory_graph_enabled, true)

      on_exit(fn ->
        Application.put_env(:jido_code, :memory_graph_enabled, previous)
        File.rm_rf!(workspace_path)
      end)

      assert {:ok, plan_result} =
               AgentWorkspace.plan_work(
                 managed_repo_id,
                 plan_work_item_id,
                 "Plan with provenance",
                 workspace_path: workspace_path
               )

      assert {:ok, code_result} =
               AgentWorkspace.execute_work(
                 managed_repo_id,
                 coding_work_item_id,
                 "Code with provenance",
                 workspace_path: workspace_path
               )

      assert {:ok, review_result} =
               AgentWorkspace.review_work(
                 managed_repo_id,
                 review_work_item_id,
                 "Review with provenance",
                 workspace_path: workspace_path
               )

      assert {:ok, explain_result} =
               AgentWorkspace.explain_work(
                 managed_repo_id,
                 explain_work_item_id,
                 "Explain with provenance",
                 workspace_path: workspace_path
               )

      assert plan_result.workflow_provenance.workflow == :plan
      assert code_result.workflow_provenance.workflow == :execute
      assert review_result.workflow_provenance.workflow == :review
      assert explain_result.workflow_provenance.workflow == :explain

      assert {:ok, plan_query} =
               AgentWorkspace.query_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 """
                 SELECT ?session ?run ?tool ?plan
                 WHERE {
                   ?session a jido:WorkSession ;
                     jido:sessionId "#{plan_result.workflow_provenance.session_id}" ;
                     jido:hasAgentRun ?run ;
                     jido:hasToolInvocation ?tool ;
                     jido:hasPlan ?plan .
                 }
                 """,
                 graph_name: "workflow_provenance",
                 allow_stale?: true
               )

      assert plan_query.row_count == 1

      assert {:ok, code_query} =
               AgentWorkspace.query_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 """
                 SELECT ?session ?patch
                 WHERE {
                   ?session a jido:WorkSession ;
                     jido:sessionId "#{code_result.workflow_provenance.session_id}" ;
                     jido:hasPatch ?patch .
                 }
                 """,
                 graph_name: "workflow_provenance",
                 allow_stale?: true
               )

      assert code_query.row_count == 1

      assert {:ok, review_query} =
               AgentWorkspace.query_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 """
                 SELECT ?session ?review
                 WHERE {
                   ?session a jido:WorkSession ;
                     jido:sessionId "#{review_result.workflow_provenance.session_id}" ;
                     jido:hasReview ?review .
                 }
                 """,
                 graph_name: "workflow_provenance",
                 allow_stale?: true
               )

      assert review_query.row_count == 1

      assert {:ok, explain_query} =
               AgentWorkspace.query_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 """
                 SELECT ?session ?run
                 WHERE {
                   ?session a jido:WorkSession ;
                     jido:sessionId "#{explain_result.workflow_provenance.session_id}" ;
                     jido:hasAgentRun ?run .
                 }
                 """,
                 graph_name: "workflow_provenance",
                 allow_stale?: true
               )

      assert explain_query.row_count == 1
    end
  end

  describe "parallel execution" do
    test "parallel_plan returns ok with results map" do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_ids = ["work-1", "work-2"]
      workspace_path = create_workspace_path!()

      on_exit(fn -> File.rm_rf!(workspace_path) end)

      Enum.each(work_item_ids, fn work_item_id ->
        assert {:ok, _pod_name} =
                 AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)
      end)

      assert {:ok, results} = AgentWorkspace.parallel_plan(managed_repo_id, work_item_ids)
      assert is_map(results)
      assert Map.has_key?(results, "work-1")
      assert Map.has_key?(results, "work-2")
      assert results["work-1"].plan =~ "deterministic planner response"
    end
  end

  describe "conversation coordination" do
    test "workspace helpers keep conversation coordination repo-scoped without exposing runtime topology" do
      managed_repo = managed_repo_fixture!("workspace-conversation")

      assert {:ok, %{conversation: conversation, snapshot: initial_snapshot}} =
               AgentWorkspace.open_repo_conversation(
                 managed_repo.id,
                 %{
                   source: "agent_workspace_test",
                   objective: "Open a repository conversation through the workspace boundary."
                 },
                 actor: Actor.operator_actor(%{"id" => "operator-workspace-conversation"})
               )

      assert initial_snapshot.conversation_id == conversation.id
      assert initial_snapshot.managed_repo_id == managed_repo.id
      refute Map.has_key?(initial_snapshot, :kernel_name)
      refute Map.has_key?(initial_snapshot, :pod_id)

      assert {:ok, latest_conversation} =
               AgentWorkspace.latest_repo_conversation(managed_repo.id,
                 actor: Actor.operator_actor()
               )

      assert latest_conversation.id == conversation.id

      assert {:ok, running_snapshot} =
               AgentWorkspace.handle_conversation_command(
                 conversation.id,
                 %{type: "turn.submit", payload: %{instruction: "Inspect the workspace boundary."}},
                 actor: Actor.operator_actor(%{"id" => "operator-workspace-conversation"})
               )

      assert running_snapshot.active_turn.command_type == "turn.submit"
      assert running_snapshot.active_turn.state == :running
      assert running_snapshot.active_child_work.turn_id == running_snapshot.active_turn.id

      assert {:ok, cancellation_snapshot} =
               AgentWorkspace.handle_conversation_command(
                 conversation.id,
                 %{type: "tool.cancel", payload: %{}},
                 actor: Actor.operator_actor(%{"id" => "operator-workspace-conversation"})
               )

      assert cancellation_snapshot.active_turn.state == :cancelling
      assert cancellation_snapshot.active_child_work.state == :cancel_acknowledged
      assert Enum.any?(cancellation_snapshot.control_history, &(&1.type == "tool.cancel"))

      assert {:ok, persisted_snapshot} =
               AgentWorkspace.conversation_snapshot(conversation.id)

      assert persisted_snapshot.conversation_id == conversation.id
      refute Map.has_key?(persisted_snapshot, :kernel_name)
      refute Map.has_key?(persisted_snapshot, :pod_id)

      assert {:ok, replayed_events} =
               AgentWorkspace.conversation_events_since(conversation.id, running_snapshot.last_event_sequence,
                 actor: Actor.operator_actor()
               )

      assert Enum.map(replayed_events, & &1.name) == [
               "conversation.message_added",
               "turn.cancelling",
               "tool.cancel_requested",
               "tool.cancel_acknowledged"
             ]

      assert :ok = AgentWorkspace.stop_conversation(conversation.id)
    end

    test "workspace exposes work-item conversation boundaries without falling back to repo-global lookup" do
      managed_repo = managed_repo_fixture!("workspace-work-item-conversation")
      first_work_item = work_item_fixture!(managed_repo, "workspace-work-item-one")
      second_work_item = work_item_fixture!(managed_repo, "workspace-work-item-two")

      assert {:ok, %{conversation: first_conversation, snapshot: first_snapshot, resumed?: false}} =
               AgentWorkspace.open_work_item_conversation(
                 first_work_item.id,
                 %{
                   source: "agent_workspace_test",
                   objective: "Continue the first governed work item through the workspace boundary."
                 },
                 actor: Actor.operator_actor(%{"id" => "operator-workspace-work-item-first"})
               )

      assert first_snapshot.conversation_id == first_conversation.id
      assert first_snapshot.managed_repo_id == managed_repo.id
      assert first_snapshot.work_item_id == first_work_item.id
      assert first_snapshot.scope == :work_item_scoped
      assert first_snapshot.attachment_mode == :existing_work_item

      assert {:ok, active_first_conversation} =
               AgentWorkspace.active_work_item_conversation(first_work_item.id,
                 actor: Actor.operator_actor()
               )

      assert active_first_conversation.id == first_conversation.id

      assert {:ok, %{conversation: resumed_first_conversation, resumed?: true}} =
               AgentWorkspace.open_work_item_conversation(
                 first_work_item.id,
                 %{},
                 actor: Actor.operator_actor(%{"id" => "operator-workspace-work-item-resume"})
               )

      assert resumed_first_conversation.id == first_conversation.id

      assert {:ok, %{conversation: second_conversation, snapshot: second_snapshot, resumed?: false}} =
               AgentWorkspace.open_work_item_conversation(
                 second_work_item.id,
                 %{
                   source: "agent_workspace_test",
                   objective: "Continue the second governed work item through the workspace boundary."
                 },
                 actor: Actor.operator_actor(%{"id" => "operator-workspace-work-item-second"})
               )

      assert second_snapshot.work_item_id == second_work_item.id
      refute second_conversation.id == first_conversation.id

      assert {:ok, active_conversations} =
               AgentWorkspace.active_work_item_conversations(managed_repo.id,
                 actor: Actor.operator_actor()
               )

      active_ids = Enum.map(active_conversations, & &1.id)

      assert first_conversation.id in active_ids
      assert second_conversation.id in active_ids
      assert Enum.all?(active_conversations, &(&1.scope == :work_item_scoped))

      assert :ok = AgentWorkspace.stop_conversation(first_conversation.id)
      assert :ok = AgentWorkspace.stop_conversation(second_conversation.id)
    end
  end

  describe "source code graph workflow adoption" do
    setup do
      previous = Application.get_env(:jido_code, :source_code_graph_enabled, false)
      Application.put_env(:jido_code, :source_code_graph_enabled, true)

      workspace_path = create_workspace_path!()

      on_exit(fn ->
        Application.put_env(:jido_code, :source_code_graph_enabled, previous)
        File.rm_rf!(workspace_path)
      end)

      {:ok, workspace_path: workspace_path}
    end

    test "plan_work can gather explicit semantic graph inputs", %{workspace_path: workspace_path} do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"

      assert {:ok, result} =
               AgentWorkspace.plan_work(
                 managed_repo_id,
                 work_item_id,
                 "Plan feature",
                 workspace_path: workspace_path,
                 source_code_graph: [
                   workspace_path: workspace_path,
                   prepare: :load_if_missing,
                   modules: [module_name_contains: "Example"],
                   impact: [module_name: "Example"]
                 ]
               )

      assert result.semantic_context.workflow == :plan
      assert result.semantic_context.graph_status.ready? == true
      assert result.semantic_context.results.modules.helper == :modules
      assert result.semantic_context.results.impact.helper == :impact
    end

    test "review_work can gather explicit semantic review inputs", %{workspace_path: workspace_path} do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"

      assert {:ok, result} =
               AgentWorkspace.review_work(
                 managed_repo_id,
                 work_item_id,
                 "Review feature",
                 workspace_path: workspace_path,
                 source_code_graph: [
                   workspace_path: workspace_path,
                   prepare: :load_if_missing,
                   functions: [module_name: "Example", function_name: "greet"],
                   runtime_patterns: []
                 ]
               )

      assert result.semantic_context.workflow == :review
      assert result.semantic_context.graph_status.ready? == true
      assert result.semantic_context.results.functions.helper == :functions
      assert result.semantic_context.results.runtime_patterns.helper == :runtime_patterns
    end

    test "explain_work can query the graph through explicit workspace entrypoints", %{workspace_path: workspace_path} do
      managed_repo_id = "test-repo-#{System.unique_integer()}"
      work_item_id = "work-#{System.unique_integer()}"

      assert {:ok, result} =
               AgentWorkspace.explain_work(
                 managed_repo_id,
                 work_item_id,
                 "Explain feature",
                 workspace_path: workspace_path,
                 source_code_graph: [
                   workspace_path: workspace_path,
                   prepare: :load_if_missing,
                   query: """
                   SELECT ?module
                   WHERE {
                     ?module a struct:Module .
                   }
                   ORDER BY ?module
                   """
                 ]
               )

      assert result.semantic_context.workflow == :explain
      assert result.semantic_context.results.query.engine == :sparql
      assert result.semantic_context.results.query.row_count >= 1
    end
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_agent_workspace_source_graph_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule AgentWorkspaceExample.MixProject do
        use Mix.Project

        def project do
          [app: :agent_workspace_example, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example.ex"),
      """
      defmodule Example do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    workspace_path
  end

  defp managed_repo_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "agent-workspace-#{suffix}",
        github_full_name: "owner/agent-workspace-#{suffix}",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    managed_repo
  end

  defp work_item_fixture!(managed_repo, actor_id) do
    {:ok, %{work_item: work_item}} =
      Ingress.record_operator_intake(%{
        managed_repo_id: managed_repo.id,
        channel: "workbench",
        intent: "fix_workflow_kickoff",
        actor: %{id: actor_id, email: "#{actor_id}@example.com"},
        payload: %{
          "workflow_name" => "fix_failing_tests_#{actor_id}",
          "context_item" => %{"type" => "issue", "id" => actor_id}
        },
        source_metadata: %{
          "trigger" => %{"source" => "workbench", "mode" => "manual"}
        }
      })

    work_item
  end
end
