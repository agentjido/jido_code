defmodule JidoCode.Governance.ReviewPolicy do
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :mode, :string do
      allow_nil? false
      default "approval_required"
      constraints match: ~r/^(auto_post|approval_required)$/
      public? true
    end

    attribute :requires_human_approval, :boolean do
      allow_nil? false
      default true
      public? true
    end

    attribute :change_request_required, :boolean do
      allow_nil? false
      default true
      public? true
    end

    attribute :review_threshold, :string do
      allow_nil? false
      default "human_approval"
      public? true
    end

    attribute :required_stage, :string do
      allow_nil? false
      default "approval"
      public? true
    end

    attribute :source, :string do
      allow_nil? false
      default "policy_set.review_policy.default"
      public? true
    end
  end
end
