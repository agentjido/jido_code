defmodule JidoCode.Conversations.LongTermProvenance do
  # covers: architecture.conversation_orchestration.long_term_conversation_recall_is_provenance_first
  # covers: architecture.memory_capture_plane.conversation_history_is_captured_as_workflow_provenance
  @moduledoc false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.Actor
  alias JidoCode.Conversations.{Conversation, RuntimeReadiness}
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.CaptureEnvelope

  @provenance_actor Actor.factory_system_actor(%{
                      "id" => "system:conversation-long-term-provenance",
                      "email" => "conversation-long-term-provenance@system.local"
                    })

  @spec capture_work_attachment(Conversation.t(), keyword()) :: :ok
  def capture_work_attachment(%Conversation{} = conversation, opts \\ []) when is_list(opts) do
    work_resolution = last_work_resolution(conversation)

    with true <- MemoryGraph.capability_enabled?(opts),
         true <- is_binary(conversation.managed_repo_id),
         true <- is_binary(conversation.work_item_id),
         true <- work_resolution != %{},
         {:ok, readiness} <-
           RuntimeReadiness.resolve(
             conversation.managed_repo_id,
             conversation_metadata: normalize_map(conversation.conversation_metadata)
           ),
         {:ok, revision} <- revision(readiness.workspace_path),
         :ok <- ensure_workflow_provenance_ready(conversation.managed_repo_id, readiness.workspace_path, revision),
         {:ok, _result} <-
           AgentWorkspace.record_memory_graph(
             conversation.managed_repo_id,
             readiness.workspace_path,
             CaptureEnvelope.conversation_turn(
               id: work_attachment_resource_id(conversation, work_resolution),
               session_id: conversation_session_id(conversation.id),
               actor_id: actor_id(Keyword.get(opts, :actor)),
               workflow: Map.get(work_resolution, "workflow"),
               work_item_id: conversation.work_item_id,
               content: work_attachment_summary(conversation, work_resolution),
               revision: revision,
               conversation_id: conversation.id,
               turn_id: Map.get(work_resolution, "turn_id"),
               command_id: Map.get(work_resolution, "command_id"),
               conversation_event: "work_attached",
               conversation_scope: Atom.to_string(conversation.scope),
               conversation_attachment_mode: Atom.to_string(conversation.attachment_mode),
               conversation_status: Atom.to_string(conversation.status),
               conversation_source: conversation.source,
               governed_references: governed_references(conversation.managed_repo_id, conversation.work_item_id)
             ),
             graph_name: MemoryGraph.workflow_provenance_graph_name(),
             revision: revision
           ) do
      :ok
    else
      _other -> :ok
    end
  end

  @spec capture_turn_started(map(), map(), map()) :: :ok
  def capture_turn_started(runtime_spec, request, readiness)
      when is_map(runtime_spec) and is_map(request) and is_map(readiness) do
    conversation_event =
      if clarification_resume?(request) do
        "turn_resumed"
      else
        "turn_started"
      end

    capture_runtime_event(
      runtime_spec,
      request,
      readiness,
      conversation_event,
      bounded_summary(Map.get(request, :user_instruction), "Conversation turn started.")
    )
  end

  @spec capture_clarification_request(map(), map(), map(), String.t() | nil) :: :ok
  def capture_clarification_request(runtime_spec, request, readiness, prompt)
      when is_map(runtime_spec) and is_map(request) and is_map(readiness) do
    capture_runtime_event(
      runtime_spec,
      request,
      readiness,
      "clarification_requested",
      bounded_summary(prompt, "Conversation clarification is required."),
      clarification_state: "awaiting_input"
    )
  end

  @spec capture_turn_completed(map(), map(), map(), String.t() | nil) :: :ok
  def capture_turn_completed(runtime_spec, request, readiness, summary)
      when is_map(runtime_spec) and is_map(request) and is_map(readiness) do
    capture_runtime_event(
      runtime_spec,
      request,
      readiness,
      "turn_completed",
      bounded_summary(summary, "Conversation turn completed.")
    )
  end

  @spec capture_turn_failed(map(), map(), map(), String.t() | nil) :: :ok
  def capture_turn_failed(runtime_spec, request, readiness, detail)
      when is_map(runtime_spec) and is_map(request) and is_map(readiness) do
    capture_runtime_event(
      runtime_spec,
      request,
      readiness,
      "turn_failed",
      bounded_summary(detail, "Conversation turn failed.")
    )
  end

  defp capture_runtime_event(runtime_spec, request, readiness, conversation_event, content, extra_fields \\ []) do
    managed_repo_id = Map.get(request, :managed_repo_id)
    workspace_path = Map.get(readiness, :workspace_path)
    conversation_id = normalize_optional_string(map_get(runtime_spec, :conversation_id))
    turn_id = normalize_optional_string(map_get(runtime_spec, :turn_id))
    work_item_id = normalize_optional_string(Map.get(request, :work_item_id))

    capture =
      [
        id: runtime_resource_id(conversation_id, turn_id, conversation_event),
        session_id: conversation_session_id(conversation_id),
        actor_id: actor_id(map_get(runtime_spec, :actor)),
        workflow: Map.get(request, :workflow),
        work_item_id: work_item_id,
        content: content,
        revision: nil,
        conversation_id: conversation_id,
        turn_id: turn_id,
        command_id: normalize_optional_string(map_get(runtime_spec, :command_id)),
        conversation_event: conversation_event,
        conversation_scope: normalize_optional_string(map_get(runtime_spec, :scope)),
        conversation_attachment_mode: normalize_optional_string(map_get(runtime_spec, :attachment_mode)),
        conversation_status: normalize_optional_string(map_get(runtime_spec, :status)),
        conversation_source: normalize_optional_string(map_get(runtime_spec, :source)),
        governed_references: governed_references(managed_repo_id, work_item_id)
      ]

    with true <- MemoryGraph.capability_enabled?(),
         true <- is_binary(managed_repo_id),
         true <- is_binary(workspace_path),
         true <- is_binary(conversation_id),
         true <- is_binary(turn_id),
         {:ok, revision} <- revision(workspace_path),
         :ok <- ensure_workflow_provenance_ready(managed_repo_id, workspace_path, revision),
         {:ok, _result} <-
           AgentWorkspace.record_memory_graph(
             managed_repo_id,
             workspace_path,
             capture
             |> Keyword.put(:revision, revision)
             |> Keyword.merge(List.wrap(extra_fields))
             |> CaptureEnvelope.conversation_turn(),
             graph_name: MemoryGraph.workflow_provenance_graph_name(),
             revision: revision
           ) do
      :ok
    else
      _other -> :ok
    end
  end

  defp clarification_resume?(request) when is_map(request) do
    request
    |> Map.get(:clarification_resume, %{})
    |> case do
      %{} = clarification_resume -> clarification_resume != %{}
      _other -> false
    end
  end

  defp work_attachment_resource_id(conversation, work_resolution) do
    [
      "conversation",
      conversation.id,
      "work-attached",
      Map.get(work_resolution, "turn_id") || "turn",
      Map.get(work_resolution, "command_id") || conversation.work_item_id || "command"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("-")
  end

  defp runtime_resource_id(conversation_id, turn_id, conversation_event) do
    "conversation-#{conversation_id}-#{conversation_event}-#{turn_id}"
  end

  defp conversation_session_id(conversation_id), do: "conversation-#{conversation_id}"

  defp work_attachment_summary(conversation, work_resolution) do
    summary =
      Map.get(work_resolution, "detail") ||
        "Conversation work attached to governed work item #{conversation.work_item_id}."

    bounded_summary(summary, "Conversation work attached to governed work.")
  end

  defp governed_references(managed_repo_id, work_item_id) do
    [
      %{kind: :managed_repo, id: managed_repo_id},
      work_item_id && %{kind: :work_item, id: work_item_id}
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp last_work_resolution(%Conversation{} = conversation) do
    conversation.conversation_metadata
    |> normalize_map()
    |> Map.get("last_work_resolution", %{})
    |> normalize_map()
  end

  defp revision(workspace_path) do
    with {:ok, revision_metadata} <- MemoryGraph.current_revision_metadata(workspace_path),
         revision when is_binary(revision) <-
           revision_metadata.current_revision || revision_metadata.requested_revision do
      {:ok, revision}
    else
      _other -> {:error, :revision_unavailable}
    end
  end

  defp ensure_workflow_provenance_ready(managed_repo_id, workspace_path, revision) do
    case AgentWorkspace.memory_graph_status(
           managed_repo_id,
           workspace_path,
           graph_name: MemoryGraph.workflow_provenance_graph_name(),
           revision: revision
         ) do
      {:ok, %{ready?: true, stale?: false}} ->
        :ok

      {:ok, _status} ->
        case AgentWorkspace.recover_memory_graph(
               managed_repo_id,
               workspace_path,
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             ) do
          {:ok, %{graph_status: %{ready?: true, stale?: false}}} -> :ok
          _other -> {:error, :memory_graph_not_ready}
        end

      _other ->
        {:error, :memory_graph_not_ready}
    end
  end

  defp actor_id(%{} = actor) do
    actor["id"] || actor[:id] || @provenance_actor["id"]
  end

  defp actor_id(_actor), do: @provenance_actor["id"]

  defp bounded_summary(value, fallback) do
    value
    |> normalize_optional_string()
    |> case do
      nil -> fallback
      summary -> String.slice(summary, 0, 320)
    end
  end

  defp map_get(map, key) when is_map(map) and is_atom(key) do
    string_key = Atom.to_string(key)
    Map.get(map, key) || Map.get(map, string_key)
  end

  defp map_get(_map, _key), do: nil

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      Map.put(acc, normalized_key, normalize_nested_value(nested_value))
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil
end
