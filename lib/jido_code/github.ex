defmodule JidoCode.GitHub do
  use Ash.Domain, otp_app: :jido_code, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource JidoCode.GitHub.Repo
    resource JidoCode.GitHub.WebhookDelivery
    resource JidoCode.GitHub.IssueAnalysis
  end
end
