defmodule JidoCode.CodingAssistance do
  # covers: coding_assistance.boundary.public_jido_os_service_boundary
  # covers: coding_assistance.boundary.session_prepared_before_assist
  # covers: coding_assistance.boundary.session_authority_delegation
  # covers: coding_assistance.boundary.product_local_driver_api
  # covers: coding_assistance.boundary.public_turn_wrapper_api
  # covers: coding_assistance.boundary.live_delivery_ack_and_resume_boundary
  # covers: coding_assistance.boundary.replay_and_recovery_wrappers_remain_available
  # covers: architecture.conversation_driver.public_turn_live_delivery_is_preferred_incremental_path
  # covers: architecture.jido_os_session_turn_runtime.actor_bound_context_required
  # covers: architecture.jido_os_session_turn_runtime.authority_boundaries_preserved
  # covers: architecture.jido_os_session_turn_runtime.public_turn_lifecycle_surface
  # covers: architecture.runtime_service_overlay.public_service_facades_are_only_product_runtime_seam
  # covers: architecture.runtime_service_overlay.product_owned_gateways_preserve_contracts
  # covers: architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product
  @moduledoc """
  Thin product-context boundary for provider-neutral coding-assistance requests.

  This module keeps `jido_code` talking only to the public `jido_os` service and
  session boundaries rather than to private internal coding agents.
  """

  alias Jido.Os.CodingAssist.Service, as: CodingAssistService
  alias Jido.Os.Session.DirectoryAgent
  alias Jido.Os.Session.RuntimeAgent
  alias JidoCode.RuntimeGateway

  @default_operation "plan"
  @default_origin %{source_kind: "ui_channel", source_id: "jido_code"}
  @runtime_service_module CodingAssistService

  def runtime_service_module, do: @runtime_service_module

  def runtime_service_key do
    RuntimeGateway.runtime_service_key(@runtime_service_module)
  end

  def runtime_service_status(actor_id, attrs \\ %{}) when is_binary(actor_id) and is_map(attrs) do
    RuntimeGateway.service_status(@runtime_service_module, actor_id, attrs)
  end

  def runtime_service_available?(actor_id, attrs \\ %{})
      when is_binary(actor_id) and is_map(attrs) do
    RuntimeGateway.service_available?(@runtime_service_module, actor_id, attrs)
  end

  def assist(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_runtime_session(actor_id, params, fn runtime_attrs ->
      objective = fetch_required!(params, :objective)

      CodingAssistService.assist(
        RuntimeGateway.instance_id(),
        coding_request_payload(actor_id, params, objective, runtime_attrs),
        RuntimeGateway.context_for(actor_id, runtime_attrs)
      )
    end)
  end

  def start_turn(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_runtime_session(actor_id, params, fn runtime_attrs ->
      objective = fetch_required!(params, :objective)

      CodingAssistService.start_turn(
        RuntimeGateway.instance_id(),
        coding_request_payload(actor_id, params, objective, runtime_attrs),
        RuntimeGateway.context_for(actor_id, runtime_attrs)
      )
    end)
  end

  def get_turn(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_runtime_session(actor_id, params, fn runtime_attrs ->
      CodingAssistService.get_turn(
        RuntimeGateway.instance_id(),
        public_turn_payload(params, [:session_id, :turn_id]),
        RuntimeGateway.context_for(actor_id, runtime_attrs)
      )
    end)
  end

  def list_turns(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_runtime_session(actor_id, params, fn runtime_attrs ->
      CodingAssistService.list_turns(
        RuntimeGateway.instance_id(),
        public_turn_payload(params, [:session_id]),
        RuntimeGateway.context_for(actor_id, runtime_attrs)
      )
    end)
  end

  def list_turn_events(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_runtime_session(actor_id, params, fn runtime_attrs ->
      CodingAssistService.list_turn_events(
        RuntimeGateway.instance_id(),
        public_turn_payload(params, [:session_id, :turn_id, :after_event_id]),
        RuntimeGateway.context_for(actor_id, runtime_attrs)
      )
    end)
  end

  def subscribe_turn_events(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_runtime_session(actor_id, params, fn runtime_attrs ->
      CodingAssistService.subscribe_turn_events(
        RuntimeGateway.instance_id(),
        live_turn_payload(params, runtime_attrs),
        RuntimeGateway.context_for(actor_id, runtime_attrs)
      )
      |> normalize_live_ack_result()
    end)
  end

  def unsubscribe_turn_events(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_runtime_session(actor_id, params, fn runtime_attrs ->
      CodingAssistService.unsubscribe_turn_events(
        RuntimeGateway.instance_id(),
        live_turn_payload(params, runtime_attrs),
        RuntimeGateway.context_for(actor_id, runtime_attrs)
      )
      |> normalize_live_ack_result()
    end)
  end

  def list_turn_artifacts(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_runtime_session(actor_id, params, fn runtime_attrs ->
      CodingAssistService.list_turn_artifacts(
        RuntimeGateway.instance_id(),
        public_turn_payload(params, [:session_id, :turn_id]),
        RuntimeGateway.context_for(actor_id, runtime_attrs)
      )
    end)
  end

  def cancel_turn(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_runtime_session(actor_id, params, fn runtime_attrs ->
      CodingAssistService.cancel_turn(
        RuntimeGateway.instance_id(),
        public_turn_payload(params, [:session_id, :turn_id]),
        RuntimeGateway.context_for(actor_id, runtime_attrs)
      )
    end)
  end

  def review_turn(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_runtime_session(actor_id, params, fn runtime_attrs ->
      CodingAssistService.review_turn(
        RuntimeGateway.instance_id(),
        public_turn_payload(params, [:session_id, :turn_id]),
        RuntimeGateway.context_for(actor_id, runtime_attrs)
      )
    end)
  end

  def ensure_session(session_id, actor_id, attrs \\ %{}) do
    with :ok <- RuntimeGateway.ensure_instance() do
      context = RuntimeGateway.context_for(actor_id, attrs)

      case RuntimeAgent.load_session(context.instance_id, session_id, context) do
        {:ok, session} -> {:ok, session}
        {:error, _} -> RuntimeAgent.create_session(context.instance_id, session_id, context)
      end
    end
  end

  def lookup_session(session_id, actor_id, attrs \\ %{}) do
    with :ok <- RuntimeGateway.ensure_instance() do
      context = RuntimeGateway.context_for(actor_id, attrs)
      RuntimeAgent.load_session(context.instance_id, session_id, context)
    end
  end

  def bind_project(session_id, actor_id, project_id, attrs \\ %{}) do
    with :ok <- RuntimeGateway.ensure_instance() do
      context =
        attrs
        |> get_map()
        |> Map.put(:project_id, project_id)
        |> then(&RuntimeGateway.context_for(actor_id, &1))

      DirectoryAgent.attach_session_to_project(context.instance_id, session_id, project_id, context)
    end
  end

  def rebind_project(session_id, actor_id, project_id, attrs \\ %{}) do
    with :ok <- RuntimeGateway.ensure_instance() do
      context =
        attrs
        |> get_map()
        |> Map.put(:project_id, project_id)
        |> then(&RuntimeGateway.context_for(actor_id, &1))

      DirectoryAgent.rebind_session_project(context.instance_id, session_id, project_id, context)
    end
  end

  def unbind_project(session_id, actor_id, attrs \\ %{}) do
    with :ok <- RuntimeGateway.ensure_instance() do
      context = RuntimeGateway.context_for(actor_id, attrs)
      DirectoryAgent.detach_session_from_project(context.instance_id, session_id, context)
    end
  end

  def update_ai_selection(session_id, actor_id, selection, attrs \\ %{}) when is_map(selection) do
    with :ok <- RuntimeGateway.ensure_instance() do
      context = RuntimeGateway.context_for(actor_id, attrs)

      RuntimeAgent.update_session_ai_preferences(
        context.instance_id,
        session_id,
        selection,
        context
      )
    end
  end

  def get_ai_selection(session_id, actor_id, attrs \\ %{}) do
    with :ok <- RuntimeGateway.ensure_instance() do
      context = RuntimeGateway.context_for(actor_id, attrs)
      RuntimeAgent.get_session_ai_preferences(context.instance_id, session_id, context)
    end
  end

  defp with_runtime_session(actor_id, params, fun) when is_binary(actor_id) and is_map(params) do
    session_id = fetch_required!(params, :session_id)
    runtime_attrs = runtime_attrs(params)

    with :ok <- RuntimeGateway.ensure_instance(),
         {:ok, _session} <- ensure_session(session_id, actor_id, runtime_attrs),
         {:ok, envelope} <- fun.(runtime_attrs) do
      {:ok, envelope}
    end
  end

  defp coding_request_payload(actor_id, params, objective, runtime_attrs) do
    operation = get_string(params, :operation) || @default_operation
    project_id = get_string(params, :project_id)

    %{
      session_id: runtime_attrs.session_id,
      operation: operation,
      objective: objective,
      origin: get_map(params, :origin) || @default_origin,
      collaboration: collaboration_payload(actor_id, params),
      requested_capabilities: requested_capabilities(operation, params),
      prompt_ref: get_map(params, :prompt_ref),
      prompt_variables: get_map(params, :prompt_variables) || %{objective: objective},
      model_profile_override: get_string(params, :model_profile_override),
      operation_profile: get_map(params, :operation_profile),
      tool_intent: get_map(params, :tool_intent) || %{action_ids: [], skill_ids: []},
      context: %{
        session_id: runtime_attrs.session_id,
        project_id: project_id,
        actor_id: actor_id,
        workspace_id: get_string(runtime_attrs, :workspace_id)
      }
    }
    |> compact_nil_values()
  end

  defp public_turn_payload(params, keys) do
    Enum.reduce(keys, %{}, fn key, acc ->
      case get_string(params, key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp live_turn_payload(params, runtime_attrs) do
    %{
      session_id: runtime_attrs.session_id,
      turn_id: get_string(params, :turn_id),
      subscription_id: get_string(params, :subscription_id),
      after_event_id: get_string(params, :resume_after_event_id) || get_string(params, :after_event_id),
      subscriber: get_pid(params, :subscriber)
    }
    |> compact_nil_values()
  end

  defp runtime_attrs(params) do
    %{
      session_id: fetch_required!(params, :session_id),
      project_id: get_string(params, :project_id),
      request_id: get_string(params, :request_id),
      correlation_id: get_string(params, :correlation_id),
      workspace_id: get_string(params, :workspace_id)
    }
  end

  defp collaboration_payload(actor_id, params) do
    case get_map(params, :collaboration) do
      %{} = collaboration when map_size(collaboration) > 0 ->
        collaboration

      _ ->
        %{
          mode: get_string(params, :collaboration_mode) || "solo",
          participants: [%{actor_id: actor_id, role: "requester"}],
          lead_actor_id: actor_id
        }
    end
  end

  defp requested_capabilities(operation, params) do
    capabilities =
      get_list(params, :requested_capabilities)
      |> Enum.filter(&(is_binary(&1) and &1 != ""))

    if capabilities == [], do: [operation], else: capabilities
  end

  defp compact_nil_values(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc ->
        acc

      {key, value}, acc when is_map(value) ->
        Map.put(acc, key, compact_nil_values(value))

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end

  defp fetch_required!(map, key) do
    case get_string(map, key) do
      nil -> raise ArgumentError, "missing required #{key}"
      value -> value
    end
  end

  defp get_string(map, key) when is_map(map) do
    value = Map.get(map, key) || Map.get(map, Atom.to_string(key))

    if is_binary(value) and value != "", do: value, else: nil
  end

  defp get_string(_map, _key), do: nil

  defp get_map(map, key) when is_map(map) do
    value = Map.get(map, key) || Map.get(map, Atom.to_string(key))
    if is_map(value), do: value, else: nil
  end

  defp get_map(value) when is_map(value), do: value
  defp get_map(_value), do: %{}

  defp get_list(map, key) when is_map(map) do
    value = Map.get(map, key) || Map.get(map, Atom.to_string(key))
    if is_list(value), do: value, else: []
  end

  defp get_list(_map, _key), do: []

  defp get_pid(map, key) when is_map(map) do
    value = Map.get(map, key) || Map.get(map, Atom.to_string(key))
    if is_pid(value), do: value, else: nil
  end

  defp get_pid(_map, _key), do: nil

  defp normalize_live_ack_result({:ok, %{} = ack}), do: {:ok, normalize_live_ack(ack)}
  defp normalize_live_ack_result(other), do: other

  defp normalize_live_ack(ack) do
    %{
      delivery_status: get_string(ack, :status),
      subscription_id: get_string(ack, :subscription_id),
      session_id: get_string(ack, :session_id),
      conversation_id: get_string(ack, :conversation_id),
      turn_id: get_string(ack, :turn_id),
      resume_after_event_id: get_string(ack, :resume_after_event_id),
      replay_after_event_id: get_string(ack, :replay_after_event_id),
      latest_event_id: get_string(ack, :latest_event_id),
      terminal_state: get_string(ack, :terminal_state),
      terminal_event_id: get_string(ack, :terminal_event_id),
      detached_at: get_string(ack, :detached_at),
      reason_code: get_string(ack, :reason_code)
    }
    |> compact_nil_values()
  end
end
