defmodule AgentJido.Forge.Resources.SpriteSpec do
  @moduledoc false
  use Ash.Resource,
    otp_app: :agent_jido,
    domain: AgentJido.Forge.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "forge_sprite_specs"
    repo AgentJido.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :name,
        :description,
        :runner,
        :runner_config,
        :base_image,
        :env,
        :bootstrap_steps,
        :file_injection,
        :timeouts,
        :resource_limits
      ]
    end

    update :update do
      accept [
        :name,
        :description,
        :runner,
        :runner_config,
        :base_image,
        :env,
        :bootstrap_steps,
        :file_injection,
        :timeouts,
        :resource_limits
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true

    attribute :runner, :atom, allow_nil?: false, public?: true

    attribute :runner_config, :map, default: %{}, public?: true

    attribute :base_image, :string, default: "ubuntu-22.04", public?: true

    attribute :env, :map, default: %{}, public?: true

    attribute :bootstrap_steps, {:array, :map}, default: [], public?: true

    attribute :file_injection, {:array, :map}, default: [], public?: true

    attribute :timeouts, :map,
      default: %{
        bootstrap_timeout_ms: 300_000,
        iteration_timeout_ms: 300_000,
        idle_timeout_ms: 1_800_000,
        hard_ttl_ms: 14_400_000
      },
      public?: true

    attribute :resource_limits, :map, default: %{}, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_name, [:name]
  end
end
