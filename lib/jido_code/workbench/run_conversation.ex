defmodule JidoCode.Workbench.RunConversation do
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
  # covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  # covers: architecture.conversation_orchestration.governed_run_routes_host_work_conversations
  @moduledoc """
  Product-owned conversation shaping for governed run detail surfaces.

  This boundary keeps run detail LiveViews focused on governed work and durable
  operator behavior rather than conversation persistence lookups or driver
  topology.
  """

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.Actor
  alias JidoCode.Conversations.Conversation

  @default_objective "Continue governed work from the run detail route."

  @type notice :: %{
          error_type: String.t(),
          detail: String.t(),
          remediation: String.t() | nil
        }

  @type projection :: %{
          available?: boolean(),
          managed_repo_id: String.t() | nil,
          work_item_id: String.t() | nil,
          run_id: String.t() | nil,
          conversation: map() | nil,
          snapshot: map() | nil,
          recent_events: [map()],
          notice: notice() | nil,
          action_label: String.t()
        }

  @type open_result :: %{
          conversation: Conversation.t(),
          snapshot: map(),
          resumed?: boolean()
        }

  @spec load_run_detail(map() | nil, keyword()) :: projection()
  def load_run_detail(run_like, opts \\ []) do
    actor = normalize_actor(Keyword.get(opts, :actor))

    case scope(run_like) do
      {:ok, %{managed_repo_id: managed_repo_id, work_item_id: work_item_id, run_id: run_id}} ->
        load_projection(managed_repo_id, work_item_id, run_id, actor)

      {:error, notice} ->
        unavailable_projection(notice)
    end
  end

  @spec open_run_detail(map() | nil, keyword()) :: {:ok, open_result()} | {:error, notice()}
  def open_run_detail(run_like, opts \\ []) do
    actor = normalize_actor(Keyword.get(opts, :actor))
    restart? = Keyword.get(opts, :restart?, false)
    attrs = Keyword.get(opts, :conversation_attrs, %{})

    with {:ok, scope} <- scope(run_like) do
      open_work_item_conversation(scope, attrs, actor, restart?)
    else
      {:error, notice} -> {:error, notice}
    end
  end

  defp load_projection(managed_repo_id, work_item_id, run_id, actor) do
    case AgentWorkspace.latest_work_item_conversation(work_item_id, actor: actor) do
      {:ok, nil} ->
        %{
          available?: true,
          managed_repo_id: managed_repo_id,
          work_item_id: work_item_id,
          run_id: run_id,
          conversation: nil,
          snapshot: nil,
          recent_events: [],
          notice: nil,
          action_label: "Open work conversation"
        }

      {:ok, %Conversation{} = conversation} ->
        case AgentWorkspace.conversation_snapshot(conversation.id) do
          {:ok, snapshot} ->
            %{
              available?: true,
              managed_repo_id: managed_repo_id,
              work_item_id: work_item_id,
              run_id: run_id,
              conversation: conversation_summary(conversation),
              snapshot: snapshot,
              recent_events: recent_events(snapshot),
              notice: nil,
              action_label: action_label(conversation)
            }

          {:error, reason} ->
            %{
              available?: true,
              managed_repo_id: managed_repo_id,
              work_item_id: work_item_id,
              run_id: run_id,
              conversation: conversation_summary(conversation),
              snapshot: nil,
              recent_events: [],
              notice: snapshot_unavailable_notice(reason),
              action_label: action_label(conversation)
            }
        end

      {:error, reason} ->
        unavailable_projection(load_error_notice(reason))
        |> Map.put(:managed_repo_id, managed_repo_id)
        |> Map.put(:work_item_id, work_item_id)
        |> Map.put(:run_id, run_id)
    end
  end

  defp open_work_item_conversation(
         %{managed_repo_id: managed_repo_id, work_item_id: work_item_id} = scope,
         attrs,
         actor,
         restart?
       ) do
    if restart? do
      start_work_item_conversation(scope, attrs, actor)
    else
      case AgentWorkspace.latest_work_item_conversation(work_item_id, actor: actor) do
        {:ok, %Conversation{} = conversation} ->
          maybe_reuse_conversation(conversation, managed_repo_id, work_item_id, scope.run_id, attrs, actor)

        {:ok, nil} ->
          start_work_item_conversation(scope, attrs, actor)

        {:error, reason} ->
          {:error, load_error_notice(reason)}
      end
    end
  end

  defp maybe_reuse_conversation(
         %Conversation{status: status} = conversation,
         _managed_repo_id,
         _work_item_id,
         _run_id,
         _attrs,
         _actor
       )
       when status in [:active, :paused] do
    case AgentWorkspace.conversation_snapshot(conversation.id) do
      {:ok, snapshot} ->
        {:ok, %{conversation: conversation, snapshot: snapshot, resumed?: true}}

      {:error, reason} ->
        {:error, snapshot_unavailable_notice(reason)}
    end
  end

  defp maybe_reuse_conversation(_conversation, managed_repo_id, work_item_id, run_id, attrs, actor) do
    start_work_item_conversation(
      %{managed_repo_id: managed_repo_id, work_item_id: work_item_id, run_id: run_id},
      attrs,
      actor
    )
  end

  defp start_work_item_conversation(
         %{managed_repo_id: managed_repo_id, work_item_id: work_item_id, run_id: run_id},
         attrs,
         actor
       ) do
    start_attrs =
      attrs
      |> normalize_map()
      |> Map.put("managed_repo_id", managed_repo_id)
      |> Map.put("work_item_id", work_item_id)
      |> Map.put_new("attach_mode", :existing_work_item)
      |> Map.put_new("source", "run_detail")
      |> Map.put_new("objective", @default_objective)
      |> Map.put("source_metadata", start_source_metadata(attrs, run_id))

    case AgentWorkspace.open_work_item_conversation(managed_repo_id, work_item_id, start_attrs, actor: actor) do
      {:ok, %{conversation: %Conversation{} = conversation, snapshot: snapshot}} ->
        {:ok, %{conversation: conversation, snapshot: snapshot, resumed?: false}}

      {:error, reason} ->
        {:error, load_error_notice(reason)}
    end
  end

  defp scope(run_like) when is_map(run_like) do
    managed_repo_id =
      run_like
      |> map_get(:managed_repo_id, "managed_repo_id")
      |> normalize_optional_string()

    work_item_id =
      run_like
      |> map_get(:work_item_id, "work_item_id")
      |> normalize_optional_string()

    run_id =
      run_like
      |> map_get(:run_id, "run_id")
      |> normalize_optional_string()

    cond do
      managed_repo_id == nil ->
        {:error,
         %{
           error_type: "conversation_run_detail_scope_unavailable",
           detail: "Run detail conversations need a managed repository identifier.",
           remediation: "Reopen this run from a managed-repository route and then retry the conversation."
         }}

      work_item_id == nil ->
        {:error,
         %{
           error_type: "conversation_run_work_item_unavailable",
           detail: "Governed run conversations need a linked work item.",
           remediation: "Open a run that is linked to governed work or continue from the managed repository route."
         }}

      true ->
        {:ok, %{managed_repo_id: managed_repo_id, work_item_id: work_item_id, run_id: run_id}}
    end
  end

  defp scope(_run_like), do: {:error, unavailable_notice()}

  defp conversation_summary(%Conversation{} = conversation) do
    %{
      id: conversation.id,
      status: conversation.status,
      scope: conversation.scope,
      attachment_mode: conversation.attachment_mode,
      title: conversation.title,
      objective: conversation.objective,
      source: conversation.source,
      work_item_id: conversation.work_item_id,
      last_activity_at: conversation.last_activity_at
    }
  end

  defp recent_events(%{events: events}) when is_list(events), do: Enum.take(events, -10)
  defp recent_events(_snapshot), do: []

  defp action_label(%Conversation{status: status}) when status in [:active, :paused],
    do: "Continue work conversation"

  defp action_label(_conversation), do: "Open fresh work conversation"

  defp start_source_metadata(attrs, run_id) do
    attrs
    |> map_get(:source_metadata, "source_metadata", %{})
    |> normalize_map()
    |> Map.put_new("entry_surface", "run_detail")
    |> Map.put_new("channel", "governed_run_detail")
    |> maybe_put("run_id", run_id)
  end

  defp normalize_actor(nil), do: Actor.operator_actor()
  defp normalize_actor(%{} = actor), do: Actor.operator_actor(actor)

  defp unavailable_projection(notice) do
    %{
      available?: false,
      managed_repo_id: nil,
      work_item_id: nil,
      run_id: nil,
      conversation: nil,
      snapshot: nil,
      recent_events: [],
      notice: notice,
      action_label: "Open work conversation"
    }
  end

  defp load_error_notice(reason) do
    %{
      error_type: "run_detail_conversation_unavailable",
      detail: "Governed run conversation state could not be loaded (#{inspect(reason)}).",
      remediation: "Retry the governed work conversation after conversation services recover."
    }
  end

  defp snapshot_unavailable_notice(reason) do
    %{
      error_type: "run_detail_conversation_snapshot_unavailable",
      detail: "The latest governed run conversation snapshot is temporarily unavailable (#{inspect(reason)}).",
      remediation: "Retry the conversation or open a fresh one if the prior session cannot be recovered."
    }
  end

  defp unavailable_notice do
    %{
      error_type: "conversation_run_detail_unavailable",
      detail: "Governed run conversation state is unavailable for this route.",
      remediation: "Open a governed run from a managed repository route and then retry the conversation."
    }
  end

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp normalize_optional_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_optional_string()
  defp normalize_optional_string(_value), do: nil

  defp normalize_map(%{} = map), do: map
  defp normalize_map(_other), do: %{}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
