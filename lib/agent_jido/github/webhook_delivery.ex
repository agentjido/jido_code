defmodule AgentJido.GitHub.WebhookDelivery do
  @moduledoc false
  use Ash.Resource,
    otp_app: :agent_jido,
    domain: AgentJido.GitHub,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "github_webhook_deliveries"
    repo AgentJido.Repo
  end

  code_interface do
    define :create
    define :read
    define :get_by_id, action: :read, get_by: [:id]
    define :get_by_github_delivery_id, action: :read, get_by: [:github_delivery_id]
    define :mark_processed
    define :mark_failed
    define :list_pending, action: :list_pending
    define :list_for_repo, action: :list_for_repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:github_delivery_id, :event_type, :action, :payload, :repo_id]
      primary? true

      change set_attribute(:status, :pending)
    end

    update :mark_processed do
      change set_attribute(:status, :processed)
      change set_attribute(:processed_at, &DateTime.utc_now/0)
    end

    update :mark_failed do
      accept [:error_message]
      change set_attribute(:status, :failed)
      change set_attribute(:processed_at, &DateTime.utc_now/0)
    end

    read :list_pending do
      filter expr(status == :pending)
    end

    read :list_for_repo do
      argument :repo_id, :uuid, allow_nil?: false
      filter expr(repo_id == ^arg(:repo_id))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type(:update) do
      authorize_if always()
    end

    policy action_type(:destroy) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :github_delivery_id, :string do
      allow_nil? false
      public? true
      description "X-GitHub-Delivery header value (GUID)"
    end

    attribute :event_type, :string do
      allow_nil? false
      public? true
      description "X-GitHub-Event header value (e.g., issues, pull_request)"
    end

    attribute :action, :string do
      allow_nil? true
      public? true
      description "Payload action field (e.g., opened, closed)"
    end

    attribute :payload, :map do
      allow_nil? false
      public? true
      description "Full webhook payload (JSON)"
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      public? true
      constraints one_of: [:pending, :processed, :failed, :skipped]
      description "Processing status of this delivery"
    end

    attribute :error_message, :string do
      allow_nil? true
      public? true
      description "Error message if processing failed"
    end

    attribute :processed_at, :utc_datetime_usec do
      allow_nil? true
      public? true
      description "When this delivery was processed"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :repo, AgentJido.GitHub.Repo do
      allow_nil? false
      public? true
      attribute_type :uuid
    end
  end

  identities do
    identity :unique_github_delivery, [:github_delivery_id]
  end
end
