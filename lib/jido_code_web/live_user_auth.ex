defmodule JidoCodeWeb.LiveUserAuth do
  @moduledoc """
  Helpers for authenticating users in LiveViews.
  """

  # covers: auth.system.ready_state_local_auth_handoff

  require Logger

  import Phoenix.Component
  use JidoCodeWeb, :verified_routes

  alias JidoCode.Accounts.{SessionTokens, User}
  alias JidoCode.Setup.{BootstrapStatus, BootstrapToken, OwnerStore}

  # This is used for nested liveviews to fetch the current user.
  # To use, place the following at the top of that liveview:
  # on_mount {JidoCodeWeb.LiveUserAuth, :current_user}
  def on_mount(:current_user, _params, session, socket) do
    socket = assign_product_session_user(socket, session)

    {:cont, socket}
  end

  def on_mount(:live_user_optional, _params, session, socket) do
    socket = assign_product_session_user(socket, session)

    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  def on_mount(:live_user_required, _params, session, socket) do
    socket = assign_product_session_user(socket, session)

    case {socket.assigns[:current_user], BootstrapStatus.current().state} do
      {nil, _state} ->
        log_auth_boundary(:deny, socket, "missing_or_expired_session")
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/welcome")}

      {_user, :continue_setup} ->
        log_auth_boundary(:deny, socket, "onboarding_incomplete")
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/setup")}

      {_user, :ready} ->
        log_auth_boundary(:allow, socket, "ready_session_present")
        {:cont, socket}

      {_user, _other} ->
        log_auth_boundary(:deny, socket, "bootstrap_entry_required")
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/welcome")}
    end
  end

  def on_mount(:live_no_user, _params, session, socket) do
    socket = assign_product_session_user(socket, session)
    status = BootstrapStatus.current()

    cond do
      socket.assigns[:current_user] && status.state == :continue_setup ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/setup")}

      socket.assigns[:current_user] ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/dashboard")}

      status.state == :bootstrap_required ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/welcome")}

      true ->
        {:cont, assign(socket, :current_user, nil)}
    end
  end

  defp log_auth_boundary(:allow, socket, reason) do
    Logger.warning("auth_boundary_check outcome=allow live_view=#{inspect(socket.view)} reason=#{reason}")
  end

  defp log_auth_boundary(:deny, socket, reason) do
    Logger.warning("auth_boundary_check outcome=deny live_view=#{inspect(socket.view)} reason=#{reason}")
  end

  defp assign_product_session_user(socket, session) do
    if socket.assigns[:current_user] do
      socket
    else
      case product_session_user(session) do
        {:ok, %User{} = user} -> assign(socket, :current_user, user)
        _error -> socket
      end
    end
  end

  defp product_session_user(session) when is_map(session) do
    token =
      Map.get(session, "product_user_token") ||
        Map.get(session, :product_user_token) ||
        Map.get(session, "user_token") ||
        Map.get(session, :user_token)

    case SessionTokens.verify(token) do
      {:ok, %User{} = user} ->
        {:ok, user}

      {:error, _reason} ->
        with {:ok, %{"email" => email}} <- BootstrapToken.verify(token),
             {:ok, %User{} = owner} <- OwnerStore.get_by_email(email) do
          {:ok, owner}
        end
    end
  end

  defp product_session_user(_session), do: {:error, :missing_session}
end
