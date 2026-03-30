defmodule JidoCodeWeb.LiveUserAuth do
  @moduledoc """
  Helpers for authenticating users in LiveViews.
  """

  require Logger

  import Phoenix.Component
  use JidoCodeWeb, :verified_routes

  alias JidoCode.Setup.BootstrapStatus

  # This is used for nested liveviews to fetch the current user.
  # To use, place the following at the top of that liveview:
  # on_mount {JidoCodeWeb.LiveUserAuth, :current_user}
  def on_mount(:current_user, _params, session, socket) do
    {:cont, AshAuthentication.Phoenix.LiveSession.assign_new_resources(socket, session)}
  end

  def on_mount(:live_user_optional, _params, _session, socket) do
    if socket.assigns[:current_user] do
      {:cont, socket}
    else
      {:cont, assign(socket, :current_user, nil)}
    end
  end

  def on_mount(:live_user_required, _params, _session, socket) do
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

  def on_mount(:live_no_user, _params, _session, socket) do
    status = BootstrapStatus.current()

    cond do
      socket.assigns[:current_user] && status.state == :continue_setup ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/setup")}

      socket.assigns[:current_user] ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}

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
end
