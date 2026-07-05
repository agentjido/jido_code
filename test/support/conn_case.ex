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
  alias JidoCode.Control.{Actor, ManagedRepoStore, RepoBridge}
  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.Orchestration.{Run, WorkflowRun}
  alias JidoCode.Projects.Project
  alias JidoCode.Setup.OwnerStore

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
    setup_product_store()
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  def register_owner(email, password) do
    strategy = Info.strategy!(User, :password)

    case Strategy.action(
           strategy,
           :register,
           %{
             "email" => email,
             "password" => password,
             "password_confirmation" => password
           },
           context: %{token_type: :sign_in}
         ) do
      {:ok, _owner} ->
        seed_product_owner!(email)

      {:error, %Ash.Error.Forbidden{}} ->
        with :ok <- bootstrap_owner(email, password) do
          seed_product_owner!(email)
        end

      {:error, reason} ->
        if duplicate_email_error?(reason) do
          seed_product_owner!(email)
        else
          raise "owner registration failed: #{Exception.message(reason)}"
        end
    end
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

      with {:ok, project_id} <- governed_run_project_id(repo_scope) do
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

        run_attrs = Map.merge(base_attrs, attrs)
        workflow_attrs = workflow_run_attrs(run_attrs, project_id)

        with {:ok, workflow_run} <- WorkflowRun.create(workflow_attrs, actor: Actor.operator_actor()),
             {:ok, final_workflow_run} <- transition_workflow_run(workflow_run, run_attrs),
             {:ok, run} <- Run.get_by_workflow_run_id(final_workflow_run.id, actor: Actor.operator_actor()) do
          {:ok, run}
        end
      end
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
    {:ok, _owner} = OwnerStore.create_owner(%{email: email})
    :ok
  end

  defp duplicate_email_error?(reason) do
    Exception.message(reason) =~ "has already been taken"
  end

  defp governed_run_project_id(%{project_id: project_id}) when is_binary(project_id), do: {:ok, project_id}

  defp governed_run_project_id(%{source_repo: source_repo, managed_repo: managed_repo}) do
    full_name =
      source_repo
      |> map_get(:full_name, "full_name")
      |> normalize_optional_string()

    name =
      managed_repo
      |> map_get(:display_name, "display_name")
      |> normalize_optional_string() ||
        source_repo
        |> map_get(:name, "name")
        |> normalize_optional_string() ||
        "governed-run-fixture"

    default_branch =
      source_repo
      |> map_get(:default_branch, "default_branch")
      |> normalize_optional_string() || "main"

    if is_binary(full_name) do
      case Project.get_by_github_full_name(full_name, actor: Actor.operator_actor()) do
        {:ok, %Project{id: project_id}} ->
          {:ok, project_id}

        _other ->
          with {:ok, %Project{id: project_id}} <-
                 Project.create(
                   %{
                     name: name,
                     github_full_name: full_name,
                     default_branch: default_branch,
                     settings: project_settings_for_governed_run(managed_repo)
                   },
                   actor: Actor.factory_system_actor()
                 ) do
            {:ok, project_id}
          end
      end
    else
      {:error, :governed_run_project_unavailable}
    end
  end

  defp governed_run_project_id(_repo_scope), do: {:error, :governed_run_project_unavailable}

  defp project_settings_for_governed_run(managed_repo) do
    workspace_settings =
      managed_repo
      |> map_get(:workspace_settings, "workspace_settings")
      |> normalize_map()

    case workspace_settings do
      empty when empty == %{} -> %{}
      settings -> %{"workspace" => settings}
    end
  end

  defp workflow_run_attrs(run_attrs, project_id) do
    run_attrs
    |> Map.take([
      :run_id,
      :managed_repo_id,
      :workflow_name,
      :workflow_version,
      :trigger,
      :inputs,
      :input_metadata,
      :initiating_actor,
      :current_step,
      :started_at,
      :retry_of_run_id,
      :retry_attempt,
      :retry_lineage
    ])
    |> Map.put(:project_id, project_id)
    |> put_work_item_input(Map.get(run_attrs, :work_item_id))
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

  defp transition_workflow_run(%WorkflowRun{} = workflow_run, run_attrs) do
    target_status = Map.get(run_attrs, :status, :pending)
    current_step = Map.get(run_attrs, :current_step, workflow_run.current_step)
    transitioned_at = Map.get(run_attrs, :completed_at) || Map.get(run_attrs, :started_at)

    target_status
    |> workflow_transition_path()
    |> Enum.reduce_while({:ok, workflow_run}, fn status, {:ok, current_run} ->
      case WorkflowRun.transition_status(
             current_run,
             %{
               to_status: status,
               current_step: current_step,
               transitioned_at: transitioned_at
             },
             actor: Actor.operator_actor()
           ) do
        {:ok, updated_run} -> {:cont, {:ok, updated_run}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp workflow_transition_path(:pending), do: []
  defp workflow_transition_path(:running), do: [:running]
  defp workflow_transition_path(:awaiting_approval), do: [:running, :awaiting_approval]
  defp workflow_transition_path(status) when status in [:completed, :failed], do: [:running, status]
  defp workflow_transition_path(:cancelled), do: [:cancelled]
  defp workflow_transition_path(_status), do: []

  defp map_get(map, atom_key, string_key) when is_map(map) do
    Map.get(map, atom_key) || Map.get(map, string_key)
  end

  defp map_get(_map, _atom_key, _string_key), do: nil

  defp normalize_map(%{} = map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp bootstrap_owner(email, password) do
    case User.bootstrap_admin(
           %{
             email: email,
             password: password,
             password_confirmation: password
           },
           authorize?: false
         ) do
      {:ok, _owner} ->
        :ok

      {:error, reason} ->
        if Exception.message(reason) =~ "has already been taken" do
          :ok
        else
          raise "owner bootstrap failed: #{Exception.message(reason)}"
        end
    end
  end

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
