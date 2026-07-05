defmodule JidoCode.ControlPlane.Policy do
  @moduledoc """
  Explicit authorization guards for control-plane store requests.
  """

  alias JidoCode.ControlPlane.Store.{ActorContext, AuthorizationContext}
  alias JidoCode.ControlPlane.Validation

  @read_operations [:get, :list, :query]
  @mutate_operations [:create, :update, :upsert, :delete, :append_event]

  @spec system_actor(String.t(), map()) :: ActorContext.t()
  def system_actor(id \\ "system:control-plane", metadata \\ %{}), do: ActorContext.system(id, metadata)

  @spec human_operator(String.t(), [atom()], map()) :: ActorContext.t()
  def human_operator(id, roles \\ [], metadata \\ %{}), do: ActorContext.human_operator(id, roles, metadata)

  @spec machine_actor(String.t(), [atom()], map()) :: ActorContext.t()
  def machine_actor(id, roles \\ [], metadata \\ %{}), do: ActorContext.machine_actor(id, roles, metadata)

  @spec setup_bootstrap(String.t(), map()) :: ActorContext.t()
  def setup_bootstrap(id \\ "setup:bootstrap", metadata \\ %{}), do: ActorContext.setup_bootstrap(id, metadata)

  @spec authorize(atom(), atom(), ActorContext.t(), keyword()) :: AuthorizationContext.t()
  def authorize(operation, record_type, %ActorContext{} = actor, opts \\ []) do
    family = family_for(record_type)
    decision = authorize_decision(operation, family, actor, opts)
    metadata = audit_metadata(operation, record_type, family, actor, decision)

    case decision do
      :allow ->
        AuthorizationContext.allow(mode_for(actor), scopes_for(operation, family), metadata)

      {:deny, reason} ->
        AuthorizationContext.deny(mode_for(actor), reason, metadata)
    end
  end

  @spec authorize_read(atom(), ActorContext.t(), keyword()) :: AuthorizationContext.t()
  def authorize_read(record_type, actor, opts \\ []), do: authorize(:get, record_type, actor, opts)

  @spec authorize_mutation(atom(), atom(), ActorContext.t(), keyword()) :: AuthorizationContext.t()
  def authorize_mutation(operation, record_type, actor, opts \\ []) when operation in @mutate_operations do
    authorize(operation, record_type, actor, opts)
  end

  defp authorize_decision(_operation, _family, %{type: :system}, _opts), do: :allow

  defp authorize_decision(operation, family, %{type: :human, roles: roles}, _opts) do
    cond do
      :admin in roles ->
        :allow

      operation in @read_operations and (:operator in roles or :viewer in roles) ->
        :allow

      operation in @mutate_operations and :operator in roles and family in [:control, :operations, :governance] ->
        :allow

      true ->
        {:deny, :missing_human_operator_scope}
    end
  end

  defp authorize_decision(:append_event, _family, %{type: :machine, roles: roles}, _opts) do
    if :event_writer in roles or :automation in roles, do: :allow, else: {:deny, :missing_machine_event_scope}
  end

  defp authorize_decision(operation, _family, %{type: :machine, roles: roles}, _opts)
       when operation in @read_operations do
    if :reader in roles or :automation in roles, do: :allow, else: {:deny, :missing_machine_read_scope}
  end

  defp authorize_decision(operation, family, %{type: :setup}, _opts) do
    if operation in @mutate_operations and family in [:setup, :auth, :security] do
      :allow
    else
      {:deny, :setup_scope_limited}
    end
  end

  defp authorize_decision(_operation, _family, _actor, _opts), do: {:deny, :unsupported_actor}

  defp family_for(record_type) do
    case Validation.record_family(record_type) do
      {:ok, family} -> family
      {:error, _reason} -> :unknown
    end
  end

  defp mode_for(%{type: :human}), do: :human_operator
  defp mode_for(%{type: :machine}), do: :machine_actor
  defp mode_for(%{type: :setup}), do: :setup_bootstrap
  defp mode_for(%{type: :system}), do: :system

  defp scopes_for(operation, family), do: ["control_plane:#{operation}", "family:#{family}"]

  defp audit_metadata(operation, record_type, family, actor, decision) do
    %{
      audit: %{
        operation: operation,
        record_type: record_type,
        family: family,
        actor_id: actor.id,
        actor_type: actor.type,
        decision: audit_decision(decision),
        decided_at: DateTime.utc_now()
      }
    }
  end

  defp audit_decision(:allow), do: :allow
  defp audit_decision({:deny, reason}), do: {:deny, reason}
end
