defmodule JidoCode.Security do
  use Ash.Domain, otp_app: :jido_code, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource JidoCode.Security.SecretRef
    resource JidoCode.Security.SecretLifecycleAudit
  end
end
