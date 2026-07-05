defmodule JidoCode.Workbench.InventorySurface do
  @moduledoc """
  Shared managed-repository inventory loading and presentation helpers for
  dashboard Work and the specialist Workbench route.
  """

  alias JidoCode.ManagedRepoRoutes

  alias JidoCode.Workbench.{
    Inventory,
    IssueTriageWorkflowKickoff,
    ProjectWorkspaceBindingNotice,
    RunOutcomes
  }

  @fallback_row_id_prefix "workbench-row-"
  @type stale_warning :: Inventory.stale_warning()
  @type run_outcomes :: %{optional(String.t()) => RunOutcomes.run_outcome()}

  @spec load(String.t() | nil) ::
          {:ok, [Inventory.row()], run_outcomes(), stale_warning() | nil} | {:error, stale_warning()}
  def load(return_to \\ nil) do
    case Inventory.load() do
      {:ok, rows, warning} -> {:ok, rows, RunOutcomes.load(rows, return_to), warning}
      {:error, warning} -> {:error, warning}
    end
  end

  @spec load_recent_run_outcomes([map()], String.t() | nil) :: run_outcomes()
  def load_recent_run_outcomes(rows, return_to \\ nil)
  def load_recent_run_outcomes(rows, return_to) when is_list(rows), do: RunOutcomes.load(rows, return_to)
  def load_recent_run_outcomes(_rows, _return_to), do: %{}

  @spec fallback_row?(map() | String.t() | nil) :: boolean()
  def fallback_row?(%{} = row) do
    row
    |> map_get(:id, "id")
    |> fallback_row?()
  end

  def fallback_row?(project_id) do
    case normalize_optional_string(project_id) do
      <<@fallback_row_id_prefix, _::binary>> -> true
      _other -> false
    end
  end

  @spec recent_run_outcome(run_outcomes(), term()) :: map() | nil
  def recent_run_outcome(outcomes, project_id) when is_map(outcomes) do
    normalized_project_id = normalize_optional_string(project_id)

    if normalized_project_id do
      Map.get(outcomes, normalized_project_id)
    end
  end

  def recent_run_outcome(_outcomes, _project_id), do: nil

  @spec issue_triage_policy_state(map()) :: map()
  def issue_triage_policy_state(project_row), do: IssueTriageWorkflowKickoff.policy_state(project_row)

  @spec conversation_supervision(map()) :: map() | nil
  def conversation_supervision(project) when is_map(project) do
    case Map.get(project, :conversation_supervision) do
      %{} = supervision ->
        supervision

      _other ->
        case Map.get(project, :repo_conversation) do
          %{} = repo_intake_projection ->
            %{
              available?: true,
              managed_repo_id: Map.get(project, :managed_repo_id),
              repo_intake: repo_intake_projection,
              active_entries: [],
              active_count: 0,
              clarification_count: 0,
              latest_entry: nil,
              latest_activity_at: nil,
              notice: conversation_projection_value(repo_intake_projection, :notice)
            }

          _other ->
            nil
        end
    end
  end

  def conversation_supervision(_project), do: nil

  @spec conversation_supervision_projection(map()) :: map() | nil
  def conversation_supervision_projection(project) do
    case conversation_supervision(project) do
      %{active_count: active_count} = supervision when active_count > 0 ->
        supervision

      %{repo_intake: %{} = repo_intake} = supervision ->
        if conversation_projection_value(repo_intake, :conversation) do
          supervision
        end

      _other ->
        nil
    end
  end

  @spec conversation_supervision_notice(map()) :: map() | nil
  def conversation_supervision_notice(project) do
    project
    |> conversation_supervision()
    |> conversation_projection_value(:notice)
  end

  @spec conversation_supervision_active_count(map()) :: non_neg_integer()
  def conversation_supervision_active_count(project) do
    project
    |> conversation_supervision()
    |> conversation_projection_value(:active_count, 0)
  end

  @spec conversation_supervision_clarification_count(map()) :: non_neg_integer()
  def conversation_supervision_clarification_count(project) do
    project
    |> conversation_supervision()
    |> conversation_projection_value(:clarification_count, 0)
  end

  @spec conversation_supervision_role_scope(map()) :: term()
  def conversation_supervision_role_scope(project) do
    project
    |> conversation_supervision_role_projection()
    |> conversation_projection_value(:conversation, %{})
    |> conversation_projection_value(:scope)
  end

  @spec conversation_supervision_role_attachment_mode(map()) :: term()
  def conversation_supervision_role_attachment_mode(project) do
    project
    |> conversation_supervision_role_projection()
    |> conversation_projection_value(:conversation, %{})
    |> conversation_projection_value(:attachment_mode)
  end

  @spec conversation_supervision_role_work_item_id(map()) :: term()
  def conversation_supervision_role_work_item_id(project) do
    project
    |> conversation_supervision_role_projection()
    |> conversation_projection_value(:conversation, %{})
    |> conversation_projection_value(:work_item_id)
  end

  @spec conversation_supervision_status(map()) :: term()
  def conversation_supervision_status(project) do
    project
    |> conversation_supervision_role_projection()
    |> conversation_projection_value(:conversation, %{})
    |> conversation_projection_value(:status)
  end

  @spec conversation_supervision_work_item(map()) :: map() | nil
  def conversation_supervision_work_item(project) do
    case conversation_supervision(project) do
      %{latest_entry: %{} = latest_entry, active_count: active_count} when active_count > 0 ->
        conversation_projection_value(latest_entry, :work_item)

      _other ->
        nil
    end
  end

  @spec conversation_supervision_active_count_label(map()) :: String.t() | nil
  def conversation_supervision_active_count_label(project) do
    case conversation_supervision_active_count(project) do
      1 -> "1 active work item"
      count when is_integer(count) and count > 1 -> "#{count} active work items"
      _other -> nil
    end
  end

  @spec conversation_supervision_clarification_count_label(map()) :: String.t() | nil
  def conversation_supervision_clarification_count_label(project) do
    case conversation_supervision_clarification_count(project) do
      1 -> "1 clarification needed"
      count when is_integer(count) and count > 1 -> "#{count} clarification turns needed"
      _other -> nil
    end
  end

  @spec conversation_supervision_detail(map()) :: String.t()
  def conversation_supervision_detail(project) do
    case conversation_supervision(project) do
      %{latest_entry: %{} = latest_entry, active_count: active_count, repo_intake: %{}}
      when active_count > 0 ->
        conversation_projection_detail(
          latest_entry,
          "Repo intake has already settled onto active governed work."
        )

      %{latest_entry: %{} = latest_entry, active_count: active_count} when active_count > 0 ->
        conversation_projection_detail(latest_entry, "Governed work is active from repo detail.")

      %{repo_intake: %{} = repo_intake} ->
        conversation_projection_detail(repo_intake, "Repository intake is active from repo detail.")

      _other ->
        "Conversation supervision is available from repo detail."
    end
  end

  @spec conversation_supervision_action_label(map()) :: String.t()
  def conversation_supervision_action_label(project) do
    case conversation_supervision(project) do
      %{active_count: active_count} when active_count > 0 ->
        "Open governed supervision"

      %{clarification_count: clarification_count} when clarification_count > 0 ->
        "Open repo intake"

      %{repo_intake: %{} = repo_intake} ->
        conversation_projection_value(repo_intake, :action_label, "Open repo intake")

      _other ->
        "Open repo detail"
    end
  end

  @spec semantic_graph_hint(map()) :: map() | nil
  def semantic_graph_hint(project) when is_map(project) do
    case Map.get(project, :semantic_graph_hint) do
      %{} = hint -> hint
      _other -> nil
    end
  end

  def semantic_graph_hint(_project), do: nil

  @spec memory_graph_hint(map()) :: map() | nil
  def memory_graph_hint(project) when is_map(project) do
    case Map.get(project, :memory_graph_hint) do
      %{} = hint -> hint
      _other -> nil
    end
  end

  def memory_graph_hint(_project), do: nil

  @spec semantic_graph_hint_badge_class(map()) :: String.t()
  def semantic_graph_hint_badge_class(%{state: :ready}), do: "badge badge-success badge-xs"
  def semantic_graph_hint_badge_class(%{state: :blocked}), do: "badge badge-warning badge-xs"
  def semantic_graph_hint_badge_class(%{state: :stale}), do: "badge badge-warning badge-xs"
  def semantic_graph_hint_badge_class(%{state: :degraded}), do: "badge badge-warning badge-xs"
  def semantic_graph_hint_badge_class(%{state: :failed}), do: "badge badge-error badge-xs"
  def semantic_graph_hint_badge_class(%{state: :not_ready}), do: "badge badge-outline badge-xs"
  def semantic_graph_hint_badge_class(_hint), do: "badge badge-outline badge-xs"

  @spec memory_graph_hint_badge_class(map()) :: String.t()
  def memory_graph_hint_badge_class(%{state: :ready}), do: "badge badge-success badge-xs"
  def memory_graph_hint_badge_class(%{state: :blocked}), do: "badge badge-warning badge-xs"
  def memory_graph_hint_badge_class(%{state: :stale}), do: "badge badge-warning badge-xs"
  def memory_graph_hint_badge_class(%{state: :invalidated}), do: "badge badge-warning badge-xs"
  def memory_graph_hint_badge_class(%{state: :degraded}), do: "badge badge-warning badge-xs"
  def memory_graph_hint_badge_class(%{state: :failed}), do: "badge badge-error badge-xs"
  def memory_graph_hint_badge_class(%{state: :not_ready}), do: "badge badge-outline badge-xs"
  def memory_graph_hint_badge_class(_hint), do: "badge badge-outline badge-xs"

  @spec semantic_graph_hint_recovery_path(map(), String.t() | nil) :: String.t() | nil
  def semantic_graph_hint_recovery_path(project, detail_path) do
    hint = semantic_graph_hint(project)

    cond do
      workspace_binding_hint?(hint) ->
        detail_path && detail_path <> "#project-detail-workspace-binding-panel"

      hint && get_in(hint, [:recovery, :available?]) ->
        detail_path

      true ->
        nil
    end
  end

  @spec memory_graph_hint_recovery_path(map(), String.t() | nil) :: String.t() | nil
  def memory_graph_hint_recovery_path(project, detail_path) do
    hint = memory_graph_hint(project)

    cond do
      workspace_binding_hint?(hint) ->
        detail_path && detail_path <> "#project-detail-workspace-binding-panel"

      hint && get_in(hint, [:recovery, :available?]) ->
        detail_path

      true ->
        nil
    end
  end

  @spec workspace_binding_hint?(map() | nil) :: boolean()
  def workspace_binding_hint?(hint) do
    ProjectWorkspaceBindingNotice.workspace_binding_error?(hint)
  end

  @spec run_outcome_status_badge_class(term()) :: String.t()
  def run_outcome_status_badge_class("completed"), do: "badge badge-success badge-xs"
  def run_outcome_status_badge_class("running"), do: "badge badge-info badge-xs"
  def run_outcome_status_badge_class("failed"), do: "badge badge-error badge-xs"
  def run_outcome_status_badge_class("cancelled"), do: "badge badge-warning badge-xs"
  def run_outcome_status_badge_class("awaiting_approval"), do: "badge badge-warning badge-xs"
  def run_outcome_status_badge_class("pending"), do: "badge badge-outline badge-xs"
  def run_outcome_status_badge_class(_status), do: "badge badge-outline badge-xs"

  @spec run_outcome_status_label(term()) :: String.t()
  def run_outcome_status_label(status) do
    status
    |> normalize_optional_string()
    |> case do
      nil -> "unknown"
      normalized_status -> normalized_status
    end
  end

  @spec github_repository_path(map()) :: {:ok, String.t()} | :error
  def github_repository_path(project) do
    project
    |> Map.get(:github_full_name)
    |> normalize_optional_string()
    |> parse_github_repository_name()
    |> case do
      {:ok, owner, repository} -> {:ok, "https://github.com/#{owner}/#{repository}"}
      :error -> :error
    end
  end

  @spec issue_github_url(map()) :: String.t() | nil
  def issue_github_url(project) do
    with {:ok, repository_path} <- github_repository_path(project) do
      "#{repository_path}/issues"
    end
  end

  @spec pull_request_github_url(map()) :: String.t() | nil
  def pull_request_github_url(project) do
    with {:ok, repository_path} <- github_repository_path(project) do
      "#{repository_path}/pulls"
    end
  end

  @spec project_detail_path(map(), String.t() | nil) :: String.t() | nil
  def project_detail_path(project, return_to \\ nil) do
    project
    |> Map.get(:id)
    |> normalize_optional_string()
    |> case do
      nil ->
        nil

      project_id ->
        if fallback_row?(project_id) do
          nil
        else
          ManagedRepoRoutes.project_detail_path(
            project_id,
            return_to: normalize_optional_string(return_to)
          )
        end
    end
  end

  defp conversation_supervision_role_projection(project) do
    case conversation_supervision(project) do
      %{latest_entry: %{} = latest_entry, active_count: active_count} when active_count > 0 ->
        latest_entry

      %{repo_intake: %{} = repo_intake} ->
        repo_intake

      _other ->
        nil
    end
  end

  defp conversation_projection_detail(%{} = projection, fallback) do
    conversation = conversation_projection_value(projection, :conversation, %{})

    work_resolution =
      conversation
      |> conversation_projection_value(:work_resolution, %{})

    normalize_optional_string(conversation_projection_value(work_resolution, :detail)) ||
      normalize_optional_string(conversation_projection_value(conversation, :objective)) ||
      fallback
  end

  defp conversation_projection_detail(_projection, fallback), do: fallback

  defp conversation_projection_value(projection, key, default \\ nil)

  defp conversation_projection_value(%{} = projection, key, default) when is_atom(key) do
    Map.get(projection, key, Map.get(projection, Atom.to_string(key), default))
  end

  defp conversation_projection_value(_projection, _key, default), do: default

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
end
