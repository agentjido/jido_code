defmodule AgentJido.Forge.Domain do
  @moduledoc false
  use Ash.Domain, otp_app: :agent_jido, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource AgentJido.Forge.Resources.SpriteSpec
    resource AgentJido.Forge.Resources.Workflow
    resource AgentJido.Forge.Resources.Session
    resource AgentJido.Forge.Resources.Checkpoint
    resource AgentJido.Forge.Resources.ExecSession
    resource AgentJido.Forge.Resources.Event
  end
end
