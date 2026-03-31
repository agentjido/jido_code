defmodule JidoCode.Orchestration do
  use Ash.Domain, otp_app: :jido_code, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource JidoCode.Orchestration.ExecutionProfile
    resource JidoCode.Orchestration.Run
    resource JidoCode.Orchestration.WorkflowRun
  end
end
