defmodule AgentJido.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        AgentJidoWeb.Telemetry,
        AgentJido.Repo,
        {DNSCluster, query: Application.get_env(:agent_jido, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: AgentJido.PubSub},
        AgentJido.Jido,
        AgentJidoWeb.Endpoint,
        {AshAuthentication.Supervisor, [otp_app: :agent_jido]},
        # Forge supervision tree
        {Registry, keys: :unique, name: AgentJido.Forge.SessionRegistry},
        {DynamicSupervisor, name: AgentJido.Forge.SpriteSupervisor, strategy: :one_for_one},
        {DynamicSupervisor, name: AgentJido.Forge.ExecSessionSupervisor, strategy: :one_for_one},
        AgentJido.Forge.Manager
      ] ++ forge_dev_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AgentJido.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AgentJidoWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp forge_dev_children do
    if Application.get_env(:agent_jido, :forge_fake_sprite_client?, false) do
      [{AgentJido.Forge.SpriteClient.Fake, []}]
    else
      []
    end
  end
end
