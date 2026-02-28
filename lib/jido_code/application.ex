defmodule JidoCode.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        JidoCodeWeb.Telemetry,
        JidoCode.Repo,
        {DNSCluster, query: Application.get_env(:jido_code, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: JidoCode.PubSub},
        JidoCode.Jido,
        JidoCodeWeb.Endpoint,
        {AshAuthentication.Supervisor, [otp_app: :jido_code]},
        # Forge supervision tree
        {Registry, keys: :unique, name: JidoCode.Forge.SessionRegistry},
        {DynamicSupervisor, name: JidoCode.Forge.InfraSupervisor, strategy: :one_for_one},
        {DynamicSupervisor, name: JidoCode.Forge.ExecSessionSupervisor, strategy: :one_for_one},
        JidoCode.Forge.Manager
      ] ++ forge_dev_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: JidoCode.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    JidoCodeWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  if Application.compile_env(:jido_code, :runtime_mode, :prod) in [:dev, :test] do
    defp forge_dev_children, do: [{JidoCode.Forge.InfraClient.Fake, []}]
  else
    defp forge_dev_children, do: []
  end
end
