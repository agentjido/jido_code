defmodule JidoCodeWeb.ConnCase do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: auth.system.local_email_identity
  # covers: auth.system.password_registration_and_sign_in
  # covers: auth.github_integration.non_blocking_local_auth
  # covers: auth.operator_settings.hidden_during_bootstrap_entry
  # covers: auth.provider_login_flow.local_auth_fallback_visible
  # covers: auth.provider_login_flow.local_session_issuance
  # covers: baseline.surface.auth_entrypoints_visible
  # covers: users.admin_system.bootstrap_admin
  # covers: users.admin_system.self_service_auth_lifecycle
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Tests that need product persistence use isolated embedded store instances.
  """

  use ExUnit.CaseTemplate

  alias JidoCode.Accounts.SessionTokens
  alias JidoCode.Control.{Actor, ManagedRepoStore, RepoBridge}
  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.Orchestration.RecordStore, as: OrchestrationRecordStore
  alias JidoCode.Setup.OwnerStore

  import Phoenix.ConnTest, only: [recycle: 1]

  using do
    quote do
      # The default endpoint for testing
      @endpoint JidoCodeWeb.Endpoint

      use JidoCodeWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import JidoCodeWeb.ConnCase
      import JidoCodeWeb.LiveVueCase
    end
  end

  setup tags do
    JidoCode.DataCase.setup_sandbox(tags)
    JidoCode.DataCase.setup_policy_actor()
    setup_product_store()
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  def register_owner(email, _password) do
    seed_product_owner!(email)
  end

  def authenticate_owner_conn(email, password) when is_binary(email) and is_binary(password) do
    authenticate_owner_conn(Phoenix.ConnTest.build_conn(), email, password, include_session_token: true)
  end

  def authenticate_owner_conn(email, password, opts)
      when is_binary(email) and is_binary(password) and is_list(opts) do
    authenticate_owner_conn(
      Phoenix.ConnTest.build_conn(),
      email,
      password,
      Keyword.put_new(opts, :include_session_token, true)
    )
  end

  def authenticate_owner_conn(%Plug.Conn{} = conn, email, password)
      when is_binary(email) and is_binary(password) do
    authenticate_owner_conn(conn, email, password, [])
  end

  def authenticate_owner_conn(%Plug.Conn{} = conn, email, password, opts)
      when is_binary(email) and is_binary(password) and is_list(opts) do
    _password = password
    {:ok, owner} = seed_product_owner!(email)
    {:ok, session_token} = SessionTokens.issue(owner)

    auth_response =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session("product_user_token", session_token)
      |> Plug.Conn.put_session("product_user_email", to_string(owner.email))

    auth_result(
      recycle(auth_response),
      session_token,
      owner,
      Keyword.get(opts, :include_session_token, false),
      Keyword.get(opts, :return_owner, false)
    )
  end

  def restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  def restore_env(key, value), do: Application.put_env(:jido_code, key, value)

  def restore_system_env(key, :__missing__), do: System.delete_env(key)
  def restore_system_env(key, nil), do: System.delete_env(key)
  def restore_system_env(key, value), do: System.put_env(key, value)

  def setup_product_store do
    store_name = :"conn_case_product_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_conn_case/#{store_name}")

    ExUnit.Callbacks.start_supervised!(
      {StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start}
    )

    original = Application.get_env(:jido_code, :control_plane_product_store_server, :__missing__)
    Application.put_env(:jido_code, :control_plane_product_store_server, store_name)

    ExUnit.Callbacks.on_exit(fn ->
      restore_env(:control_plane_product_store_server, original)
      File.rm_rf!(path)
    end)

    :ok
  end

  def provision_managed_repo!(attrs) when is_map(attrs) do
    {:ok, provisioned_repo} = provision_managed_repo(attrs)
    provisioned_repo
  end

  def provision_managed_repo(attrs) when is_map(attrs) do
    with {:ok, %{managed_repo: managed_repo, source_repo: source_repo}} <-
           RepoBridge.upsert_managed_repo(attrs),
         {:ok, repo_scope} <- RepoBridge.repo_scope(managed_repo.id) do
      {:ok,
       %{
         managed_repo: managed_repo,
         source_repo: source_repo,
         repo_scope: repo_scope,
         route_id: repo_scope.route_id
       }}
    end
  end

  def create_governed_run!(repo_identifier, attrs \\ %{}) when is_map(attrs) do
    {:ok, run} = create_governed_run(repo_identifier, attrs)
    run
  end

  def create_governed_run(repo_identifier, attrs \\ %{}) when is_map(attrs) do
    with {:ok, repo_scope} <- governed_run_repo_scope(repo_identifier) do
      managed_repo_id =
        repo_scope
        |> Map.get(:managed_repo, %{})
        |> Map.get(:id)

      legacy_project_id = Map.get(repo_scope, :route_id) || managed_repo_id

      base_attrs = %{
        workflow_run_id: JidoCode.UUID.generate(),
        managed_repo_id: managed_repo_id,
        legacy_project_id: legacy_project_id,
        run_id: "run-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 1,
        status: :pending,
        current_step: "queued",
        current_stage: "repo_attach",
        trigger: %{"source" => "test", "mode" => "manual"},
        inputs: %{},
        input_metadata: %{},
        initiating_actor: %{"id" => "test-owner", "email" => "owner@example.com"},
        started_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      base_attrs
      |> Map.merge(attrs)
      |> put_work_item_input(Map.get(attrs, :work_item_id))
      |> OrchestrationRecordStore.upsert_run(actor: Actor.operator_actor())
    end
  end

  def read_managed_repo!(managed_repo_id) when is_binary(managed_repo_id) do
    {:ok, managed_repo} = ManagedRepoStore.get_by_id(managed_repo_id)
    managed_repo
  end

  defp auth_result(conn, _session_token, _owner, false, false), do: conn
  defp auth_result(conn, session_token, _owner, true, false), do: {conn, session_token}
  defp auth_result(conn, _session_token, owner, false, true), do: {conn, owner}
  defp auth_result(conn, session_token, owner, true, true), do: {conn, session_token, owner}

  defp seed_product_owner!(email) do
    case OwnerStore.get_by_email(email) do
      {:ok, nil} -> OwnerStore.create_owner(%{email: email})
      {:ok, owner} -> {:ok, owner}
      {:error, reason} -> raise "owner seed failed: #{inspect(reason)}"
    end
  end

  defp put_work_item_input(attrs, work_item_id) when is_binary(work_item_id) do
    inputs =
      attrs
      |> Map.get(:inputs, %{})
      |> normalize_map()
      |> Map.put_new("work_item_id", work_item_id)

    Map.put(attrs, :inputs, inputs)
  end

  defp put_work_item_input(attrs, _work_item_id), do: attrs

  defp normalize_map(%{} = map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_map(_value), do: %{}

  defp governed_run_repo_scope(%{repo_scope: repo_scope}) when is_map(repo_scope), do: {:ok, repo_scope}
  defp governed_run_repo_scope(%{route_id: route_id}) when is_binary(route_id), do: RepoBridge.repo_scope(route_id)

  defp governed_run_repo_scope(%{managed_repo: %{id: managed_repo_id}})
       when is_binary(managed_repo_id) do
    RepoBridge.repo_scope(managed_repo_id)
  end

  defp governed_run_repo_scope(%{id: managed_repo_id}) when is_binary(managed_repo_id) do
    RepoBridge.repo_scope(managed_repo_id)
  end

  defp governed_run_repo_scope(repo_identifier) when is_binary(repo_identifier) do
    RepoBridge.repo_scope(repo_identifier)
  end
end
