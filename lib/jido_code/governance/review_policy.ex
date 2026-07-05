defmodule JidoCode.Governance.ReviewPolicy do
  @moduledoc false

  @type t :: %__MODULE__{}

  defstruct mode: "approval_required",
            requires_human_approval: true,
            change_request_required: true,
            review_threshold: "human_approval",
            required_stage: "approval",
            source: "policy_set.review_policy.default"
end
