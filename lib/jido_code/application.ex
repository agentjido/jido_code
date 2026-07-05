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
        JidoCode.ControlPlane.StoreServer,
        {DNSCluster, query: Application.get_env(:jido_code, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: JidoCode.PubSub},
        JidoCode.Jido,
        JidoCodeWeb.Endpoint,
        {AshAuthentication.Supervisor, [otp_app: :jido_code]},
        # Conversation coordination
        {Registry, keys: :unique, name: JidoCode.Conversations.Registry},
        {DynamicSupervisor, name: JidoCode.Conversations.DynamicSupervisor, strategy: :one_for_one},
        {DynamicSupervisor, name: JidoCode.Conversations.ChildSupervisor, strategy: :one_for_one},
        # Forge supervision tree
        {Registry, keys: :unique, name: JidoCode.Forge.SessionRegistry},
        {DynamicSupervisor, name: JidoCode.Forge.SpriteSupervisor, strategy: :one_for_one},
        {DynamicSupervisor, name: JidoCode.Forge.ExecSessionSupervisor, strategy: :one_for_one},
        JidoCode.Forge.Manager,
        # Repository source-change monitoring
        {Registry, keys: :unique, name: JidoCode.RepoMonitor.SourceWatcherRegistry},
        {DynamicSupervisor, name: JidoCode.RepoMonitor.SourceWatcherSupervisor, strategy: :one_for_one},
        {Registry, keys: :unique, name: JidoCode.SourceCodeGraph.RefreshSchedulerRegistry},
        {DynamicSupervisor, name: JidoCode.SourceCodeGraph.RefreshSchedulerSupervisor, strategy: :one_for_one},
        {Task.Supervisor, name: JidoCode.SourceCodeGraph.RefreshTaskSupervisor},
        # AgentOS supervision tree
        {JidoCode.AgentOS.Manager.Server, []},
        {JidoCode.AgentOS.Manager.Supervisor, []}
      ] ++ live_vue_children() ++ forge_dev_children()

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

  if Application.compile_env(:jido_code, :runtime_mode, :prod) == :prod do
    defp live_vue_children, do: [{NodeJS.Supervisor, [path: LiveVue.SSR.NodeJS.server_path(), pool_size: 4]}]
  else
    defp live_vue_children, do: []
  end

  if Application.compile_env(:jido_code, :runtime_mode, :prod) in [:dev, :test] do
    defp forge_dev_children, do: [{JidoCode.Forge.SpriteClient.Fake, []}]
  else
    defp forge_dev_children, do: []
  end
end
