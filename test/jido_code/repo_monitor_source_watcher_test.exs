defmodule JidoCode.RepoMonitorSourceWatcherTest do
  # covers: architecture.agent_os_integration.repo_pod_singleton_per_kernel
  # covers: architecture.source_code_graph_pod.graph_revision_state_is_explicit_and_explainable
  use JidoCode.DataCase, async: false

  alias JidoCode.Agents.RepoMonitor
  alias JidoCode.AgentWorkspace
  alias JidoCode.Forge.SpriteClient
  alias JidoCode.SourceCodeGraph

  describe "source graph source scope" do
    test "keeps watcher filtering aligned with graph revision inputs" do
      workspace_path = create_workspace_path!()

      assert SourceCodeGraph.source_file?(workspace_path, Path.join(workspace_path, "mix.exs"))
      assert SourceCodeGraph.source_file?(workspace_path, Path.join(workspace_path, "lib/example.ex"))
      assert SourceCodeGraph.source_file?(workspace_path, Path.join(workspace_path, "lib/example_script.exs"))
      assert SourceCodeGraph.source_file?(workspace_path, Path.join(workspace_path, "test/example_test.exs"))
      assert SourceCodeGraph.source_file?(workspace_path, Path.join(workspace_path, "config/runtime.exs"))

      refute SourceCodeGraph.source_file?(workspace_path, Path.join(workspace_path, "lib/example.txt"))
      refute SourceCodeGraph.source_file?(workspace_path, Path.join(workspace_path, "deps/package/lib/example.ex"))

      refute SourceCodeGraph.source_file?(
               workspace_path,
               Path.join(workspace_path, ".jido_code/source_code_graph/triple_store/generated.ex")
             )

      refute SourceCodeGraph.source_file?(workspace_path, Path.join(System.tmp_dir!(), "outside.ex"))

      assert Enum.all?(SourceCodeGraph.source_files(workspace_path), &SourceCodeGraph.source_file?(workspace_path, &1))
    end
  end

  describe "repo monitor source watcher" do
    test "publishes normalized source change events for source files" do
      managed_repo_id = "repo-#{System.unique_integer([:positive])}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> RepoMonitor.stop_source_watcher(managed_repo_id) end)

      assert {:ok, _pid} =
               RepoMonitor.ensure_source_watcher(
                 managed_repo_id,
                 workspace_path,
                 start_file_system?: false,
                 debounce_ms: 1
               )

      Phoenix.PubSub.subscribe(JidoCode.PubSub, RepoMonitor.source_change_topic(managed_repo_id))

      changed_path = Path.join(workspace_path, "lib/example.ex")
      assert :ok = RepoMonitor.notify_source_changed(managed_repo_id, changed_path, [:modified], :human_watcher)

      assert_receive {:workspace_source_changed, event}, 100

      assert event.kind == :workspace_source_changed
      assert event.managed_repo_id == managed_repo_id
      assert event.workspace_path == Path.expand(workspace_path)
      assert event.changed_paths == ["lib/example.ex"]
      assert event.changed_path == "lib/example.ex"
      assert event.file_events == [:modified]
      assert event.event_source == :human_watcher
      assert event.event_sources == [:human_watcher]
      assert is_binary(event.current_revision)
      assert %DateTime{} = event.observed_at
    end

    test "coalesces source write bursts into one normalized event" do
      managed_repo_id = "repo-#{System.unique_integer([:positive])}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> RepoMonitor.stop_source_watcher(managed_repo_id) end)

      assert {:ok, _pid} =
               RepoMonitor.ensure_source_watcher(
                 managed_repo_id,
                 workspace_path,
                 start_file_system?: false,
                 debounce_ms: 10
               )

      Phoenix.PubSub.subscribe(JidoCode.PubSub, RepoMonitor.source_change_topic(managed_repo_id))

      assert :ok =
               RepoMonitor.notify_source_changed(
                 managed_repo_id,
                 Path.join(workspace_path, "lib/example.ex"),
                 [:modified],
                 :human_watcher
               )

      assert :ok =
               RepoMonitor.notify_source_changed(
                 managed_repo_id,
                 Path.join(workspace_path, "config/runtime.exs"),
                 [:created],
                 :runtime_write
               )

      assert_receive {:workspace_source_changed, event}, 100

      assert event.changed_paths == ["config/runtime.exs", "lib/example.ex"]
      assert event.file_events == [:created, :modified]
      assert event.event_source == :mixed
      assert event.event_sources == [:human_watcher, :runtime_write]
      refute_receive {:workspace_source_changed, _event}, 50
    end

    test "coalesces delete and rename-style source events while capping pending paths" do
      managed_repo_id = "repo-#{System.unique_integer([:positive])}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> RepoMonitor.stop_source_watcher(managed_repo_id) end)

      assert {:ok, _pid} =
               RepoMonitor.ensure_source_watcher(
                 managed_repo_id,
                 workspace_path,
                 start_file_system?: false,
                 debounce_ms: 10,
                 max_pending_paths: 1
               )

      Phoenix.PubSub.subscribe(JidoCode.PubSub, RepoMonitor.source_change_topic(managed_repo_id))

      assert :ok =
               RepoMonitor.notify_source_changed(
                 managed_repo_id,
                 Path.join(workspace_path, "lib/alpha.ex"),
                 [:deleted],
                 :human_watcher
               )

      assert :ok =
               RepoMonitor.notify_source_changed(
                 managed_repo_id,
                 Path.join(workspace_path, "lib/beta.ex"),
                 [:renamed],
                 :human_watcher
               )

      assert_receive {:workspace_source_changed, event}, 100

      assert event.changed_paths == ["lib/alpha.ex"]
      assert event.file_events == [:deleted, :renamed]
      assert event.event_source == :human_watcher
      refute_receive {:workspace_source_changed, _event}, 50
    end

    test "ignores non-source files and graph store self writes" do
      managed_repo_id = "repo-#{System.unique_integer([:positive])}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> RepoMonitor.stop_source_watcher(managed_repo_id) end)

      assert {:ok, _pid} =
               RepoMonitor.ensure_source_watcher(
                 managed_repo_id,
                 workspace_path,
                 start_file_system?: false,
                 debounce_ms: 1
               )

      Phoenix.PubSub.subscribe(JidoCode.PubSub, RepoMonitor.source_change_topic(managed_repo_id))

      assert :ok =
               RepoMonitor.notify_source_changed(
                 managed_repo_id,
                 Path.join(workspace_path, ".jido_code/source_code_graph/triple_store/generated.ex"),
                 [:modified],
                 :human_watcher
               )

      refute_receive {:workspace_source_changed, _event}, 50
    end

    test "AgentWorkspace exposes product-owned source change notification" do
      managed_repo_id = "repo-#{System.unique_integer([:positive])}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> RepoMonitor.stop_source_watcher(managed_repo_id) end)

      Phoenix.PubSub.subscribe(JidoCode.PubSub, RepoMonitor.source_change_topic(managed_repo_id))

      assert :ok =
               AgentWorkspace.notify_workspace_source_changed(
                 managed_repo_id,
                 workspace_path,
                 "lib/example.ex",
                 event_source: :llm_write,
                 start_file_system?: false,
                 debounce_ms: 1
               )

      assert_receive {:workspace_source_changed, event}, 100

      assert event.changed_paths == ["lib/example.ex"]
      assert event.event_source == :llm_write
      assert event.event_sources == [:llm_write]
    end

    test "SpriteClient write_file can notify source graph changes after successful writes" do
      managed_repo_id = "repo-#{System.unique_integer([:positive])}"
      workspace_path = create_workspace_path!()

      on_exit(fn -> RepoMonitor.stop_source_watcher(managed_repo_id) end)

      Phoenix.PubSub.subscribe(JidoCode.PubSub, RepoMonitor.source_change_topic(managed_repo_id))

      assert {:ok, client, sprite_id} = SpriteClient.create(%{base_dir: System.tmp_dir!()})

      on_exit(fn ->
        if Process.alive?(client.agent_pid), do: SpriteClient.destroy(client, sprite_id)
      end)

      changed_path = Path.join(workspace_path, "lib/example.ex")

      assert :ok =
               SpriteClient.write_file(client, changed_path, "defmodule Example do\n  def changed, do: :ok\nend\n",
                 managed_repo_id: managed_repo_id,
                 workspace_path: workspace_path,
                 event_source: :tool_write,
                 start_file_system?: false,
                 debounce_ms: 1
               )

      assert_receive {:workspace_source_changed, event}, 100

      assert event.changed_paths == ["lib/example.ex"]
      assert event.event_source == :tool_write
    end
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_repo_monitor_source_watcher_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(workspace_path)
    File.mkdir_p!(Path.join(workspace_path, "lib"))
    File.mkdir_p!(Path.join(workspace_path, "test"))
    File.mkdir_p!(Path.join(workspace_path, "config"))
    File.mkdir_p!(Path.join(workspace_path, "deps/package/lib"))
    File.mkdir_p!(Path.join(workspace_path, ".jido_code/source_code_graph/triple_store"))

    File.write!(Path.join(workspace_path, "mix.exs"), "defmodule Example.MixProject do\nend\n")
    File.write!(Path.join(workspace_path, "lib/example.ex"), "defmodule Example do\nend\n")
    File.write!(Path.join(workspace_path, "lib/example_script.exs"), "defmodule ExampleScript do\nend\n")
    File.write!(Path.join(workspace_path, "test/example_test.exs"), "defmodule ExampleTest do\nend\n")
    File.write!(Path.join(workspace_path, "config/runtime.exs"), "import Config\n")
    File.write!(Path.join(workspace_path, "lib/example.txt"), "not source\n")
    File.write!(Path.join(workspace_path, "deps/package/lib/example.ex"), "defmodule Ignored do\nend\n")

    on_exit(fn -> File.rm_rf!(workspace_path) end)

    workspace_path
  end
end
