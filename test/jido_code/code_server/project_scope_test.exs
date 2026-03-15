defmodule JidoCode.CodeServer.ProjectScopeTest do
  use ExUnit.Case, async: false

  alias JidoCode.CodeServer.ProjectScope
  alias JidoCode.TestSupport.CodeServer.ProjectReaderFake

  setup do
    original_reader_module = Application.get_env(:jido_code, :code_server_project_reader_module, :__missing__)
    Application.put_env(:jido_code, :code_server_project_reader_module, ProjectReaderFake)
    ProjectReaderFake.clear()

    on_exit(fn ->
      ProjectReaderFake.clear()

      case original_reader_module do
        :__missing__ -> Application.delete_env(:jido_code, :code_server_project_reader_module)
        module -> Application.put_env(:jido_code, :code_server_project_reader_module, module)
      end
    end)

    :ok
  end

  test "resolves valid local workspace scope when readiness and path checks pass" do
    workspace_path = create_workspace_path!()

    ProjectReaderFake.put_read_result(
      {:ok,
       [
         project_fixture("project-local-ready", %{
           "workspace_environment" => "local",
           "workspace_path" => workspace_path,
           "clone_status" => "ready",
           "workspace_initialized" => true,
           "baseline_synced" => true
         })
       ]}
    )

    assert {:ok,
            %{
              project_id: "project-local-ready",
              root_path: ^workspace_path,
              project: %{id: "project-local-ready"}
            }} = ProjectScope.resolve("project-local-ready")
  end

  test "returns typed unsupported error when workspace environment is sprite" do
    ProjectReaderFake.put_read_result(
      {:ok,
       [
         project_fixture("project-sprite", %{
           "workspace_environment" => "sprite",
           "workspace_path" => "/tmp/ignored",
           "clone_status" => "ready",
           "workspace_initialized" => true,
           "baseline_synced" => true
         })
       ]}
    )

    assert {:error, typed_error} = ProjectScope.resolve("project-sprite")
    assert typed_error.error_type == "code_server_workspace_environment_unsupported"
    assert typed_error.project_id == "project-sprite"
  end

  test "returns workspace unavailable when local workspace path is missing" do
    ProjectReaderFake.put_read_result(
      {:ok,
       [
         project_fixture("project-missing-path", %{
           "workspace_environment" => "local",
           "clone_status" => "ready",
           "workspace_initialized" => true,
           "baseline_synced" => true
         })
       ]}
    )

    assert {:error, typed_error} = ProjectScope.resolve("project-missing-path")
    assert typed_error.error_type == "code_server_workspace_unavailable"
    assert typed_error.detail =~ "workspace path is missing"
    assert typed_error.project_id == "project-missing-path"
  end

  test "returns readiness remediation and workspace error context when baseline sync is blocked" do
    ProjectReaderFake.put_read_result(
      {:ok,
       [
         project_fixture("project-blocked", %{
           "workspace_environment" => "local",
           "clone_status" => "error",
           "workspace_initialized" => true,
           "baseline_synced" => false,
           "last_error_type" => "baseline_sync_unavailable",
           "retry_instructions" => "Retry step 7 after baseline sync is repaired."
         })
       ]}
    )

    assert {:error, typed_error} = ProjectScope.resolve("project-blocked")
    assert typed_error.error_type == "code_server_workspace_unavailable"
    assert typed_error.detail =~ "clone or baseline sync failed"
    assert typed_error.detail =~ "workspace error: baseline_sync_unavailable"
    assert typed_error.remediation =~ "Retry step 7"
  end

  defp project_fixture(project_id, workspace_settings) do
    %{
      id: project_id,
      settings: %{"workspace" => workspace_settings}
    }
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-scope-test-workspace-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end
end
