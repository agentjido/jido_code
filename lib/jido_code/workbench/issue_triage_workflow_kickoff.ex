defmodule JidoCode.Workbench.IssueTriageWorkflowKickoff do
  # covers: architecture.demand_ingress.entrypoint_policy_metadata_preserved
  # covers: architecture.run_governance.review_policy_controls_change_request_creation
  @moduledoc """
  Validates policy and launches issue triage workflow runs from workbench issue quick actions.
  """

  alias JidoCode.Governance.PolicyBridge
  alias JidoCode.ManagedRepoRoutes
  alias JidoCode.Operations.Ingress

  @fallback_row_id_prefix "workbench-row-"
  @workflow_name "issue_triage"

  @default_policy "issue_triage_manual_launch"
  @default_error_type "workbench_issue_triage_workflow_kickoff_failed"
  @validation_error_type "workbench_issue_triage_workflow_validation_failed"
  @policy_error_type "workbench_issue_triage_policy_blocked"
  @approval_mode_auto_post "auto_post"
  @approval_mode_approval_required "approval_required"
  @default_issue_bot_approval_mode @approval_mode_approval_required
  @approval_policy_source "support_agent_config.github_issue_bot.approval_mode"

  @validation_remediation """
  Select a valid imported project issue row and retry triage kickoff from workbench.
  """

  @policy_remediation """
  Enable issue triage policy for this project and retry from workbench.
  """

  @launcher_remediation """
  Verify issue triage workflow runtime setup and retry kickoff from workbench.
  """

  @type kickoff_error :: %{
          error_type: String.t(),
          detail: String.t(),
          remediation: String.t(),
          run_creation_state: :created | :not_created | nil,
          run_id: String.t() | nil
        }

  @type policy_state :: %{
          status: :enabled | :disabled,
          enabled: boolean(),
          policy: String.t(),
          approval_policy: map(),
          error_type: String.t() | nil,
          detail: String.t() | nil,
          remediation: String.t() | nil
        }

  @type kickoff_run :: %{
          run_id: String.t(),
          workflow_name: String.t(),
          project_id: String.t(),
          project_name: String.t(),
          context_item_type: :issue,
          context_item_label: String.t(),
          context_item_url: String.t() | nil,
          trigger: map(),
          initiating_actor: map(),
          detail_path: String.t(),
          started_at: DateTime.t()
        }

  @spec kickoff(map() | nil, term(), map() | nil) ::
          {:ok, kickoff_run()} | {:error, kickoff_error()}
  def kickoff(project_row, context_item_type, initiating_actor),
    do: kickoff(project_row, context_item_type, initiating_actor, [])

  @spec kickoff(map() | nil, term(), map() | nil, keyword()) ::
          {:ok, kickoff_run()} | {:error, kickoff_error()}
  def kickoff(project_row, context_item_type, initiating_actor, opts) when is_list(opts) do
    with {:ok, project_scope} <- normalize_project_scope(project_row),
         {:ok, normalized_context_item_type} <- normalize_context_item_type(context_item_type),
         {:ok, triage_policy_state} <- ensure_policy_enabled(project_row),
         normalized_actor <- normalize_initiating_actor(initiating_actor),
         kickoff_request <-
           build_kickoff_request(
             project_scope,
             normalized_context_item_type,
             normalized_actor,
             triage_policy_state,
             opts
           ),
         :ok <- record_workbench_intake(kickoff_request),
         {:ok, kickoff_run} <- invoke_launcher(kickoff_request) do
      {:ok, kickoff_run}
    else
      {:error, error} ->
        {:error, normalize_error(error)}

      other ->
        {:error,
         kickoff_error(
           @default_error_type,
           "Issue triage workflow kickoff failed with an unexpected result (#{inspect(other)}).",
           @launcher_remediation
         )}
    end
  end

  @spec policy_state(map() | nil) :: policy_state()
  def policy_state(project_row) when is_map(project_row) do
    explicit_policy = map_get(project_row, :issue_triage_policy, "issue_triage_policy")

    cond do
      is_map(explicit_policy) and explicit_policy_disabled?(explicit_policy) ->
        normalize_policy_state(explicit_policy)

      true ->
        case policy_state_from_governance(project_row) do
          {:ok, triage_policy_state} ->
            triage_policy_state

          :error ->
            case explicit_policy do
              triage_policy when is_map(triage_policy) ->
                normalize_policy_state(triage_policy)

              _other ->
                project_row
                |> map_get(:settings, "settings", %{})
                |> normalize_map()
                |> policy_state_from_settings()
            end
        end
    end
  end

  def policy_state(_project_row), do: enabled_policy_state()

  defp policy_state_from_governance(project_row) when is_map(project_row) do
    managed_repo_id =
      project_row
      |> map_get(:managed_repo_id, "managed_repo_id")
      |> normalize_optional_string()

    project_id =
      project_row
      |> map_get(:id, "id")
      |> normalize_optional_string()

    approval_policy_result =
      cond do
        is_binary(managed_repo_id) ->
          PolicyBridge.approval_policy_for_managed_repo(managed_repo_id)

        is_binary(project_id) ->
          PolicyBridge.approval_policy_for_project(project_id)

        true ->
          :error
      end

    case approval_policy_result do
      {:ok, approval_policy} ->
        {:ok, enabled_policy_state(@default_policy, approval_policy)}

      _other ->
        :error
    end
  end

  defp policy_state_from_governance(_project_row), do: :error

  defp explicit_policy_disabled?(policy) when is_map(policy) do
    normalized_policy = normalize_policy_state(policy)
    normalized_policy.enabled == false or normalized_policy.status == :disabled
  end

  defp explicit_policy_disabled?(_policy), do: false

  @doc false
  @spec default_launcher(map()) :: {:ok, map()}
  def default_launcher(_kickoff_request) do
    {:ok,
     %{
       run_id: generated_run_id(),
       started_at: DateTime.utc_now() |> DateTime.truncate(:second)
     }}
  end

  defp invoke_launcher(kickoff_request) do
    launcher =
      Application.get_env(
        :jido_code,
        :workbench_issue_triage_workflow_launcher,
        &__MODULE__.default_launcher/1
      )

    if is_function(launcher, 1) do
      safe_invoke_launcher(launcher, kickoff_request)
    else
      {:error,
       kickoff_error(
         @default_error_type,
         "Workbench issue triage workflow launcher configuration is invalid.",
         @launcher_remediation
       )}
    end
  end

  defp safe_invoke_launcher(launcher, kickoff_request) do
    try do
      case launcher.(kickoff_request) do
        {:ok, run_result} ->
          normalize_run_result(run_result, kickoff_request)

        {:error, error} ->
          {:error, normalize_error(error)}

        other ->
          {:error,
           kickoff_error(
             @default_error_type,
             "Issue triage workflow launcher returned an invalid result (#{inspect(other)}).",
             @launcher_remediation
           )}
      end
    rescue
      exception ->
        {:error,
         kickoff_error(
           @default_error_type,
           "Issue triage workflow launcher crashed (#{Exception.message(exception)}).",
           @launcher_remediation
         )}
    catch
      kind, reason ->
        {:error,
         kickoff_error(
           @default_error_type,
           "Issue triage workflow launcher threw #{inspect({kind, reason})}.",
           @launcher_remediation
         )}
    end
  end

  defp normalize_run_result(run_result, kickoff_request) do
    run_id = extract_run_id(run_result)

    if is_binary(run_id) do
      started_at =
        run_result
        |> map_get(:started_at, "started_at")
        |> normalize_optional_datetime() ||
          DateTime.utc_now() |> DateTime.truncate(:second)

      context_item = Map.fetch!(kickoff_request, :context_item)
      project_id = Map.fetch!(kickoff_request, :project_id)

      {:ok,
       %{
         run_id: run_id,
         workflow_name: Map.fetch!(kickoff_request, :workflow_name),
         project_id: project_id,
         project_name: Map.fetch!(kickoff_request, :project_name),
         context_item_type: Map.fetch!(context_item, :type),
         context_item_label: Map.fetch!(context_item, :label),
         context_item_url: Map.get(context_item, :github_url),
         trigger: Map.fetch!(kickoff_request, :trigger),
         initiating_actor: Map.fetch!(kickoff_request, :initiating_actor),
         detail_path:
           ManagedRepoRoutes.run_detail_path(
             project_id,
             run_id,
             return_to: Map.get(kickoff_request, :return_to)
           ),
         started_at: started_at
       }}
    else
      {:error,
       kickoff_error(
         @default_error_type,
         "Issue triage workflow kickoff did not return a run identifier.",
         @launcher_remediation
       )}
    end
  end

  defp extract_run_id(run_result) when is_binary(run_result),
    do: normalize_optional_string(run_result)

  defp extract_run_id(run_result) when is_map(run_result) do
    run_result
    |> map_get(:run_id, "run_id")
    |> normalize_optional_string()
  end

  defp extract_run_id(_run_result), do: nil

  defp build_kickoff_request(
         project_scope,
         :issue = context_item_type,
         initiating_actor,
         triage_policy_state,
         opts
       ) do
    project_id = Map.fetch!(project_scope, :project_id)
    approval_policy = Map.fetch!(triage_policy_state, :approval_policy)
    return_to = opts |> Keyword.get(:return_to) |> normalize_optional_string()

    %{
      workflow_name: @workflow_name,
      project_id: project_id,
      project_name: Map.fetch!(project_scope, :project_name),
      return_to: return_to,
      trigger: %{
        source: "workbench",
        mode: "manual",
        source_row: %{
          route: return_to || "/workbench",
          project_id: project_id,
          context_item_type: context_item_type
        },
        approval_policy: approval_policy,
        policy: %{
          name: Map.fetch!(triage_policy_state, :policy),
          approval_policy: approval_policy
        }
      },
      initiating_actor: initiating_actor,
      context_item: %{
        type: context_item_type,
        label: context_item_label(context_item_type),
        github_url:
          context_item_github_url(
            Map.get(project_scope, :github_full_name),
            context_item_type
          )
      }
    }
  end

  defp record_workbench_intake(kickoff_request) do
    case Ingress.record_operator_intake(%{
           channel: "workbench",
           intent: "issue_triage_workflow_kickoff",
           project_id: Map.fetch!(kickoff_request, :project_id),
           actor: Map.fetch!(kickoff_request, :initiating_actor),
           payload: %{
             "workflow_name" => Map.fetch!(kickoff_request, :workflow_name),
             "project_name" => Map.fetch!(kickoff_request, :project_name),
             "context_item" => Map.fetch!(kickoff_request, :context_item)
           },
           source_metadata: %{
             "trigger" => Map.fetch!(kickoff_request, :trigger)
           }
         }) do
      {:ok, _intake} -> :ok
      {:error, reason} -> {:error, intake_error(reason)}
    end
  end

  defp context_item_label(:issue), do: "Issue row"

  defp context_item_github_url(nil, _context_item_type), do: nil

  defp context_item_github_url(github_full_name, :issue) do
    with {:ok, repository_path} <- github_repository_path(github_full_name) do
      "#{repository_path}/issues"
    end
  end

  defp normalize_project_scope(project_row) when is_map(project_row) do
    project_id =
      project_row
      |> map_get(:id, "id")
      |> normalize_optional_string()

    github_full_name =
      project_row
      |> map_get(:github_full_name, "github_full_name")
      |> normalize_optional_string()

    project_name =
      project_row
      |> map_get(:name, "name")
      |> normalize_optional_string()

    cond do
      is_nil(project_id) ->
        {:error, validation_error("Workbench row is missing a durable project identifier for issue triage kickoff.")}

      String.starts_with?(project_id, @fallback_row_id_prefix) ->
        {:error,
         validation_error("Workbench row #{project_id} is synthetic and cannot scope issue triage workflow runs.")}

      true ->
        {:ok,
         %{
           project_id: project_id,
           project_name: github_full_name || project_name || project_id,
           github_full_name: github_full_name
         }}
    end
  end

  defp normalize_project_scope(_project_row) do
    {:error, validation_error("Workbench row is unavailable for issue triage kickoff.")}
  end

  defp normalize_context_item_type(:issue), do: {:ok, :issue}
  defp normalize_context_item_type("issue"), do: {:ok, :issue}

  defp normalize_context_item_type(other) do
    {:error, validation_error("Workbench triage kickoff context #{inspect(other)} is invalid. Use issue.")}
  end

  defp ensure_policy_enabled(project_row) do
    triage_policy_state = policy_state(project_row)

    if Map.get(triage_policy_state, :enabled, true) do
      {:ok, triage_policy_state}
    else
      {:error, policy_blocked_error(triage_policy_state)}
    end
  end

  defp policy_state_from_settings(settings) when is_map(settings) do
    issue_triage_policy =
      settings
      |> map_get(:issue_triage_policy, "issue_triage_policy")
      |> normalize_map_or_nil()

    issue_triage_settings =
      settings
      |> map_get(:issue_triage, "issue_triage")
      |> normalize_map_or_nil()

    issue_bot_settings =
      settings
      |> map_get(:issue_bot, "issue_bot")
      |> normalize_map_or_nil()

    support_agent_issue_bot_settings =
      settings
      |> map_get(:support_agent_config, "support_agent_config", %{})
      |> normalize_map()
      |> map_get(:github_issue_bot, "github_issue_bot")
      |> normalize_map_or_nil()

    approval_policy = issue_bot_approval_policy_from_settings(settings)

    cond do
      is_map(issue_triage_policy) ->
        normalize_policy_state(issue_triage_policy)

      policy_explicitly_disabled?(issue_triage_settings) ->
        disabled_policy_state(
          "Issue triage workflow launches are disabled for this project.",
          issue_triage_settings,
          "issue_triage.enabled",
          approval_policy
        )

      policy_explicitly_disabled?(issue_bot_settings) ->
        disabled_policy_state(
          "Issue Bot is disabled for this project.",
          issue_bot_settings,
          "issue_bot.enabled",
          approval_policy
        )

      policy_explicitly_disabled?(support_agent_issue_bot_settings) ->
        disabled_policy_state(
          "Issue Bot support agent is disabled for this project.",
          support_agent_issue_bot_settings,
          "support_agent_config.github_issue_bot.enabled",
          approval_policy
        )

      true ->
        enabled_policy_state(@default_policy, approval_policy)
    end
  end

  defp policy_state_from_settings(_settings), do: enabled_policy_state()

  defp normalize_policy_state(policy) when is_map(policy) do
    policy_name = normalize_optional_string(map_get(policy, :policy, "policy")) || @default_policy

    approval_policy =
      policy |> map_get(:approval_policy, "approval_policy") |> normalize_approval_policy()

    if policy_explicitly_disabled?(policy) do
      disabled_policy_state(
        map_get(policy, :detail, "detail", nil),
        policy,
        policy_name,
        approval_policy
      )
    else
      enabled_policy_state(policy_name, approval_policy)
    end
  end

  defp normalize_policy_state(_policy), do: enabled_policy_state()

  defp policy_explicitly_disabled?(policy) when is_map(policy) do
    case map_get(policy, :enabled, "enabled", :__missing__) do
      :__missing__ ->
        policy
        |> map_get(:status, "status")
        |> normalize_optional_string()
        |> case do
          "disabled" -> true
          "blocked" -> true
          _other -> false
        end

      enabled_value ->
        normalize_enabled(enabled_value, true) == false
    end
  end

  defp policy_explicitly_disabled?(_policy), do: false

  defp enabled_policy_state(
         policy_name \\ @default_policy,
         approval_policy \\ default_issue_bot_approval_policy()
       ) do
    %{
      status: :enabled,
      enabled: true,
      policy: normalize_optional_string(policy_name) || @default_policy,
      approval_policy: normalize_approval_policy(approval_policy),
      error_type: nil,
      detail: nil,
      remediation: nil
    }
  end

  defp disabled_policy_state(
         detail,
         policy_source,
         fallback_policy_name,
         approval_policy
       ) do
    %{
      status: :disabled,
      enabled: false,
      policy:
        normalize_optional_string(map_get(policy_source, :policy, "policy", fallback_policy_name)) ||
          @default_policy,
      approval_policy: normalize_approval_policy(approval_policy),
      error_type:
        normalize_optional_string(map_get(policy_source, :error_type, "error_type", @policy_error_type)) ||
          @policy_error_type,
      detail:
        normalize_optional_string(detail) ||
          normalize_optional_string(map_get(policy_source, :detail, "detail")) ||
          "Issue triage workflow launches from workbench are disabled by policy.",
      remediation:
        normalize_optional_string(map_get(policy_source, :remediation, "remediation", @policy_remediation)) ||
          @policy_remediation
    }
  end

  defp issue_bot_approval_policy_from_settings(settings) when is_map(settings) do
    settings
    |> map_get(:support_agent_config, "support_agent_config", %{})
    |> normalize_map()
    |> map_get(:github_issue_bot, "github_issue_bot", %{})
    |> normalize_map()
    |> map_get(:approval_mode, "approval_mode")
    |> normalize_issue_bot_approval_mode()
    |> approval_policy_from_mode()
  end

  defp issue_bot_approval_policy_from_settings(_settings), do: default_issue_bot_approval_policy()

  defp default_issue_bot_approval_policy do
    approval_policy_from_mode(@default_issue_bot_approval_mode)
  end

  defp normalize_approval_policy(approval_policy) when is_map(approval_policy) do
    mode =
      approval_policy
      |> map_get(:mode, "mode")
      |> normalize_issue_bot_approval_mode() ||
        infer_issue_bot_approval_mode(approval_policy)

    normalized_policy =
      mode
      |> approval_policy_from_mode()
      |> maybe_put_extra_approval_policy_field(
        :change_request_required,
        map_get(approval_policy, :change_request_required, "change_request_required")
      )
      |> maybe_put_extra_approval_policy_field(
        :review_threshold,
        map_get(approval_policy, :review_threshold, "review_threshold")
      )
      |> maybe_put_extra_approval_policy_field(
        :required_stage,
        map_get(approval_policy, :required_stage, "required_stage")
      )
      |> maybe_put_extra_approval_policy_field(
        :source,
        map_get(approval_policy, :source, "source")
      )

    on_reject = map_get(approval_policy, :on_reject, "on_reject")

    if is_map(on_reject) do
      Map.put(normalized_policy, :on_reject, on_reject)
    else
      normalized_policy
    end
  end

  defp normalize_approval_policy(_approval_policy), do: default_issue_bot_approval_policy()

  defp maybe_put_extra_approval_policy_field(policy, _field, nil), do: policy
  defp maybe_put_extra_approval_policy_field(policy, field, value), do: Map.put(policy, field, value)

  defp infer_issue_bot_approval_mode(approval_policy) do
    cond do
      map_get(approval_policy, :auto_post, "auto_post") == true ->
        @approval_mode_auto_post

      map_get(approval_policy, :requires_approval, "requires_approval") == true ->
        @approval_mode_approval_required

      map_get(approval_policy, :post_behavior, "post_behavior") in ["auto_post", "auto-post"] ->
        @approval_mode_auto_post

      map_get(approval_policy, :post_behavior, "post_behavior") in [
        "approval_required",
        "approval-required",
        "manual",
        "manual_gate",
        "manual-gate"
      ] ->
        @approval_mode_approval_required

      true ->
        @default_issue_bot_approval_mode
    end
  end

  defp approval_policy_from_mode(mode) do
    normalized_mode = normalize_issue_bot_approval_mode(mode)

    if normalized_mode == @approval_mode_auto_post do
      %{
        mode: @approval_mode_auto_post,
        post_behavior: @approval_mode_auto_post,
        auto_post: true,
        requires_approval: false,
        source: @approval_policy_source
      }
    else
      %{
        mode: @approval_mode_approval_required,
        post_behavior: @approval_mode_approval_required,
        auto_post: false,
        requires_approval: true,
        source: @approval_policy_source
      }
    end
  end

  defp normalize_issue_bot_approval_mode(mode) when is_binary(mode) do
    case mode |> String.trim() |> String.downcase() do
      "auto_post" -> @approval_mode_auto_post
      "auto-post" -> @approval_mode_auto_post
      "auto" -> @approval_mode_auto_post
      "approval_required" -> @approval_mode_approval_required
      "approval-required" -> @approval_mode_approval_required
      "manual" -> @approval_mode_approval_required
      "manual_gate" -> @approval_mode_approval_required
      "manual-gate" -> @approval_mode_approval_required
      _other -> nil
    end
  end

  defp normalize_issue_bot_approval_mode(mode) when is_atom(mode) do
    mode
    |> Atom.to_string()
    |> normalize_issue_bot_approval_mode()
  end

  defp normalize_issue_bot_approval_mode(_mode), do: nil

  defp policy_blocked_error(triage_policy_state) do
    kickoff_error(
      Map.get(triage_policy_state, :error_type) || @policy_error_type,
      Map.get(triage_policy_state, :detail) ||
        "Issue triage workflow launch is blocked by policy.",
      Map.get(triage_policy_state, :remediation) || @policy_remediation
    )
  end

  defp normalize_initiating_actor(actor) when is_map(actor) do
    actor_id =
      actor
      |> map_get(:id, "id")
      |> normalize_optional_string() || "unknown"

    %{
      id: actor_id,
      email:
        actor
        |> map_get(:email, "email")
        |> normalize_optional_string()
    }
  end

  defp normalize_initiating_actor(_actor), do: %{id: "unknown", email: nil}

  defp validation_error(detail) do
    kickoff_error(@validation_error_type, detail, @validation_remediation)
  end

  defp normalize_error(error) do
    kickoff_error(
      map_get(error, :error_type, "error_type", @default_error_type),
      map_get(error, :detail, "detail", "Issue triage workflow kickoff failed."),
      map_get(error, :remediation, "remediation", @launcher_remediation),
      map_get(error, :run_creation_state, "run_creation_state"),
      map_get(error, :run_id, "run_id")
    )
  end

  defp intake_error(reason) do
    kickoff_error(
      "workbench_issue_triage_intake_record_failed",
      "Issue triage kickoff could not be normalized into a durable intake (#{inspect(reason)}).",
      @launcher_remediation
    )
  end

  defp kickoff_error(error_type, detail, remediation, run_creation_state \\ nil, run_id \\ nil) do
    %{
      error_type: normalize_optional_string(error_type) || @default_error_type,
      detail: normalize_optional_string(detail) || "Issue triage workflow kickoff failed.",
      remediation: normalize_optional_string(remediation) || @launcher_remediation,
      run_creation_state: normalize_run_creation_state(run_creation_state),
      run_id: normalize_optional_string(run_id)
    }
  end

  defp normalize_run_creation_state(:created), do: :created
  defp normalize_run_creation_state("created"), do: :created
  defp normalize_run_creation_state(:not_created), do: :not_created
  defp normalize_run_creation_state("not_created"), do: :not_created
  defp normalize_run_creation_state(_run_creation_state), do: nil

  defp github_repository_path(github_full_name) do
    github_full_name
    |> normalize_optional_string()
    |> parse_github_repository_name()
    |> case do
      {:ok, owner, repository} -> {:ok, "https://github.com/#{owner}/#{repository}"}
      :error -> :error
    end
  end

  defp parse_github_repository_name(nil), do: :error

  defp parse_github_repository_name(github_full_name) do
    case String.split(github_full_name, "/", parts: 2) do
      [owner, repository] ->
        owner = String.trim(owner)
        repository = String.trim(repository)

        if owner == "" or repository == "" or String.contains?(owner <> repository, " ") do
          :error
        else
          {:ok, owner, repository}
        end

      _other ->
        :error
    end
  end

  defp generated_run_id do
    unique_integer = System.unique_integer([:positive, :monotonic])
    "run-#{unique_integer}"
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

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_boolean(value), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(value) when is_float(value), do: :erlang.float_to_binary(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_optional_datetime(%DateTime{} = datetime), do: datetime

  defp normalize_optional_datetime(%NaiveDateTime{} = datetime) do
    case DateTime.from_naive(datetime, "Etc/UTC") do
      {:ok, parsed_datetime} -> parsed_datetime
      _other -> nil
    end
  end

  defp normalize_optional_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, parsed_datetime, _offset} ->
        parsed_datetime

      _other ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, parsed_naive_datetime} ->
            normalize_optional_datetime(parsed_naive_datetime)

          _fallback ->
            nil
        end
    end
  end

  defp normalize_optional_datetime(_value), do: nil

  defp normalize_enabled(true, _default), do: true
  defp normalize_enabled(false, _default), do: false
  defp normalize_enabled("true", _default), do: true
  defp normalize_enabled("false", _default), do: false
  defp normalize_enabled(:enabled, _default), do: true
  defp normalize_enabled(:disabled, _default), do: false
  defp normalize_enabled("enabled", _default), do: true
  defp normalize_enabled("disabled", _default), do: false
  defp normalize_enabled("blocked", _default), do: false
  defp normalize_enabled(_value, default), do: default

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp normalize_map_or_nil(value) when is_map(value), do: value
  defp normalize_map_or_nil(_value), do: nil
end
