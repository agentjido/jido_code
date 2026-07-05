defmodule JidoCode.ControlPlane.Store do
  @moduledoc """
  Product-level persistence contract for the control plane.

  Domain services should depend on this behaviour instead of Ash resources,
  Ecto repos, or raw RDF store calls. Implementations receive product-shaped
  requests and return product-shaped outcomes or typed errors.
  """

  alias JidoCode.ControlPlane.Store.{Outcome, Request}

  alias JidoCode.ControlPlane.Store.Errors.{
    ConflictError,
    NotFoundError,
    UnauthorizedError,
    UnavailableError,
    ValidationError
  }

  @type error ::
          ValidationError.t()
          | ConflictError.t()
          | NotFoundError.t()
          | UnavailableError.t()
          | UnauthorizedError.t()

  @type result :: {:ok, Outcome.t()} | {:error, error()}

  @callback create(Request.t()) :: result()
  @callback update(Request.t()) :: result()
  @callback upsert(Request.t()) :: result()
  @callback delete(Request.t()) :: result()
  @callback get(Request.t()) :: result()
  @callback list(Request.t()) :: result()
  @callback append_event(Request.t()) :: result()
  @callback query(Request.t()) :: result()

  @spec dispatch(module(), atom(), Request.t()) :: result()
  def dispatch(implementation, operation, %Request{} = request)
      when operation in [:create, :update, :upsert, :delete, :get, :list, :append_event, :query] do
    if Code.ensure_loaded?(implementation) and function_exported?(implementation, operation, 1) do
      apply(implementation, operation, [Request.put_operation(request, operation)])
    else
      {:error,
       UnavailableError.exception(
         stage: :dispatch,
         reason: {:invalid_store_implementation, implementation, operation}
       )}
    end
  end
end
