defmodule JidoCode.Conversations do
  # covers: architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
  # covers: architecture.conversation_orchestration.steering_preserves_short_term_context
  # covers: architecture.conversation_orchestration.work_item_conversation_lifecycle_tracks_governed_work_status
  # covers: architecture.work_synthesis.productive_conversations_route_through_work_resolution
  # covers: architecture.work_synthesis.historical_conversation_lineage_stays_attached_to_work_item
  # covers: architecture.work_synthesis.work_item_origin_can_preserve_conversation_context
  use Ash.Domain, otp_app: :jido_code, extensions: [AshAdmin.Domain]

  require Ash.Query

  alias JidoCode.Control.Actor
  alias JidoCode.Conversations.{Conversation, EventRecord, SnapshotRecord}
  alias JidoCode.Conversations.{Driver, LongTermProvenance, Persistence, Snapshot}
  alias JidoCode.Operations.{Ingress, WorkItem}

  admin do
    show? true
  end

  resources do
    resource Conversation
    resource EventRecord
    resource SnapshotRecord
  end

  @active_statuses [:active, :paused]
  @resumable_work_item_statuses [:open, :in_progress, :blocked]
  @terminal_work_item_conversation_statuses %{completed: :completed, cancelled: :cancelled, suppressed: :cancelled}

  @type start_result :: %{
          conversation: Conversation.t(),
          work_item: WorkItem.t() | nil,
          work_action: :created | :reprioritized | :suppressed_duplicate | :steered | :unscoped | nil
        }

  @type steer_result :: %{
          conversation: Conversation.t(),
          work_item: WorkItem.t() | nil,
          work_action: :created | :reprioritized | :suppressed_duplicate | :steered | :unscoped | nil
        }

  @type work_item_conversation_result :: %{
          conversation: Conversation.t(),
          work_item: WorkItem.t(),
          resumed?: boolean()
        }

  @type lifecycle_reconciliation_result :: %{
          work_item: WorkItem.t(),
          active_conversation: Conversation.t() | nil,
          settled_conversation: Conversation.t() | nil
        }

  @spec start(map()) :: {:ok, start_result()} | {:error, term()}
  def start(%{} = attrs) do
    with {:ok, context} <- build_start_context(attrs),
         :ok <- ensure_start_work_item_conversation_available(context),
         {:ok, conversation} <- Conversation.create(conversation_attrs(context), actor: context.actor) do
      {:ok,
       %{
         conversation: conversation,
         work_item: context.work_item,
         work_action: context.work_action
       }}
    end
  end

  def start(_attrs), do: {:error, :invalid_conversation_start}

  @spec resume(String.t(), keyword()) :: {:ok, Conversation.t()} | {:error, term()}
  def resume(conversation_id, opts \\ []) when is_binary(conversation_id) and is_list(opts) do
    actor = normalize_actor(Keyword.get(opts, :actor))

    with {:ok, %Conversation{} = conversation} <- fetch_conversation(conversation_id, actor),
         {:ok, resumed} <-
           Conversation.update(
             conversation,
             %{last_activity_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)},
             actor: actor
           ) do
      {:ok, resumed}
    end
  end

  @spec latest_for_managed_repo(String.t(), keyword()) :: {:ok, Conversation.t() | nil} | {:error, term()}
  def latest_for_managed_repo(managed_repo_id, opts \\ [])
      when is_binary(managed_repo_id) and is_list(opts) do
    actor = normalize_actor(Keyword.get(opts, :actor))

    case Conversation.read(
           query: [
             filter: [managed_repo_id: managed_repo_id],
             sort: [last_activity_at: :desc, inserted_at: :desc],
             limit: 1
           ],
           actor: actor
         ) do
      {:ok, [%Conversation{} = conversation | _rest]} -> {:ok, conversation}
      {:ok, []} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec latest_repo_intake_for_managed_repo(String.t(), keyword()) ::
          {:ok, Conversation.t() | nil} | {:error, term()}
  def latest_repo_intake_for_managed_repo(managed_repo_id, opts \\ [])
      when is_binary(managed_repo_id) and is_list(opts) do
    actor = normalize_actor(Keyword.get(opts, :actor))

    query =
      Conversation
      |> Ash.Query.filter(
        managed_repo_id == ^managed_repo_id and
          scope == :repo_scoped and
          attachment_mode == :pre_work
      )
      |> Ash.Query.sort(last_activity_at: :desc, inserted_at: :desc)
      |> Ash.Query.limit(1)

    case Ash.read(query, domain: __MODULE__, actor: actor) do
      {:ok, [%Conversation{} = conversation | _rest]} -> {:ok, conversation}
      {:ok, []} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec latest_for_work_item(String.t(), keyword()) :: {:ok, Conversation.t() | nil} | {:error, term()}
  def latest_for_work_item(work_item_id, opts \\ [])
      when is_binary(work_item_id) and is_list(opts) do
    actor = normalize_actor(Keyword.get(opts, :actor))

    case Conversation.read(
           query: [
             filter: [work_item_id: work_item_id],
             sort: [last_activity_at: :desc, inserted_at: :desc],
             limit: 1
           ],
           actor: actor
         ) do
      {:ok, [%Conversation{} = conversation | _rest]} -> {:ok, conversation}
      {:ok, []} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec active_for_work_item(String.t(), keyword()) ::
          {:ok, Conversation.t() | nil} | {:error, term()}
  def active_for_work_item(work_item_id, opts \\ [])
      when is_binary(work_item_id) and is_list(opts) do
    actor = normalize_actor(Keyword.get(opts, :actor))
    active_statuses = @active_statuses

    query =
      Conversation
      |> Ash.Query.filter(work_item_id == ^work_item_id and status in ^active_statuses)
      |> Ash.Query.sort(last_activity_at: :desc, inserted_at: :desc)
      |> Ash.Query.limit(1)

    case Ash.read(query, domain: __MODULE__, actor: actor) do
      {:ok, [%Conversation{} = conversation | _rest]} -> {:ok, conversation}
      {:ok, []} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec latest_historical_for_work_item(String.t(), keyword()) ::
          {:ok, Conversation.t() | nil} | {:error, term()}
  def latest_historical_for_work_item(work_item_id, opts \\ [])
      when is_binary(work_item_id) and is_list(opts) do
    actor = normalize_actor(Keyword.get(opts, :actor))
    active_statuses = @active_statuses

    query =
      Conversation
      |> Ash.Query.filter(work_item_id == ^work_item_id and status not in ^active_statuses)
      |> Ash.Query.sort(last_activity_at: :desc, inserted_at: :desc)
      |> Ash.Query.limit(1)

    case Ash.read(query, domain: __MODULE__, actor: actor) do
      {:ok, [%Conversation{} = conversation | _rest]} -> {:ok, conversation}
      {:ok, []} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec active_repo_intake_for_managed_repo(String.t(), keyword()) ::
          {:ok, Conversation.t() | nil} | {:error, term()}
  def active_repo_intake_for_managed_repo(managed_repo_id, opts \\ [])
      when is_binary(managed_repo_id) and is_list(opts) do
    actor = normalize_actor(Keyword.get(opts, :actor))
    active_statuses = @active_statuses

    query =
      Conversation
      |> Ash.Query.filter(
        managed_repo_id == ^managed_repo_id and
          scope == :repo_scoped and
          attachment_mode == :pre_work and
          status in ^active_statuses
      )
      |> Ash.Query.sort(last_activity_at: :desc, inserted_at: :desc)
      |> Ash.Query.limit(1)

    case Ash.read(query, domain: __MODULE__, actor: actor) do
      {:ok, [%Conversation{} = conversation | _rest]} -> {:ok, conversation}
      {:ok, []} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec active_work_item_conversations_for_managed_repo(String.t(), keyword()) ::
          {:ok, [Conversation.t()]} | {:error, term()}
  def active_work_item_conversations_for_managed_repo(managed_repo_id, opts \\ [])
      when is_binary(managed_repo_id) and is_list(opts) do
    actor = normalize_actor(Keyword.get(opts, :actor))
    active_statuses = @active_statuses

    query =
      Conversation
      |> Ash.Query.filter(
        managed_repo_id == ^managed_repo_id and
          scope == :work_item_scoped and
          status in ^active_statuses
      )
      |> Ash.Query.sort(last_activity_at: :desc, inserted_at: :desc)

    Ash.read(query, domain: __MODULE__, actor: actor)
  end

  @spec open_or_resume_for_work_item(String.t(), keyword()) ::
          {:ok, work_item_conversation_result()} | {:error, term()}
  def open_or_resume_for_work_item(work_item_id, opts \\ [])
      when is_binary(work_item_id) and is_list(opts) do
    actor = normalize_actor(Keyword.get(opts, :actor))
    attrs = normalize_map(Keyword.get(opts, :attrs))

    with {:ok, %{work_item: %WorkItem{} = work_item, active_conversation: active_conversation}} <-
           reconcile_work_item_conversation_lifecycle(work_item_id, actor: actor),
         :ok <- validate_work_item_open(work_item) do
      case active_conversation do
        %Conversation{} = conversation ->
          with {:ok, resumed} <- resume(conversation.id, actor: actor) do
            {:ok, %{conversation: resumed, work_item: work_item, resumed?: true}}
          end

        nil ->
          start_or_recover_work_item_conversation(work_item, attrs, actor)
      end
    end
  end

  @spec reconcile_work_item_conversation_lifecycle(String.t(), keyword()) ::
          {:ok, lifecycle_reconciliation_result()} | {:error, term()}
  def reconcile_work_item_conversation_lifecycle(work_item_id, opts \\ [])
      when is_binary(work_item_id) and is_list(opts) do
    actor = normalize_actor(Keyword.get(opts, :actor))

    with {:ok, %WorkItem{} = work_item} <- fetch_work_item(work_item_id, actor),
         {:ok, active_conversation} <- active_for_work_item(work_item.id, actor: actor),
         {:ok, settled_conversation, next_active_conversation} <-
           maybe_reconcile_terminal_work_item(work_item, active_conversation, actor) do
      {:ok,
       %{
         work_item: work_item,
         active_conversation: next_active_conversation,
         settled_conversation: settled_conversation
       }}
    end
  end

  @spec steer_work(Conversation.t(), map(), keyword()) :: {:ok, steer_result()} | {:error, term()}
  def steer_work(conversation, payload, opts \\ [])

  def steer_work(%Conversation{} = conversation, %{} = payload, opts) when is_list(opts) do
    actor = normalize_actor(Keyword.get(opts, :actor))
    payload = normalize_map(payload)
    shared_context = normalize_map(Keyword.get(opts, :shared_context))
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    requested_work_item_id = optional_string(payload, :work_item_id)

    case normalize_steering_attach_mode(map_get(payload, :attach_mode), requested_work_item_id, conversation) do
      :existing_work_item ->
        steer_existing_work_item(
          conversation,
          payload,
          requested_work_item_id || conversation.work_item_id,
          shared_context,
          actor,
          now
        )

      :synthesized_work_item ->
        synthesize_conversation_work_item(conversation, payload, shared_context, actor, now)

      :pre_work ->
        with {:ok, updated_conversation} <-
               update_conversation_for_steering(
                 conversation,
                 payload,
                 shared_context,
                 conversation.work_item_id && %{id: conversation.work_item_id},
                 nil,
                 conversation.attachment_mode,
                 conversation.scope,
                 actor,
                 now
               ) do
          {:ok, %{conversation: updated_conversation, work_item: nil, work_action: nil}}
        end
    end
  end

  def steer_work(_conversation, _payload, _opts), do: {:error, :invalid_conversation_steering}

  defp build_start_context(attrs) do
    actor = normalize_actor(Map.get(attrs, :actor) || Map.get(attrs, "actor"))
    source = required_string(attrs, :source)
    objective = optional_string(attrs, :objective)
    title = optional_string(attrs, :title) || objective
    source_metadata = normalize_map(Map.get(attrs, :source_metadata) || Map.get(attrs, "source_metadata"))

    conversation_metadata =
      normalize_map(Map.get(attrs, :conversation_metadata) || Map.get(attrs, "conversation_metadata"))

    work_item_id = optional_string(attrs, :work_item_id)
    managed_repo_id = optional_string(attrs, :managed_repo_id)
    attach_mode = normalize_attach_mode(Map.get(attrs, :attach_mode) || Map.get(attrs, "attach_mode"), work_item_id)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    with {:ok, source} <- validate_required_string(source, :source),
         {:ok, resolved} <- resolve_work_attachment(attach_mode, managed_repo_id, work_item_id, attrs, actor) do
      {:ok,
       %{
         actor: actor,
         source: source,
         title: title,
         objective: objective,
         source_metadata: source_metadata,
         conversation_metadata: conversation_metadata,
         managed_repo_id: resolved.managed_repo_id,
         work_item: resolved.work_item,
         work_action: resolved.work_action,
         attachment_mode: resolved.attachment_mode,
         scope: resolved.scope,
         started_at: now,
         last_activity_at: now
       }}
    end
  end

  defp resolve_work_attachment(:existing_work_item, managed_repo_id, work_item_id, _attrs, actor) do
    with {:ok, work_item_id} <- validate_required_string(work_item_id, :work_item_id),
         {:ok, %WorkItem{} = work_item} <- fetch_work_item(work_item_id, actor),
         :ok <- validate_managed_repo_scope(managed_repo_id, work_item.managed_repo_id) do
      {:ok,
       %{
         managed_repo_id: work_item.managed_repo_id,
         work_item: work_item,
         work_action: nil,
         attachment_mode: :existing_work_item,
         scope: :work_item_scoped
       }}
    end
  end

  defp resolve_work_attachment(:synthesized_work_item, managed_repo_id, _work_item_id, attrs, actor) do
    with {:ok, managed_repo_id} <- validate_required_string(managed_repo_id, :managed_repo_id),
         {:ok, %{work_item: %WorkItem{} = work_item, work_action: work_action}} <-
           Ingress.record_operator_intake(%{
             managed_repo_id: managed_repo_id,
             channel: optional_string(attrs, :source) || "conversation",
             intent: optional_string(attrs, :intent) || "conversation_work_kickoff",
             actor: actor,
             payload:
               %{}
               |> maybe_put("objective", optional_string(attrs, :objective))
               |> maybe_put("title", optional_string(attrs, :title))
               |> maybe_put(
                 "context_item",
                 normalize_map(Map.get(attrs, :context_item) || Map.get(attrs, "context_item"))
               ),
             source_metadata:
               normalize_map(Map.get(attrs, :source_metadata) || Map.get(attrs, "source_metadata"))
               |> Map.put("conversation_entry", true)
           }) do
      {:ok,
       %{
         managed_repo_id: work_item.managed_repo_id,
         work_item: work_item,
         work_action: work_action,
         attachment_mode: :synthesized_work_item,
         scope: :work_item_scoped
       }}
    end
  end

  defp resolve_work_attachment(:pre_work, managed_repo_id, _work_item_id, _attrs, _actor) do
    with {:ok, managed_repo_id} <- validate_required_string(managed_repo_id, :managed_repo_id) do
      {:ok,
       %{
         managed_repo_id: managed_repo_id,
         work_item: nil,
         work_action: nil,
         attachment_mode: :pre_work,
         scope: :repo_scoped
       }}
    end
  end

  defp steer_existing_work_item(conversation, payload, work_item_id, shared_context, actor, now) do
    with {:ok, work_item_id} <- validate_required_string(work_item_id, :work_item_id),
         {:ok, %WorkItem{} = work_item} <- fetch_work_item(work_item_id, actor),
         :ok <- validate_managed_repo_scope(conversation.managed_repo_id, work_item.managed_repo_id),
         :ok <- validate_work_item_open(work_item),
         {:ok, %{work_item: %WorkItem{} = steered_work_item, work_action: work_action}} <-
           record_conversation_intake(
             conversation,
             payload,
             shared_context,
             actor,
             work_item.id,
             "conversation_steer_work"
           ),
         next_attachment_mode <- steering_attachment_mode(conversation, work_item.id),
         {:ok, updated_conversation} <-
           update_conversation_for_steering(
             conversation,
             payload,
             shared_context,
             steered_work_item,
             work_action,
             next_attachment_mode,
             :work_item_scoped,
             actor,
             now
           ) do
      {:ok,
       %{
         conversation: updated_conversation,
         work_item: steered_work_item,
         work_action: work_action
       }}
    end
  end

  defp synthesize_conversation_work_item(conversation, payload, shared_context, actor, now) do
    with {:ok, %{work_item: %WorkItem{} = work_item, work_action: work_action}} <-
           record_conversation_intake(
             conversation,
             payload,
             shared_context,
             actor,
             nil,
             "conversation_work_kickoff"
           ),
         {:ok, updated_conversation} <-
           update_conversation_for_steering(
             conversation,
             payload,
             shared_context,
             work_item,
             work_action,
             :synthesized_work_item,
             :work_item_scoped,
             actor,
             now
           ) do
      {:ok,
       %{
         conversation: updated_conversation,
         work_item: work_item,
         work_action: work_action
       }}
    end
  end

  defp record_conversation_intake(conversation, payload, shared_context, actor, work_item_id, intent) do
    Ingress.record_operator_intake(%{
      managed_repo_id: conversation.managed_repo_id,
      channel: "conversation",
      intent: intent,
      actor: actor,
      payload: steering_payload(conversation, payload, shared_context, work_item_id),
      source_metadata: steering_source_metadata(conversation, payload, shared_context, work_item_id, intent)
    })
  end

  defp steering_payload(conversation, payload, shared_context, work_item_id) do
    %{}
    |> maybe_put("work_item_id", work_item_id)
    |> maybe_put("instruction", optional_string(payload, :instruction))
    |> maybe_put("reason", optional_string(payload, :reason))
    |> maybe_put("workflow_name", optional_string(payload, :workflow_name))
    |> maybe_put("turn_id", optional_string(payload, :turn_id))
    |> maybe_put("command_id", optional_string(payload, :command_id))
    |> maybe_put("resolution_reason", optional_string(payload, :resolution_reason))
    |> maybe_put(
      "resolution_command_type",
      optional_string(payload, :resolution_command_type)
    )
    |> maybe_put("shared_context", shared_context)
    |> Map.put("context_item", %{
      "type" => "conversation",
      "conversation_id" => conversation.id,
      "conversation_turn_id" => optional_string(payload, :turn_id),
      "conversation_command_id" => optional_string(payload, :command_id),
      "conversation_scope" => Atom.to_string(conversation.scope),
      "attachment_mode" => Atom.to_string(conversation.attachment_mode),
      "workflow" => optional_string(payload, :workflow_name),
      "shared_context_summary" => shared_context_summary(shared_context)
    })
  end

  defp steering_source_metadata(conversation, payload, shared_context, work_item_id, intent) do
    %{}
    |> Map.put("conversation_entry", true)
    |> Map.put("conversation_id", conversation.id)
    |> Map.put(
      "conversation_control_command",
      optional_string(payload, :resolution_command_type) || "turn.steer"
    )
    |> Map.put("conversation_scope", Atom.to_string(conversation.scope))
    |> Map.put("conversation_attachment_mode", Atom.to_string(conversation.attachment_mode))
    |> Map.put("steering_intent", intent)
    |> maybe_put("target_work_item_id", work_item_id)
    |> maybe_put("instruction", optional_string(payload, :instruction))
    |> maybe_put("conversation_turn_id", optional_string(payload, :turn_id))
    |> maybe_put("conversation_command_id", optional_string(payload, :command_id))
    |> maybe_put("conversation_workflow", optional_string(payload, :workflow_name))
    |> maybe_put("conversation_resolution_reason", optional_string(payload, :resolution_reason))
    |> maybe_put("shared_context_summary", shared_context_summary(shared_context))
  end

  defp update_conversation_for_steering(
         conversation,
         payload,
         shared_context,
         work_item,
         work_action,
         attachment_mode,
         scope,
         actor,
         now
       ) do
    with :ok <- ensure_work_item_conversation_available(conversation, work_item, actor) do
      case Conversation.update(
             conversation,
             %{
               work_item_id: optional_id(work_item),
               attachment_mode: attachment_mode,
               scope: scope,
               conversation_metadata:
                 steering_conversation_metadata(
                   conversation,
                   payload,
                   shared_context,
                   work_item,
                   work_action,
                   attachment_mode,
                   scope,
                   now
                 ),
               last_activity_at: now
             },
             actor: actor
           ) do
        {:ok, updated_conversation} ->
          _ = LongTermProvenance.capture_work_attachment(updated_conversation, actor: actor)
          {:ok, updated_conversation}

        other ->
          other
      end
    end
  end

  defp ensure_start_work_item_conversation_available(%{work_item: %{id: work_item_id}, actor: actor})
       when is_binary(work_item_id) do
    case active_for_work_item(work_item_id, actor: actor) do
      {:ok, nil} ->
        :ok

      {:ok, %Conversation{} = active_conversation} ->
        {:error, active_work_item_conflict(work_item_id, active_conversation)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_start_work_item_conversation_available(_context), do: :ok

  defp ensure_work_item_conversation_available(%Conversation{} = conversation, %{id: work_item_id}, actor)
       when is_binary(work_item_id) do
    case active_for_work_item(work_item_id, actor: actor) do
      {:ok, nil} ->
        :ok

      {:ok, %Conversation{id: active_conversation_id}} when active_conversation_id == conversation.id ->
        :ok

      {:ok, %Conversation{} = active_conversation} ->
        {:error, active_work_item_conflict(work_item_id, active_conversation, conversation.id)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_work_item_conversation_available(_conversation, _work_item, _actor), do: :ok

  defp active_work_item_conflict(work_item_id, %Conversation{} = active_conversation, attempted_conversation_id \\ nil) do
    details =
      %{
        work_item_id: work_item_id,
        active_conversation_id: active_conversation.id
      }
      |> maybe_put(:attempted_conversation_id, attempted_conversation_id)

    {:active_work_item_conversation_exists, details}
  end

  defp steering_conversation_metadata(
         conversation,
         payload,
         shared_context,
         work_item,
         work_action,
         attachment_mode,
         scope,
         now
       ) do
    current_metadata = normalize_map(conversation.conversation_metadata)
    instruction = optional_string(payload, :instruction) || optional_string(payload, :reason)

    resolution_command =
      optional_string(payload, :resolution_command_type) || "turn.steer"

    workflow_name = optional_string(payload, :workflow_name)
    work_item_id = optional_id(work_item) || conversation.work_item_id
    resolved_at = DateTime.to_iso8601(now)

    intake_handoff =
      repo_intake_handoff(
        conversation,
        work_item_id,
        attachment_mode,
        scope,
        workflow_name,
        resolution_command,
        payload,
        resolved_at
      )

    steering_entry =
      %{
        "at" => resolved_at,
        "command" => resolution_command,
        "work_item_id" => work_item_id,
        "attachment_mode" => Atom.to_string(attachment_mode),
        "scope" => Atom.to_string(scope)
      }
      |> maybe_put("work_action", work_action && Atom.to_string(work_action))
      |> maybe_put("instruction", instruction)
      |> maybe_put("turn_id", optional_string(payload, :turn_id))
      |> maybe_put("command_id", optional_string(payload, :command_id))
      |> maybe_put("workflow", workflow_name)

    work_resolution =
      %{
        "action" =>
          normalize_work_resolution_action(
            work_action,
            work_item_id,
            attachment_mode,
            scope
          ),
        "detail" =>
          work_resolution_detail(
            work_action,
            work_item_id,
            attachment_mode,
            scope,
            workflow_name,
            payload
          ),
        "resolved_at" => resolved_at,
        "command" => resolution_command,
        "scope" => Atom.to_string(scope),
        "attachment_mode" => Atom.to_string(attachment_mode)
      }
      |> maybe_put("work_action", work_action && Atom.to_string(work_action))
      |> maybe_put("work_item_id", work_item_id)
      |> maybe_put("turn_id", optional_string(payload, :turn_id))
      |> maybe_put("command_id", optional_string(payload, :command_id))
      |> maybe_put("workflow", workflow_name)
      |> maybe_put("reason", optional_string(payload, :resolution_reason))

    current_metadata
    |> Map.put("canonical_work_surface", "work_item")
    |> Map.put("shared_context_contract", "bounded")
    |> Map.put("active_work_item_id", work_item_id)
    |> Map.put("last_work_resolution", work_resolution)
    |> Map.put("last_work_resolved_at", resolved_at)
    |> maybe_put("last_work_action", work_action && Atom.to_string(work_action))
    |> maybe_put("last_intake_handoff", intake_handoff)
    |> Map.put("shared_context_summary", shared_context_summary(shared_context))
    |> Map.put("work_resolution_history", work_resolution_history(current_metadata, work_resolution))
    |> maybe_put("intake_handoff_history", intake_handoff_history(current_metadata, intake_handoff))
    |> maybe_update_steering_metadata(resolution_command, resolved_at, instruction, steering_entry)
  end

  defp steering_history(current_metadata, steering_entry) do
    current_metadata
    |> Map.get("steering_history", [])
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Kernel.++([steering_entry])
    |> Enum.take(-10)
  end

  defp work_resolution_history(current_metadata, work_resolution) do
    current_metadata
    |> Map.get("work_resolution_history", [])
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Kernel.++([work_resolution])
    |> Enum.take(-10)
  end

  defp intake_handoff_history(current_metadata, %{} = intake_handoff) do
    current_metadata
    |> Map.get("intake_handoff_history", [])
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Kernel.++([intake_handoff])
    |> Enum.take(-10)
  end

  defp intake_handoff_history(_current_metadata, _intake_handoff), do: nil

  defp maybe_update_steering_metadata(metadata, "turn.steer", resolved_at, instruction, steering_entry) do
    metadata
    |> Map.put("last_steer_command", "turn.steer")
    |> Map.put("last_steered_at", resolved_at)
    |> maybe_put("last_steer_instruction", instruction)
    |> Map.put("steering_history", steering_history(metadata, steering_entry))
  end

  defp maybe_update_steering_metadata(metadata, _resolution_command, _resolved_at, _instruction, _entry),
    do: metadata

  defp normalize_work_resolution_action(work_action, work_item_id, attachment_mode, scope) do
    cond do
      is_atom(work_action) ->
        Atom.to_string(work_action)

      is_binary(work_item_id) and attachment_mode == :synthesized_work_item ->
        "created"

      is_binary(work_item_id) ->
        "attached"

      scope == :repo_scoped ->
        "repo_scoped"

      true ->
        "attached"
    end
  end

  defp work_resolution_detail(work_action, work_item_id, attachment_mode, scope, workflow_name, payload) do
    optional_string(payload, :resolution_reason) ||
      cond do
        is_binary(work_item_id) and attachment_mode == :synthesized_work_item ->
          "Created governed #{workflow_label(workflow_name)} work item #{work_item_id} for conversation execution."

        is_binary(work_item_id) and is_atom(work_action) ->
          "Updated governed work item #{work_item_id} through conversation work resolution."

        is_binary(work_item_id) ->
          "Attached conversation work to governed work item #{work_item_id}."

        scope == :repo_scoped ->
          "The conversation remains exploratory and repo-scoped."

        true ->
          "Conversation work resolution completed."
      end
  end

  defp repo_intake_handoff(
         %Conversation{scope: :repo_scoped, attachment_mode: :pre_work} = conversation,
         work_item_id,
         attachment_mode,
         :work_item_scoped,
         workflow_name,
         resolution_command,
         payload,
         resolved_at
       )
       when is_binary(work_item_id) do
    %{
      "handoff_kind" => "repo_intake_to_work_item",
      "conversation_id" => conversation.id,
      "from_scope" => "repo_scoped",
      "from_attachment_mode" => "pre_work",
      "to_scope" => "work_item_scoped",
      "to_attachment_mode" => Atom.to_string(attachment_mode),
      "work_item_id" => work_item_id,
      "workflow" => workflow_name,
      "command" => resolution_command,
      "at" => resolved_at
    }
    |> maybe_put("turn_id", optional_string(payload, :turn_id))
    |> maybe_put("command_id", optional_string(payload, :command_id))
    |> maybe_put("reason", optional_string(payload, :resolution_reason))
  end

  defp repo_intake_handoff(
         _conversation,
         _work_item_id,
         _attachment_mode,
         _scope,
         _workflow_name,
         _resolution_command,
         _payload,
         _resolved_at
       ),
       do: nil

  defp workflow_label("plan"), do: "planning"
  defp workflow_label("execute"), do: "implementation"
  defp workflow_label("review"), do: "review"
  defp workflow_label("explain"), do: "follow-up"
  defp workflow_label(_workflow_name), do: "governed"

  defp shared_context_summary(shared_context) do
    %{
      "referenced_file_count" =>
        shared_context
        |> Map.get("referenced_files", [])
        |> List.wrap()
        |> length(),
      "accepted_tool_result_count" =>
        shared_context
        |> Map.get("accepted_tool_results", [])
        |> List.wrap()
        |> length(),
      "pending_clarification" => is_map(Map.get(shared_context, "pending_clarification"))
    }
  end

  defp steering_attachment_mode(conversation, work_item_id) do
    if conversation.work_item_id == work_item_id and
         conversation.attachment_mode in [:existing_work_item, :synthesized_work_item] do
      conversation.attachment_mode
    else
      :existing_work_item
    end
  end

  defp normalize_steering_attach_mode(:synthesized_work_item, _requested_work_item_id, _conversation),
    do: :synthesized_work_item

  defp normalize_steering_attach_mode("synthesized_work_item", _requested_work_item_id, _conversation),
    do: :synthesized_work_item

  defp normalize_steering_attach_mode(_attach_mode, requested_work_item_id, _conversation)
       when is_binary(requested_work_item_id),
       do: :existing_work_item

  defp normalize_steering_attach_mode(_attach_mode, _requested_work_item_id, %Conversation{work_item_id: work_item_id})
       when is_binary(work_item_id),
       do: :existing_work_item

  defp normalize_steering_attach_mode(_attach_mode, _requested_work_item_id, _conversation), do: :pre_work

  defp validate_work_item_open(%WorkItem{status: status}) when status in @resumable_work_item_statuses,
    do: :ok

  defp validate_work_item_open(%WorkItem{}), do: {:error, :work_item_not_open}

  defp maybe_reconcile_terminal_work_item(%WorkItem{status: status}, nil, _actor)
       when is_map_key(@terminal_work_item_conversation_statuses, status) do
    {:ok, nil, nil}
  end

  defp maybe_reconcile_terminal_work_item(%WorkItem{status: status} = work_item, %Conversation{} = conversation, actor)
       when is_map_key(@terminal_work_item_conversation_statuses, status) do
    settle_terminal_work_item_conversation(work_item, conversation, actor)
  end

  defp maybe_reconcile_terminal_work_item(%WorkItem{}, %Conversation{} = conversation, _actor),
    do: {:ok, nil, conversation}

  defp maybe_reconcile_terminal_work_item(%WorkItem{}, nil, _actor), do: {:ok, nil, nil}

  defp settle_terminal_work_item_conversation(%WorkItem{status: status}, %Conversation{} = conversation, actor) do
    target_status = Map.fetch!(@terminal_work_item_conversation_statuses, status)

    case fetch_idle_snapshot(conversation) do
      {:ok, snapshot} ->
        if snapshot_idle?(snapshot) do
          finalized_conversation =
            finalize_work_item_conversation(conversation, target_status, status, actor)

          case finalized_conversation do
            {:ok, %Conversation{} = updated_conversation} ->
              terminal_snapshot =
                snapshot
                |> Map.put(:status, target_status)
                |> Map.put(:admission_paused, false)
                |> Map.put(:child_execution_paused, false)
                |> Map.put(:active_turn_id, nil)
                |> Map.put(:active_turn, nil)
                |> Map.put(:active_child_work_id, nil)
                |> Map.put(:active_child_work, nil)
                |> Map.put(:queued_turn_ids, [])
                |> Map.put(:work_item_id, updated_conversation.work_item_id)
                |> Map.put(:scope, updated_conversation.scope)
                |> Map.put(:attachment_mode, updated_conversation.attachment_mode)
                |> Map.put(:shared_context, terminal_shared_context(snapshot, updated_conversation))

              _ = Persistence.persist_snapshot(terminal_snapshot)
              :ok = Driver.stop(updated_conversation.id)
              {:ok, updated_conversation, nil}

            {:error, reason} ->
              {:error, reason}
          end
        else
          {:ok, nil, conversation}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_idle_snapshot(%Conversation{} = conversation) do
    case Driver.snapshot(conversation.id) do
      {:ok, snapshot} ->
        {:ok, snapshot}

      {:error, :conversation_snapshot_not_found} ->
        {:ok, Snapshot.empty(conversation)}

      {:error, reason} ->
        if snapshot_not_found?(reason) do
          {:ok, Snapshot.empty(conversation)}
        else
          {:error, reason}
        end
    end
  end

  defp snapshot_not_found?(%Ash.Error.Invalid{errors: errors}) when is_list(errors) do
    Enum.any?(errors, &snapshot_not_found?/1)
  end

  defp snapshot_not_found?(%Ash.Error.Query.NotFound{}), do: true
  defp snapshot_not_found?(_reason), do: false

  defp snapshot_idle?(snapshot) when is_map(snapshot) do
    active_turn_id = map_get(snapshot, :active_turn_id)
    active_child_work_id = map_get(snapshot, :active_child_work_id)
    queued_turn_ids = map_get(snapshot, :queued_turn_ids) || []

    is_nil(optional_string(active_turn_id)) and is_nil(optional_string(active_child_work_id)) and
      List.wrap(queued_turn_ids) == []
  end

  defp snapshot_idle?(_snapshot), do: false

  defp finalize_work_item_conversation(
         %Conversation{} = conversation,
         target_status,
         work_item_status,
         actor
       ) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    metadata = terminal_lifecycle_metadata(conversation, target_status, work_item_status, now)

    Conversation.update(
      conversation,
      %{
        status: target_status,
        conversation_metadata: metadata,
        last_activity_at: now
      },
      actor: actor
    )
  end

  defp terminal_lifecycle_metadata(%Conversation{} = conversation, target_status, work_item_status, now) do
    metadata = normalize_map(conversation.conversation_metadata)
    settled_at = DateTime.to_iso8601(now)

    settlement_entry = %{
      "at" => settled_at,
      "conversation_status" => Atom.to_string(target_status),
      "work_item_status" => Atom.to_string(work_item_status)
    }

    metadata
    |> Map.put("last_work_item_status", Atom.to_string(work_item_status))
    |> Map.put("last_conversation_settlement", settlement_entry)
    |> Map.put(
      "conversation_settlement_history",
      conversation_settlement_history(metadata, settlement_entry)
    )
  end

  defp conversation_settlement_history(metadata, settlement_entry) do
    metadata
    |> Map.get("conversation_settlement_history", [])
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Kernel.++([settlement_entry])
    |> Enum.take(-10)
  end

  defp terminal_shared_context(snapshot, %Conversation{} = conversation) when is_map(snapshot) do
    snapshot
    |> map_get(:shared_context)
    |> normalize_map()
    |> Map.put("work_item_id", conversation.work_item_id)
    |> Map.put("scope", Atom.to_string(conversation.scope))
    |> Map.put("attachment_mode", Atom.to_string(conversation.attachment_mode))
    |> Map.put("work_resolution", Snapshot.empty(conversation).shared_context["work_resolution"])
  end

  defp terminal_shared_context(_snapshot, %Conversation{} = conversation),
    do: Snapshot.empty(conversation).shared_context

  defp start_or_recover_work_item_conversation(%WorkItem{} = work_item, attrs, actor) do
    start_attrs =
      attrs
      |> Map.put("managed_repo_id", work_item.managed_repo_id)
      |> Map.put("work_item_id", work_item.id)
      |> Map.put("actor", actor)
      |> Map.put_new("attach_mode", "existing_work_item")
      |> Map.put_new("source", "work_item_conversation")
      |> Map.put_new("objective", work_item.summary)
      |> Map.put("source_metadata", work_item_source_metadata(attrs, work_item))

    case start(start_attrs) do
      {:ok, %{conversation: %Conversation{} = conversation, work_item: %WorkItem{} = attached_work_item}} ->
        {:ok, %{conversation: conversation, work_item: attached_work_item, resumed?: false}}

      {:error, reason} ->
        recover_active_work_item_conversation(reason, work_item, actor)
    end
  end

  defp recover_active_work_item_conversation(reason, %WorkItem{} = work_item, actor) do
    case active_for_work_item(work_item.id, actor: actor) do
      {:ok, %Conversation{} = conversation} ->
        with {:ok, resumed} <- resume(conversation.id, actor: actor) do
          {:ok, %{conversation: resumed, work_item: work_item, resumed?: true}}
        end

      _other ->
        {:error, reason}
    end
  end

  defp work_item_source_metadata(attrs, %WorkItem{} = work_item) do
    source_metadata =
      case attrs do
        %{} ->
          Map.get(attrs, :source_metadata) || Map.get(attrs, "source_metadata") || %{}

        _other ->
          %{}
      end

    source_metadata
    |> normalize_map()
    |> Map.put_new("entry_surface", "work_item")
    |> Map.put_new("channel", "work_item_detail")
    |> Map.put_new("work_item_conversation", true)
    |> Map.put_new("work_item_id", work_item.id)
  end

  defp conversation_attrs(context) do
    %{
      managed_repo_id: context.managed_repo_id,
      work_item_id: optional_id(context.work_item),
      status: :active,
      scope: context.scope,
      attachment_mode: context.attachment_mode,
      source: context.source,
      title: context.title,
      objective: context.objective,
      initiating_actor: context.actor,
      source_metadata: context.source_metadata,
      conversation_metadata: context.conversation_metadata,
      started_at: context.started_at,
      last_activity_at: context.last_activity_at
    }
  end

  defp fetch_conversation(conversation_id, actor) do
    case Conversation.read(query: [filter: [id: conversation_id], limit: 1], actor: actor) do
      {:ok, [%Conversation{} = conversation | _rest]} -> {:ok, conversation}
      {:ok, []} -> {:error, :conversation_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_work_item(work_item_id, actor) do
    case WorkItem.read(query: [filter: [id: work_item_id], limit: 1], actor: actor) do
      {:ok, [%WorkItem{} = work_item | _rest]} -> {:ok, work_item}
      {:ok, []} -> {:error, :work_item_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_managed_repo_scope(nil, _resolved_managed_repo_id), do: :ok

  defp validate_managed_repo_scope(managed_repo_id, resolved_managed_repo_id)
       when managed_repo_id == resolved_managed_repo_id,
       do: :ok

  defp validate_managed_repo_scope(_managed_repo_id, _resolved_managed_repo_id),
    do: {:error, :managed_repo_scope_mismatch}

  defp normalize_attach_mode(nil, work_item_id) when is_binary(work_item_id), do: :existing_work_item
  defp normalize_attach_mode(nil, _work_item_id), do: :pre_work
  defp normalize_attach_mode(:existing_work_item, _work_item_id), do: :existing_work_item
  defp normalize_attach_mode("existing_work_item", _work_item_id), do: :existing_work_item
  defp normalize_attach_mode(:synthesized_work_item, _work_item_id), do: :synthesized_work_item
  defp normalize_attach_mode("synthesized_work_item", _work_item_id), do: :synthesized_work_item
  defp normalize_attach_mode(:pre_work, _work_item_id), do: :pre_work
  defp normalize_attach_mode("pre_work", _work_item_id), do: :pre_work
  defp normalize_attach_mode(_other, work_item_id), do: normalize_attach_mode(nil, work_item_id)

  defp normalize_actor(nil), do: Actor.operator_actor()

  defp normalize_actor(%{} = actor) do
    actor
    |> stringify_keys()
    |> Actor.operator_actor()
  end

  defp validate_required_string(value, _field_name) when is_binary(value) and value != "", do: {:ok, value}
  defp validate_required_string(_value, field_name), do: {:error, {:missing_required_field, field_name}}

  defp required_string(attrs, key) do
    attrs
    |> map_get(key)
    |> optional_string()
  end

  defp optional_string(attrs, key) when is_map(attrs) do
    attrs
    |> map_get(key)
    |> optional_string()
  end

  defp optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp optional_string(nil), do: nil
  defp optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> optional_string()
  defp optional_string(_value), do: nil

  defp normalize_map(value) when is_map(value), do: stringify_keys(value)
  defp normalize_map(_value), do: %{}

  defp stringify_keys(value) when is_map(value) and not is_struct(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      Map.put(acc, normalized_key, stringify_nested_value(nested_value))
    end)
  end

  defp stringify_keys(_value), do: %{}

  defp stringify_nested_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp stringify_nested_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp stringify_nested_value(%Date{} = value), do: Date.to_iso8601(value)
  defp stringify_nested_value(%Time{} = value), do: Time.to_iso8601(value)
  defp stringify_nested_value(value) when is_struct(value), do: value |> Map.from_struct() |> stringify_keys()
  defp stringify_nested_value(value) when is_map(value), do: stringify_keys(value)
  defp stringify_nested_value(value) when is_list(value), do: Enum.map(value, &stringify_nested_value/1)
  defp stringify_nested_value(value), do: value

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp optional_id(nil), do: nil
  defp optional_id(%{id: id}), do: id

  defp map_get(map, atom_key) when is_map(map) do
    string_key = Atom.to_string(atom_key)

    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> nil
    end
  end
end
