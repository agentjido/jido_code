defmodule JidoCode.GitHub.IssueAnalysis do
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.GitHub,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Control.Checks.ActorClassIn

  postgres do
    table "github_issue_analyses"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :get_by_id, action: :read, get_by: [:id]
    define :get_by_issue, action: :get_by_issue
    define :update_analysis
    define :mark_labels_applied
    define :mark_comment_posted
    define :list_for_repo, action: :list_for_repo
    define :list_pending, action: :list_pending
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :repo_id,
        :issue_number,
        :issue_url,
        :title,
        :body,
        :original_labels
      ]

      primary? true
      change set_attribute(:status, :pending)
    end

    update :update_analysis do
      accept [
        :suggested_labels,
        :priority,
        :complexity,
        :assignee_recommendation,
        :analysis_summary,
        :raw_llm_response
      ]

      change set_attribute(:status, :analyzed)
      change set_attribute(:analyzed_at, &DateTime.utc_now/0)
    end

    update :mark_labels_applied do
      accept [:applied_labels]
      change set_attribute(:labels_applied, true)
    end

    update :mark_comment_posted do
      change set_attribute(:comment_posted, true)
    end

    read :get_by_issue do
      argument :repo_id, :uuid, allow_nil?: false
      argument :issue_number, :integer, allow_nil?: false

      get? true

      filter expr(
               repo_id == ^arg(:repo_id) and
                 issue_number == ^arg(:issue_number)
             )
    end

    read :list_for_repo do
      argument :repo_id, :uuid, allow_nil?: false
      filter expr(repo_id == ^arg(:repo_id))
    end

    read :list_pending do
      filter expr(status == :pending)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {ActorClassIn,
                    classes: [
                      :admin,
                      :operator,
                      :factory_system,
                      :external_ingress,
                      :run_worker
                    ]}
    end

    policy action_type(:create) do
      authorize_if {ActorClassIn,
                    classes: [
                      :admin,
                      :operator,
                      :factory_system,
                      :external_ingress,
                      :run_worker
                    ]}
    end

    policy action_type(:update) do
      authorize_if {ActorClassIn,
                    classes: [
                      :admin,
                      :operator,
                      :factory_system,
                      :external_ingress,
                      :run_worker
                    ]}
    end

    policy action_type(:destroy) do
      authorize_if {ActorClassIn, classes: [:admin, :operator, :factory_system]}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :issue_number, :integer do
      allow_nil? false
      public? true
      description "GitHub issue number"
    end

    attribute :issue_url, :string do
      allow_nil? false
      public? true
      description "Full URL to the GitHub issue"
    end

    attribute :title, :string do
      allow_nil? false
      public? true
      description "Issue title at time of analysis"
    end

    attribute :body, :string do
      allow_nil? true
      public? true
      description "Issue body at time of analysis"
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :analyzing, :analyzed, :failed]
      description "Analysis status"
    end

    attribute :original_labels, {:array, :string} do
      allow_nil? true
      default []
      public? true
      description "Labels on the issue before analysis"
    end

    attribute :suggested_labels, {:array, :string} do
      allow_nil? true
      default []
      public? true
      description "Labels suggested by LLM analysis"
    end

    attribute :applied_labels, {:array, :string} do
      allow_nil? true
      default []
      public? true
      description "Labels actually applied to the issue"
    end

    attribute :priority, :atom do
      allow_nil? true
      public? true
      constraints one_of: [:critical, :high, :medium, :low]
      description "Suggested priority level"
    end

    attribute :complexity, :atom do
      allow_nil? true
      public? true
      constraints one_of: [:trivial, :simple, :moderate, :complex, :epic]
      description "Estimated complexity"
    end

    attribute :assignee_recommendation, :string do
      allow_nil? true
      public? true
      description "Suggested assignee (if any)"
    end

    attribute :analysis_summary, :string do
      allow_nil? true
      public? true
      description "Human-readable summary of the analysis"
    end

    attribute :raw_llm_response, :map do
      allow_nil? true
      public? true
      sensitive? true
      description "Raw response from LLM for debugging"
    end

    attribute :labels_applied, :boolean do
      allow_nil? false
      default false
      public? true
      description "Whether labels were applied to GitHub"
    end

    attribute :comment_posted, :boolean do
      allow_nil? false
      default false
      public? true
      description "Whether analysis comment was posted"
    end

    attribute :analyzed_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "When analysis completed"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :repo, JidoCode.GitHub.Repo do
      allow_nil? false
      public? true
      attribute_type :uuid
    end

    belongs_to :webhook_delivery, JidoCode.GitHub.WebhookDelivery do
      allow_nil? true
      public? true
      attribute_type :uuid
      description "The webhook delivery that triggered this analysis"
    end
  end

  identities do
    identity :unique_issue_per_repo, [:repo_id, :issue_number]
  end
end
