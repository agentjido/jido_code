defmodule JidoCode.Workbench.ProjectConversation do
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
  # covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  # covers: architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations
  # covers: architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage
  # covers: architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage
  @moduledoc """
  Product-owned conversation shaping for managed-repository and governed-work
  surfaces.

  This boundary keeps operator LiveViews focused on product behavior rather
  than conversation persistence lookups or driver topology.
  """

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.Actor
  alias JidoCode.Conversations
  alias JidoCode.Conversations.{Conversation, WorkResolution}
  alias JidoCode.Operations.WorkItem

  @default_objective "Coordinate repository work from the managed repository detail route."

  @type notice :: %{
          error_type: String.t(),
          detail: String.t(),
          remediation: String.t() | nil
        }

  @type projection :: %{
          available?: boolean(),
          managed_repo_id: String.t() | nil,
          conversation: map() | nil,
          work_item: map() | nil,
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

  @type work_item_projection :: %{
          managed_repo_id: String.t() | nil,
          conversation: map() | nil,
          work_item: map() | nil,
          origin: map() | nil,
          snapshot: map() | nil,
          recent_events: [map()],
          notice: notice() | nil,
          action_label: String.t()
        }

  @spec load_attached_work_item(String.t() | nil, keyword()) :: map() | nil
  def load_attached_work_item(work_item_id, opts \\ [])

  def load_attached_work_item(work_item_id, opts) when is_binary(work_item_id) and is_list(opts) do
    actor = normalize_actor(Keyword.get(opts, :actor))

    case WorkItem.read(query: [filter: [id: work_item_id], limit: 1], actor: actor) do
      {:ok, [%WorkItem{} = work_item | _rest]} -> work_item_summary(work_item)
      _other -> placeholder_work_item_summary(work_item_id)
    end
  end

  def load_attached_work_item(_work_item_id, _opts), do: nil

  @spec load_repo_detail(map() | nil, keyword()) :: projection()
  def load_repo_detail(project_like, opts \\ []) do
    actor = normalize_actor(Keyword.get(opts, :actor))

    case scope(project_like) do
      {:ok, managed_repo_id} ->
        load_projection(managed_repo_id, actor)

      {:error, notice} ->
        unavailable_projection(notice)
    end
  end

  @spec load_managed_repo(String.t(), keyword()) :: projection()
  def load_managed_repo(managed_repo_id, opts \\ [])
      when is_binary(managed_repo_id) and is_list(opts) do
    actor = normalize_actor(Keyword.get(opts, :actor))
    load_projection(managed_repo_id, actor)
  end

  @spec load_work_item_linkage(WorkItem.t() | map() | String.t() | nil, keyword()) :: work_item_projection()
  def load_work_item_linkage(work_item_like, opts \\ []) when is_list(opts) do
    actor = normalize_actor(Keyword.get(opts, :actor))

    case work_item_reference(work_item_like, actor) do
      {:ok, reference} ->
        projection_for_work_item(reference, actor)

      :none ->
        %{
          managed_repo_id: nil,
          conversation: nil,
          work_item: nil,
          origin: nil,
          snapshot: nil,
          recent_events: [],
          notice: nil,
          action_label: "Open repo conversation"
        }
    end
  end

  @spec open_repo_detail(map() | nil, keyword()) :: {:ok, open_result()} | {:error, notice()}
  def open_repo_detail(project_like, opts \\ []) do
    actor = normalize_actor(Keyword.get(opts, :actor))
    restart? = Keyword.get(opts, :restart?, false)
    attrs = Keyword.get(opts, :conversation_attrs, %{})

    with {:ok, managed_repo_id} <- scope(project_like) do
      open_repo_conversation(managed_repo_id, attrs, actor, restart?)
    else
      {:error, notice} -> {:error, notice}
    end
  end

  defp load_projection(managed_repo_id, actor) do
    case AgentWorkspace.latest_repo_conversation(managed_repo_id, actor: actor) do
      {:ok, nil} ->
        %{
          available?: true,
          managed_repo_id: managed_repo_id,
          conversation: nil,
          work_item: nil,
          snapshot: nil,
          recent_events: [],
          notice: nil,
          action_label: "Open repo conversation"
        }

      {:ok, %Conversation{} = conversation} ->
        case AgentWorkspace.conversation_snapshot(conversation.id) do
          {:ok, snapshot} ->
            projection_for(conversation, snapshot, managed_repo_id, actor)

          {:error, reason} ->
            %{
              available?: true,
              managed_repo_id: managed_repo_id,
              conversation: conversation_summary(conversation, nil),
              work_item: load_attached_work_item(conversation.work_item_id, actor: actor),
              snapshot: nil,
              recent_events: [],
              notice: snapshot_unavailable_notice(reason),
              action_label: action_label(conversation)
            }
        end

      {:error, reason} ->
        unavailable_projection(load_error_notice(reason))
        |> Map.put(:managed_repo_id, managed_repo_id)
    end
  end

  defp open_repo_conversation(managed_repo_id, attrs, actor, restart?) do
    if restart? do
      start_repo_conversation(managed_repo_id, attrs, actor)
    else
      case AgentWorkspace.latest_repo_conversation(managed_repo_id, actor: actor) do
        {:ok, %Conversation{} = conversation} ->
          maybe_reuse_conversation(conversation, managed_repo_id, attrs, actor)

        {:ok, nil} ->
          start_repo_conversation(managed_repo_id, attrs, actor)

        {:error, reason} ->
          {:error, load_error_notice(reason)}
      end
    end
  end

  defp maybe_reuse_conversation(%Conversation{status: status} = conversation, _managed_repo_id, _attrs, _actor)
       when status in [:active, :paused] do
    case AgentWorkspace.conversation_snapshot(conversation.id) do
      {:ok, snapshot} ->
        {:ok, %{conversation: conversation, snapshot: snapshot, resumed?: true}}

      {:error, reason} ->
        {:error, snapshot_unavailable_notice(reason)}
    end
  end

  defp maybe_reuse_conversation(_conversation, managed_repo_id, attrs, actor) do
    start_repo_conversation(managed_repo_id, attrs, actor)
  end

  defp start_repo_conversation(managed_repo_id, attrs, actor) do
    start_attrs =
      attrs
      |> normalize_map()
      |> Map.put("managed_repo_id", managed_repo_id)
      |> Map.put_new("source", "project_detail")
      |> Map.put_new("objective", @default_objective)
      |> Map.put("source_metadata", start_source_metadata(attrs))

    case AgentWorkspace.open_repo_conversation(managed_repo_id, start_attrs, actor: actor) do
      {:ok, %{conversation: %Conversation{} = conversation, snapshot: snapshot}} ->
        {:ok, %{conversation: conversation, snapshot: snapshot, resumed?: false}}

      {:error, reason} ->
        {:error, load_error_notice(reason)}
    end
  end

  defp scope(project_like) when is_map(project_like) do
    managed_repo_id =
      project_like
      |> map_get(:managed_repo_id, "managed_repo_id")
      |> normalize_optional_string()

    case managed_repo_id do
      nil ->
        {:error,
         %{
           error_type: "conversation_repo_scope_unavailable",
           detail: "Repository conversations need a managed repository identifier.",
           remediation: "Reopen this repository from a managed-repo route and then retry the conversation."
         }}

      managed_repo_id ->
        {:ok, managed_repo_id}
    end
  end

  defp scope(_project_like), do: {:error, unavailable_notice()}

  defp projection_for(%Conversation{} = conversation, snapshot, managed_repo_id, actor) do
    %{
      available?: true,
      managed_repo_id: managed_repo_id,
      conversation: conversation_summary(conversation, snapshot),
      work_item:
        load_attached_work_item(
          attached_work_item_id(conversation, snapshot),
          actor: actor
        ),
      snapshot: snapshot,
      recent_events: recent_events(snapshot),
      notice: nil,
      action_label: action_label(conversation)
    }
  end

  defp projection_for_work_item(reference, actor) do
    conversation_result =
      reference.origin_conversation_id
      |> fetch_conversation(actor)
      |> case do
        {:ok, %Conversation{} = conversation} ->
          {:ok, conversation}

        _other ->
          Conversations.latest_for_work_item(reference.work_item_id, actor: actor)
      end

    case conversation_result do
      {:ok, %Conversation{} = conversation} ->
        case AgentWorkspace.conversation_snapshot(conversation.id) do
          {:ok, snapshot} ->
            %{
              managed_repo_id: reference.managed_repo_id,
              conversation: conversation_summary(conversation, snapshot),
              work_item: reference.work_item,
              origin: reference.origin,
              snapshot: snapshot,
              recent_events: recent_events(snapshot),
              notice: nil,
              action_label: action_label(conversation)
            }

          {:error, reason} ->
            %{
              managed_repo_id: reference.managed_repo_id,
              conversation: conversation_summary(conversation, nil),
              work_item: reference.work_item,
              origin: reference.origin,
              snapshot: nil,
              recent_events: [],
              notice: snapshot_unavailable_notice(reason),
              action_label: action_label(conversation)
            }
        end

      {:ok, nil} ->
        %{
          managed_repo_id: reference.managed_repo_id,
          conversation: nil,
          work_item: reference.work_item,
          origin: reference.origin,
          snapshot: nil,
          recent_events: [],
          notice: nil,
          action_label: "Open repo conversation"
        }

      {:error, reason} ->
        %{
          managed_repo_id: reference.managed_repo_id,
          conversation: nil,
          work_item: reference.work_item,
          origin: reference.origin,
          snapshot: nil,
          recent_events: [],
          notice: load_error_notice(reason),
          action_label: "Open repo conversation"
        }
    end
  end

  defp conversation_summary(%Conversation{} = conversation, snapshot) do
    %{
      id: conversation.id,
      status: snapshot_value(snapshot, :status, conversation.status),
      scope: snapshot_value(snapshot, :scope, conversation.scope),
      attachment_mode: snapshot_value(snapshot, :attachment_mode, conversation.attachment_mode),
      title: conversation.title,
      objective: conversation.objective,
      source: conversation.source,
      work_item_id: attached_work_item_id(conversation, snapshot),
      last_activity_at: conversation.last_activity_at,
      work_resolution: snapshot_value(snapshot, :work_resolution, WorkResolution.summary(conversation))
    }
  end

  defp attached_work_item_id(%Conversation{} = conversation, snapshot) do
    normalize_optional_string(snapshot_value(snapshot, :work_item_id, conversation.work_item_id))
  end

  defp recent_events(%{events: events}) when is_list(events), do: Enum.take(events, -10)
  defp recent_events(_snapshot), do: []

  defp action_label(%Conversation{status: status}) when status in [:active, :paused],
    do: "Continue repo conversation"

  defp action_label(_conversation), do: "Open fresh repo conversation"

  defp start_source_metadata(attrs) do
    attrs
    |> map_get(:source_metadata, "source_metadata", %{})
    |> normalize_map()
    |> Map.put_new("entry_surface", "project_detail")
    |> Map.put_new("channel", "managed_repo_detail")
  end

  defp normalize_actor(nil), do: Actor.operator_actor()
  defp normalize_actor(%{} = actor), do: Actor.operator_actor(actor)

  defp work_item_reference(%WorkItem{} = work_item, _actor) do
    {:ok,
     %{
       work_item_id: work_item.id,
       managed_repo_id: work_item.managed_repo_id,
       work_item: work_item_summary(work_item),
       origin: work_item_origin(work_item),
       origin_conversation_id: origin_conversation_id(work_item)
     }}
  end

  defp work_item_reference(%{} = work_item, actor) do
    case normalize_optional_string(map_get(work_item, :id, "id")) do
      nil ->
        :none

      work_item_id ->
        with {:ok, %WorkItem{} = persisted_work_item} <- fetch_work_item(work_item_id, actor) do
          work_item_reference(persisted_work_item, actor)
        else
          _other ->
            {:ok,
             %{
               work_item_id: work_item_id,
               managed_repo_id:
                 work_item
                 |> map_get(:managed_repo_id, "managed_repo_id")
                 |> normalize_optional_string(),
               work_item: normalize_work_item_map(work_item),
               origin: work_item_origin(work_item),
               origin_conversation_id: origin_conversation_id(work_item)
             }}
        end
    end
  end

  defp work_item_reference(work_item_id, actor) when is_binary(work_item_id) do
    with {:ok, %WorkItem{} = work_item} <- fetch_work_item(work_item_id, actor) do
      work_item_reference(work_item, actor)
    else
      _other ->
        {:ok,
         %{
           work_item_id: work_item_id,
           managed_repo_id: nil,
           work_item: placeholder_work_item_summary(work_item_id),
           origin: nil,
           origin_conversation_id: nil
         }}
    end
  end

  defp work_item_reference(_work_item_like, _actor), do: :none

  defp fetch_work_item(work_item_id, actor) when is_binary(work_item_id) do
    case WorkItem.read(query: [filter: [id: work_item_id], limit: 1], actor: actor) do
      {:ok, [%WorkItem{} = work_item | _rest]} -> {:ok, work_item}
      {:ok, []} -> {:error, :work_item_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_conversation(nil, _actor), do: {:ok, nil}

  defp fetch_conversation(conversation_id, actor) when is_binary(conversation_id) do
    case Conversation.read(query: [filter: [id: conversation_id], limit: 1], actor: actor) do
      {:ok, [%Conversation{} = conversation | _rest]} -> {:ok, conversation}
      {:ok, []} -> {:error, :conversation_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp unavailable_projection(notice) do
    %{
      available?: false,
      managed_repo_id: nil,
      conversation: nil,
      work_item: nil,
      snapshot: nil,
      recent_events: [],
      notice: notice,
      action_label: "Open repo conversation"
    }
  end

  defp work_item_origin(%WorkItem{} = work_item) do
    work_item
    |> Map.get(:work_metadata, %{})
    |> conversation_origin_from_metadata()
  end

  defp work_item_origin(%{} = work_item) do
    work_item
    |> map_get(:work_metadata, "work_metadata", %{})
    |> conversation_origin_from_metadata()
  end

  defp work_item_origin(_work_item), do: nil

  defp conversation_origin_from_metadata(metadata) when is_map(metadata) do
    metadata
    |> normalize_map()
    |> Map.get("conversation_origin")
    |> normalize_map()
    |> case do
      origin when map_size(origin) == 0 -> nil
      origin -> origin
    end
  end

  defp conversation_origin_from_metadata(_metadata), do: nil

  defp origin_conversation_id(work_item) do
    work_item
    |> work_item_origin()
    |> case do
      %{} = origin -> normalize_optional_string(Map.get(origin, "conversation_id"))
      _other -> nil
    end
  end

  defp normalize_work_item_map(%{} = work_item) do
    %{
      id: work_item |> map_get(:id, "id") |> normalize_optional_string(),
      status: work_item |> map_get(:status, "status") || :open,
      priority: work_item |> map_get(:priority, "priority") || :medium,
      summary:
        work_item
        |> map_get(:summary, "summary")
        |> normalize_optional_string() ||
          "Governed work item",
      category:
        work_item
        |> map_get(:category, "category")
        |> normalize_optional_string() ||
          "operator_work_request",
      recommended_action:
        work_item
        |> map_get(:recommended_action, "recommended_action")
        |> normalize_optional_string() ||
          "review_operator_request",
      updated_at: work_item |> map_get(:updated_at, "updated_at")
    }
  end

  defp work_item_summary(%WorkItem{} = work_item) do
    %{
      id: work_item.id,
      status: work_item.status,
      priority: work_item.priority,
      summary: work_item.summary,
      category: work_item.category,
      recommended_action: work_item.recommended_action,
      updated_at: work_item.updated_at
    }
  end

  defp placeholder_work_item_summary(work_item_id) when is_binary(work_item_id) do
    %{
      id: work_item_id,
      status: :open,
      priority: :medium,
      summary: "Governed work item #{work_item_id}",
      category: "operator_work_request",
      recommended_action: "review_operator_request",
      updated_at: nil
    }
  end

  defp load_error_notice(reason) do
    %{
      error_type: "project_detail_conversation_unavailable",
      detail: "Repository conversation state could not be loaded (#{inspect(reason)}).",
      remediation: "Retry the repository conversation after managed-repository services recover."
    }
  end

  defp snapshot_unavailable_notice(reason) do
    %{
      error_type: "project_detail_conversation_snapshot_unavailable",
      detail: "The latest repository conversation snapshot is temporarily unavailable (#{inspect(reason)}).",
      remediation: "Retry the repository conversation or open a fresh one if the prior session cannot be recovered."
    }
  end

  defp unavailable_notice do
    %{
      error_type: "conversation_project_detail_unavailable",
      detail: "Repository conversation state is unavailable for this route.",
      remediation: "Open a managed repository from Workbench and then retry the conversation."
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

  defp snapshot_value(snapshot, atom_key, default) when is_map(snapshot) do
    string_key = Atom.to_string(atom_key)

    cond do
      Map.has_key?(snapshot, atom_key) -> Map.get(snapshot, atom_key)
      Map.has_key?(snapshot, string_key) -> Map.get(snapshot, string_key)
      true -> default
    end
  end

  defp snapshot_value(_snapshot, _atom_key, default), do: default

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil

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
end
