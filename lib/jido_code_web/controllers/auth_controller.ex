defmodule JidoCodeWeb.AuthController do
  # covers: auth.system.ready_state_local_auth_handoff
  use JidoCodeWeb, :controller

  require Logger

  alias JidoCode.Accounts.{SessionTokens, UserStore}
  alias JidoCode.Setup.BootstrapStatus

  @sign_out_success_message "You are now signed out"
  @sign_out_retry_message "Sign-out could not complete. Please retry; your current session is still active."

  def success(conn, activity, user, _token) do
    return_to = get_session(conn, :return_to) || default_return_to()

    message =
      case activity do
        {:confirm_new_user, :confirm} -> "Your email address has now been confirmed"
        {:password, :reset} -> "Your password has successfully been reset"
        _ -> "You are now signed in"
      end

    conn
    |> delete_session(:return_to)
    |> configure_session(renew: true)
    |> put_product_session(user)
    |> assign(:current_user, user)
    |> put_flash(:info, message)
    |> redirect(to: return_to)
  end

  def failure(conn, _activity, _reason) do
    conn
    |> put_flash(:error, "Incorrect email or password")
    |> redirect(to: ~p"/sign-in")
  end

  def sign_out(conn, _params) do
    return_to = get_session(conn, :return_to) || ~p"/"

    case invalidate_session(conn) do
      {:ok, cleared_conn} ->
        cleared_conn
        |> put_flash(:info, @sign_out_success_message)
        |> redirect(to: return_to)

      {:error, reason} ->
        Logger.warning("auth_sign_out_failed reason=#{inspect(reason)}")

        conn
        |> put_flash(:error, @sign_out_retry_message)
        |> redirect(to: return_to)
    end
  end

  defp invalidate_session(conn) do
    invalidator =
      Application.get_env(
        :jido_code,
        :sign_out_invalidator,
        &default_sign_out_invalidator/2
      )

    try do
      case invalidator.(conn, :jido_code) do
        %Plug.Conn{} = cleared_conn -> {:ok, cleared_conn}
        {:ok, %Plug.Conn{} = cleared_conn} -> {:ok, cleared_conn}
        {:error, reason} -> {:error, reason}
        other -> {:error, {:unexpected_sign_out_invalidator_result, other}}
      end
    rescue
      error -> {:error, {:exception, error}}
    end
  end

  defp default_sign_out_invalidator(conn, _otp_app), do: configure_session(conn, drop: true)

  defp put_product_session(conn, user) do
    with {:ok, product_user} <- product_user_for(user),
         {:ok, token} <- SessionTokens.issue(product_user) do
      conn
      |> put_session("product_user_token", token)
      |> put_session("product_user_email", to_string(product_user.email))
    else
      _error -> conn
    end
  end

  defp product_user_for(user) do
    email = user |> Map.get(:email) |> to_string()

    case UserStore.get_by_email(email) do
      {:ok, nil} ->
        UserStore.upsert(%{
          user_id: user |> Map.get(:id) |> to_string(),
          email: email,
          is_admin: Map.get(user, :is_admin, false),
          confirmed_at: Map.get(user, :confirmed_at)
        })

      {:ok, product_user} ->
        {:ok, product_user}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp default_return_to do
    case BootstrapStatus.current().state do
      :continue_setup -> ~p"/setup"
      :ready -> ~p"/dashboard"
      _other -> ~p"/welcome"
    end
  end
end
