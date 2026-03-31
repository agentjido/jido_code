defmodule JidoCode.GitHub.WebhookPipeline do
  # covers: architecture.demand_ingress.entrypoint_policy_metadata_preserved
  # covers: architecture.demand_ingress.trusted_ingress_uses_explicit_actor_classes
  # covers: architecture.policy_layers.legacy_and_ingress_surfaces_require_explicit_actor_context
  @moduledoc """
  Routes verified webhook deliveries into downstream pipeline stages.
  """

  require Logger

  alias JidoCode.Agents.SupportAgentConfigs
  alias JidoCode.Control.Actor
  alias JidoCode.GitHub.Repo
  alias JidoCode.GitHub.WebhookDelivery
  alias JidoCode.Governance.PolicyBridge
  alias JidoCode.Operations.Ingress
  alias JidoCode.Orchestration.WorkflowRun
  alias JidoCode.Projects.Project
  alias JidoCode.Setup.GitHubInstallationSync

  @issue_triage_workflow_name "issue_triage"
  @issue_triage_workflow_version 1
  @issue_triage_webhook_opened_policy "issue_triage_webhook_opened"
  @issue_triage_webhook_retriage_policy "issue_triage_webhook_retriage"
  @issue_triage_webhook_follow_up_policy "issue_triage_webhook_follow_up"
  @issue_triage_workflow_trigger_events [
    "issues.opened",
    "issues.edited",
    "issue_comment.created"
  ]
  @approval_mode_auto_post "auto_post"
  @approval_mode_approval_required "approval_required"
  @default_issue_bot_approval_mode @approval_mode_approval_required
  @approval_policy_source "support_agent_config.github_issue_bot.approval_mode"
  @retriage_prior_issue_analysis_limit 25
  @issue_reference_input_name "issue_reference"
  @issue_triage_artifact_persistence_error_type "issue_triage_artifact_persistence_failed"
  @issue_triage_artifact_persistence_operation "persist_issue_triage_artifacts"
  @issue_triage_artifact_persistence_failed_step "persist_issue_triage_artifacts"
  @issue_triage_artifact_persistence_remediation """
  Restore Issue Bot artifact persistence health, then retry issue triage so run detail can capture full triage and response artifacts.
  """
  @webhook_actor Actor.external_ingress_actor(%{
                   "id" => "system:github-webhook",
                   "email" => "github-webhook@system.local"
                 })

  @type verified_delivery :: %{
          delivery_id: String.t() | nil,
          event: String.t() | nil,
          payload: map(),
          raw_payload: binary()
        }

  @type dispatch_decision :: :dispatch | :duplicate

  @spec route_verified_delivery(verified_delivery()) :: :ok | {:error, :verified_dispatch_failed}
  def route_verified_delivery(%{} = delivery) do
    with {:ok, dispatch_decision} <- persist_delivery_for_idempotency(delivery) do
      case dispatch_decision do
        :dispatch ->
          with :ok <- record_control_plane_ingress(delivery) do
            maybe_sync_installation_metadata(delivery)
            maybe_dispatch_configured_issue_bot_delivery(delivery)
          end

        :duplicate ->
          :ok
      end
    else
      {:error, reason} ->
        Logger.error(
          "github_webhook_delivery_persist_failed reason=#{inspect(reason)} delivery_id=#{log_value(Map.get(delivery, :delivery_id))} event=#{log_value(Map.get(delivery, :event))}"
        )

        {:error, :verified_dispatch_failed}
    end
  end

  defp record_control_plane_ingress(delivery) do
    case Ingress.record_github_webhook_delivery(delivery) do
      {:ok, _recorded} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "github_webhook_ingress_record_failed reason=#{inspect(reason)} delivery_id=#{log_value(Map.get(delivery, :delivery_id))} event=#{log_value(Map.get(delivery, :event))}"
        )

        {:error, :verified_dispatch_failed}
    end
  end

  @doc false
  @spec default_dispatcher(verified_delivery()) :: :ok
  def default_dispatcher(%{} = delivery) do
    Logger.info(
      "github_webhook_pipeline_handoff stage=idempotency stage_next=trigger_mapping delivery_id=#{log_value(Map.get(delivery, :delivery_id))} event=#{log_value(Map.get(delivery, :event))}"
    )

    :ok
  end

  @spec persist_delivery_for_idempotency(verified_delivery()) ::
          {:ok, dispatch_decision()} | {:error, term()}
  defp persist_delivery_for_idempotency(%{} = delivery) do
    with {:ok, delivery_id} <-
           normalize_required_string(Map.get(delivery, :delivery_id), :missing_delivery_id),
         {:ok, existing_delivery} <- get_delivery_by_id(delivery_id),
         {:ok, dispatch_decision} <-
           persist_or_acknowledge_duplicate(existing_delivery, delivery, delivery_id) do
      {:ok, dispatch_decision}
    end
  end

  @spec persist_or_acknowledge_duplicate(
          WebhookDelivery.t() | nil,
          verified_delivery(),
          String.t()
        ) ::
          {:ok, dispatch_decision()} | {:error, term()}
  defp persist_or_acknowledge_duplicate(%WebhookDelivery{}, delivery, delivery_id) do
    log_duplicate_delivery_ack(delivery_id, Map.get(delivery, :event))
    {:ok, :duplicate}
  end

  defp persist_or_acknowledge_duplicate(nil, delivery, delivery_id) do
    with {:ok, event} <- normalize_required_string(Map.get(delivery, :event), :missing_event),
         {:ok, payload} <- normalize_payload(Map.get(delivery, :payload)),
         {:ok, repo_id} <- resolve_repo_id(event, payload),
         {:ok, dispatch_decision} <- create_delivery_record(delivery_id, event, payload, repo_id) do
      {:ok, dispatch_decision}
    end
  end

  @spec create_delivery_record(String.t(), String.t(), map(), Ash.UUID.t()) ::
          {:ok, dispatch_decision()} | {:error, term()}
  defp create_delivery_record(delivery_id, event, payload, repo_id) do
    case WebhookDelivery.create(
           %{
             github_delivery_id: delivery_id,
             event_type: event,
             action: normalize_action(payload),
             payload: payload,
             repo_id: repo_id
           },
           actor: @webhook_actor
         ) do
      {:ok, %WebhookDelivery{}} ->
        Logger.info(
          "github_webhook_delivery_persisted outcome=recorded delivery_id=#{delivery_id} event=#{event} repo_id=#{repo_id}"
        )

        {:ok, :dispatch}

      {:error, reason} ->
        resolve_delivery_create_error(delivery_id, event, reason)
    end
  end

  @spec resolve_delivery_create_error(String.t(), String.t(), term()) ::
          {:ok, dispatch_decision()} | {:error, term()}
  defp resolve_delivery_create_error(delivery_id, event, reason) do
    case get_delivery_by_id(delivery_id) do
      {:ok, %WebhookDelivery{}} ->
        log_duplicate_delivery_ack(delivery_id, event)
        {:ok, :duplicate}

      {:ok, nil} ->
        {:error, {:delivery_persist_failed, reason}}

      {:error, lookup_reason} ->
        {:error, {:delivery_persist_failed, {reason, lookup_reason}}}
    end
  end

  @spec get_delivery_by_id(String.t()) :: {:ok, WebhookDelivery.t() | nil} | {:error, term()}
  defp get_delivery_by_id(delivery_id) when is_binary(delivery_id) do
    case WebhookDelivery.get_by_github_delivery_id(delivery_id, actor: @webhook_actor) do
      {:ok, %WebhookDelivery{} = delivery} ->
        {:ok, delivery}

      {:ok, nil} ->
        {:ok, nil}

      {:error, reason} ->
        if ash_not_found?(reason) do
          {:ok, nil}
        else
          {:error, reason}
        end
    end
  end

  @spec resolve_repo_id(String.t(), map()) :: {:ok, Ash.UUID.t()} | {:error, term()}
  defp resolve_repo_id(event, payload) when is_binary(event) and is_map(payload) do
    with {:ok, %Repo{id: repo_id}} <- resolve_repo_for_event(event, payload) do
      {:ok, repo_id}
    end
  end

  @spec resolve_repo_for_event(String.t(), map()) :: {:ok, Repo.t()} | {:error, term()}
  defp resolve_repo_for_event(event, payload) when is_binary(event) and is_map(payload) do
    case extract_repo_full_name(payload) do
      {:ok, repo_full_name} ->
        if installation_event?(event) do
          get_or_create_repo_by_full_name(repo_full_name, extract_installation_id(payload))
        else
          get_repo_by_full_name(repo_full_name)
        end

      {:error, :missing_repository_full_name} ->
        resolve_installation_repo(event, payload)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec resolve_installation_repo(String.t(), map()) :: {:ok, Repo.t()} | {:error, term()}
  defp resolve_installation_repo(event, payload) when is_binary(event) and is_map(payload) do
    if installation_event?(event) do
      with {:ok, repository_candidates} <- repository_name_candidates(payload),
           {:ok, repo_full_name} <- first_repository_candidate(repository_candidates) do
        get_or_create_repo_by_full_name(repo_full_name, extract_installation_id(payload))
      else
        {:error, :missing_repository_candidates} ->
          resolve_repo_by_installation_id(payload)

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :missing_repository_full_name}
    end
  end

  @spec resolve_repo_by_installation_id(map()) :: {:ok, Repo.t()} | {:error, term()}
  defp resolve_repo_by_installation_id(payload) when is_map(payload) do
    case extract_installation_id(payload) do
      nil ->
        {:error, :missing_installation_id}

      installation_id ->
        case Repo.read(
               query: [
                 filter: [github_app_installation_id: installation_id],
                 sort: [inserted_at: :asc],
                 limit: 1
               ],
               actor: @webhook_actor
             ) do
          {:ok, [%Repo{} = repo | _rest]} ->
            {:ok, repo}

          {:ok, []} ->
            {:error, :repo_not_found_for_installation_event}

          {:error, reason} ->
            {:error, {:repo_lookup_failed, reason}}
        end
    end
  end

  @spec get_or_create_repo_by_full_name(String.t(), integer() | nil) ::
          {:ok, Repo.t()} | {:error, term()}
  defp get_or_create_repo_by_full_name(repo_full_name, installation_id)
       when is_binary(repo_full_name) do
    case get_repo_by_full_name(repo_full_name) do
      {:ok, %Repo{} = repo} ->
        maybe_update_repo_installation(repo, installation_id)

      {:error, :repo_not_found} ->
        with {:ok, owner, name} <- split_repo_full_name(repo_full_name),
             {:ok, %Repo{} = repo} <-
               create_repo_for_event(owner, name, installation_id, repo_full_name) do
          {:ok, repo}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec create_repo_for_event(String.t(), String.t(), integer() | nil, String.t()) ::
          {:ok, Repo.t()} | {:error, term()}
  defp create_repo_for_event(owner, name, installation_id, repo_full_name)
       when is_binary(owner) and is_binary(name) do
    attributes =
      %{
        owner: owner,
        name: name
      }
      |> maybe_put_installation_id(installation_id)

    case Repo.create(attributes, actor: @webhook_actor) do
      {:ok, %Repo{} = repo} ->
        Logger.info(
          "github_webhook_repo_anchor_created repo_full_name=#{repo_full_name} installation_id=#{log_integer_value(installation_id)}"
        )

        {:ok, repo}

      {:error, reason} ->
        {:error, {:repo_create_failed, reason}}
    end
  end

  @spec maybe_update_repo_installation(Repo.t(), integer() | nil) ::
          {:ok, Repo.t()} | {:error, term()}
  defp maybe_update_repo_installation(%Repo{} = repo, nil), do: {:ok, repo}

  defp maybe_update_repo_installation(%Repo{} = repo, installation_id)
       when is_integer(installation_id) do
    current_installation_id = Map.get(repo, :github_app_installation_id)

    if current_installation_id == installation_id do
      {:ok, repo}
    else
      case Repo.update(repo, %{github_app_installation_id: installation_id}, actor: @webhook_actor) do
        {:ok, %Repo{} = updated_repo} ->
          {:ok, updated_repo}

        {:error, reason} ->
          {:error, {:repo_installation_update_failed, reason}}
      end
    end
  end

  @spec split_repo_full_name(String.t()) ::
          {:ok, String.t(), String.t()} | {:error, :invalid_repository_full_name}
  defp split_repo_full_name(repo_full_name) when is_binary(repo_full_name) do
    case String.split(repo_full_name, "/", parts: 2) do
      [owner, name] when owner != "" and name != "" ->
        {:ok, owner, name}

      _other ->
        {:error, :invalid_repository_full_name}
    end
  end

  @spec repository_name_candidates(map()) ::
          {:ok, [String.t()]} | {:error, :missing_repository_candidates}
  defp repository_name_candidates(payload) when is_map(payload) do
    candidates =
      payload
      |> repository_candidate_sources()
      |> Enum.flat_map(&extract_repository_full_names/1)
      |> Enum.uniq()

    case candidates do
      [] -> {:error, :missing_repository_candidates}
      repository_candidates -> {:ok, repository_candidates}
    end
  end

  @spec first_repository_candidate([String.t()]) ::
          {:ok, String.t()} | {:error, :missing_repository_candidates}
  defp first_repository_candidate([repo_full_name | _rest]) when is_binary(repo_full_name),
    do: {:ok, repo_full_name}

  defp first_repository_candidate(_repository_candidates),
    do: {:error, :missing_repository_candidates}

  @spec repository_candidate_sources(map()) :: [term()]
  defp repository_candidate_sources(payload) when is_map(payload) do
    [
      map_get(payload, :repositories, "repositories", []),
      map_get(payload, :repositories_added, "repositories_added", []),
      map_get(payload, :repositories_removed, "repositories_removed", [])
    ]
  end

  @spec extract_repository_full_names(term()) :: [String.t()]
  defp extract_repository_full_names(repositories) when is_list(repositories) do
    repositories
    |> Enum.map(&extract_repository_full_name/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_repository_full_names(_repositories), do: []

  @spec extract_repository_full_name(term()) :: String.t() | nil
  defp extract_repository_full_name(repository) when is_binary(repository) do
    normalize_optional_string(repository)
  end

  defp extract_repository_full_name(repository) when is_map(repository) do
    repository
    |> map_get(:full_name, "full_name")
    |> normalize_optional_string()
    |> case do
      nil ->
        owner =
          repository
          |> map_get(:owner, "owner")
          |> normalize_owner_value()

        name =
          repository
          |> map_get(:name, "name")
          |> normalize_optional_string()

        if owner && name, do: "#{owner}/#{name}", else: nil

      repository_full_name ->
        repository_full_name
    end
  end

  defp extract_repository_full_name(_repository), do: nil

  @spec normalize_owner_value(term()) :: String.t() | nil
  defp normalize_owner_value(owner) when is_binary(owner) do
    normalize_optional_string(owner)
  end

  defp normalize_owner_value(%{} = owner) do
    owner
    |> map_get(:login, "login")
    |> normalize_optional_string()
  end

  defp normalize_owner_value(_owner), do: nil

  @spec maybe_put_installation_id(map(), integer() | nil) :: map()
  defp maybe_put_installation_id(attributes, installation_id) when is_integer(installation_id) do
    Map.put(attributes, :github_app_installation_id, installation_id)
  end

  defp maybe_put_installation_id(attributes, _installation_id), do: attributes

  @spec installation_event?(String.t()) :: boolean()
  defp installation_event?(event) when is_binary(event) do
    event in ["installation", "installation_repositories"]
  end

  @spec extract_installation_id(map()) :: integer() | nil
  defp extract_installation_id(payload) when is_map(payload) do
    payload
    |> map_get(:installation, "installation", %{})
    |> map_get(:id, "id")
    |> normalize_installation_id()
  end

  defp extract_installation_id(_payload), do: nil

  @spec normalize_installation_id(term()) :: integer() | nil
  defp normalize_installation_id(value) when is_integer(value) and value > 0, do: value

  defp normalize_installation_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed_value, ""} when parsed_value > 0 -> parsed_value
      _other -> nil
    end
  end

  defp normalize_installation_id(_value), do: nil

  @spec extract_repo_full_name(map()) ::
          {:ok, String.t()} | {:error, :missing_repository_full_name}
  defp extract_repo_full_name(payload) when is_map(payload) do
    repository =
      Map.get(payload, "repository") ||
        Map.get(payload, :repository)

    full_name =
      case repository do
        %{} = repository_map ->
          Map.get(repository_map, "full_name") || Map.get(repository_map, :full_name)

        _other ->
          nil
      end

    normalize_required_string(full_name, :missing_repository_full_name)
  end

  @spec get_repo_by_full_name(String.t()) :: {:ok, Repo.t()} | {:error, term()}
  defp get_repo_by_full_name(repo_full_name) when is_binary(repo_full_name) do
    case Repo.get_by_full_name(repo_full_name, actor: @webhook_actor) do
      {:ok, %Repo{} = repo} ->
        {:ok, repo}

      {:ok, nil} ->
        {:error, :repo_not_found}

      {:error, reason} ->
        if ash_not_found?(reason) do
          {:error, :repo_not_found}
        else
          {:error, {:repo_lookup_failed, reason}}
        end
    end
  end

  @spec normalize_action(map()) :: String.t() | nil
  defp normalize_action(payload) when is_map(payload) do
    case Map.get(payload, "action") || Map.get(payload, :action) do
      action when is_binary(action) ->
        case String.trim(action) do
          "" -> nil
          normalized_action -> normalized_action
        end

      _other ->
        nil
    end
  end

  @spec normalize_payload(term()) :: {:ok, map()} | {:error, :missing_payload}
  defp normalize_payload(payload) when is_map(payload), do: {:ok, payload}
  defp normalize_payload(_payload), do: {:error, :missing_payload}

  @spec normalize_required_string(term(), term()) :: {:ok, String.t()} | {:error, term()}
  defp normalize_required_string(value, error_reason) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, error_reason}
      normalized_value -> {:ok, normalized_value}
    end
  end

  defp normalize_required_string(_value, error_reason), do: {:error, error_reason}

  @spec log_duplicate_delivery_ack(String.t(), String.t() | nil) :: :ok
  defp log_duplicate_delivery_ack(delivery_id, event) do
    Logger.info(
      "github_webhook_delivery_persisted outcome=duplicate_acknowledged delivery_id=#{delivery_id} event=#{log_value(event)}"
    )

    :ok
  end

  @spec ash_not_found?(term()) :: boolean()
  defp ash_not_found?(%Ash.Error.Query.NotFound{}), do: true

  defp ash_not_found?(%Ash.Error.Invalid{errors: errors}) when is_list(errors) do
    Enum.any?(errors, &ash_not_found?/1)
  end

  defp ash_not_found?(%{errors: errors}) when is_list(errors) do
    Enum.any?(errors, &ash_not_found?/1)
  end

  defp ash_not_found?(_reason), do: false

  defp maybe_sync_installation_metadata(delivery) do
    case GitHubInstallationSync.sync_verified_delivery(delivery) do
      :ignored ->
        :ok

      {:ok, summary} ->
        Logger.info(
          "github_installation_sync outcome=updated event=#{log_value(Map.get(summary, :event))} action=#{log_value(Map.get(summary, :action))} installation_id=#{log_integer_value(Map.get(summary, :installation_id))} affected_repositories=#{log_repositories(GitHubInstallationSync.repository_names(summary))}"
        )

        :ok

      {:error, summary} ->
        Logger.warning(
          "github_installation_sync outcome=stale event=#{log_value(Map.get(summary, :event))} action=#{log_value(Map.get(summary, :action))} installation_id=#{log_integer_value(Map.get(summary, :installation_id))} error_type=#{log_value(Map.get(summary, :error_type))} affected_repositories=#{log_repositories(GitHubInstallationSync.repository_names(summary))}"
        )

        :ok
    end
  end

  defp maybe_dispatch_configured_issue_bot_delivery(delivery) do
    case issue_bot_delivery_event(delivery) do
      nil ->
        dispatch_verified_delivery(delivery)

      issue_bot_event ->
        if issue_bot_candidate_event?(issue_bot_event) do
          maybe_dispatch_issue_bot_candidate_delivery(delivery, issue_bot_event)
        else
          dispatch_verified_delivery(delivery)
        end
    end
  end

  defp maybe_dispatch_issue_bot_candidate_delivery(delivery, issue_bot_event) do
    case issue_bot_project_policy_for_delivery(delivery) do
      {:ok, %Project{} = project, false, _configured_events} ->
        log_issue_bot_disabled_noop(delivery, issue_bot_event, project)
        :ok

      {:ok, %Project{} = project, true, configured_events} ->
        maybe_dispatch_issue_bot_event_for_project(
          delivery,
          issue_bot_event,
          project,
          configured_events
        )

      {:error, :project_not_found} ->
        maybe_dispatch_issue_bot_event_without_project(delivery, issue_bot_event)
    end
  end

  defp maybe_dispatch_issue_bot_event_for_project(
         delivery,
         issue_bot_event,
         project,
         configured_events
       ) do
    if issue_bot_event in configured_events do
      with :ok <- maybe_create_issue_triage_run(delivery, issue_bot_event, project),
           :ok <- dispatch_verified_delivery(delivery) do
        :ok
      end
    else
      log_webhook_event_filtered_noop(delivery, issue_bot_event, configured_events)
      :ok
    end
  end

  defp maybe_dispatch_issue_bot_event_without_project(delivery, issue_bot_event) do
    configured_events = supported_issue_bot_webhook_events()

    if issue_bot_event in configured_events do
      dispatch_verified_delivery(delivery)
    else
      log_webhook_event_filtered_noop(delivery, issue_bot_event, configured_events)
      :ok
    end
  end

  defp issue_bot_project_policy_for_delivery(delivery) do
    case fetch_project_for_delivery(delivery) do
      {:ok, %Project{} = project} ->
        {:ok, project, project_issue_bot_enabled?(project), project_issue_bot_webhook_events(project)}

      {:error, :project_not_found} ->
        {:error, :project_not_found}
    end
  end

  defp issue_bot_delivery_event(%{} = delivery) do
    event =
      delivery
      |> Map.get(:event)
      |> normalize_optional_string()

    action =
      delivery
      |> Map.get(:payload)
      |> case do
        payload when is_map(payload) -> normalize_action(payload)
        _other -> nil
      end

    cond do
      is_nil(event) ->
        nil

      String.contains?(event, ".") ->
        event

      is_binary(action) ->
        "#{event}.#{action}"

      true ->
        event
    end
  end

  defp issue_bot_delivery_event(_delivery), do: nil

  defp issue_bot_candidate_event?(event) when is_binary(event) do
    String.starts_with?(event, "issues.") or String.starts_with?(event, "issue_comment.")
  end

  defp issue_bot_candidate_event?(_event), do: false

  defp fetch_project_for_delivery(%{} = delivery) do
    with payload when is_map(payload) <- Map.get(delivery, :payload),
         {:ok, repo_full_name} <- extract_repo_full_name(payload),
         {:ok, projects} <-
           Project.read(
             query: [filter: [github_full_name: repo_full_name], limit: 1],
             actor: @webhook_actor
           ),
         [%Project{} = project | _rest] <- projects do
      {:ok, project}
    else
      _other -> {:error, :project_not_found}
    end
  end

  defp fetch_project_for_delivery(_delivery), do: {:error, :project_not_found}

  defp project_issue_bot_webhook_events(%Project{} = project) do
    issue_bot_settings = issue_bot_settings(project)

    if map_has_key?(issue_bot_settings, :webhook_events, "webhook_events") do
      issue_bot_settings
      |> map_get(:webhook_events, "webhook_events")
      |> normalize_webhook_events()
      |> sort_webhook_events_by_supported_order()
    else
      supported_issue_bot_webhook_events()
    end
  end

  defp project_issue_bot_webhook_events(_project), do: supported_issue_bot_webhook_events()

  defp project_issue_bot_enabled?(%Project{} = project) do
    project
    |> issue_bot_settings()
    |> map_get(:enabled, "enabled")
    |> normalize_enabled(true)
  end

  defp project_issue_bot_enabled?(_project), do: true

  defp issue_bot_settings(%Project{} = project) do
    project
    |> map_get(:settings, "settings", %{})
    |> map_get(:support_agent_config, "support_agent_config", %{})
    |> map_get(:github_issue_bot, "github_issue_bot", %{})
  end

  defp issue_bot_settings(_project), do: %{}

  defp project_issue_bot_approval_policy(%Project{} = project) do
    case PolicyBridge.approval_policy_for_project(Map.get(project, :id)) do
      {:ok, approval_policy} ->
        approval_policy

      _other ->
        project
        |> issue_bot_settings()
        |> map_get(:approval_mode, "approval_mode")
        |> issue_bot_approval_policy()
    end
  end

  defp project_issue_bot_approval_policy(_project),
    do: issue_bot_approval_policy(@default_issue_bot_approval_mode)

  defp maybe_create_issue_triage_run(_delivery, issue_bot_event, _project)
       when issue_bot_event not in @issue_triage_workflow_trigger_events,
       do: :ok

  defp maybe_create_issue_triage_run(delivery, issue_bot_event, %Project{} = project)
       when issue_bot_event in @issue_triage_workflow_trigger_events do
    with {:ok, issue_triage_run_plan} <-
           build_issue_triage_run_attributes(delivery, project, issue_bot_event),
         run_attributes <- Map.fetch!(issue_triage_run_plan, :run_attributes),
         artifact_persistence_failure <- Map.get(issue_triage_run_plan, :artifact_persistence_failure),
         {:ok, %WorkflowRun{} = workflow_run} <-
           WorkflowRun.create(run_attributes, actor: @webhook_actor),
         :ok <- maybe_mark_issue_triage_run_failed(workflow_run, artifact_persistence_failure),
         {:ok, %WorkflowRun{} = finalized_run} <-
           maybe_advance_issue_triage_run(workflow_run, artifact_persistence_failure) do
      artifact_persistence_status =
        if is_map(artifact_persistence_failure),
          do: "partial_failed",
          else: "persisted"

      run_status =
        finalized_run
        |> Map.get(:status)
        |> normalize_optional_string() || "unknown"

      posting_status = issue_triage_posting_status(finalized_run)

      Logger.info(
        "github_webhook_issue_triage_run_created delivery_id=#{log_value(Map.get(delivery, :delivery_id))} project_id=#{log_value(Map.get(project, :id))} trigger_event=#{issue_bot_event} run_id=#{workflow_run.run_id} workflow_name=#{workflow_run.workflow_name} artifact_persistence=#{artifact_persistence_status} status=#{run_status} posting=#{posting_status}"
      )

      :ok
    else
      {:error, reason} ->
        Logger.error(
          "github_webhook_issue_triage_run_create_failed reason=#{inspect(reason)} delivery_id=#{log_value(Map.get(delivery, :delivery_id))} project_id=#{log_value(Map.get(project, :id))} trigger_event=#{issue_bot_event}"
        )

        {:error, :issue_triage_run_create_failed}
    end
  end

  defp build_issue_triage_run_attributes(
         %{} = delivery,
         %Project{} = project,
         issue_bot_event
       )
       when is_binary(issue_bot_event) do
    with payload when is_map(payload) <- Map.get(delivery, :payload),
         {:ok, issue_payload} <- issue_payload(payload),
         {:ok, issue_identifiers} <- source_issue_identifiers(issue_payload),
         issue_reference when is_binary(issue_reference) <-
           issue_reference(source_repo_full_name(payload, project), issue_identifiers) do
      run_id = generated_run_id()
      delivery_id = delivery |> Map.get(:delivery_id) |> normalize_optional_string()
      event = delivery |> Map.get(:event) |> normalize_optional_string()
      action = normalize_action(payload)
      project_id = project |> Map.get(:id) |> normalize_optional_string()
      started_at = DateTime.utc_now() |> DateTime.truncate(:second)

      project_github_full_name =
        project |> Map.get(:github_full_name) |> normalize_optional_string()

      policy_name = issue_triage_webhook_policy_name(issue_bot_event)
      approval_policy = project_issue_bot_approval_policy(project)

      retriage_context =
        retriage_context(issue_bot_event, project, issue_identifiers, issue_reference)

      follow_up_context = follow_up_context(issue_bot_event, payload)

      trigger =
        %{
          "source" => "github_webhook",
          "mode" => "webhook",
          "source_row" =>
            reject_nil_values(%{
              "route" => "/api/github/webhooks",
              "delivery_id" => delivery_id,
              "event" => event,
              "action" => action,
              "project_id" => project_id,
              "project_github_full_name" => project_github_full_name
            }),
          "webhook" =>
            reject_nil_values(%{
              "delivery_id" => delivery_id,
              "event" => event,
              "action" => action
            }),
          "source_issue" => issue_identifiers,
          "retriage" => retriage_context,
          "follow_up" => follow_up_context,
          "approval_policy" => approval_policy,
          "policy" => %{
            "name" => policy_name,
            "source" => "support_agent_config.github_issue_bot",
            "approval_policy" => approval_policy
          }
        }
        |> reject_nil_values()

      input_metadata = %{
        @issue_reference_input_name => %{
          "label" => "Issue reference",
          "required" => true,
          "source" => "github_webhook",
          "source_issue" => issue_identifiers
        }
      }

      artifact_bundle =
        issue_triage_artifact_bundle(run_id, issue_reference, issue_identifiers, issue_payload, started_at)

      artifact_persistence_context =
        %{
          "run_id" => run_id,
          "workflow_name" => @issue_triage_workflow_name,
          "issue_reference" => issue_reference,
          "source_issue" => issue_identifiers,
          "artifacts" => artifact_bundle
        }
        |> reject_nil_values()

      case persist_issue_triage_artifacts(artifact_persistence_context) do
        :ok ->
          {:ok,
           %{
             run_attributes: %{
               run_id: run_id,
               project_id: project_id,
               workflow_name: @issue_triage_workflow_name,
               workflow_version: @issue_triage_workflow_version,
               trigger: trigger,
               inputs: %{@issue_reference_input_name => issue_reference},
               input_metadata: input_metadata,
               initiating_actor: @webhook_actor,
               current_step: "queued",
               started_at: started_at,
               step_results:
                 issue_triage_step_results(
                   artifact_bundle,
                   issue_triage_artifact_linkage(run_id, issue_reference, issue_identifiers),
                   "persisted"
                 )
             },
             artifact_persistence_failure: nil
           }}

        {:error, artifact_failure_reason} ->
          artifact_persistence_failure =
            issue_triage_artifact_persistence_failure(
              artifact_failure_reason,
              run_id,
              issue_reference,
              issue_identifiers
            )

          partial_artifact_bundle =
            %{
              "run_issue_triage" =>
                artifact_bundle
                |> map_get(:run_issue_triage, "run_issue_triage", %{})
            }
            |> reject_nil_values()

          {:ok,
           %{
             run_attributes: %{
               run_id: run_id,
               project_id: project_id,
               workflow_name: @issue_triage_workflow_name,
               workflow_version: @issue_triage_workflow_version,
               trigger: trigger,
               inputs: %{@issue_reference_input_name => issue_reference},
               input_metadata: input_metadata,
               initiating_actor: @webhook_actor,
               current_step: "queued",
               started_at: started_at,
               step_results:
                 issue_triage_step_results(
                   partial_artifact_bundle,
                   issue_triage_artifact_linkage(run_id, issue_reference, issue_identifiers),
                   "partial_persistence_failed",
                   artifact_persistence_failure
                 )
             },
             artifact_persistence_failure: artifact_persistence_failure
           }}
      end
    else
      _other ->
        {:error, :invalid_issue_payload}
    end
  end

  defp maybe_mark_issue_triage_run_failed(%WorkflowRun{} = _workflow_run, nil), do: :ok

  defp maybe_mark_issue_triage_run_failed(%WorkflowRun{} = workflow_run, artifact_persistence_failure)
       when is_map(artifact_persistence_failure) do
    failed_at = DateTime.utc_now() |> DateTime.truncate(:second)

    with {:ok, %WorkflowRun{} = running_run} <-
           WorkflowRun.transition_status(
             workflow_run,
             %{
               to_status: :running,
               current_step: @issue_triage_artifact_persistence_failed_step,
               transitioned_at: failed_at
             },
             actor: @webhook_actor
           ),
         {:ok, %WorkflowRun{}} <-
           WorkflowRun.transition_status(
             running_run,
             %{
               to_status: :failed,
               current_step: @issue_triage_artifact_persistence_failed_step,
               transitioned_at: failed_at,
               transition_metadata: %{
                 "typed_failure" => artifact_persistence_failure,
                 "failure_context" => artifact_persistence_failure
               }
             },
             actor: @webhook_actor
           ) do
      :ok
    else
      {:error, reason} ->
        {:error, {:issue_triage_artifact_failure_transition_failed, reason}}
    end
  end

  defp maybe_mark_issue_triage_run_failed(_workflow_run, _artifact_persistence_failure) do
    {:error, :invalid_issue_triage_run}
  end

  defp maybe_advance_issue_triage_run(%WorkflowRun{} = workflow_run, nil) do
    case WorkflowRun.advance_issue_triage_run(workflow_run) do
      {:ok, %WorkflowRun{} = finalized_run} ->
        {:ok, finalized_run}

      {:error, reason} ->
        {:error, {:issue_triage_run_advance_failed, reason}}
    end
  end

  defp maybe_advance_issue_triage_run(%WorkflowRun{} = workflow_run, _artifact_persistence_failure) do
    {:ok, workflow_run}
  end

  defp maybe_advance_issue_triage_run(_workflow_run, _artifact_persistence_failure) do
    {:error, :invalid_issue_triage_run}
  end

  defp issue_triage_posting_status(%WorkflowRun{} = run) do
    run
    |> Map.get(:step_results, %{})
    |> map_get(:post_issue_response, "post_issue_response", %{})
    |> map_get(:status, "status")
    |> normalize_optional_string() || "pending"
  end

  defp issue_triage_posting_status(_run), do: "unknown"

  @spec default_issue_triage_artifact_persister(map()) :: :ok
  def default_issue_triage_artifact_persister(%{} = _artifact_persistence_context), do: :ok

  def default_issue_triage_artifact_persister(_artifact_persistence_context), do: :ok

  defp persist_issue_triage_artifacts(%{} = artifact_persistence_context) do
    persister =
      Application.get_env(
        :jido_code,
        :issue_triage_artifact_persister,
        &__MODULE__.default_issue_triage_artifact_persister/1
      )

    safe_invoke_issue_triage_artifact_persister(persister, artifact_persistence_context)
  end

  defp persist_issue_triage_artifacts(_artifact_persistence_context) do
    {:error, normalize_issue_triage_artifact_persistence_failure(:invalid_artifact_context)}
  end

  defp safe_invoke_issue_triage_artifact_persister(persister, artifact_persistence_context)
       when is_function(persister, 1) and is_map(artifact_persistence_context) do
    try do
      case persister.(artifact_persistence_context) do
        :ok ->
          :ok

        {:ok, _result} ->
          :ok

        {:error, reason} ->
          {:error, normalize_issue_triage_artifact_persistence_failure(reason)}

        other ->
          {:error, normalize_issue_triage_artifact_persistence_failure({:invalid_artifact_persister_result, other})}
      end
    rescue
      exception ->
        {:error,
         normalize_issue_triage_artifact_persistence_failure(%{
           reason_type: "artifact_persister_exception",
           detail: "Issue triage artifact persister crashed (#{Exception.message(exception)})."
         })}
    catch
      kind, reason ->
        {:error,
         normalize_issue_triage_artifact_persistence_failure(%{
           reason_type: "artifact_persister_throw",
           detail: "Issue triage artifact persister threw #{inspect({kind, reason})}."
         })}
    end
  end

  defp safe_invoke_issue_triage_artifact_persister(_persister, _artifact_persistence_context) do
    {:error, normalize_issue_triage_artifact_persistence_failure(:invalid_artifact_persister)}
  end

  defp normalize_issue_triage_artifact_persistence_failure(%{} = artifact_failure) do
    reason_type =
      artifact_failure
      |> map_get(:reason_type, "reason_type")
      |> normalize_optional_string() ||
        "artifact_persistence_failed"

    detail =
      artifact_failure
      |> map_get(:detail, "detail")
      |> normalize_optional_string() ||
        "Issue triage artifact persistence failed."

    remediation =
      artifact_failure
      |> map_get(:remediation, "remediation")
      |> normalize_optional_string() ||
        @issue_triage_artifact_persistence_remediation

    %{
      "reason_type" => reason_type,
      "detail" => detail,
      "remediation" => remediation
    }
  end

  defp normalize_issue_triage_artifact_persistence_failure(artifact_failure) do
    %{
      "reason_type" => "artifact_persistence_failed",
      "detail" => "Issue triage artifact persistence failed (#{inspect(artifact_failure)}).",
      "remediation" => @issue_triage_artifact_persistence_remediation
    }
  end

  defp issue_triage_artifact_persistence_failure(
         artifact_failure_reason,
         run_id,
         issue_reference,
         issue_identifiers
       ) do
    normalized_failure = normalize_issue_triage_artifact_persistence_failure(artifact_failure_reason)

    %{
      "error_type" => @issue_triage_artifact_persistence_error_type,
      "operation" => @issue_triage_artifact_persistence_operation,
      "reason_type" => normalized_failure |> map_get(:reason_type, "reason_type"),
      "detail" => normalized_failure |> map_get(:detail, "detail"),
      "remediation" => normalized_failure |> map_get(:remediation, "remediation"),
      "failed_step" => @issue_triage_artifact_persistence_failed_step,
      "last_successful_step" => "run_issue_triage",
      "run_id" => normalize_optional_string(run_id),
      "issue_reference" => normalize_optional_string(issue_reference),
      "source_issue" => issue_identifiers,
      "timestamp" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
    |> reject_nil_values()
  end

  defp issue_triage_artifact_bundle(
         run_id,
         issue_reference,
         issue_identifiers,
         issue_payload,
         generated_at
       )
       when is_map(issue_identifiers) and is_map(issue_payload) do
    linkage = issue_triage_artifact_linkage(run_id, issue_reference, issue_identifiers)
    triage_artifact = issue_triage_classification_artifact(issue_payload, linkage, generated_at)

    research_artifact =
      issue_triage_research_artifact(issue_payload, triage_artifact, linkage, generated_at)

    response_artifact =
      issue_triage_response_draft_artifact(
        issue_payload,
        triage_artifact,
        research_artifact,
        linkage,
        generated_at
      )

    %{
      "run_issue_triage" => triage_artifact,
      "run_issue_research" => research_artifact,
      "compose_issue_response" => response_artifact
    }
  end

  defp issue_triage_artifact_bundle(
         _run_id,
         _issue_reference,
         _issue_identifiers,
         _issue_payload,
         _generated_at
       ) do
    %{}
  end

  defp issue_triage_step_results(
         artifact_bundle,
         linkage,
         persistence_status,
         artifact_persistence_failure \\ nil
       )

  defp issue_triage_step_results(
         artifact_bundle,
         linkage,
         persistence_status,
         artifact_persistence_failure
       )
       when is_map(artifact_bundle) and is_map(linkage) and is_binary(persistence_status) do
    artifact_keys =
      artifact_bundle
      |> Map.keys()
      |> Enum.map(&normalize_optional_string/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()

    persistence_metadata =
      %{
        "status" => persistence_status,
        "artifact_keys" => artifact_keys,
        "linked_run" => linkage
      }
      |> maybe_put_typed_failure(artifact_persistence_failure)
      |> reject_nil_values()

    artifact_bundle
    |> Map.put("issue_bot_artifact_lineage", persistence_metadata)
  end

  defp issue_triage_step_results(_artifact_bundle, _linkage, _persistence_status, _artifact_persistence_failure) do
    %{}
  end

  defp maybe_put_typed_failure(map, nil) when is_map(map), do: map

  defp maybe_put_typed_failure(map, artifact_persistence_failure)
       when is_map(map) and is_map(artifact_persistence_failure) do
    Map.put(map, "typed_failure", artifact_persistence_failure)
  end

  defp maybe_put_typed_failure(map, _artifact_persistence_failure) when is_map(map), do: map

  defp issue_triage_artifact_linkage(run_id, issue_reference, issue_identifiers)
       when is_map(issue_identifiers) do
    %{
      "run_id" => normalize_optional_string(run_id),
      "workflow_name" => @issue_triage_workflow_name,
      "issue_reference" => normalize_optional_string(issue_reference),
      "source_issue" => issue_identifiers
    }
    |> reject_nil_values()
  end

  defp issue_triage_artifact_linkage(_run_id, _issue_reference, _issue_identifiers), do: %{}

  defp issue_triage_classification_artifact(issue_payload, linkage, generated_at)
       when is_map(issue_payload) and is_map(linkage) do
    classification = issue_triage_classification(issue_payload)

    %{
      "classification" => classification,
      "confidence" => issue_triage_classification_confidence(issue_payload),
      "summary" => "Issue triage classified this report as #{classification}.",
      "linked_run" => linkage,
      "generated_at" => generated_at |> normalize_generated_at()
    }
    |> reject_nil_values()
  end

  defp issue_triage_classification_artifact(_issue_payload, _linkage, _generated_at), do: %{}

  defp issue_triage_research_artifact(issue_payload, triage_artifact, linkage, generated_at)
       when is_map(issue_payload) and is_map(triage_artifact) and is_map(linkage) do
    classification =
      triage_artifact
      |> map_get(:classification, "classification")
      |> normalize_optional_string() || "needs_triage"

    issue_subject = issue_subject(issue_payload)

    %{
      "summary" =>
        "Initial research for #{issue_subject} focused on #{classification} signals and reproducibility context.",
      "linked_run" => linkage,
      "generated_at" => generated_at |> normalize_generated_at()
    }
    |> reject_nil_values()
  end

  defp issue_triage_research_artifact(_issue_payload, _triage_artifact, _linkage, _generated_at), do: %{}

  defp issue_triage_response_draft_artifact(
         issue_payload,
         triage_artifact,
         research_artifact,
         linkage,
         generated_at
       )
       when is_map(issue_payload) and is_map(triage_artifact) and is_map(research_artifact) and
              is_map(linkage) do
    classification =
      triage_artifact
      |> map_get(:classification, "classification")
      |> normalize_optional_string() || "needs_triage"

    research_summary =
      research_artifact
      |> map_get(:summary, "summary")
      |> normalize_optional_string() || "Initial research summary is available in run artifacts."

    issue_subject = issue_subject(issue_payload)

    %{
      "proposed_response" =>
        "Thanks for reporting #{issue_subject}. We triaged this as #{classification}. #{research_summary} Maintainers can review and post this response once approved.",
      "linked_run" => linkage,
      "generated_at" => generated_at |> normalize_generated_at()
    }
    |> reject_nil_values()
  end

  defp issue_triage_response_draft_artifact(
         _issue_payload,
         _triage_artifact,
         _research_artifact,
         _linkage,
         _generated_at
       ) do
    %{}
  end

  defp issue_triage_classification(issue_payload) when is_map(issue_payload) do
    issue_text = issue_payload_text(issue_payload)

    cond do
      contains_any?(issue_text, [
        "bug",
        "error",
        "failing",
        "failure",
        "exception",
        "panic",
        "regression",
        "crash"
      ]) ->
        "bug"

      contains_any?(issue_text, ["feature", "enhancement", "request", "proposal", "improvement"]) ->
        "feature"

      contains_any?(issue_text, ["docs", "documentation", "readme", "typo"]) ->
        "documentation"

      contains_any?(issue_text, ["question", "help", "how do", "how to"]) ->
        "question"

      true ->
        "needs_triage"
    end
  end

  defp issue_triage_classification(_issue_payload), do: "needs_triage"

  defp issue_triage_classification_confidence(issue_payload) when is_map(issue_payload) do
    issue_text = issue_payload_text(issue_payload)

    cond do
      issue_text == "" ->
        "low"

      contains_any?(issue_text, [
        "bug",
        "error",
        "failing",
        "failure",
        "exception",
        "panic",
        "regression",
        "crash",
        "feature",
        "enhancement",
        "request",
        "proposal",
        "docs",
        "documentation"
      ]) ->
        "medium"

      true ->
        "low"
    end
  end

  defp issue_triage_classification_confidence(_issue_payload), do: "low"

  defp issue_payload_text(issue_payload) when is_map(issue_payload) do
    title =
      issue_payload
      |> map_get(:title, "title")
      |> normalize_optional_string()
      |> case do
        nil -> ""
        normalized_title -> normalized_title
      end

    body =
      issue_payload
      |> map_get(:body, "body")
      |> normalize_optional_string()
      |> case do
        nil -> ""
        normalized_body -> normalized_body
      end

    [title, body]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
    |> String.downcase()
  end

  defp issue_payload_text(_issue_payload), do: ""

  defp issue_subject(issue_payload) when is_map(issue_payload) do
    title =
      issue_payload
      |> map_get(:title, "title")
      |> normalize_optional_string()

    issue_number =
      issue_payload
      |> map_get(:number, "number")
      |> normalize_optional_positive_integer()

    cond do
      is_binary(title) ->
        title

      is_integer(issue_number) ->
        "issue ##{issue_number}"

      true ->
        "this issue"
    end
  end

  defp issue_subject(_issue_payload), do: "this issue"

  defp contains_any?(value, candidates) when is_binary(value) and is_list(candidates) do
    Enum.any?(candidates, fn candidate ->
      is_binary(candidate) and String.contains?(value, candidate)
    end)
  end

  defp contains_any?(_value, _candidates), do: false

  defp normalize_generated_at(%DateTime{} = generated_at), do: DateTime.to_iso8601(generated_at)
  defp normalize_generated_at(generated_at) when is_binary(generated_at), do: generated_at
  defp normalize_generated_at(_generated_at), do: nil

  defp issue_payload(payload) when is_map(payload) do
    case map_get(payload, :issue, "issue") do
      issue when is_map(issue) -> {:ok, issue}
      _other -> {:error, :missing_issue_payload}
    end
  end

  defp issue_payload(_payload), do: {:error, :missing_issue_payload}

  defp source_issue_identifiers(issue_payload) when is_map(issue_payload) do
    issue_number =
      issue_payload
      |> map_get(:number, "number")
      |> normalize_optional_positive_integer()

    if is_integer(issue_number) do
      issue_identifiers =
        %{
          "number" => issue_number,
          "id" =>
            issue_payload
            |> map_get(:id, "id")
            |> normalize_optional_positive_integer(),
          "node_id" =>
            issue_payload
            |> map_get(:node_id, "node_id")
            |> normalize_optional_string(),
          "html_url" =>
            issue_payload
            |> map_get(:html_url, "html_url")
            |> normalize_optional_string(),
          "api_url" =>
            issue_payload
            |> map_get(:url, "url")
            |> normalize_optional_string()
        }
        |> reject_nil_values()

      {:ok, issue_identifiers}
    else
      {:error, :missing_issue_number}
    end
  end

  defp source_issue_identifiers(_issue_payload), do: {:error, :missing_issue_number}

  defp source_repo_full_name(payload, %Project{} = project) when is_map(payload) do
    case extract_repo_full_name(payload) do
      {:ok, repo_full_name} ->
        repo_full_name

      {:error, _reason} ->
        project
        |> Map.get(:github_full_name)
        |> normalize_optional_string()
    end
  end

  defp source_repo_full_name(_payload, _project), do: nil

  defp issue_reference(repo_full_name, issue_identifiers)
       when is_binary(repo_full_name) and is_map(issue_identifiers) do
    issue_number =
      issue_identifiers
      |> map_get(:number, "number")
      |> normalize_optional_positive_integer()

    if is_integer(issue_number) do
      "#{repo_full_name}##{issue_number}"
    else
      issue_reference(nil, issue_identifiers)
    end
  end

  defp issue_reference(_repo_full_name, issue_identifiers) when is_map(issue_identifiers) do
    issue_identifiers
    |> map_get(:html_url, "html_url")
    |> normalize_optional_string() ||
      issue_identifiers
      |> map_get(:api_url, "api_url")
      |> normalize_optional_string()
  end

  defp issue_reference(_repo_full_name, _issue_identifiers), do: nil

  defp issue_triage_webhook_policy_name("issues.edited"),
    do: @issue_triage_webhook_retriage_policy

  defp issue_triage_webhook_policy_name("issue_comment.created"),
    do: @issue_triage_webhook_follow_up_policy

  defp issue_triage_webhook_policy_name(_issue_bot_event),
    do: @issue_triage_webhook_opened_policy

  defp follow_up_context("issue_comment.created", payload) when is_map(payload) do
    comment =
      payload
      |> map_get(:comment, "comment", %{})
      |> case do
        %{} = comment_payload -> comment_payload
        _other -> %{}
      end

    comment_author =
      comment
      |> map_get(:user, "user", %{})
      |> case do
        %{} = author -> author
        _other -> %{}
      end

    comment_context =
      %{
        "id" => comment |> map_get(:id, "id") |> normalize_optional_positive_integer(),
        "node_id" => comment |> map_get(:node_id, "node_id") |> normalize_optional_string(),
        "html_url" => comment |> map_get(:html_url, "html_url") |> normalize_optional_string(),
        "body" => comment |> map_get(:body, "body") |> normalize_optional_string(),
        "author_login" => comment_author |> map_get(:login, "login") |> normalize_optional_string(),
        "author_association" =>
          comment |> map_get(:author_association, "author_association") |> normalize_optional_string()
      }
      |> reject_nil_values()

    if map_size(comment_context) > 0 do
      %{
        "event" => "issue_comment.created",
        "comment" => comment_context
      }
    else
      nil
    end
  end

  defp follow_up_context(_issue_bot_event, _payload), do: nil

  defp retriage_context(
         "issues.edited",
         %Project{} = project,
         issue_identifiers,
         issue_reference
       )
       when is_map(issue_identifiers) and is_binary(issue_reference) do
    prior_issue_analysis_artifacts =
      list_prior_issue_analysis_artifacts(project, issue_identifiers, issue_reference)

    %{
      "event" => "issues.edited",
      "comparison_context" => %{
        "issue_reference" => issue_reference,
        "prior_issue_analysis_artifact_count" => length(prior_issue_analysis_artifacts),
        "prior_issue_analysis_artifacts" => prior_issue_analysis_artifacts
      }
    }
  end

  defp retriage_context(_issue_bot_event, _project, _issue_identifiers, _issue_reference), do: nil

  defp list_prior_issue_analysis_artifacts(
         %Project{} = project,
         issue_identifiers,
         issue_reference
       )
       when is_map(issue_identifiers) and is_binary(issue_reference) do
    project_id = project |> Map.get(:id) |> normalize_optional_string()

    issue_number =
      issue_identifiers
      |> map_get(:number, "number")
      |> normalize_optional_positive_integer()

    issue_id =
      issue_identifiers
      |> map_get(:id, "id")
      |> normalize_optional_positive_integer()

    if is_binary(project_id) do
      case WorkflowRun.read(
             query: [
               filter: [project_id: project_id, workflow_name: @issue_triage_workflow_name],
               sort: [inserted_at: :desc],
               limit: @retriage_prior_issue_analysis_limit
             ],
             actor: @webhook_actor
           ) do
        {:ok, prior_runs} when is_list(prior_runs) ->
          prior_runs
          |> Enum.filter(&matching_issue_triage_run?(&1, issue_reference, issue_number, issue_id))
          |> Enum.map(&prior_issue_analysis_artifact_link/1)

        {:ok, _other} ->
          []

        {:error, reason} ->
          Logger.warning(
            "github_webhook_retriage_history_lookup_failed reason=#{inspect(reason)} project_id=#{project_id} issue_reference=#{issue_reference}"
          )

          []
      end
    else
      []
    end
  end

  defp list_prior_issue_analysis_artifacts(_project, _issue_identifiers, _issue_reference), do: []

  defp matching_issue_triage_run?(%WorkflowRun{} = run, issue_reference, issue_number, issue_id)
       when is_binary(issue_reference) do
    run_issue_reference =
      run
      |> Map.get(:inputs, %{})
      |> map_get(:issue_reference, @issue_reference_input_name)
      |> normalize_optional_string()

    run_source_issue =
      run
      |> Map.get(:trigger, %{})
      |> map_get(:source_issue, "source_issue", %{})

    run_issue_number =
      run_source_issue
      |> map_get(:number, "number")
      |> normalize_optional_positive_integer()

    run_issue_id =
      run_source_issue
      |> map_get(:id, "id")
      |> normalize_optional_positive_integer()

    run_issue_reference == issue_reference or
      (is_integer(issue_number) and run_issue_number == issue_number) or
      (is_integer(issue_id) and run_issue_id == issue_id)
  end

  defp matching_issue_triage_run?(_run, _issue_reference, _issue_number, _issue_id), do: false

  defp prior_issue_analysis_artifact_link(%WorkflowRun{} = run) do
    trigger = Map.get(run, :trigger, %{})
    source_row = map_get(trigger, :source_row, "source_row", %{})
    source_issue = map_get(trigger, :source_issue, "source_issue", %{})

    step_results =
      case Map.get(run, :step_results) do
        %{} = result_map -> result_map
        _other -> %{}
      end

    %{
      "run_id" => run |> Map.get(:run_id) |> normalize_optional_string(),
      "status" => run |> Map.get(:status) |> normalize_optional_string(),
      "delivery_id" => source_row |> map_get(:delivery_id, "delivery_id") |> normalize_optional_string(),
      "issue_reference" =>
        run
        |> Map.get(:inputs, %{})
        |> map_get(:issue_reference, @issue_reference_input_name)
        |> normalize_optional_string(),
      "artifact_keys" => step_results |> Map.keys() |> normalize_string_list(),
      "source_issue" =>
        reject_nil_values(%{
          "number" => source_issue |> map_get(:number, "number") |> normalize_optional_positive_integer(),
          "id" => source_issue |> map_get(:id, "id") |> normalize_optional_positive_integer()
        }),
      "started_at" => run |> Map.get(:started_at) |> normalize_datetime_string(),
      "completed_at" => run |> Map.get(:completed_at) |> normalize_datetime_string()
    }
    |> reject_nil_values()
  end

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
  end

  defp normalize_string_list(_values), do: []

  defp normalize_datetime_string(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp normalize_datetime_string(%NaiveDateTime{} = datetime) do
    datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp normalize_datetime_string(datetime) when is_binary(datetime),
    do: normalize_optional_string(datetime)

  defp normalize_datetime_string(_datetime), do: nil

  defp log_issue_bot_disabled_noop(delivery, issue_bot_event, project) do
    Logger.info(
      "github_webhook_trigger_filtered outcome=noop policy=support_agent_config.github_issue_bot.enabled delivery_id=#{log_value(Map.get(delivery, :delivery_id))} event=#{issue_bot_event} project_id=#{log_value(Map.get(project, :id))}"
    )
  end

  defp log_webhook_event_filtered_noop(delivery, issue_bot_event, configured_events) do
    Logger.info(
      "github_webhook_trigger_filtered outcome=noop policy=support_agent_config.github_issue_bot.webhook_events delivery_id=#{log_value(Map.get(delivery, :delivery_id))} event=#{issue_bot_event} configured_events=#{log_repositories(configured_events)}"
    )
  end

  defp supported_issue_bot_webhook_events do
    SupportAgentConfigs.supported_issue_bot_webhook_events()
  end

  defp dispatch_verified_delivery(delivery) do
    dispatcher =
      Application.get_env(
        :jido_code,
        :github_webhook_verified_dispatcher,
        &__MODULE__.default_dispatcher/1
      )

    case safe_dispatch(dispatcher, delivery) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error(
          "github_webhook_pipeline_dispatch_failed reason=#{inspect(reason)} delivery_id=#{log_value(Map.get(delivery, :delivery_id))} event=#{log_value(Map.get(delivery, :event))}"
        )

        {:error, :verified_dispatch_failed}
    end
  end

  defp safe_dispatch(dispatcher, delivery) when is_function(dispatcher, 1) do
    try do
      case dispatcher.(delivery) do
        :ok -> :ok
        {:ok, _result} -> :ok
        {:error, reason} -> {:error, reason}
        other -> {:error, {:unexpected_dispatch_result, other}}
      end
    rescue
      exception ->
        {:error, {:dispatch_exception, Exception.message(exception)}}
    catch
      kind, reason ->
        {:error, {:dispatch_throw, {kind, reason}}}
    end
  end

  defp safe_dispatch(_dispatcher, _delivery), do: {:error, :invalid_dispatcher}

  defp sort_webhook_events_by_supported_order(webhook_events) when is_list(webhook_events) do
    supported_issue_bot_webhook_events()
    |> Enum.filter(&(&1 in webhook_events))
  end

  defp sort_webhook_events_by_supported_order(_webhook_events), do: []

  defp normalize_webhook_events(webhook_events) when is_binary(webhook_events) do
    webhook_events
    |> normalize_optional_string()
    |> case do
      nil -> []
      normalized_event -> [normalized_event]
    end
  end

  defp normalize_webhook_events(webhook_events) when is_list(webhook_events) do
    webhook_events
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_webhook_events(_webhook_events), do: []

  defp issue_bot_approval_policy(approval_mode) do
    normalized_mode = normalize_issue_bot_approval_mode(approval_mode)

    if normalized_mode == @approval_mode_auto_post do
      %{
        "mode" => @approval_mode_auto_post,
        "post_behavior" => @approval_mode_auto_post,
        "auto_post" => true,
        "requires_approval" => false,
        "source" => @approval_policy_source
      }
    else
      %{
        "mode" => @approval_mode_approval_required,
        "post_behavior" => @approval_mode_approval_required,
        "auto_post" => false,
        "requires_approval" => true,
        "source" => @approval_policy_source
      }
    end
  end

  defp normalize_issue_bot_approval_mode(approval_mode) when is_binary(approval_mode) do
    case approval_mode |> String.trim() |> String.downcase() do
      "auto_post" -> @approval_mode_auto_post
      "auto-post" -> @approval_mode_auto_post
      "auto" -> @approval_mode_auto_post
      "approval_required" -> @approval_mode_approval_required
      "approval-required" -> @approval_mode_approval_required
      "manual" -> @approval_mode_approval_required
      "manual_gate" -> @approval_mode_approval_required
      "manual-gate" -> @approval_mode_approval_required
      _other -> @default_issue_bot_approval_mode
    end
  end

  defp normalize_issue_bot_approval_mode(approval_mode) when is_atom(approval_mode) do
    approval_mode
    |> Atom.to_string()
    |> normalize_issue_bot_approval_mode()
  end

  defp normalize_issue_bot_approval_mode(_approval_mode), do: @default_issue_bot_approval_mode

  defp normalize_enabled(true, _default), do: true
  defp normalize_enabled(false, _default), do: false
  defp normalize_enabled("true", _default), do: true
  defp normalize_enabled("false", _default), do: false
  defp normalize_enabled("enabled", _default), do: true
  defp normalize_enabled("disabled", _default), do: false
  defp normalize_enabled(:enabled, _default), do: true
  defp normalize_enabled(:disabled, _default), do: false
  defp normalize_enabled(_enabled, default), do: default

  defp generated_run_id do
    "run-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp reject_nil_values(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      if is_nil(value), do: acc, else: Map.put(acc, key, value)
    end)
  end

  defp reject_nil_values(_map), do: %{}

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp map_has_key?(map, atom_key, string_key) when is_map(map) do
    Map.has_key?(map, atom_key) or Map.has_key?(map, string_key)
  end

  defp map_has_key?(_map, _atom_key, _string_key), do: false

  defp log_value(value) when is_binary(value) and value != "", do: value
  defp log_value(_value), do: "unknown"

  defp log_integer_value(value) when is_integer(value) and value > 0, do: Integer.to_string(value)
  defp log_integer_value(_value), do: "unknown"

  defp log_repositories([]), do: "none"
  defp log_repositories(repositories) when is_list(repositories), do: Enum.join(repositories, ",")

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: normalize_optional_string(Atom.to_string(value))

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(value) when is_float(value), do: :erlang.float_to_binary(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_optional_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp normalize_optional_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed_value, ""} when parsed_value > 0 -> parsed_value
      _other -> nil
    end
  end

  defp normalize_optional_positive_integer(_value), do: nil
end
