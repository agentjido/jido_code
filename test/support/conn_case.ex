defmodule JidoCodeWeb.ConnCase do
  # covers: package.jido_code.version_controlled_quality_surfaces
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

  defp auth_result(conn, _session_token, _owner, false, false), do: conn
  defp auth_result(conn, session_token, _owner, true, false), do: {conn, session_token}
  defp auth_result(conn, _session_token, owner, false, true), do: {conn, owner}
  defp auth_result(conn, session_token, owner, true, true), do: {conn, session_token, owner}

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
