defmodule JidoCode.PhaseEightySevenIntegrationTest do
  # covers: architecture.repository_runtime_integration.signal_routing_within_pod
  # covers: architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary
  use ExUnit.Case, async: true

  alias JidoCode.Actions.{GitDiff, ReadFile, RunTests}
  alias JidoCode.ContextBudget

  test "history packing trims old context without corrupting tool-call groups" do
    packed =
      ContextBudget.pack_messages(
        [
          %{role: :system, content: "system"},
          %{role: :user, content: "old " <> String.duplicate("x", 500)},
          %{
            role: :assistant,
            content: nil,
            tool_calls: [%{id: "tool-1", name: "jido_code_read_file", arguments: %{path: "lib/a.ex"}}]
          },
          %{role: :tool, tool_call_id: "tool-1", name: "jido_code_read_file", content: "bounded output"},
          %{role: :user, content: "current request"}
        ],
        token_budget: 48,
        max_messages: 4
      )

    assert Enum.map(packed.messages, & &1.role) == [:system, :assistant, :tool, :user]
    assert packed.diagnostics.state == :trimmed
  end

  test "large file, diff, and test outputs are capped with diagnostics" do
    workspace_path = git_workspace!()
    large_file = Path.join(workspace_path, "large.txt")

    File.write!(large_file, String.duplicate("large-line\n", 2_000))

    assert {:ok, read_result} =
             ReadFile.run(%{path: "large.txt", max_chars: 50_000}, %{tool_context: %{workspace_path: workspace_path}})

    assert read_result.truncated?
    assert read_result.budget.state == :truncated

    File.write!(Path.join(workspace_path, "tracked.txt"), String.duplicate("changed\n", 2_000))

    assert {:ok, diff_result} =
             GitDiff.run(%{path: "tracked.txt", cached: false, max_lines: 5_000}, %{
               tool_context: %{workspace_path: workspace_path}
             })

    assert diff_result.truncated
    assert diff_result.budget.state == :truncated

    assert {:ok, test_result} =
             RunTests.run(%{test_path: nil, command: "seq 1 20000", timeout_ms: 5_000}, %{
               tool_context: %{workspace_path: workspace_path}
             })

    assert test_result.budget.state == :truncated
    assert test_result.output =~ "tool output truncated"
  end

  defp git_workspace! do
    workspace_path =
      Path.join(System.tmp_dir!(), "jido-code-phase-eighty-seven-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workspace_path)
    File.write!(Path.join(workspace_path, "tracked.txt"), "original\n")

    System.cmd("git", ["init"], cd: workspace_path, stderr_to_stdout: true)
    System.cmd("git", ["config", "user.email", "phase87@example.com"], cd: workspace_path, stderr_to_stdout: true)
    System.cmd("git", ["config", "user.name", "Phase 87"], cd: workspace_path, stderr_to_stdout: true)
    System.cmd("git", ["add", "tracked.txt"], cd: workspace_path, stderr_to_stdout: true)
    System.cmd("git", ["commit", "-m", "seed"], cd: workspace_path, stderr_to_stdout: true)

    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end
end
