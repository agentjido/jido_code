# Phase 56 - Multi-Provider LLM Support

This phase implements multi-provider LLM support by exposing all ReqLLM providers (18+) and their available models through a hierarchical configuration system operating at application, repository, and conversation levels.

<!-- covers: architecture.llm.multi_provider_support.implementation -->
<!-- covers: architecture.llm.multi_provider_llm_support.discovery -->
<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/llm_provider_configuration.spec.md`
- `../specs/llm_model_selection.spec.md`
- `../decisions/jido_code.multi_provider_llm_support.md`
- `lib/jido_code/security/secret_refs.ex`
- `req_llm` (Hex package)
- `llm_db` (Hex package)

## Relevant Assumptions / Defaults
- ReqLLM library is already installed and configured for Anthropic and OpenAI
- Existing SecretRefs system handles API key storage for :anthropic and :openai
- LLMDB catalog contains 665+ models across 18+ providers
- Ash framework is available for governed resources

[ ] 56 Phase 56 - Multi-Provider LLM Support
  Expose all ReqLLM providers and their available models through a hierarchical configuration system operating at application, repository, and conversation levels, enabling users to select any provider and model based on their needs.

  [ ] 56.1 Section - Provider and Model Discovery
    Create the discovery layer that exposes all ReqLLM providers and their models from LLMDB at runtime without hardcoding any provider-specific logic.

    [ ] 56.1.1 Task - Create LLM.Discovery module
      Build a new module to interface with ReqLLM and LLMDB for provider and model discovery.

      [ ] 56.1.1.1 Subtask - Create lib/jido_code/llm/discovery.ex with module definition and @moduledoc
      [ ] 56.1.1.2 Subtask - Define @type provider :: atom() for provider identifiers
      [ ] 56.1.1.3 Subtask - Define @type provider_info map with id, name, description, env_key, and base_url fields
      [ ] 56.1.1.4 Subtask - Add @spec list_providers() :: [provider_info()] function
      [ ] 56.1.1.5 Subtask - Implement list_providers/0 by calling ReqLLM.Providers.list/0
      [ ] 56.1.1.6 Subtask - Implement provider_info/1 that fetches metadata from ReqLLM.Providers.get!/1
      [ ] 56.1.1.7 Subtask - Implement list_models/1 that calls LLMDB.models/1 for a given provider
      [ ] 56.1.1.8 Subtask - Implement model_info/2 that calls LLMDB.model/2 for provider and model ID
      [ ] 56.1.1.9 Subtask - Add helper function provider_name/1 for human-readable provider names
      [ ] 56.1.1.10 Subtask - Add helper function provider_description/1 for provider descriptions
      [ ] 56.1.1.11 Subtask - Add helper function provider_base_url/1 for custom base URL support

    [ ] 56.1.2 Task - Create discovery tests
      Verify the discovery module correctly interfaces with ReqLLM and LLMDB.

      [ ] 56.1.2.1 Subtask - Create test/jido_code/llm/discovery_test.exs
      [ ] 56.1.2.2 Subtask - Add test proving list_providers/0 returns at least 18 providers
      [ ] 56.1.2.3 Subtask - Add test proving :anthropic is in the provider list
      [ ] 56.1.2.4 Subtask - Add test proving :openai is in the provider list
      [ ] 56.1.2.5 Subtask - Add test proving provider_info/1 returns expected metadata structure
      [ ] 56.1.2.6 Subtask - Add test proving provider_info/1 includes correct env_key for :anthropic
      [ ] 56.1.2.7 Subtask - Add test proving list_models/1 returns non-empty list for :anthropic
      [ ] 56.1.2.8 Subtask - Add test proving list_models/1 returns LLMDB.Model structs
      [ ] 56.1.2.9 Subtask - Add test proving model_info/2 returns {:ok, LLMDB.Model.t()} or :error

  [ ] 56.2 Section - Credential Management Extension
    Extend the existing SecretRefs system to support all ReqLLM providers while maintaining backward compatibility with existing :anthropic and :openai usage.

    [ ] 56.2.1 Task - Update SecretRefs provider type
      Remove the constrained provider type to allow any atom provider.

      [ ] 56.2.1.1 Subtask - Change @type provider from :anthropic | :openai to atom()
      [ ] 56.2.1.2 Subtask - Verify existing @provider_rotation_options still works with constrained list
      [ ] 56.2.1.3 Subtask - Update module documentation to reflect dynamic provider support

    [ ] 56.2.2 Task - Add dynamic provider env key resolution
      Implement provider_env_key/1 to delegate to ReqLLM for automatic discovery.

      [ ] 56.2.2.1 Subtask - Implement provider_env_key/1 to call ReqLLM.Providers.get_env_key/1
      [ ] 56.2.2.2 Subtask - Add fallback to :"#{provider}_api_key" for unknown providers
      [ ] 56.2.2.3 Subtask - Maintain existing :anthropic and :openai behavior as special cases
      [ ] 56.2.2.4 Subtask - Add provider_secret_ref_name/1 to build secret reference paths

    [ ] 56.2.3 Task - Extend credential validation
      Add validation methods for additional provider credential formats.

      [ ] 56.2.3.1 Subtask - Implement valid_anthropic_key/1 if not already present
      [ ] 56.2.3.2 Subtask - Implement valid_openai_key/1 if not already present
      [ ] 56.2.3.3 Subtask - Add valid_google_key/1 for Google API key validation
      [ ] 56.2.3.4 Subtask - Add valid_groq_key/1 for Groq API key validation
      [ ] 56.2.3.5 Subtask - Add valid_generic_key/1 for fallback provider validation
      [ ] 56.2.3.6 Subtask - Implement valid_provider_credential_value?/2 dispatch function

    [ ] 56.2.4 Task - Update SecretRefs tests
      Extend test coverage for the new dynamic provider support.

      [ ] 56.2.4.1 Subtask - Add test proving provider_env_key/1 returns correct key for :anthropic
      [ ] 56.2.4.2 Subtask - Add test proving provider_env_key/1 returns correct key for :openai
      [ ] 56.2.4.3 Subtask - Add test proving provider_env_key/1 falls back for unknown providers
      [ ] 56.2.4.4 Subtask - Add test proving valid_provider_credential_value?/2 works for all known providers
      [ ] 56.2.4.5 Subtask - Add test proving backward compatibility with existing provider type usage

  [ ] 56.3 Section - Configuration Storage
    Create the hierarchical configuration storage system for application, repository, and conversation level settings.

    [ ] 56.3.1 Task - Add application-level configuration
      Define application configuration structure for LLM providers.

      [ ] 56.3.1.1 Subtask - Add :llm configuration to config/dev.exs
      [ ] 56.3.1.2 Subtask - Add available_providers: :all or explicit list option
      [ ] 56.3.1.3 Subtask - Add default_provider: :anthropic option
      [ ] 56.3.1.4 Subtask - Add default_model: "claude-3-5-sonnet-20250929" option
      [ ] 56.3.1.5 Subtask - Add default_capabilities map with chat, tools, streaming flags
      [ ] 56.3.1.6 Subtask - Add :feature_multi_provider_llm feature flag to config/dev.exs
      [ ] 56.3.1.7 Subtask - Add similar configuration to config/prod.exs with feature flag defaulting to false

    [ ] 56.3.2 Task - Create LLMPreferences Ash resource
      Build a governed resource for per-repository LLM preferences.

      [ ] 56.3.2.1 Subtask - Create lib/jido_code/control/llm_preferences.ex
      [ ] 56.3.2.2 Subtask - Add uuid_primary_key :id
      [ ] 56.3.2.3 Subtask - Add belongs_to :managed_repo relationship
      [ ] 56.3.2.4 Subtask - Add attribute :enabled_providers as {:array, :atom} with default [:anthropic]
      [ ] 56.3.2.5 Subtask - Add attribute :default_provider as :atom with default :anthropic
      [ ] 56.3.2.6 Subtask - Add attribute :default_model as :string with default model ID
      [ ] 56.3.2.7 Subtask - Add attribute :require_capabilities as :map with default %{}
      [ ] 56.3.2.8 Subtask - Add attribute :max_context_length as optional :integer
      [ ] 56.3.2.9 Subtask - Add attribute :allow_custom_models as :boolean with default true
      [ ] 56.3.2.10 Subtask - Add timestamps (inserted_at, updated_at)
      [ ] 56.3.2.11 Subtask - Create unique index on managed_repo_id
      [ ] 56.3.2.12 Subtask - Define read action :for_managed_repo with managed_repo_id argument

    [ ] 56.3.3 Task - Create database migration for LLMPreferences
      Generate and implement the migration for the llm_preferences table.

      [ ] 56.3.3.1 Subtask - Run mix ecto.gen.migration add_llm_preferences
      [ ] 56.3.3.2 Subtask - Create llm_preferences table with uuid primary key
      [ ] 56.3.3.3 Subtask - Add managed_repo_id uuid column with null: false
      [ ] 56.3.3.4 Subtask - Add enabled_providers column as {:array, :text} with default ["anthropic"]
      [ ] 56.3.3.5 Subtask - Add default_provider column as :text with default "anthropic"
      [ ] 56.3.3.6 Subtask - Add default_model column as :text with default model ID
      [ ] 56.3.3.7 Subtask - Add require_capabilities column as :map with default "{}"
      [ ] 56.3.3.8 Subtask - Add max_context_length column as optional :integer
      [ ] 56.3.3.9 Subtask - Add allow_custom_models column as :boolean with default true
      [ ] 56.3.3.10 Subtask - Add timestamps column
      [ ] 56.3.3.11 Subtask - Create unique index on managed_repo_id
      [ ] 56.3.3.12 Subtask - Run migration and verify table creation

    [ ] 56.3.4 Task - Define conversation-level metadata schema
      Document the metadata structure for conversation-level LLM configuration.

      [ ] 56.3.4.1 Subtask - Define "llm_provider" key as string provider identifier
      [ ] 56.3.4.2 Subtask - Define "llm_model" key as string model identifier
      [ ] 56.3.4.3 Subtask - Define "llm_capabilities" key as map of capability flags
      [ ] 56.3.4.4 Subtask - Document where metadata is stored (WorkItem or Conversation)

    [ ] 56.3.5 Task - Create LLMPreferences tests
      Add test coverage for the LLMPreferences resource.

      [ ] 56.3.5.1 Subtask - Create test/jido_code/control/llm_preferences_test.exs
      [ ] 56.3.5.2 Subtask - Add test proving creation of LLMPreferences with valid attributes
      [ ] 56.3.5.3 Subtask - Add test proving enabled_providers defaults to [:anthropic]
      [ ] 56.3.5.4 Subtask - Add test proving default_provider defaults to :anthropic
      [ ] 56.3.5.5 Subtask - Add test proving for_managed_repo action returns preferences for a repo
      [ ] 56.3.5.6 Subtask - Add test proving unique constraint on managed_repo_id

  [ ] 56.4 Section - Model Selection API
    Create the selection module that resolves model selection across the hierarchical configuration levels with validation.

    [ ] 56.4.1 Task - Create LLM.Selection module
      Build the core selection and resolution logic for hierarchical model selection.

      [ ] 56.4.1.1 Subtask - Create lib/jido_code/llm/selection.ex with module definition
      [ ] 56.4.1.2 Subtask - Define @type selection_result with provider, model, llmdb_model, source, and capabilities
      [ ] 56.4.1.3 Subtask - Define @spec resolve/3 with conversation_opts, repo_id, and app_opts parameters
      [ ] 56.4.1.4 Subtask - Implement resolve/3 with ordered fallback logic (conversation -> repo -> application)
      [ ] 56.4.1.5 Subtask - Implement resolve_provider/3 to extract provider from conversation opts
      [ ] 56.4.1.6 Subtask - Implement resolve_model/4 to extract model from opts and validate
      [ ] 56.4.1.7 Subtask - Implement validate_provider_enabled/2 to check provider is enabled
      [ ] 56.4.1.8 Subtask - Implement fetch_model_metadata/2 to get LLMDB model info
      [ ] 56.4.1.9 Subtask - Implement validate_capabilities/3 to check model capabilities
      [ ] 56.4.1.10 Subtask - Implement determine_source/2 to track which level provided the selection
      [ ] 56.4.1.11 Subtask - Define @spec available_models/2 with repo_id and capabilities parameters
      [ ] 56.4.1.12 Subtask - Implement available_models/2 returning filtered list of models
      [ ] 56.4.1.13 Subtask - Implement enabled_providers_for_repo/1 helper
      [ ] 56.4.1.14 Subtask - Implement get_repo_preferences/1 to fetch LLMPreferences
      [ ] 56.4.1.15 Subtask - Implement has_capabilities?/2 for model capability filtering
      [ ] 56.4.1.16 Subtask - Implement model_label/2 for display names

    [ ] 56.4.2 Task - Create Selection validation helpers
      Build validation functions for provider, model, and capability checks.

      [ ] 56.4.2.1 Subtask - Implement validate_provider_in_available/2
      [ ] 56.4.2.2 Subtask - Implement validate_model_exists_for_provider/2
      [ ] 56.4.2.3 Subtask - Implement validate_capabilities_met/2
      [ ] 56.4.2.4 Subtask - Implement format_error/1 for user-friendly error messages

    [ ] 56.4.3 Task - Create Selection tests
      Add comprehensive test coverage for the selection logic.

      [ ] 56.4.3.1 Subtask - Create test/jido_code/llm/selection_test.exs
      [ ] 56.4.3.2 Subtask - Add test proving resolve/3 uses conversation-level provider when specified
      [ ] 56.4.3.3 Subtask - Add test proving resolve/3 falls back to repository prefs when no conversation opts
      [ ] 56.4.3.4 Subtask - Add test proving resolve/3 falls back to application defaults when no prefs exist
      [ ] 56.4.3.5 Subtask - Add test proving resolve/3 returns {:error, :provider_not_enabled} for disabled provider
      [ ] 56.4.3.6 Subtask - Add test proving resolve/3 returns {:error, :model_not_found} for invalid model
      [ ] 56.4.3.7 Subtask - Add test proving resolve/3 validates capabilities
      [ ] 56.4.3.8 Subtask - Add test proving available_models/2 filters by capabilities
      [ ] 56.4.3.9 Subtask - Add test proving available_models/2 filters by enabled providers
      [ ] 56.4.3.10 Subtask - Add test proving selection result includes correct source level
      [ ] 56.4.3.11 Subtask - Add test proving String.to_existing_atom safely handles provider strings

  [ ] 56.5 Section - UI Components
    Create the user interface components for configuring providers and selecting models at all levels.

    [ ] 56.5.1 Task - Create LLM Settings LiveView
      Build the application-level LLM configuration page.

      [ ] 56.5.1.1 Subtask - Create lib/jido_code_web/live/llm_settings_live.ex
      [ ] 56.5.1.2 Subtask - Define mount/3 with assign_providers, assign_credentials, assign_application_defaults
      [ ] 56.5.1.3 Subtask - Create render/1 with header, provider list, defaults, and test connection sections
      [ ] 56.5.1.4 Subtask - Implement handle_event for "save_credential" to store API keys
      [ ] 56.5.1.5 Subtask - Implement handle_event for "test_provider" to test connectivity
      [ ] 56.5.1.6 Subtask - Implement handle_info for async test results
      [ ] 56.5.1.7 Subtask - Add route /settings/llm to router

    [ ] 56.5.2 Task - Create LLMProvidersComponent
      Build the provider list and card component for settings display.

      [ ] 56.5.2.1 Subtask - Create lib/jido_code_web/components/llm_providers.ex
      [ ] 56.5.2.2 Subtask - Define provider_list/1 function with providers and credentials assigns
      [ ] 56.5.2.3 Subtask - Define provider_card/1 function for individual provider display
      [ ] 56.5.2.4 Subtask - Define credential_status/1 for showing configured state
      [ ] 56.5.2.5 Subtask - Define description/1 for provider info display
      [ ] 56.5.2.6 Subtask - Define capability_badges/1 for showing provider capabilities
      [ ] 56.5.2.7 Subtask - Define credential_form/1 for API key input
      [ ] 56.5.2.8 Subtask - Define test_button/1 for connection testing

    [ ] 56.5.3 Task - Create ModelSelector component
      Build the dynamic model selector with provider grouping and filtering.

      [ ] 56.5.3.1 Subtask - Create lib/jido_code_web/components/model_selector.ex
      [ ] 56.5.3.2 Subtask - Define model_selector/1 with id, name, selected_provider, selected_model, repo_id, capabilities
      [ ] 56.5.3.3 Subtask - Define provider_filter/1 for provider tab buttons
      [ ] 56.5.3.4 Subtask - Define model_list/1 for listing filtered models
      [ ] 56.5.3.5 Subtask - Define model_option/1 for individual model selection
      [ ] 56.5.3.6 Subtask - Define model_badges/1 for capability indicators
      [ ] 56.5.3.7 Subtask - Add JavaScript hook for ModelSelector interactivity

    [ ] 56.5.4 Task - Create ModelPicker component
      Build the compact model picker for conversation composer.

      [ ] 56.5.4.1 Subtask - Create lib/jido_code_web/components/model_picker.ex
      [ ] 56.5.4.2 Subtask - Define model_picker/1 with repo_id, selected, available_models
      [ ] 56.5.4.3 Subtask - Define model_icon/1 for provider icon display
      [ ] 56.5.4.4 Subtask - Define model_popover/1 for dropdown model list
      [ ] 56.5.4.5 Subtask - Add JavaScript hook for ModelPicker interactivity

    [ ] 56.5.5 Task - Integrate LLM preferences into ManagedRepoDetailLive
      Add LLM configuration section to repository detail page.

      [ ] 56.5.5.1 Subtask - Add assign_llm_preferences/1 to ManagedRepoDetailLive
      [ ] 56.5.5.2 Subtask - Add llm_preferences section to render/1
      [ ] 56.5.5.3 Subtask - Implement handle_event for "toggle_provider"
      [ ] 56.5.5.4 Subtask - Implement handle_event for "model_selected"
      [ ] 56.5.5.5 Subtask - Implement handle_event for "toggle_capability"
      [ ] 56.5.5.6 Subtask - Add LLMPreferencesForm component

    [ ] 56.5.6 Task - Create LLM error handling components
      Build error message components for LLM-related failures.

      [ ] 56.5.6.1 Subtask - Create lib/jido_code_web/live/llm_model_errors.ex
      [ ] 56.5.6.2 Subtask - Implement error_message(:provider_not_enabled)
      [ ] 56.5.6.3 Subtask - Implement error_message(:model_not_found)
      [ ] 56.5.6.4 Subtask - Implement error_message(:missing_capability, capability)
      [ ] 56.5.6.5 Subtask - Implement error_message(:credential_missing, provider)
      [ ] 56.5.6.6 Subtask - Add format_error/1 helper for consistent error formatting

    [ ] 56.5.7 Task - Create UI styles for LLM components
      Add CSS/SCSS styles for LLM selector components.

      [ ] 56.5.7.1 Subtask - Create assets/css/llm_selector.scss
      [ ] 56.5.7.2 Subtask - Add .model-selector styles
      [ ] 56.5.7.3 Subtask - Add .provider-tab styles with active state
      [ ] 56.5.7.4 Subtask - Add .model-option styles with hover and selected states
      [ ] 56.5.7.5 Subtask - Add .badge utility styles for capability indicators
      [ ] 56.5.7.6 Subtask - Add .model-picker styles for compact picker
      [ ] 56.5.7.7 Subtask - Add .provider-icon styles for provider-specific icons

    [ ] 56.5.8 Task - Create UI component tests
      Add test coverage for LLM UI components.

      [ ] 56.5.8.1 Subtask - Create test/jido_code_web/live/llm_settings_live_test.exs
      [ ] 56.5.8.2 Subtask - Add test proving LLMSettingsLive lists all available providers
      [ ] 56.5.8.3 Subtask - Add test proving LLMSettingsLive allows saving API keys
      [ ] 56.5.8.4 Subtask - Add test proving provider cards show credential status
      [ ] 56.5.8.5 Subtask - Create test/jido_code_web/components/model_selector_test.exs
      [ ] 56.5.8.6 Subtask - Add test proving ModelSelector filters by provider
      [ ] 56.5.8.7 Subtask - Add test proving ModelSelector filters by capabilities
      [ ] 56.5.8.8 Subtask - Add test proving ModelSelector shows model badges

  [ ] 56.6 Section - Integration Tests and Verification
    Prove end-to-end functionality of the multi-provider LLM system with proper provider discovery, credential management, hierarchical configuration, model selection, and UI interaction.

    [ ] 56.6.1 Task - Discovery integration scenarios
      Prove provider and model discovery works end-to-end with ReqLLM and LLMDB.

      [ ] 56.6.1.1 Subtask - Add coverage proving list_providers/0 returns all ReqLLM providers at runtime
      [ ] 56.6.1.2 Subtask - Add coverage proving provider_info/1 returns complete metadata for each provider
      [ ] 56.6.1.3 Subtask - Add coverage proving list_models/1 returns all LLMDB models for a provider
      [ ] 56.6.1.4 Subtask - Add coverage proving model_info/2 returns complete model metadata including capabilities

    [ ] 56.6.2 Task - Credential management integration scenarios
      Prove API keys can be stored and retrieved for all provider types.

      [ ] 56.6.2.1 Subtask - Add coverage proving provider_env_key/1 works for all known providers
      [ ] 56.6.2.2 Subtask - Add coverage proving API keys can be stored via SecretRefs for new providers
      [ ] 56.6.2.3 Subtask - Add coverage proving existing :anthropic and :openai usage continues to work
      [ ] 56.6.2.4 Subtask - Add coverage proving credential validation works for all provider types

    [ ] 56.6.3 Task - Configuration resolution scenarios
      Prove hierarchical configuration resolves correctly at all levels.

      [ ] 56.6.3.1 Subtask - Add coverage proving conversation-level config overrides repository config
      [ ] 56.6.3.2 Subtask - Add coverage proving repository-level config overrides application config
      [ ] 56.6.3.3 Subtask - Add coverage proving application defaults are used when no other config exists
      [ ] 56.6.3.4 Subtask - Add coverage proving disabled providers are rejected at selection time
      [ ] 56.6.3.5 Subtask - Add coverage proving models are filtered by enabled providers
      [ ] 56.6.3.6 Subtask - Add coverage proving models are filtered by required capabilities

    [ ] 56.6.4 Task - Model selection API scenarios
      Prove the Selection API correctly resolves and validates models.

      [ ] 56.6.4.1 Subtask - Add coverage proving resolve/3 returns {:ok, selection_result} for valid inputs
      [ ] 56.6.4.2 Subtask - Add coverage proving resolve/3 returns {:error, reason} for invalid providers
      [ ] 56.6.4.3 Subtask - Add coverage proving resolve/3 returns {:error, reason} for invalid models
      [ ] 56.6.4.4 Subtask - Add coverage proving resolve/3 returns {:error, reason} for missing capabilities
      [ ] 56.6.4.5 Subtask - Add coverage proving available_models/2 returns only enabled provider models
      [ ] 56.6.4.6 Subtask - Add coverage proving available_models/2 filters by capabilities

    [ ] 56.6.5 Task - UI integration scenarios
      Prove users can configure providers and select models through the UI.

      [ ] 56.6.5.1 Subtask - Add coverage proving settings page displays all available providers
      [ ] 56.6.5.2 Subtask - Add coverage proving users can save API keys for any provider
      [ ] 56.6.5.3 Subtask - Add coverage proving test connection button validates credentials
      [ ] 56.6.5.4 Subtask - Add coverage proving repository settings allow enabling providers
      [ ] 56.6.5.5 Subtask - Add coverage proving model selector shows models for enabled providers
      [ ] 56.6.5.6 Subtask - Add coverage proving conversation composer allows model selection

    [ ] 56.6.6 Task - End-to-end conversation scenarios
      Prove conversations can use non-default providers end-to-end.

      [ ] 56.6.6.1 Subtask - Add coverage proving conversation with OpenAI provider works end-to-end
      [ ] 56.6.6.2 Subtask - Add coverage proving conversation with Google provider works end-to-end
      [ ] 56.6.6.3 Subtask - Add coverage proving disabled provider is rejected with clear error
      [ ] 56.6.6.4 Subtask - Add coverage proving model without required capabilities is rejected
      [ ] 56.6.6.5 Subtask - Add coverage proving conversation metadata stores selected provider and model

    [ ] 56.6.7 Task - Backward compatibility scenarios
      Prove existing Anthropic and OpenAI usage continues to work without changes.

      [ ] 56.6.7.1 Subtask - Add coverage proving existing conversations continue to work with Anthropic
      [ ] 56.6.7.2 Subtask - Add coverage proving existing conversations continue to work with OpenAI
      [ ] 56.6.7.3 Subtask - Add coverage proving no breaking changes to existing SecretRefs usage
      [ ] 56.6.7.4 Subtask - Add coverage proving feature flag allows gradual rollout
