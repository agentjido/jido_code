defmodule JidoCode.Orchestration.ExecutionProfile do
  # covers: architecture.run_governance.execution_profile_governs_environment_defaults
  # covers: architecture.run_governance.execution_profile_preserves_repo_and_workflow_compatibility
  @moduledoc false

  use JidoCode.ControlPlane.RecordStruct

  @default_governed_stages [
    "repo_attach",
    "repo_sync",
    "repo_prep",
    "validation",
    "approval",
    "cleanup"
  ]

  @default_validation_plan ["lint", "tests", "spec_check"]
  @default_repo_prep_plan ["repo_attach", "repo_sync", "repo_prep"]
  @default_checkpoint_strategy "resume_from_runic_state"

  def default_governed_stages, do: @default_governed_stages
  def default_repo_prep_plan, do: @default_repo_prep_plan
  def default_validation_plan, do: @default_validation_plan
  def default_checkpoint_strategy, do: @default_checkpoint_strategy
end
