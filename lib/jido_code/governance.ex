defmodule JidoCode.Governance do
  use Ash.Domain, otp_app: :jido_code, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource JidoCode.Governance.ChangeRequest
    resource JidoCode.Governance.Decision
    resource JidoCode.Governance.Evidence
    resource JidoCode.Governance.PolicySet
  end
end
