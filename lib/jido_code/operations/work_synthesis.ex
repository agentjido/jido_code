defmodule JidoCode.Operations.WorkSynthesis do
  # covers: architecture.work_synthesis.work_item_is_canonical_operational_record
  # covers: architecture.work_synthesis.work_item_metadata_and_origin_links_preserved
  # covers: architecture.work_synthesis.work_item_creation_can_stop_before_execution
  # covers: architecture.work_synthesis.work_item_reprioritization_and_duplicate_suppression
  # covers: architecture.work_synthesis.work_item_auditability_preserved
  @moduledoc """
  Creates or reconciles durable work items from synthesized assessments.
  """

  alias JidoCode.Control.Actor
  alias JidoCode.Operations.{Assessment, Event, ExternalObject, Intake, Observation, WorkItem}

  @work_actor Actor.factory_system_actor(%{
                "id" => "system:work-synthesis",
                "email" => "work-synthesis@system.local"
              })

  @spec from_assessment(Assessment.t(), keyword()) ::
          {:ok,
           %{
             work_item: WorkItem.t() | nil,
             action: :created | :reprioritized | :suppressed_duplicate | :steered | :unscoped
           }}
          | {:error, term()}
  def from_assessment(%Assessment{} = assessment, opts \\ []) do
    with {:ok, %Event{} = event} <- resolve_event(assessment, opts),
         {:ok, context} <- build_context(assessment, event, opts) do
      case context.managed_repo_id do
        nil ->
          {:ok, %{work_item: nil, action: :unscoped}}

        _managed_repo_id ->
          reconcile_work_item(context)
      end
    end
  end

  defp resolve_event(assessment, opts) do
    case Keyword.get(opts, :event) do
      %Event{} = event ->
        {:ok, event}

      _other ->
        case Event.read(query: [filter: [id: assessment.event_id], limit: 1], actor: @work_actor) do
          {:ok, [%Event{} = event | _rest]} -> {:ok, event}
          {:ok, []} -> {:error, :event_not_found}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp build_context(assessment, event, opts) do
    external_object =
      resolve_optional_record(opts, :external_object, ExternalObject, event.external_object_id)

    observation =
      resolve_optional_record(opts, :observation, Observation, event.observation_id)

    intake =
      resolve_optional_record(opts, :intake, Intake, event.intake_id)

    {:ok,
     %{
       assessment: assessment,
       event: event,
       external_object: external_object,
       observation: observation,
       intake: intake,
       target_work_item: steering_target_work_item(intake, assessment.managed_repo_id || event.managed_repo_id),
       managed_repo_id: assessment.managed_repo_id || event.managed_repo_id,
       category: assessment.category,
       priority: assessment.priority,
       recommended_action: assessment.recommended_action,
       summary: work_summary(assessment, external_object, intake),
       dedup_key: work_dedup_key(assessment, event, external_object, intake),
       initiating_actor: normalize_map(initiating_actor(observation, intake) || %{}),
       work_metadata: work_metadata(assessment, event, external_object, observation, intake)
     }}
  end

  defp reconcile_work_item(context) do
    case context.target_work_item do
      %WorkItem{} = work_item ->
        steer_existing_work_item(work_item, context)

      _other ->
        case find_open_work_item(context.managed_repo_id, context.dedup_key) do
          {:ok, nil} ->
            create_work_item(context)

          {:ok, %WorkItem{} = work_item} ->
            update_existing_work_item(work_item, context)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp create_work_item(context) do
    attrs = %{
      managed_repo_id: context.managed_repo_id,
      assessment_id: context.assessment.id,
      event_id: context.event.id,
      external_object_id: optional_id(context.external_object),
      observation_id: optional_id(context.observation),
      intake_id: optional_id(context.intake),
      category: context.category,
      status: :open,
      priority: context.priority,
      recommended_action: context.recommended_action,
      summary: context.summary,
      dedup_key: context.dedup_key,
      initiating_actor: context.initiating_actor,
      work_metadata: context.work_metadata,
      audit_log: [audit_entry("created", "Created work item from synthesized assessment.", context)],
      opened_at: context.assessment.assessed_at,
      last_assessed_at: context.assessment.assessed_at
    }

    with {:ok, work_item} <- WorkItem.create(attrs, actor: @work_actor) do
      {:ok, %{work_item: work_item, action: :created}}
    end
  end

  defp update_existing_work_item(work_item, context) do
    next_action = existing_work_action(work_item, context)
    do_update_work_item(work_item, context, next_action)
  end

  defp steer_existing_work_item(work_item, context) do
    do_update_work_item(work_item, context, :steered)
  end

  defp do_update_work_item(work_item, context, next_action) do
    attrs = %{
      assessment_id: context.assessment.id,
      event_id: context.event.id,
      external_object_id: optional_id(context.external_object),
      observation_id: optional_id(context.observation),
      intake_id: optional_id(context.intake),
      category: context.category,
      priority: highest_priority(work_item.priority, context.priority),
      recommended_action: context.recommended_action,
      summary: context.summary,
      initiating_actor: context.initiating_actor,
      work_metadata: context.work_metadata,
      audit_log:
        work_item.audit_log
        |> List.wrap()
        |> Kernel.++([audit_entry(Atom.to_string(next_action), audit_reason(next_action), context)]),
      last_assessed_at: context.assessment.assessed_at
    }

    with {:ok, updated_work_item} <- WorkItem.update(work_item, attrs, actor: @work_actor) do
      {:ok, %{work_item: updated_work_item, action: next_action}}
    end
  end

  defp existing_work_action(work_item, context) do
    if priority_rank(context.priority) < priority_rank(work_item.priority) do
      :reprioritized
    else
      :suppressed_duplicate
    end
  end

  defp audit_reason(:reprioritized),
    do: "Merged equivalent work demand and raised priority from fresher assessment data."

  defp audit_reason(:steered),
    do: "Normalized demand updated an existing work item through the managed-repository control loop."

  defp audit_reason(:suppressed_duplicate),
    do: "Suppressed equivalent duplicate work demand and refreshed existing work context."

  defp find_open_work_item(managed_repo_id, dedup_key) do
    case WorkItem.read(
           query: [filter: [managed_repo_id: managed_repo_id, dedup_key: dedup_key, status: :open], limit: 1],
           actor: @work_actor
         ) do
      {:ok, [%WorkItem{} = work_item | _rest]} -> {:ok, work_item}
      {:ok, []} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp work_dedup_key(assessment, event, external_object, intake) do
    case {external_object, intake} do
      {%ExternalObject{} = external_object, _intake} ->
        [
          assessment.managed_repo_id || event.managed_repo_id,
          assessment.recommended_action,
          external_object.canonical_key
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(":")

      {nil, %Intake{} = intake} ->
        [
          assessment.managed_repo_id || event.managed_repo_id,
          assessment.recommended_action,
          requested_workflow_name(intake) || intake.channel,
          context_item_type(intake) || intake.intent
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(":")

      _other ->
        [assessment.managed_repo_id || event.managed_repo_id, assessment.recommended_action, event.category]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(":")
    end
  end

  defp work_summary(assessment, external_object, intake) do
    case {assessment.recommended_action, external_object, intake} do
      {"triage_issue", %ExternalObject{} = external_object, _intake} ->
        "Triage #{external_object.canonical_reference || external_object.canonical_key}."

      {"review_pull_request_signal", %ExternalObject{} = external_object, _intake} ->
        "Review pull request signal for #{external_object.canonical_reference || external_object.canonical_key}."

      {"prepare_managed_repo", _external_object, _intake} ->
        "Prepare managed repository for imported project demand."

      {"launch_fix_workflow", _external_object, _intake} ->
        "Queue fix workflow demand for the managed repository."

      {"launch_issue_triage_workflow", _external_object, _intake} ->
        "Queue issue triage demand for the managed repository."

      {"steer_existing_work_item", _external_object, %Intake{} = intake} ->
        work_item_id =
          intake.payload
          |> map_get("work_item_id", :work_item_id)
          |> normalize_optional_string()

        "Steer existing work item #{work_item_id || "for the managed repository"} through normalized demand."

      {recommended_action, _external_object, _intake} ->
        humanized_action = recommended_action |> to_string() |> String.replace("_", " ")
        "Queue #{humanized_action} work for the managed repository."
    end
  end

  defp work_metadata(assessment, event, external_object, observation, intake) do
    %{
      "assessment_id" => assessment.id,
      "event_id" => event.id,
      "event_category" => event.category,
      "assessment_category" => assessment.category,
      "source_record_type" => source_record_type(observation, intake),
      "recommended_action" => assessment.recommended_action
    }
    |> maybe_put("external_object_id", optional_id(external_object))
    |> maybe_put("external_reference", external_reference(external_object))
    |> maybe_put("observation_id", optional_id(observation))
    |> maybe_put("intake_id", optional_id(intake))
    |> maybe_put("conversation_origin", conversation_origin(intake))
  end

  defp conversation_origin(%Intake{} = intake) do
    source_metadata = normalize_map(intake.source_metadata)

    context_item =
      intake.payload
      |> map_get("context_item", :context_item, %{})
      |> normalize_map()

    if intake.channel == "conversation" or truthy?(source_metadata["conversation_entry"]) do
      %{
        "conversation_id" =>
          normalize_optional_string(source_metadata["conversation_id"] || context_item["conversation_id"]),
        "turn_id" =>
          normalize_optional_string(
            source_metadata["conversation_turn_id"] ||
              context_item["conversation_turn_id"] ||
              intake.payload |> map_get(:turn_id, "turn_id")
          ),
        "command_id" =>
          normalize_optional_string(
            source_metadata["conversation_command_id"] ||
              context_item["conversation_command_id"] ||
              intake.payload |> map_get(:command_id, "command_id")
          ),
        "workflow" =>
          normalize_optional_string(
            source_metadata["conversation_workflow"] ||
              context_item["workflow"] ||
              intake.payload |> map_get(:workflow_name, "workflow_name")
          ),
        "scope" =>
          normalize_optional_string(
            source_metadata["conversation_scope"] || context_item["conversation_scope"]
          ),
        "attachment_mode" =>
          normalize_optional_string(
            source_metadata["conversation_attachment_mode"] || context_item["attachment_mode"]
          ),
        "resolution_reason" =>
          normalize_optional_string(
            source_metadata["conversation_resolution_reason"] ||
              intake.payload |> map_get(:resolution_reason, "resolution_reason")
          )
      }
      |> reject_nil_values()
      |> case do
        origin when map_size(origin) == 0 -> nil
        origin -> origin
      end
    else
      nil
    end
  end

  defp conversation_origin(_intake), do: nil

  defp source_record_type(%Observation{}, _intake), do: "observation"
  defp source_record_type(_observation, %Intake{}), do: "intake"
  defp source_record_type(_observation, _intake), do: "event"

  defp audit_entry(action, reason, context) do
    %{
      "action" => action,
      "reason" => reason,
      "at" => DateTime.to_iso8601(DateTime.utc_now() |> DateTime.truncate(:second)),
      "assessment_id" => context.assessment.id,
      "event_id" => context.event.id,
      "priority" => to_string(context.priority)
    }
  end

  defp highest_priority(existing, incoming) do
    if priority_rank(incoming) < priority_rank(existing), do: incoming, else: existing
  end

  defp priority_rank(:critical), do: 0
  defp priority_rank(:high), do: 1
  defp priority_rank(:medium), do: 2
  defp priority_rank(:low), do: 3
  defp priority_rank(_other), do: 99

  defp requested_workflow_name(%Intake{} = intake) do
    intake.payload
    |> map_get("workflow_name", :workflow_name)
    |> normalize_optional_string()
  end

  defp context_item_type(%Intake{} = intake) do
    intake.payload
    |> map_get("context_item", :context_item, %{})
    |> map_get("type", :type)
    |> normalize_optional_string()
  end

  defp initiating_actor(%Observation{} = observation, _intake), do: observation.captured_by
  defp initiating_actor(_observation, %Intake{} = intake), do: intake.requested_by
  defp initiating_actor(_observation, _intake), do: %{}

  defp external_reference(%ExternalObject{} = external_object),
    do: normalize_optional_string(external_object.canonical_reference || external_object.canonical_key)

  defp external_reference(_external_object), do: nil

  defp optional_id(%{id: id}), do: id
  defp optional_id(_record), do: nil

  defp resolve_optional_record(opts, key, module, id) do
    case Keyword.get(opts, key) do
      %^module{} = record ->
        record

      _other ->
        read_optional_record(module, id)
    end
  end

  defp read_optional_record(_module, nil), do: nil

  defp read_optional_record(module, id) do
    case module.read(query: [filter: [id: id], limit: 1], actor: @work_actor) do
      {:ok, [record | _rest]} -> record
      _other -> nil
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp steering_target_work_item(%Intake{} = intake, managed_repo_id) when is_binary(managed_repo_id) do
    work_item_id =
      intake.payload
      |> map_get("work_item_id", :work_item_id)
      |> normalize_optional_string()

    case work_item_id do
      nil ->
        nil

      normalized_work_item_id ->
        case WorkItem.read(
               query: [
                 filter: [id: normalized_work_item_id, managed_repo_id: managed_repo_id, status: :open],
                 limit: 1
               ],
               actor: @work_actor
             ) do
          {:ok, [%WorkItem{} = work_item | _rest]} -> work_item
          _other -> nil
        end
    end
  end

  defp steering_target_work_item(_intake, _managed_repo_id), do: nil

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(%{} = map, atom_key, string_key, default) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      normalized_value =
        case nested_value do
          nested when is_map(nested) -> normalize_map(nested)
          other -> other
        end

      Map.put(acc, normalized_key, normalized_value)
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?("TRUE"), do: true
  defp truthy?("1"), do: true
  defp truthy?(1), do: true
  defp truthy?(_value), do: false

  defp reject_nil_values(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end
end
