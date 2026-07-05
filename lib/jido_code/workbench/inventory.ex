defmodule JidoCode.Workbench.Inventory do
  # covers: architecture.source_code_graph_product_adoption.managed_repo_routes_host_semantic_inspection
  # covers: architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery
  # covers: architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage
  @moduledoc """
  Loads managed-repo-first workbench inventory rows and stale-state warnings.
  """

  alias JidoCode.Setup.SystemConfig
  alias JidoCode.Control.{Actor, RepoBridge}

  alias JidoCode.Workbench.{
    IssueTriageWorkflowKickoff,
    ProjectConversation,
    ProjectMemoryInspection,
    ProjectSemanticInspection
  }

  @default_fetch_error_type "workbench_inventory_fetch_failed"

  @default_fetch_remediation """
  Retry workbench data fetch. If this persists, review setup step 7 repository sync diagnostics.
  """

  @type row :: %{
          id: String.t(),
          legacy_project_id: String.t() | nil,
          managed_repo_id: String.t() | nil,
          source_repo_id: String.t() | nil,
          workspace_path: String.t() | nil,
          name: String.t(),
          github_full_name: String.t(),
          default_branch: String.t(),
          open_issue_count: non_neg_integer(),
          open_pr_count: non_neg_integer(),
          recent_activity_summary: String.t(),
          recent_activity_at: DateTime.t() | nil,
          issue_triage_policy: map(),
          semantic_graph_hint: map() | nil,
          memory_graph_hint: map() | nil,
          repo_conversation: map() | nil,
          conversation_supervision: map() | nil
        }

  @type stale_warning :: %{
          error_type: String.t(),
          detail: String.t(),
          remediation: String.t()
        }

  @spec load() :: {:ok, [row()], stale_warning() | nil} | {:error, stale_warning()}
  def load do
    loader =
      Application.get_env(:jido_code, :workbench_inventory_loader, &__MODULE__.default_loader/0)

    if is_function(loader, 0) do
      safe_invoke_loader(loader)
    else
      {:error,
       stale_warning(
         "workbench_inventory_loader_invalid",
         "Workbench inventory loader is invalid.",
         @default_fetch_remediation
       )}
    end
  end

  @doc false
  @spec default_loader() :: {:ok, [row()], stale_warning() | nil} | {:error, stale_warning()}
  def default_loader do
    with {:ok, managed_repo_rows} <- managed_repo_rows() do
      rows =
        managed_repo_rows
        |> Enum.sort_by(fn row ->
          row
          |> map_get(:github_full_name, "github_full_name")
          |> normalize_optional_string() ||
            row
            |> map_get(:name, "name")
            |> normalize_optional_string() || ""
        end)

      {:ok, rows, setup_stale_warning()}
    else
      {:error, warning} ->
        {:error,
         normalize_warning(warning) ||
           stale_warning(
             @default_fetch_error_type,
             "Workbench inventory data may be stale.",
             @default_fetch_remediation
           )}
    end
  end

  defp managed_repo_rows do
    case RepoBridge.list_repo_scopes() do
      {:ok, repo_scopes} ->
        {:ok,
         Enum.map(repo_scopes, fn scope ->
           to_inventory_row(scope)
         end)}

      {:error, reason} ->
        {:error,
         stale_warning(
           @default_fetch_error_type,
           "Workbench inventory fetch failed (#{format_reason(reason)}).",
           @default_fetch_remediation
         )}
    end
  end

  defp safe_invoke_loader(loader) do
    try do
      case loader.() do
        {:ok, rows, warning} when is_list(rows) ->
          {:ok, normalize_rows(rows), normalize_warning(warning)}

        {:error, warning} ->
          {:error,
           normalize_warning(warning) ||
             stale_warning(
               @default_fetch_error_type,
               "Workbench inventory data may be stale.",
               @default_fetch_remediation
             )}

        other ->
          {:error,
           stale_warning(
             @default_fetch_error_type,
             "Workbench inventory loader returned an invalid result (#{inspect(other)}).",
             @default_fetch_remediation
           )}
      end
    rescue
      exception ->
        {:error,
         stale_warning(
           @default_fetch_error_type,
           "Workbench inventory loader crashed (#{Exception.message(exception)}).",
           @default_fetch_remediation
         )}
    catch
      kind, reason ->
        {:error,
         stale_warning(
           @default_fetch_error_type,
           "Workbench inventory loader threw #{inspect({kind, reason})}.",
           @default_fetch_remediation
         )}
    end
  end

  defp setup_stale_warning do
    case SystemConfig.load() do
      {:ok, config} ->
        config
        |> Map.get(:onboarding_state, %{})
        |> repository_listing_warning()

      {:error, reason} ->
        stale_warning(
          "workbench_setup_state_unavailable",
          "Setup diagnostics are unavailable (#{format_reason(reason)}). Workbench data may be stale.",
          @default_fetch_remediation
        )
    end
  end

  defp repository_listing_warning(onboarding_state) when is_map(onboarding_state) do
    listing =
      onboarding_state
      |> fetch_step_state(7)
      |> map_get(:repository_listing, "repository_listing", %{})

    listing_status =
      listing
      |> map_get(:status, "status")
      |> normalize_repository_listing_status()

    case listing_status do
      :ready ->
        nil

      :blocked ->
        stale_warning(
          map_get(listing, :error_type, "error_type", "workbench_repository_listing_stale"),
          map_get(
            listing,
            :detail,
            "detail",
            "Repository listing is blocked and workbench inventory may be stale."
          ),
          map_get(
            listing,
            :remediation,
            "remediation",
            "Retry repository refresh in setup step 7 and then reload workbench inventory."
          )
        )

      _other ->
        nil
    end
  end

  defp repository_listing_warning(_onboarding_state), do: nil

  defp to_inventory_row(%{} = scope) do
    managed_repo = map_get(scope, :managed_repo, "managed_repo")
    source_repo = map_get(scope, :source_repo, "source_repo")

    managed_workspace_settings =
      managed_repo
      |> map_get(:workspace_settings, "workspace_settings", %{})
      |> normalize_map()

    managed_execution_settings =
      managed_repo
      |> map_get(:execution_settings, "execution_settings", %{})
      |> normalize_map()

    managed_integration_settings =
      managed_repo
      |> map_get(:integration_settings, "integration_settings", %{})
      |> normalize_map()

    inventory_settings =
      managed_integration_settings
      |> map_get(:inventory, "inventory", %{})
      |> normalize_map()

    github_settings =
      source_repo
      |> map_get(:source_metadata, "source_metadata", %{})
      |> normalize_map()
      |> Map.get("github", %{})
      |> normalize_map()

    workspace_settings = managed_workspace_settings

    recent_activity_at =
      resolve_recent_activity_at(scope, inventory_settings, github_settings, workspace_settings)

    legacy_project_id =
      scope
      |> map_get(:project_id, "project_id")
      |> normalize_optional_string() ||
        managed_repo
        |> map_get(:legacy_project_id, "legacy_project_id")
        |> normalize_optional_string()

    managed_repo_id =
      scope
      |> map_get(:managed_repo_id, "managed_repo_id")
      |> normalize_optional_string() ||
        managed_repo
        |> map_get(:id, "id")
        |> normalize_optional_string()

    source_repo_id =
      scope
      |> map_get(:source_repo_id, "source_repo_id")
      |> normalize_optional_string() ||
        source_repo
        |> map_get(:id, "id")
        |> normalize_optional_string()

    route_id =
      scope
      |> map_get(:route_id, "route_id")
      |> normalize_optional_string() ||
        managed_repo_id || source_repo_id || legacy_project_id

    settings =
      %{}
      |> Map.put("workspace", workspace_settings)
      |> Map.put("execution", managed_execution_settings)
      |> Map.merge(managed_integration_settings)

    row = %{
      id: route_id,
      legacy_project_id: legacy_project_id,
      managed_repo_id: managed_repo_id,
      source_repo_id: source_repo_id,
      workspace_path:
        workspace_settings
        |> map_get(:workspace_path, "workspace_path")
        |> normalize_optional_string(),
      name:
        managed_repo
        |> map_get(:display_name, "display_name")
        |> normalize_optional_string() ||
          source_repo
          |> map_get(:name, "name")
          |> normalize_optional_string(),
      github_full_name:
        source_repo
        |> map_get(:full_name, "full_name")
        |> normalize_optional_string(),
      default_branch:
        source_repo
        |> map_get(:default_branch, "default_branch")
        |> normalize_optional_string() || "main",
      open_issue_count:
        first_non_negative_integer([
          map_get(inventory_settings, :open_issue_count, "open_issue_count"),
          map_get(inventory_settings, :open_issues_count, "open_issues_count"),
          map_get(github_settings, :open_issue_count, "open_issue_count"),
          map_get(github_settings, :open_issues_count, "open_issues_count"),
          map_get(settings, :open_issue_count, "open_issue_count"),
          map_get(settings, :open_issues_count, "open_issues_count")
        ]),
      open_pr_count:
        first_non_negative_integer([
          map_get(inventory_settings, :open_pr_count, "open_pr_count"),
          map_get(inventory_settings, :open_prs_count, "open_prs_count"),
          map_get(inventory_settings, :open_pull_request_count, "open_pull_request_count"),
          map_get(inventory_settings, :open_pull_requests_count, "open_pull_requests_count"),
          map_get(github_settings, :open_pr_count, "open_pr_count"),
          map_get(github_settings, :open_prs_count, "open_prs_count"),
          map_get(github_settings, :open_pull_request_count, "open_pull_request_count"),
          map_get(github_settings, :open_pull_requests_count, "open_pull_requests_count"),
          map_get(settings, :open_pr_count, "open_pr_count"),
          map_get(settings, :open_prs_count, "open_prs_count"),
          map_get(settings, :open_pull_request_count, "open_pull_request_count"),
          map_get(settings, :open_pull_requests_count, "open_pull_requests_count")
        ]),
      recent_activity_summary:
        resolve_recent_activity_summary(
          settings,
          inventory_settings,
          github_settings,
          recent_activity_at
        ),
      recent_activity_at: recent_activity_at,
      issue_triage_policy:
        IssueTriageWorkflowKickoff.policy_state(%{
          id: route_id,
          name:
            managed_repo
            |> map_get(:display_name, "display_name")
            |> normalize_optional_string(),
          github_full_name:
            source_repo
            |> map_get(:full_name, "full_name")
            |> normalize_optional_string(),
          settings: settings,
          managed_repo_id: managed_repo_id,
          source_repo_id: source_repo_id
        })
    }

    conversation_supervision =
      managed_repo_id &&
        ProjectConversation.load_supervision_summary(managed_repo_id, actor: Actor.operator_actor())

    row
    |> Map.put(:semantic_graph_hint, ProjectSemanticInspection.status_hint(row))
    |> Map.put(:memory_graph_hint, ProjectMemoryInspection.status_hint(row))
    |> Map.put(
      :repo_conversation,
      managed_repo_id &&
        ProjectConversation.load_repo_detail(
          %{managed_repo_id: managed_repo_id},
          actor: Actor.operator_actor()
        )
    )
    |> Map.put(:conversation_supervision, conversation_supervision)
  end

  defp resolve_recent_activity_summary(
         settings,
         inventory_settings,
         github_settings,
         recent_activity_at
       ) do
    summary =
      first_non_empty_string([
        map_get(inventory_settings, :recent_activity_summary, "recent_activity_summary"),
        map_get(inventory_settings, :activity_summary, "activity_summary"),
        map_get(github_settings, :recent_activity_summary, "recent_activity_summary"),
        map_get(github_settings, :activity_summary, "activity_summary"),
        map_get(settings, :recent_activity_summary, "recent_activity_summary"),
        map_get(settings, :activity_summary, "activity_summary")
      ])

    summary ||
      case recent_activity_at do
        nil -> "No recent activity metadata."
        datetime -> "Last activity: #{format_utc_datetime(datetime)}"
      end
  end

  defp resolve_recent_activity_at(
         scope,
         inventory_settings,
         github_settings,
         workspace_settings
       ) do
    first_datetime([
      map_get(inventory_settings, :recent_activity_at, "recent_activity_at"),
      map_get(inventory_settings, :last_activity_at, "last_activity_at"),
      map_get(github_settings, :pushed_at, "pushed_at"),
      map_get(github_settings, :updated_at, "updated_at"),
      map_get(workspace_settings, :last_synced_at, "last_synced_at"),
      map_get(map_get(scope, :managed_repo, "managed_repo"), :updated_at, "updated_at"),
      map_get(map_get(scope, :source_repo, "source_repo"), :updated_at, "updated_at"),
      map_get(map_get(scope, :source_repo, "source_repo"), :inserted_at, "inserted_at")
    ])
  end

  defp normalize_rows(rows) do
    rows
    |> Enum.with_index()
    |> Enum.map(fn {row, index} -> normalize_row(row, index) end)
  end

  defp normalize_row(row, index) when is_map(row) do
    fallback_id = "workbench-row-#{index + 1}"

    github_full_name =
      row
      |> map_get(:github_full_name, "github_full_name")
      |> normalize_optional_string()

    name =
      row
      |> map_get(:name, "name")
      |> normalize_optional_string()

    recent_activity_at =
      row
      |> map_get(:recent_activity_at, "recent_activity_at")
      |> normalize_optional_datetime()

    %{
      id:
        row
        |> map_get(:id, "id")
        |> normalize_optional_string() || fallback_id,
      legacy_project_id:
        row
        |> map_get(:legacy_project_id, "legacy_project_id")
        |> normalize_optional_string(),
      managed_repo_id:
        row
        |> map_get(:managed_repo_id, "managed_repo_id")
        |> normalize_optional_string(),
      source_repo_id:
        row
        |> map_get(:source_repo_id, "source_repo_id")
        |> normalize_optional_string(),
      workspace_path:
        row
        |> map_get(:workspace_path, "workspace_path")
        |> normalize_optional_string(),
      name: name || github_full_name || fallback_id,
      github_full_name: github_full_name || name || fallback_id,
      default_branch:
        row
        |> map_get(:default_branch, "default_branch")
        |> normalize_optional_string() || "main",
      open_issue_count:
        row
        |> map_get(:open_issue_count, "open_issue_count", 0)
        |> parse_non_negative_integer()
        |> case do
          nil -> 0
          value -> value
        end,
      open_pr_count:
        row
        |> map_get(:open_pr_count, "open_pr_count", 0)
        |> parse_non_negative_integer()
        |> case do
          nil -> 0
          value -> value
        end,
      recent_activity_summary:
        row
        |> map_get(:recent_activity_summary, "recent_activity_summary")
        |> normalize_optional_string() ||
          case recent_activity_at do
            nil -> "No recent activity metadata."
            datetime -> "Last activity: #{format_utc_datetime(datetime)}"
          end,
      recent_activity_at: recent_activity_at,
      issue_triage_policy: IssueTriageWorkflowKickoff.policy_state(row),
      semantic_graph_hint:
        row
        |> map_get(:semantic_graph_hint, "semantic_graph_hint")
        |> normalize_semantic_graph_hint() ||
          ProjectSemanticInspection.status_hint(row),
      memory_graph_hint:
        row
        |> map_get(:memory_graph_hint, "memory_graph_hint")
        |> normalize_memory_graph_hint() ||
          ProjectMemoryInspection.status_hint(row),
      repo_conversation:
        row
        |> map_get(:repo_conversation, "repo_conversation")
        |> normalize_repo_conversation_projection(),
      conversation_supervision:
        row
        |> map_get(:conversation_supervision, "conversation_supervision")
        |> normalize_conversation_supervision_projection()
    }
  end

  defp normalize_row(_row, index) do
    fallback_id = "workbench-row-#{index + 1}"

    %{
      id: fallback_id,
      legacy_project_id: nil,
      managed_repo_id: nil,
      source_repo_id: nil,
      workspace_path: nil,
      name: fallback_id,
      github_full_name: fallback_id,
      default_branch: "main",
      open_issue_count: 0,
      open_pr_count: 0,
      recent_activity_summary: "No recent activity metadata.",
      recent_activity_at: nil,
      issue_triage_policy: IssueTriageWorkflowKickoff.policy_state(%{}),
      semantic_graph_hint: nil,
      memory_graph_hint: nil,
      repo_conversation: nil,
      conversation_supervision: nil
    }
  end

  defp normalize_repo_conversation_projection(value) when is_map(value), do: value
  defp normalize_repo_conversation_projection(_value), do: nil

  defp normalize_conversation_supervision_projection(value) when is_map(value), do: value
  defp normalize_conversation_supervision_projection(_value), do: nil

  defp normalize_warning(nil), do: nil

  defp normalize_warning(warning) do
    stale_warning(
      map_get(warning, :error_type, "error_type", @default_fetch_error_type),
      map_get(warning, :detail, "detail", "Workbench inventory data may be stale."),
      map_get(warning, :remediation, "remediation", @default_fetch_remediation)
    )
  end

  defp stale_warning(error_type, detail, remediation) do
    %{
      error_type: normalize_optional_string(error_type) || @default_fetch_error_type,
      detail: normalize_optional_string(detail) || "Workbench inventory data may be stale.",
      remediation: normalize_optional_string(remediation) || @default_fetch_remediation
    }
  end

  defp first_non_empty_string(values) when is_list(values) do
    Enum.find_value(values, &normalize_optional_string/1)
  end

  defp first_non_negative_integer(values) when is_list(values) do
    Enum.find_value(values, &parse_non_negative_integer/1) || 0
  end

  defp parse_non_negative_integer(value) when is_integer(value) and value >= 0, do: value

  defp parse_non_negative_integer(value) when is_float(value) and value >= 0,
    do: value |> trunc()

  defp parse_non_negative_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed_value, ""} when parsed_value >= 0 -> parsed_value
      _other -> nil
    end
  end

  defp parse_non_negative_integer(_value), do: nil

  defp normalize_semantic_graph_hint(hint) when is_map(hint), do: hint
  defp normalize_semantic_graph_hint(_hint), do: nil

  defp normalize_memory_graph_hint(hint) when is_map(hint), do: hint
  defp normalize_memory_graph_hint(_hint), do: nil

  defp first_datetime(values) when is_list(values) do
    Enum.find_value(values, &normalize_optional_datetime/1)
  end

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

  defp format_utc_datetime(datetime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%Y-%m-%d %H:%M UTC")
  end

  defp format_reason(%{diagnostic: diagnostic}) when is_binary(diagnostic), do: diagnostic
  defp format_reason(reason), do: inspect(reason)

  defp normalize_repository_listing_status(:ready), do: :ready
  defp normalize_repository_listing_status("ready"), do: :ready
  defp normalize_repository_listing_status(:blocked), do: :blocked
  defp normalize_repository_listing_status("blocked"), do: :blocked
  defp normalize_repository_listing_status(:stale), do: :blocked
  defp normalize_repository_listing_status("stale"), do: :blocked
  defp normalize_repository_listing_status(_status), do: nil

  defp fetch_step_state(onboarding_state, onboarding_step) when is_map(onboarding_state) do
    step_key = Integer.to_string(onboarding_step)
    Map.get(onboarding_state, step_key) || Map.get(onboarding_state, onboarding_step) || %{}
  end

  defp fetch_step_state(_onboarding_state, _onboarding_step), do: %{}

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_atom(value),
    do: normalize_optional_string(Atom.to_string(value))

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(value) when is_float(value), do: :erlang.float_to_binary(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default
end
