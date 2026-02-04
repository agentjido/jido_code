defmodule AgentJido.Folio do
  @moduledoc false
  use Ash.Domain

  resources do
    resource AgentJido.Folio.InboxItem
    resource AgentJido.Folio.Action
    resource AgentJido.Folio.Project
  end
end
