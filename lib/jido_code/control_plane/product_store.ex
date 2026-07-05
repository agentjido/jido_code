defmodule JidoCode.ControlPlane.ProductStore do
  @moduledoc """
  Product-facing helpers for dispatching control-plane store requests.

  Domain services use this boundary instead of naming the embedded store
  adapter directly, which keeps tests free to supply a fake store or a
  supervised temporary store process.
  """

  alias JidoCode.ControlPlane.{EmbeddedStore, Policy, Store, StoreServer}
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
      Application.get_env(:jido_code, :control_plane_product_store_server, StoreServer)
  end

  defp request_attrs(opts, operation, record_type) do
    actor = Keyword.get(opts, :actor, Policy.system_actor("system:product-store"))

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
end
