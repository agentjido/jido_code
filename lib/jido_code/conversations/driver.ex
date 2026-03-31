defmodule JidoCode.Conversations.Driver do
  # covers: architecture.conversation_driver.code_server_routes_through_boundary
  # covers: architecture.conversation_driver.conversation_identity_maps_to_session
  # covers: architecture.conversation_driver.actor_context_propagated
  # covers: coding_assistance.boundary.policy_context_propagation
  @moduledoc """
  Product-local conversation driver for coding-oriented turns.

  The driver resolves managed-repository scope, prepares the `jido_os` session
  boundary through `JidoCode.CodingAssistance`, normalizes the turn into the
  product control loop, and translates public service outcomes back into the
  stable conversation event contract.
  """

  alias JidoCode.CodingAssistance
  alias JidoCode.Control.RepoBridge
  alias JidoCode.Conversations.{EventBridge, Ingress}

  @default_operation "plan"

  @type driver_result ::
          {:ok,
           %{
             context: map(),
             ingress: map(),
             envelope: map(),
             events: [map()]
           }}
          | {:error, term(), map(), map()}

  @spec prepare_conversation(map()) :: {:ok, map()} | {:error, term()}
  def prepare_conversation(%{} = attrs) do
    context = conversation_context(attrs)

    case normalize_optional_string(context.actor_id) do
      nil ->
        {:ok, context}

      actor_id ->
        runtime_attrs = runtime_attrs(context)

        with {:ok, _session} <- coding_assistance_module().ensure_session(context.session_id, actor_id, runtime_attrs),
             {:ok, _session} <- maybe_bind_project(context, actor_id, runtime_attrs) do
          {:ok, context}
        end
    end
  end

  def prepare_conversation(_attrs), do: {:error, :invalid_conversation_context}

  @spec handle_turn(map()) :: driver_result()
  def handle_turn(%{} = attrs) do
    with {:ok, context} <- prepare_conversation(attrs),
         actor_id when is_binary(actor_id) <- normalize_optional_string(context.actor_id) || :missing_actor_id,
         {:ok, ingress_result} <- conversation_ingress_module().record_turn(conversation_turn_attrs(attrs, context)),
         {:ok, envelope} <- coding_assistance_module().assist(actor_id, assist_params(attrs, context, ingress_result)) do
      {:ok,
       %{
         context: context,
         ingress: ingress_result,
         envelope: envelope,
         events: event_bridge_module().success_events(envelope, ingress_result, context)
       }}
    else
      :missing_actor_id ->
        context = conversation_context(attrs)
        {:error, :missing_actor_id, context, event_bridge_module().failure_event(:missing_actor_id, context, attrs)}

      {:error, reason} ->
        context = conversation_context(attrs)
        {:error, reason, context, event_bridge_module().failure_event(reason, context, attrs)}
    end
  end

  def handle_turn(_attrs) do
    context = conversation_context(%{})

    {:error, :invalid_conversation_turn, context,
     event_bridge_module().failure_event(:invalid_conversation_turn, context, %{})}
  end

  defp maybe_bind_project(%{managed_repo_id: managed_repo_id}, actor_id, runtime_attrs)
       when is_binary(managed_repo_id) do
    coding_assistance_module().bind_project(runtime_attrs.session_id, actor_id, managed_repo_id, runtime_attrs)
  end

  defp maybe_bind_project(_context, _actor_id, _runtime_attrs), do: {:ok, %{}}

  defp assist_params(attrs, context, ingress_result) do
    %{
      session_id: context.session_id,
      project_id: context.managed_repo_id || context.project_id,
      request_id: context.request_id,
      correlation_id: context.correlation_id,
      workspace_id: context.workspace_id,
      objective: normalize_optional_string(Map.get(attrs, :content) || Map.get(attrs, "content")),
      operation:
        normalize_optional_string(Map.get(attrs, :operation) || Map.get(attrs, "operation")) || @default_operation,
      prompt_variables: %{
        objective: normalize_optional_string(Map.get(attrs, :content) || Map.get(attrs, "content")),
        managed_repo_id: context.managed_repo_id,
        legacy_project_id: context.project_id,
        work_item_id: ingress_result |> nested_get([:work_item, :id]) |> normalize_optional_string(),
        turn_mode: ingress_result |> Map.get(:turn_mode) |> normalize_optional_string()
      },
      tool_intent: %{
        action_ids: [],
        skill_ids: [],
        work_item_id: ingress_result |> nested_get([:work_item, :id]) |> normalize_optional_string()
      }
    }
    |> compact_nil_values()
  end

  defp conversation_turn_attrs(attrs, context) do
    %{
      actor_id: context.actor_id,
      actor_email: context.actor_email,
      project_id: context.project_id,
      managed_repo_id: context.managed_repo_id,
      conversation_id: context.session_id,
      content: Map.get(attrs, :content) || Map.get(attrs, "content"),
      operation: Map.get(attrs, :operation) || Map.get(attrs, "operation"),
      work_item_id: Map.get(attrs, :work_item_id) || Map.get(attrs, "work_item_id"),
      request_id: context.request_id,
      correlation_id: context.correlation_id,
      workspace_id: context.workspace_id
    }
    |> compact_nil_values()
  end

  defp conversation_context(attrs) do
    project_id =
      normalize_optional_string(Map.get(attrs, :project_id) || Map.get(attrs, "project_id"))

    managed_repo_id =
      case normalize_optional_string(Map.get(attrs, :managed_repo_id) || Map.get(attrs, "managed_repo_id")) do
        nil -> resolve_managed_repo_id(project_id)
        explicit_id -> explicit_id
      end

    session_id =
      normalize_optional_string(Map.get(attrs, :conversation_id) || Map.get(attrs, "conversation_id")) ||
        normalize_optional_string(Map.get(attrs, :session_id) || Map.get(attrs, "session_id"))

    %{
      project_id: project_id,
      managed_repo_id: managed_repo_id,
      session_id: session_id,
      actor_id: normalize_optional_string(Map.get(attrs, :actor_id) || Map.get(attrs, "actor_id")),
      actor_email: normalize_optional_string(Map.get(attrs, :actor_email) || Map.get(attrs, "actor_email")),
      request_id:
        normalize_optional_string(Map.get(attrs, :request_id) || Map.get(attrs, "request_id")) ||
          unique_id("req"),
      correlation_id:
        normalize_optional_string(Map.get(attrs, :correlation_id) || Map.get(attrs, "correlation_id")) ||
          unique_id("corr"),
      workspace_id: normalize_optional_string(Map.get(attrs, :workspace_id) || Map.get(attrs, "workspace_id"))
    }
  end

  defp resolve_managed_repo_id(nil), do: nil

  defp resolve_managed_repo_id(project_id) when is_binary(project_id) do
    case repo_bridge_module().managed_repo_for_project(project_id) do
      {:ok, managed_repo} -> nested_get(managed_repo, [:id]) |> normalize_optional_string()
      _other -> nil
    end
  end

  defp runtime_attrs(context) do
    %{
      session_id: context.session_id,
      project_id: context.managed_repo_id || context.project_id,
      request_id: context.request_id,
      correlation_id: context.correlation_id,
      workspace_id: context.workspace_id
    }
  end

  defp compact_nil_values(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc ->
        acc

      {key, value}, acc when is_map(value) ->
        compacted = compact_nil_values(value)
        if compacted == %{}, do: acc, else: Map.put(acc, key, compacted)

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end

  defp nested_get(value, keys) when is_list(keys) do
    Enum.reduce_while(keys, value, fn key, acc ->
      cond do
        is_map(acc) and Map.has_key?(acc, key) ->
          {:cont, Map.get(acc, key)}

        is_map(acc) and is_atom(key) and Map.has_key?(acc, Atom.to_string(key)) ->
          {:cont, Map.get(acc, Atom.to_string(key))}

        true ->
          {:halt, nil}
      end
    end)
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_boolean(value), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp coding_assistance_module do
    Application.get_env(:jido_code, :conversation_driver_coding_assistance_module, CodingAssistance)
  end

  defp conversation_ingress_module do
    Application.get_env(:jido_code, :conversation_driver_ingress_module, Ingress)
  end

  defp event_bridge_module do
    Application.get_env(:jido_code, :conversation_driver_event_bridge_module, EventBridge)
  end

  defp repo_bridge_module do
    Application.get_env(:jido_code, :conversation_driver_repo_bridge_module, RepoBridge)
  end
end
