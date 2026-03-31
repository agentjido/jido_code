defmodule JidoCode.GitHub.Repo do
  require Logger

  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.GitHub,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTypescript.Resource]

  alias JidoCode.Control.Checks.ActorClassIn

  postgres do
    table "github_repos"
    repo JidoCode.Repo
  end

  typescript do
    type_name "GitHubRepo"
  end

  code_interface do
    define :create
    define :read
    define :get_by_id, action: :read, get_by: [:id]
    define :get_by_full_name, action: :read, get_by: [:full_name]
    define :update
    define :disable
    define :enable
    define :list_enabled, action: :list_enabled
  end

  @webhook_secret_placeholder "__managed_by_secret_ref__"
  @plaintext_secret_error_type "plaintext_secret_persistence_blocked"
  @plaintext_secret_policy "operational_secret_plaintext_forbidden"
  @plaintext_secret_remediation """
  Persist operational secrets through encrypted SecretRef entries and retry without plaintext secret fields.
  """

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:owner, :name, :webhook_secret, :webhook_id, :settings, :github_app_installation_id]
      primary? true

      change fn changeset, _ctx ->
        changeset
        |> reject_plaintext_secret_persistence()
        |> assign_full_name()
      end
    end

    update :update do
      accept [:webhook_secret, :webhook_id, :settings, :enabled, :github_app_installation_id]
      primary? true
      require_atomic? false

      change fn changeset, _ctx ->
        reject_plaintext_secret_persistence(changeset)
      end
    end

    update :disable do
      change set_attribute(:enabled, false)
    end

    update :enable do
      change set_attribute(:enabled, true)
    end

    read :list_enabled do
      filter expr(enabled == true)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {ActorClassIn,
                    classes: [
                      :admin,
                      :operator,
                      :factory_system,
                      :external_ingress
                    ]}
    end

    policy action_type(:create) do
      authorize_if {ActorClassIn, classes: [:admin, :operator, :factory_system, :external_ingress]}
    end

    policy action_type(:update) do
      authorize_if {ActorClassIn, classes: [:admin, :operator, :factory_system, :external_ingress]}
    end

    policy action_type(:destroy) do
      authorize_if {ActorClassIn, classes: [:admin, :operator, :factory_system]}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :owner, :string do
      allow_nil? false
      public? true
      description "GitHub repository owner (user or organization)"
    end

    attribute :name, :string do
      allow_nil? false
      public? true
      description "GitHub repository name"
    end

    attribute :full_name, :string do
      allow_nil? false
      public? true
      description "Full repository name (owner/name)"
    end

    attribute :webhook_secret, :string do
      allow_nil? false
      default @webhook_secret_placeholder
      sensitive? true
      description "Placeholder marker; webhook secrets are stored via encrypted SecretRef entries"
    end

    attribute :webhook_id, :integer do
      allow_nil? true
      public? true
      description "GitHub webhook ID (if auto-configured)"
    end

    attribute :enabled, :boolean do
      allow_nil? false
      default true
      public? true
      description "Whether webhook processing is enabled for this repo"
    end

    attribute :settings, :map do
      allow_nil? true
      default %{}
      public? true
      description "Repository-specific settings (auto_label, auto_comment, etc.)"
    end

    attribute :github_app_installation_id, :integer do
      allow_nil? true
      public? true
      description "GitHub App installation ID (if using GitHub App auth)"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, JidoCode.Accounts.User do
      allow_nil? true
      public? true
      description "User who owns this watched repository"
    end

    has_many :webhook_deliveries, JidoCode.GitHub.WebhookDelivery do
      destination_attribute :repo_id
    end

    has_many :issue_analyses, JidoCode.GitHub.IssueAnalysis do
      destination_attribute :repo_id
    end
  end

  identities do
    identity :unique_full_name, [:full_name]
  end

  defp assign_full_name(changeset) do
    owner = Ash.Changeset.get_attribute(changeset, :owner)
    name = Ash.Changeset.get_attribute(changeset, :name)

    if owner && name do
      Ash.Changeset.force_change_attribute(changeset, :full_name, "#{owner}/#{name}")
    else
      changeset
    end
  end

  defp reject_plaintext_secret_persistence(changeset) do
    if plaintext_webhook_secret_input?(changeset) do
      emit_plaintext_secret_audit(changeset)

      Ash.Changeset.add_error(
        changeset,
        field: :webhook_secret,
        message: "plaintext webhook secret persistence is forbidden",
        type: @plaintext_secret_error_type,
        error_type: @plaintext_secret_error_type,
        policy: @plaintext_secret_policy,
        remediation: String.trim(@plaintext_secret_remediation)
      )
    else
      changeset
    end
  end

  defp plaintext_webhook_secret_input?(changeset) do
    params = changeset.params || %{}
    Map.has_key?(params, :webhook_secret) or Map.has_key?(params, "webhook_secret")
  end

  defp emit_plaintext_secret_audit(changeset) do
    actor = actor_from_changeset(changeset)
    actor_id = actor_identifier(actor, :id)
    actor_email = actor_identifier(actor, :email)
    action_name = changeset.action && changeset.action.name

    Logger.warning(
      "security_audit=blocked_plaintext_secret_persistence resource=github_repo field=webhook_secret action=#{action_name} actor_id=#{actor_id} actor_email=#{actor_email}"
    )
  end

  defp actor_from_changeset(changeset) do
    context = changeset.context || %{}

    case context do
      %{private: %{actor: actor}} when not is_nil(actor) ->
        actor

      _other ->
        Map.get(context, :actor)
    end
  end

  defp actor_identifier(%{} = actor, field) do
    actor
    |> Map.get(field)
    |> normalize_actor_identifier()
  end

  defp actor_identifier(_actor, _field), do: "unknown"

  defp normalize_actor_identifier(nil), do: "unknown"

  defp normalize_actor_identifier(value) when is_binary(value) do
    case String.trim(value) do
      "" -> "unknown"
      normalized_value -> normalized_value
    end
  end

  defp normalize_actor_identifier(value), do: to_string(value)
end
