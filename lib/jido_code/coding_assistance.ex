defmodule JidoCode.CodingAssistance do
  # covers: coding_assistance.boundary.public_jido_os_service_boundary
  # covers: coding_assistance.boundary.session_prepared_before_assist
  # covers: coding_assistance.boundary.session_authority_delegation
  # covers: coding_assistance.boundary.product_local_driver_api
  @moduledoc """
  Thin product-context boundary for provider-neutral coding-assistance requests.

  This module keeps `jido_code` talking only to the public `jido_os` service and
  session boundaries rather than to private internal coding agents.
  """

  alias Jido.Os.CodingAssist.Service, as: CodingAssistService
  alias Jido.Os.Session.DirectoryAgent
  alias Jido.Os.Session.RuntimeAgent
  alias JidoCode.JidoOsRuntime

  @default_operation "plan"
  @default_origin %{source_kind: "ui_channel", source_id: "jido_code"}

  def assist(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_runtime_session(actor_id, params, fn runtime_attrs ->
      objective = fetch_required!(params, :objective)

      CodingAssistService.assist(
        JidoOsRuntime.instance_id(),
        coding_request_payload(actor_id, params, objective, runtime_attrs),
        JidoOsRuntime.context_for(actor_id, runtime_attrs)
      )
    end)
  end

  def start_turn(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_runtime_session(actor_id, params, fn runtime_attrs ->
      objective = fetch_required!(params, :objective)

      CodingAssistService.start_turn(
        JidoOsRuntime.instance_id(),
        coding_request_payload(actor_id, params, objective, runtime_attrs),
        JidoOsRuntime.context_for(actor_id, runtime_attrs)
      )
    end)
  end

  def get_turn(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_runtime_session(actor_id, params, fn runtime_attrs ->
      CodingAssistService.get_turn(
        JidoOsRuntime.instance_id(),
        public_turn_payload(params, [:session_id, :turn_id]),
        JidoOsRuntime.context_for(actor_id, runtime_attrs)
      )
    end)
  end

  def list_turns(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_runtime_session(actor_id, params, fn runtime_attrs ->
      CodingAssistService.list_turns(
        JidoOsRuntime.instance_id(),
        public_turn_payload(params, [:session_id]),
        JidoOsRuntime.context_for(actor_id, runtime_attrs)
      )
    end)
  end

  def list_turn_events(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_runtime_session(actor_id, params, fn runtime_attrs ->
      CodingAssistService.list_turn_events(
        JidoOsRuntime.instance_id(),
        public_turn_payload(params, [:session_id, :turn_id, :after_event_id]),
        JidoOsRuntime.context_for(actor_id, runtime_attrs)
      )
    end)
  end

  def list_turn_artifacts(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_runtime_session(actor_id, params, fn runtime_attrs ->
      CodingAssistService.list_turn_artifacts(
        JidoOsRuntime.instance_id(),
        public_turn_payload(params, [:session_id, :turn_id]),
        JidoOsRuntime.context_for(actor_id, runtime_attrs)
      )
    end)
  end

  def cancel_turn(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_runtime_session(actor_id, params, fn runtime_attrs ->
      CodingAssistService.cancel_turn(
        JidoOsRuntime.instance_id(),
        public_turn_payload(params, [:session_id, :turn_id]),
        JidoOsRuntime.context_for(actor_id, runtime_attrs)
      )
    end)
  end

  def review_turn(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_runtime_session(actor_id, params, fn runtime_attrs ->
      CodingAssistService.review_turn(
        JidoOsRuntime.instance_id(),
        public_turn_payload(params, [:session_id, :turn_id]),
        JidoOsRuntime.context_for(actor_id, runtime_attrs)
      )
    end)
  end

  def ensure_session(session_id, actor_id, attrs \\ %{}) do
    with :ok <- JidoOsRuntime.ensure_instance() do
      context = JidoOsRuntime.context_for(actor_id, attrs)

      case RuntimeAgent.load_session(context.instance_id, session_id, context) do
        {:ok, session} -> {:ok, session}
        {:error, _} -> RuntimeAgent.create_session(context.instance_id, session_id, context)
      end
    end
  end

  def lookup_session(session_id, actor_id, attrs \\ %{}) do
    with :ok <- JidoOsRuntime.ensure_instance() do
      context = JidoOsRuntime.context_for(actor_id, attrs)
      RuntimeAgent.load_session(context.instance_id, session_id, context)
    end
  end

  def bind_project(session_id, actor_id, project_id, attrs \\ %{}) do
    with :ok <- JidoOsRuntime.ensure_instance() do
      context =
        attrs
        |> get_map()
        |> Map.put(:project_id, project_id)
        |> then(&JidoOsRuntime.context_for(actor_id, &1))

      DirectoryAgent.attach_session_to_project(context.instance_id, session_id, project_id, context)
    end
  end

  def rebind_project(session_id, actor_id, project_id, attrs \\ %{}) do
    with :ok <- JidoOsRuntime.ensure_instance() do
      context =
        attrs
        |> get_map()
        |> Map.put(:project_id, project_id)
        |> then(&JidoOsRuntime.context_for(actor_id, &1))

      DirectoryAgent.rebind_session_project(context.instance_id, session_id, project_id, context)
    end
  end

  def unbind_project(session_id, actor_id, attrs \\ %{}) do
    with :ok <- JidoOsRuntime.ensure_instance() do
      context = JidoOsRuntime.context_for(actor_id, attrs)
      DirectoryAgent.detach_session_from_project(context.instance_id, session_id, context)
    end
  end

  def update_ai_selection(session_id, actor_id, selection, attrs \\ %{}) when is_map(selection) do
    with :ok <- JidoOsRuntime.ensure_instance() do
      context = JidoOsRuntime.context_for(actor_id, attrs)

      RuntimeAgent.update_session_ai_preferences(
        context.instance_id,
        session_id,
        selection,
        context
      )
    end
  end

  def get_ai_selection(session_id, actor_id, attrs \\ %{}) do
    with :ok <- JidoOsRuntime.ensure_instance() do
      context = JidoOsRuntime.context_for(actor_id, attrs)
      RuntimeAgent.get_session_ai_preferences(context.instance_id, session_id, context)
    end
  end

  defp with_runtime_session(actor_id, params, fun) when is_binary(actor_id) and is_map(params) do
    session_id = fetch_required!(params, :session_id)
    runtime_attrs = runtime_attrs(params)

    with :ok <- JidoOsRuntime.ensure_instance(),
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
end
