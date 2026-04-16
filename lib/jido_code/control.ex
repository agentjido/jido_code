defmodule JidoCode.Control do
  use Ash.Domain, otp_app: :jido_code, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource JidoCode.Control.SourceRepo
    resource JidoCode.Control.ManagedRepo
    resource JidoCode.Control.LLMPreferences
  end
end
