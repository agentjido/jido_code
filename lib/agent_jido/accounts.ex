defmodule AgentJido.Accounts do
  @moduledoc false
  use Ash.Domain, otp_app: :agent_jido, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource AgentJido.Accounts.Token
    resource AgentJido.Accounts.User
    resource AgentJido.Accounts.ApiKey
  end
end
