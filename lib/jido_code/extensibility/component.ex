defmodule JidoCode.Extensibility.Component do
  @moduledoc """
  Behavior for extensibility components.

  Defines the lifecycle contract for extensibility components that can be
  configured and loaded through the JidoCode extensibility system.

  ## Components

  This behavior is implemented by:
  - `JidoCode.Extensibility.ChannelConfig` (Phase 1)
  - `JidoCode.Extensibility.Permissions` (Phase 1)
  - `JidoCode.Extensibility.Hooks` (Phase 3 - future)
  - `JidoCode.Extensibility.Agents` (Phase 6 - future)
  - `JidoCode.Extensibility.Plugins` (Phase 5 - future)

  ## Example

      defmodule MyExtension do
        @behaviour JidoCode.Extensibility.Component

        @impl true
        def defaults, do: %{enabled: true}

        @impl true
        def validate(config) do
          if is_map(config) do
            {:ok, config}
          else
            {:error, %JidoCode.Extensibility.Error{code: :validation_failed, message: "config must be a map"}}
          end
        end

        @impl true
        def from_settings(%JidoCode.Settings{my_extension: config}), do: config
        def from_settings(_), do: defaults()
      end

  """

  alias JidoCode.Extensibility.Error
  alias JidoCode.Settings

  @doc """
  Returns default configuration for this component.

  This callback is optional. If not implemented, an empty map is returned.

  ## Returns

  - `map()` - Default configuration map

  """
  @callback defaults() :: map()

  @doc """
  Validates configuration for this component.

  Should return `{:ok, validated}` or `{:error, reason}`.
  The reason can be a string or a `%JidoCode.Extensibility.Error{}` struct.

  ## Parameters

  - `config` - Configuration map to validate

  ## Returns

  - `{:ok, map()}` - Valid configuration
  - `{:error, String.t() | Error.t()}` - Validation failed

  """
  @callback validate(map()) :: {:ok, map()} | {:error, String.t() | Error.t()}

  @doc """
  Extracts this component's configuration from settings.

  ## Parameters

  - `settings` - JidoCode.Settings struct

  ## Returns

  - `map() | nil` - Component configuration or nil if not present

  """
  @callback from_settings(Settings.t()) :: map() | nil

  @optional_callbacks [defaults: 0, validate: 1, from_settings: 1]
end
