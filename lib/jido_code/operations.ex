defmodule JidoCode.Operations do
  use Ash.Domain, otp_app: :jido_code, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource JidoCode.Operations.Event
    resource JidoCode.Operations.Assessment
    resource JidoCode.Operations.ExternalObject
    resource JidoCode.Operations.Observation
    resource JidoCode.Operations.Intake
  end
end
