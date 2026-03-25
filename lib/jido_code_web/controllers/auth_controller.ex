defmodule JidoCodeWeb.AuthController do
  use JidoCodeWeb, :controller
  use AshAuthentication.Phoenix.Controller

  require Logger

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
    |> store_in_session(user)
    # If your resource has a different name, update the assign name here (i.e :current_admin)
    |> assign(:current_user, user)
    |> put_flash(:info, message)
    |> redirect(to: return_to)
  end

  def failure(conn, activity, reason) do
    message =
      case {activity, reason} do
        {_,
         %AshAuthentication.Errors.AuthenticationFailed{
           caused_by: %Ash.Error.Forbidden{
             errors: [%AshAuthentication.Errors.CannotConfirmUnconfirmedUser{}]
           }
         }} ->
          """
          You have already signed in another way, but have not confirmed your account.
          You can confirm your account using the link we sent to you, or by resetting your password.
          """

        _ ->
          "Incorrect email or password"
      end

    conn
    |> put_flash(:error, message)
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

  defp default_sign_out_invalidator(conn, otp_app), do: clear_session(conn, otp_app)

  defp default_return_to do
    case BootstrapStatus.current().state do
      :continue_setup -> ~p"/setup"
      :ready -> ~p"/"
      _other -> ~p"/welcome"
    end
  end
end
