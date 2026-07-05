defmodule JidoCode.Operations.Synthesis do
  # covers: architecture.event_assessment_synthesis.event_records_derived_from_ingress
  # covers: architecture.event_assessment_synthesis.event_categories_and_repo_correlation_preserved
  # covers: architecture.event_assessment_synthesis.assessment_records_interpret_events
  # covers: architecture.event_assessment_synthesis.assessment_priority_and_next_action
  # covers: architecture.event_assessment_synthesis.assessment_space_for_future_inputs
  # covers: architecture.event_assessment_synthesis.repo_native_state_informs_assessment_inputs
  # covers: architecture.event_assessment_synthesis.correlation_prefers_persisted_requested_by_actor_identity
  # covers: architecture.work_synthesis.work_item_audit_can_fall_back_to_persisted_ingress_actor_identity
  @moduledoc """
  Derives durable control-plane events and assessments from normalized ingress records.
  """

  alias JidoCode.Control.Actor
  alias JidoCode.Operations.RepoNativeState
  alias JidoCode.Operations.{Assessment, Event, ExternalObject, Intake, Observation, RecordStore, WorkSynthesis}

  @synthesis_actor Actor.factory_system_actor(%{
                     "id" => "system:ingress-synthesis",
                     "email" => "ingress-synthesis@system.local"
                   })

  @spec from_observation(Observation.t(), keyword()) ::
          {:ok,
           %{
             event: Event.t(),
             assessment: Assessment.t(),
             work_item: JidoCode.Operations.WorkItem.t() | nil,
             work_action: :created | :reprioritized | :suppressed_duplicate | :steered | :unscoped
           }}
          | {:error, term()}
  def from_observation(%Observation{} = observation, opts \\ []) do
    external_object = Keyword.get(opts, :external_object)
    event_attrs = event_attrs_from_observation(observation, external_object)

    with {:ok, event} <- RecordStore.create(:event, event_attrs, actor: @synthesis_actor),
         {:ok, assessment} <-
           RecordStore.create(
             :assessment,
             assessment_attrs_from_observation(observation, event, external_object),
             actor: @synthesis_actor
           ),
         {:ok, %{work_item: work_item, action: work_action}} <-
           WorkSynthesis.from_assessment(
             assessment,
             event: event,
             observation: observation,
             external_object: external_object
           ) do
      {:ok, %{event: event, assessment: assessment, work_item: work_item, work_action: work_action}}
    end
  end

  @spec from_intake(Intake.t()) ::
          {:ok,
           %{
             event: Event.t(),
             assessment: Assessment.t(),
             work_item: JidoCode.Operations.WorkItem.t() | nil,
             work_action: :created | :reprioritized | :suppressed_duplicate | :steered | :unscoped
           }}
          | {:error, term()}
  def from_intake(%Intake{} = intake) do
    event_attrs = event_attrs_from_intake(intake)

    with {:ok, event} <- RecordStore.create(:event, event_attrs, actor: @synthesis_actor),
         {:ok, assessment} <-
           RecordStore.create(:assessment, assessment_attrs_from_intake(intake, event), actor: @synthesis_actor),
         {:ok, %{work_item: work_item, action: work_action}} <-
           WorkSynthesis.from_assessment(assessment, event: event, intake: intake) do
      {:ok, %{event: event, assessment: assessment, work_item: work_item, work_action: work_action}}
    end
  end

  defp event_attrs_from_observation(observation, external_object) do
    action =
      observation.payload
      |> map_get("action", :action)
      |> normalize_optional_string()

    category =
      case external_object_type(external_object) do
        :github_issue -> "external.github.issue.#{action || "observed"}"
        :github_pull_request -> "external.github.pull_request.#{action || "observed"}"
        :github_repository -> "external.github.repository.#{action || "observed"}"
        _other -> "external.#{normalize_token(observation.source)}.#{normalize_token(observation.category)}"
      end

    %{
      managed_repo_id: observation.managed_repo_id,
      external_object_id: external_object_id(external_object) || observation.external_object_id,
      observation_id: observation.id,
      category: category,
      summary: observation.summary,
      correlation_key: observation_correlation_key(observation, external_object, action),
      payload: %{
        "observation_id" => observation.id,
        "payload" => observation.payload
      },
      source_metadata:
        observation.source_metadata
        |> normalize_map()
        |> Map.put("source_record_type", "observation")
        |> Map.put("source_record_id", observation.id)
    }
  end

  defp assessment_attrs_from_observation(observation, event, external_object) do
    action =
      observation.payload
      |> map_get("action", :action)
      |> normalize_optional_string()

    {category, priority, urgency, recommended_action, rationale} =
      case external_object_type(external_object) do
        :github_issue ->
          {"github_issue_demand", :high, urgency_for_issue_action(action), "triage_issue",
           "Verified GitHub issue demand entered the control plane through normalized observation."}

        :github_pull_request ->
          {"github_pull_request_demand", :medium, :medium, "review_pull_request_signal",
           "Verified GitHub pull-request demand entered the control plane through normalized observation."}

        :github_repository ->
          {"github_repository_signal", :low, :low, "review_repository_signal",
           "Verified repository-level GitHub demand entered the control plane through normalized observation."}

        _other ->
          {"external_signal", :medium, :medium, "review_external_signal",
           "Normalized external demand entered the control plane through observation."}
      end

    repo_native_state = repo_native_inputs(observation.managed_repo_id)

    %{
      managed_repo_id: observation.managed_repo_id,
      event_id: event.id,
      external_object_id: external_object_id(external_object) || observation.external_object_id,
      category: category,
      summary: "Assess #{event.category} for downstream work synthesis.",
      priority: priority,
      urgency: urgency,
      recommended_action: recommended_action,
      rationale: rationale,
      inputs: %{
        "event_category" => event.category,
        "observation_id" => observation.id,
        "observation_source" => observation.source,
        "repo_native_state" => repo_native_state
      },
      assessment_metadata:
        observation.source_metadata
        |> normalize_map()
        |> Map.put("assessment_origin", "observation")
        |> maybe_put("external_reference", external_reference(external_object))
    }
  end

  defp event_attrs_from_intake(intake) do
    category = intake_event_category(intake)

    %{
      managed_repo_id: intake.managed_repo_id,
      intake_id: intake.id,
      category: category,
      summary: intake_event_summary(intake),
      correlation_key: intake_correlation_key(intake, category),
      payload: %{
        "intake_id" => intake.id,
        "payload" => intake.payload
      },
      source_metadata:
        intake.source_metadata
        |> normalize_map()
        |> Map.put("source_record_type", "intake")
        |> Map.put("source_record_id", intake.id)
    }
  end

  defp assessment_attrs_from_intake(intake, event) do
    {category, priority, urgency, recommended_action, rationale} =
      intake_assessment_profile(intake)

    repo_native_state = repo_native_inputs(intake.managed_repo_id)
    requested_by_actor_id = requested_by_actor_id(intake)

    %{
      managed_repo_id: intake.managed_repo_id,
      event_id: event.id,
      category: category,
      summary: "Assess #{event.category} for downstream work synthesis.",
      priority: priority,
      urgency: urgency,
      recommended_action: recommended_action,
      rationale: rationale,
      inputs: %{
        "event_category" => event.category,
        "intake_id" => intake.id,
        "channel" => intake.channel,
        "intent" => intake.intent,
        "repo_native_state" => repo_native_state
      },
      assessment_metadata:
        intake.source_metadata
        |> normalize_map()
        |> Map.put("assessment_origin", "intake")
        |> maybe_put("requested_by_actor_id", requested_by_actor_id)
    }
  end

  defp observation_correlation_key(observation, external_object, action) do
    cond do
      is_binary(external_reference(external_object)) ->
        [external_reference(external_object), action || "observed"]
        |> Enum.join(":")

      is_binary(observation.external_object_id) ->
        [observation.external_object_id, action || "observed"]
        |> Enum.join(":")

      true ->
        [observation.managed_repo_id || "unscoped", "observation", observation.id]
        |> Enum.join(":")
    end
  end

  defp intake_correlation_key(intake, category) do
    actor_reference = requested_by_actor_id(intake) || actor_reference(intake, :email)

    [
      intake.managed_repo_id || "unscoped",
      category,
      actor_reference || "anonymous"
    ]
    |> Enum.join(":")
  end

  defp intake_event_category(intake) do
    channel = normalize_token(intake.channel)
    intent = normalize_token(intake.intent)
    "operator.#{channel}.#{intent}.requested"
  end

  defp intake_event_summary(intake) do
    channel = humanize_token(intake.channel)
    intent = humanize_token(intake.intent)
    "Operator requested #{intent} via #{channel}."
  end

  defp intake_assessment_profile(intake) do
    case {normalize_token(intake.channel), normalize_token(intake.intent), requested_workflow_name(intake)} do
      {"conversation", "conversation_steer_work", _workflow_name} ->
        {"operator_work_request", :high, :high, "steer_existing_work_item",
         "Conversation steering redirected governed work through the managed-repository control loop."}

      {"conversation", "conversation_work_kickoff", _workflow_name} ->
        {"operator_work_request", :medium, :medium, "review_operator_request",
         "Conversation demand promoted managed-repository work into the governed work loop."}

      {"setup", "project_import", _workflow_name} ->
        {"operator_setup_request", :high, :medium, "prepare_managed_repo",
         "Signed-in setup import requested durable repository preparation work."}

      {"workbench", "fix_workflow_kickoff", _workflow_name} ->
        {"operator_work_request", :high, :high, "launch_fix_workflow",
         "Workbench requested fix workflow launch for a managed repository."}

      {"workbench", "issue_triage_workflow_kickoff", _workflow_name} ->
        {"operator_work_request", :high, :high, "launch_issue_triage_workflow",
         "Workbench requested issue triage workflow launch for a managed repository."}

      {"project_detail", "project_detail_workflow_kickoff", "fix_failing_tests"} ->
        {"operator_work_request", :high, :high, "launch_fix_workflow",
         "Repo detail requested fix workflow launch for a managed repository."}

      {"project_detail", "project_detail_workflow_kickoff", "issue_triage"} ->
        {"operator_work_request", :high, :high, "launch_issue_triage_workflow",
         "Repo detail requested issue triage workflow launch for a managed repository."}

      {"project_detail", "project_detail_workflow_kickoff", _workflow_name} ->
        {"operator_work_request", :medium, :medium, "review_operator_request",
         "Repo detail requested managed-repository work that should be reviewed before execution."}

      _other ->
        {"operator_request", :medium, :medium, "review_operator_request",
         "Trusted operator demand entered the control plane through normalized intake."}
    end
  end

  defp requested_workflow_name(intake) do
    intake.payload
    |> map_get("workflow_name", :workflow_name)
    |> normalize_optional_string()
  end

  defp requested_by_actor_id(intake) do
    intake
    |> Map.get(:source_metadata, %{})
    |> normalize_map()
    |> Map.get("requested_by_actor_id")
    |> normalize_optional_string()
    |> Kernel.||(actor_reference(intake, :id))
  end

  defp actor_reference(intake, key) do
    intake
    |> Map.get(:requested_by, %{})
    |> normalize_map()
    |> Map.get(to_string(key))
    |> normalize_optional_string()
  end

  defp urgency_for_issue_action("opened"), do: :high
  defp urgency_for_issue_action("edited"), do: :medium
  defp urgency_for_issue_action("created"), do: :medium
  defp urgency_for_issue_action(_action), do: :medium

  defp external_reference(%ExternalObject{} = external_object),
    do: normalize_optional_string(external_object.canonical_reference || external_object.canonical_key)

  defp external_reference(_external_object), do: nil

  defp external_object_type(%ExternalObject{} = external_object), do: external_object.object_type
  defp external_object_type(_external_object), do: nil

  defp external_object_id(%ExternalObject{} = external_object), do: external_object.id
  defp external_object_id(_external_object), do: nil

  defp normalize_token(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil ->
        "unknown"

      normalized ->
        normalized
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9]+/u, "_")
        |> String.trim("_")
        |> case do
          "" -> "unknown"
          token -> token
        end
    end
  end

  defp humanize_token(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil -> "request"
      normalized -> normalized |> String.replace("_", " ") |> String.replace(".", " ")
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

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

  defp repo_native_inputs(nil), do: %{}

  defp repo_native_inputs(managed_repo_id) when is_binary(managed_repo_id) do
    case RepoNativeState.latest_signal_snapshot(managed_repo_id) do
      {:ok, snapshot} -> snapshot
      _other -> %{}
    end
  end

  defp repo_native_inputs(_managed_repo_id), do: %{}
end
