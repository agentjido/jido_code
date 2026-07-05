defmodule JidoCode.ControlPlane.ProductStore do
  @moduledoc """
  Product-facing helpers for dispatching control-plane store requests.

  Domain services use this boundary instead of naming the embedded store
  adapter directly, which keeps tests free to supply a fake store or a
  supervised temporary store process.
  """

  alias JidoCode.ControlPlane.{EmbeddedStore, Policy, Store, StoreServer}
  alias JidoCode.ControlPlane.Store.ActorContext
  alias JidoCode.ControlPlane.Store.Request

  @read_operations [:get, :list, :query]
  @mutate_operations [:create, :update, :upsert, :delete, :append_event]

  @type dispatch_opts :: [
          implementation: module(),
          store: GenServer.server(),
          actor: JidoCode.ControlPlane.Store.ActorContext.t(),
          authorization: JidoCode.ControlPlane.Store.AuthorizationContext.t(),
          subject_iri: String.t(),
          record: map(),
          identity: map(),
          expected_updated_at: term(),
          query: map(),
          event: map(),
          correlation_id: String.t(),
          metadata: map()
        ]

  @spec dispatch(Store.Request.operation(), atom(), dispatch_opts()) :: Store.result()
  def dispatch(operation, record_type, opts \\ [])
      when operation in @read_operations or operation in @mutate_operations do
    request =
      opts
      |> request_attrs(operation, record_type)
      |> Request.new()

    Store.dispatch(implementation(opts), operation, request)
  end

  @spec implementation(keyword()) :: module()
  def implementation(opts \\ []) do
    Keyword.get(opts, :implementation) ||
      Application.get_env(:jido_code, :control_plane_product_store, EmbeddedStore)
  end

  @spec store(keyword()) :: GenServer.server()
  def store(opts \\ []) do
    Keyword.get(opts, :store) ||
      Keyword.get(opts, :server) ||
      configured_store()
  end

  defp configured_store do
    configured = Application.get_env(:jido_code, :control_plane_product_store_server, StoreServer)

    cond do
      configured == StoreServer -> StoreServer
      live_server?(configured) -> configured
      true -> StoreServer
    end
  end

  defp live_server?(server) do
    case GenServer.whereis(server) do
      pid when is_pid(pid) -> Process.alive?(pid)
      _not_found -> false
    end
  rescue
    ArgumentError -> false
  end

  defp request_attrs(opts, operation, record_type) do
    actor = store_actor(Keyword.get(opts, :actor))

    attrs =
      opts
      |> Keyword.take([
        :subject_iri,
        :record,
        :identity,
        :expected_updated_at,
        :query,
        :event,
        :correlation_id,
        :metadata
      ])
      |> Keyword.put(:record_type, record_type)
      |> Keyword.put(:store, store(opts))
      |> Keyword.put(:actor, actor)

    Keyword.put(attrs, :authorization, authorization(opts, operation, record_type, actor))
  end

  defp authorization(opts, operation, record_type, actor) do
    Keyword.get(opts, :authorization) || default_authorization(operation, record_type, actor)
  end

  defp default_authorization(operation, record_type, actor) when operation in @read_operations do
    Policy.authorize_read(record_type, actor)
  end

  defp default_authorization(operation, record_type, actor) when operation in @mutate_operations do
    Policy.authorize_mutation(operation, record_type, actor)
  end

  defp store_actor(%ActorContext{} = actor), do: actor
  defp store_actor(nil), do: Policy.system_actor("system:product-store")

  defp store_actor(actor) when is_map(actor) do
    Policy.system_actor("system:legacy-product-store", %{
      legacy_actor_id: Map.get(actor, :id) || Map.get(actor, "id"),
      legacy_actor_class: Map.get(actor, :actor_class) || Map.get(actor, "actor_class"),
      legacy_actor_email: Map.get(actor, :email) || Map.get(actor, "email")
    })
  end

  defp store_actor(_actor), do: Policy.system_actor("system:product-store")
end
