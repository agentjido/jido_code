defmodule AgentJido.Secrets do
  @moduledoc false
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        AgentJido.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:agent_jido, :token_signing_secret)
  end
end
