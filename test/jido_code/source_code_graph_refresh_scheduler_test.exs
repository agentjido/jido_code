defmodule JidoCode.SourceCodeGraphRefreshSchedulerTest do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.graph_refresh_replaces_named_graph_coherently
  use ExUnit.Case, async: false

  alias JidoCode.SourceCodeGraph.RefreshScheduler

  setup do
    previous_auto_refresh = Application.get_env(:jido_code, :source_code_graph_auto_refresh_enabled)
    Application.put_env(:jido_code, :source_code_graph_auto_refresh_enabled, true)

    on_exit(fn ->
      restore_env(:source_code_graph_auto_refresh_enabled, previous_auto_refresh)
    end)

    :ok
  end

  test "coalesces queued source changes into one refresh request" do
    managed_repo_id = "repo-#{System.unique_integer([:positive])}"
    workspace_path = System.tmp_dir!()
    parent = self()

    refresh_fun = fn _managed_repo_id, _workspace_path, event, _opts ->
      send(parent, {:refresh, event})
      {:ok, %{status: :graph_refreshed}}
    end

    on_exit(fn -> RefreshScheduler.stop(managed_repo_id) end)

    assert {:ok, _pid} =
             RefreshScheduler.ensure_started(
               managed_repo_id,
               refresh_fun: refresh_fun,
               refresh_debounce_ms: 10
             )

    assert :ok = RefreshScheduler.enqueue(event(managed_repo_id, workspace_path, ["lib/alpha.ex"]))
    assert :ok = RefreshScheduler.enqueue(event(managed_repo_id, workspace_path, ["config/runtime.exs"]))

    assert_receive {:refresh, refresh_event}, 200

    assert refresh_event.changed_paths == ["config/runtime.exs", "lib/alpha.ex"]
    assert refresh_event.event_sources == [:human_watcher]
    refute_receive {:refresh, _event}, 50

    assert {:ok, status} = RefreshScheduler.status(managed_repo_id)
    assert status.state in [:running, :succeeded]
  end

  test "runs one follow-up refresh when source changes arrive during an in-flight refresh" do
    managed_repo_id = "repo-#{System.unique_integer([:positive])}"
    workspace_path = System.tmp_dir!()
    parent = self()

    refresh_fun = fn _managed_repo_id, _workspace_path, event, _opts ->
      send(parent, {:refresh_started, self(), event})

      receive do
        :release_refresh -> :ok
      after
        1_000 -> :ok
      end

      {:ok, %{status: :graph_refreshed}}
    end

    on_exit(fn -> RefreshScheduler.stop(managed_repo_id) end)

    assert {:ok, _pid} =
             RefreshScheduler.ensure_started(
               managed_repo_id,
               refresh_fun: refresh_fun,
               refresh_debounce_ms: 1
             )

    assert :ok = RefreshScheduler.enqueue(event(managed_repo_id, workspace_path, ["lib/alpha.ex"]))
    assert_receive {:refresh_started, first_task, first_event}, 200
    assert first_event.changed_paths == ["lib/alpha.ex"]

    assert :ok = RefreshScheduler.enqueue(event(managed_repo_id, workspace_path, ["lib/beta.ex"]))
    send(first_task, :release_refresh)

    assert_receive {:refresh_started, second_task, second_event}, 300
    assert second_event.changed_paths == ["lib/beta.ex"]
    send(second_task, :release_refresh)
  end

  test "disabled auto refresh accepts source changes without starting scheduler work" do
    Application.put_env(:jido_code, :source_code_graph_auto_refresh_enabled, false)

    managed_repo_id = "repo-#{System.unique_integer([:positive])}"

    assert :ok = RefreshScheduler.enqueue(event(managed_repo_id, System.tmp_dir!(), ["lib/alpha.ex"]))
    assert {:error, :not_started} = RefreshScheduler.status(managed_repo_id)
  end

  test "bounds retry attempts for failed refresh work" do
    managed_repo_id = "repo-#{System.unique_integer([:positive])}"
    workspace_path = System.tmp_dir!()
    parent = self()

    refresh_fun = fn _managed_repo_id, _workspace_path, _event, _opts ->
      send(parent, :refresh_attempt)
      {:error, :source_code_graph_store_failed}
    end

    on_exit(fn -> RefreshScheduler.stop(managed_repo_id) end)

    assert {:ok, _pid} =
             RefreshScheduler.ensure_started(
               managed_repo_id,
               refresh_fun: refresh_fun,
               refresh_debounce_ms: 1,
               max_refresh_attempts: 2
             )

    assert :ok = RefreshScheduler.enqueue(event(managed_repo_id, workspace_path, ["lib/alpha.ex"]))

    assert_receive :refresh_attempt, 100
    assert_receive :refresh_attempt, 100
    refute_receive :refresh_attempt, 50
  end

  defp event(managed_repo_id, workspace_path, changed_paths) do
    %{
      kind: :workspace_source_changed,
      managed_repo_id: managed_repo_id,
      workspace_path: workspace_path,
      changed_paths: changed_paths,
      changed_path: List.first(changed_paths),
      file_events: [:modified],
      event_source: :human_watcher,
      event_sources: [:human_watcher],
      observed_at: DateTime.utc_now()
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
