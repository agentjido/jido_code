defmodule JidoCode.GitHub.RepoStoreTest do
  use ExUnit.Case, async: false

  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.GitHub.{Repo, RepoStore}

  setup do
    store_name = :"github_repo_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_github_repo_store/#{store_name}")

    start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    original = Application.get_env(:jido_code, :control_plane_product_store_server, :__missing__)
    Application.put_env(:jido_code, :control_plane_product_store_server, store_name)

    on_exit(fn ->
      restore_env(:control_plane_product_store_server, original)
      File.rm_rf!(path)
    end)

    :ok
  end

  test "creates lists updates and hides GitHub repo anchors through product stores" do
    assert {:ok, %Repo{} = repo} =
             RepoStore.create(%{
               owner: "owner",
               name: "repo-store",
               github_app_installation_id: 123,
               settings: %{"auto_comment" => true}
             })

    assert repo.full_name == "owner/repo-store"
    assert repo.enabled
    assert repo.github_app_installation_id == 123
    assert repo.settings["auto_comment"] == true

    assert {:ok, %Repo{id: repo_id}} = RepoStore.get_by_full_name("owner/repo-store")
    assert repo_id == repo.id

    assert {:ok, %Repo{id: repo_id}} = RepoStore.get_by_installation_id(123)
    assert repo_id == repo.id

    assert {:ok, disabled} = RepoStore.disable(repo)
    refute disabled.enabled

    assert {:ok, [listed]} = RepoStore.list()
    assert listed.id == repo.id
    refute listed.enabled

    assert :ok = RepoStore.delete(repo)
    assert {:ok, []} = RepoStore.list()
    assert {:ok, nil} = RepoStore.get_by_full_name("owner/repo-store")
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
