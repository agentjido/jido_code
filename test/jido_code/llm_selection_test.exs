defmodule JidoCode.LLMSelectionTest do
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.RepoBridge
  alias JidoCode.Conversations.RuntimeReadiness
  alias JidoCode.LLMSelection

  setup do
    llm_selection = Application.get_env(:jido_code, :llm_selection, :__missing__)
    llm_adapter = Application.get_env(:jido_code_server, :llm_adapter, :__missing__)

    on_exit(fn ->
      restore_env(:jido_code, :llm_selection, llm_selection)
      restore_env(:jido_code_server, :llm_adapter, llm_adapter)
    end)

    :ok
  end

  test "conversation metadata override wins over the repo default" do
    managed_repo =
      managed_repo_fixture!(
        "conversation-override",
        repo_llm: %{"provider" => "anthropic", "model" => "claude-sonnet-4-20250514"}
      )

    assert {:ok, readiness} =
             RuntimeReadiness.resolve(
               managed_repo.id,
               conversation_metadata: %{
                 "llm" => %{"provider" => "openai", "model" => "gpt-5-mini"}
               }
             )

    assert readiness.llm_selection.provider == "openai"
    assert readiness.llm_selection.model == "gpt-5-mini"
    assert readiness.llm_selection.model_spec == "openai:gpt-5-mini"
    assert readiness.llm_selection.source == :conversation
  end

  test "repo default wins over the system default" do
    Application.put_env(:jido_code, :llm_selection, %{
      default: %{provider: "system-provider", model: "system-model"}
    })

    managed_repo =
      managed_repo_fixture!(
        "repo-default",
        repo_llm: %{"provider" => "groq", "model" => "llama-3.3-70b-versatile"}
      )

    assert {:ok, selection} = LLMSelection.resolve(managed_repo.id)
    assert selection.provider == "groq"
    assert selection.model == "llama-3.3-70b-versatile"
    assert selection.model_spec == "groq:llama-3.3-70b-versatile"
    assert selection.source == :repo_default
  end

  test "deterministic adapter still resolves a concrete selection when no configured default exists" do
    Application.delete_env(:jido_code, :llm_selection)
    Application.put_env(:jido_code_server, :llm_adapter, :deterministic)

    managed_repo = managed_repo_fixture!("deterministic-fallback")

    assert {:ok, selection} = LLMSelection.resolve(managed_repo.id)
    assert selection.provider == "deterministic"
    assert selection.model == "deterministic"
    assert selection.model_spec == "deterministic:deterministic"
    assert selection.source == :deterministic
  end

  test "runtime readiness fails closed when a real adapter has no concrete selection" do
    Application.delete_env(:jido_code, :llm_selection)
    Application.put_env(:jido_code_server, :llm_adapter, :jido_ai)

    managed_repo = managed_repo_fixture!("missing-selection")

    assert {:error, %{"error_type" => "conversation_runtime_llm_selection_missing"}} =
             RuntimeReadiness.resolve(managed_repo.id)
  end

  defp managed_repo_fixture!(suffix, opts \\ []) do
    workspace_path = workspace_path!(suffix)

    execution_settings =
      case Keyword.get(opts, :repo_llm) do
        %{} = repo_llm -> %{"llm" => repo_llm}
        _other -> %{}
      end

    {:ok, %{managed_repo: managed_repo}} =
      RepoBridge.upsert_managed_repo(%{
        name: "llm-selection-#{suffix}",
        full_name: "owner/llm-selection-#{suffix}-#{System.unique_integer([:positive])}",
        default_branch: "main",
        workspace_settings: %{
          "workspace_environment" => "local",
          "workspace_path" => workspace_path,
          "clone_status" => "ready",
          "workspace_initialized" => true,
          "baseline_synced" => true
        },
        execution_settings: execution_settings
      })

    managed_repo
  end

  defp workspace_path!(suffix) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-llm-selection-#{suffix}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
  end

  defp restore_env(app, key, :__missing__), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
