defmodule JidoCode.SourceProviders.Adapter do
  @moduledoc """
  Provider-neutral boundary for source control service integrations.
  """

  # covers: source.provider_adapter.behavior_contract

  @type provider :: :github | :gitlab | :bitbucket
  @type credential_resolution ::
          {:ok, String.t(), map()}
          | {:error, atom(), map()}

  @callback provider() :: provider()
  @callback config() :: map()
  @callback path_definitions() :: [map()]
  @callback resolve_service_credential(atom()) :: credential_resolution()
  @callback resolve_api_token(map()) :: String.t() | nil
  @callback list_accessible_repositories(atom(), String.t(), keyword()) ::
              {:ok, [map()]} | {:error, map()}
end
