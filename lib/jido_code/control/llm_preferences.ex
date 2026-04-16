defmodule JidoCode.Control.LLMPreferences do
  @moduledoc """
  Per-repository LLM provider and model preferences.

  Each managed repository can configure:
  - Which providers are enabled (subset of application-available)
  - Default provider and model for conversations
  - Required model capabilities
  - Maximum context length
  - Whether custom models are allowed
  """

  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Control,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Control.Checks.ActorClassIn

  postgres do
    table "llm_preferences"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :update
    define :destroy
    define :for_managed_repo, action: :for_managed_repo, args: [:managed_repo_id]
    define :get_by_managed_repo, action: :read, get_by: [:managed_repo_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :managed_repo_id,
        :enabled_providers,
        :default_provider,
        :default_model,
        :require_capabilities,
        :max_context_length,
        :allow_custom_models
      ]
    end

    update :update do
      primary? true
      require_atomic? false

      accept [
        :enabled_providers,
        :default_provider,
        :default_model,
        :require_capabilities,
        :max_context_length,
        :allow_custom_models
      ]
    end

    read :for_managed_repo do
      argument :managed_repo_id, :string do
        allow_nil? false
      end

      filter expr(managed_repo_id == ^arg(:managed_repo_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :managed_repo_id, :uuid do
      allow_nil? false
    end

    attribute :enabled_providers, {:array, :atom} do
      default [:anthropic]
    end

    attribute :default_provider, :atom do
      default :anthropic
    end

    attribute :default_model, :string do
      default "claude-3-5-sonnet-20250929"
    end

    attribute :require_capabilities, :map do
      default %{}
    end

    attribute :max_context_length, :integer

    attribute :allow_custom_models, :boolean do
      default true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :managed_repo, JidoCode.Control.ManagedRepo do
      allow_nil? false
      attribute_writable? true
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {ActorClassIn,
                    classes: [:admin, :operator, :factory_system, :managed_repo_orchestrator, :run_worker]}
    end

    policy action_type(:create) do
      authorize_if {ActorClassIn,
                    classes: [:admin, :operator, :factory_system, :managed_repo_orchestrator]}
    end

    policy action_type(:update) do
      authorize_if {ActorClassIn,
                    classes: [:admin, :operator, :factory_system, :managed_repo_orchestrator]}
    end

    policy action_type(:destroy) do
      authorize_if {ActorClassIn,
                    classes: [:admin, :factory_system, :managed_repo_orchestrator]}
    end
  end

  # validations will be added in a follow-up
  # validations do
  #   validate {JidoCode.Control.LLMPreferences.Validation, :providers_subset_of_available}
  #   validate {JidoCode.Control.LLMPreferences.Validation, :default_provider_in_enabled}
  #   validate {JidoCode.Control.LLMPreferences.Validation, :default_model_exists_for_provider}
  # end
end
