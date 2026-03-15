defmodule JidoCode.AuthProviders do
  # covers: auth.provider_foundation.provider_login_configuration
  use Ash.Domain, otp_app: :jido_code, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource JidoCode.AuthProviders.ProviderConfig
  end
end
