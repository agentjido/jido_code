defmodule JidoCode.ControlPlane.Store.Request do
  @moduledoc """
  Common request shape accepted by control-plane store implementations.
  """

  alias JidoCode.ControlPlane.Store.{ActorContext, AuthorizationContext}

  defstruct [
    :operation,
    :record_type,
    :subject_iri,
    :record,
    :identity,
    :expected_updated_at,
    :query,
    :event,
    :correlation_id,
    :store,
    actor: ActorContext.system(),
    authorization: AuthorizationContext.allow(),
    metadata: %{}
  ]

  @type operation :: :create | :update | :upsert | :delete | :get | :list | :append_event | :query

  @type t :: %__MODULE__{
          operation: operation() | nil,
          record_type: atom() | nil,
          subject_iri: String.t() | nil,
          record: map() | nil,
          identity: map() | nil,
          expected_updated_at: term(),
          query: map() | nil,
          event: map() | nil,
          correlation_id: String.t() | nil,
          store: GenServer.server() | nil,
          actor: ActorContext.t(),
          authorization: AuthorizationContext.t(),
          metadata: map()
        }

  @spec new(keyword() | map()) :: t()
  def new(attrs \\ []) do
    attrs = attrs_map(attrs)

    struct(__MODULE__, attrs)
  end

  @spec put_operation(t(), operation()) :: t()
  def put_operation(%__MODULE__{} = request, operation), do: %{request | operation: operation}

  defp attrs_map(attrs) when is_list(attrs), do: Map.new(attrs)
  defp attrs_map(attrs) when is_map(attrs), do: attrs
end
