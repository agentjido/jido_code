defmodule JidoCode.Accounts do
  use Ash.Domain, otp_app: :jido_code, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource JidoCode.Accounts.Token
    resource JidoCode.Accounts.User
    resource JidoCode.Accounts.ApiKey
    resource JidoCode.Accounts.UserIdentity
  end
end
