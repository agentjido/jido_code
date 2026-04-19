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

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use JidoCodeWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User
  alias JidoCode.Control.{Actor, ManagedRepo, RepoBridge}
  alias JidoCode.Orchestration.Run

  import Phoenix.ConnTest, only: [recycle: 1]
  import Plug.Conn, only: [get_session: 2]

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
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  def register_owner(email, password) do
    strategy = Info.strategy!(User, :password)

    {:ok, _owner} =
      Strategy.action(
        strategy,
        :register,
        %{
          "email" => email,
          "password" => password,
          "password_confirmation" => password
        },
        context: %{token_type: :sign_in}
      )

    :ok
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
    strategy = Info.strategy!(User, :password)

    {:ok, owner} =
      Strategy.action(
        strategy,
        :sign_in,
        %{"email" => email, "password" => password},
        context: %{token_type: :sign_in}
      )

    token =
      owner
      |> Map.get(:__metadata__, %{})
      |> Map.fetch!(:token)

    auth_response =
      Phoenix.ConnTest.dispatch(
        conn,
        JidoCodeWeb.Endpoint,
        :get,
        owner_sign_in_with_token_path(strategy, token)
      )

    session_token = get_session(auth_response, "user_token")

    ExUnit.Assertions.assert(is_binary(session_token))

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

      Run.create(Map.merge(base_attrs, attrs), actor: Actor.operator_actor())
    end
  end

  def read_managed_repo!(managed_repo_id) when is_binary(managed_repo_id) do
    {:ok, [managed_repo]} =
      ManagedRepo.read(
        query: [filter: [id: managed_repo_id], limit: 1],
        actor: Actor.operator_actor()
      )

    managed_repo
  end

  defp auth_result(conn, _session_token, _owner, false, false), do: conn
  defp auth_result(conn, session_token, _owner, true, false), do: {conn, session_token}
  defp auth_result(conn, _session_token, owner, false, true), do: {conn, owner}
  defp auth_result(conn, session_token, owner, true, true), do: {conn, session_token, owner}

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

  defp owner_sign_in_with_token_path(strategy, token) do
    strategy_path =
      strategy
      |> Strategy.routes()
      |> Enum.find_value(fn
        {path, :sign_in_with_token} -> path
        _other -> nil
      end)

    path =
      Path.join(
        "/auth",
        String.trim_leading(strategy_path || "/user/password/sign_in_with_token", "/")
      )

    query = URI.encode_query(%{"token" => token})
    "#{path}?#{query}"
  end
end
