defmodule JidoCode.Workbench.ProjectDetail do
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  @moduledoc """
  Loads managed-repo-first detail state and execution readiness metadata for `/repos/:id`.
  """

  alias JidoCode.Control.RepoBridge

  @project_not_found_error_type "project_detail_not_found"
  @project_load_failed_error_type "project_detail_load_failed"
  @project_not_ready_error_type "project_execution_not_ready"

  @project_not_found_remediation """
  Open Workbench, select an imported repository, and then retry repo detail.
  """

  @project_not_ready_remediation """
  Complete setup step 7 project import and baseline sync, then retry workflow launch.
  """

  @type execution_readiness :: %{
          status: :ready | :blocked,
          enabled: boolean(),
          error_type: String.t() | nil,
          detail: String.t() | nil,
          remediation: String.t() | nil
        }

  @type project_detail :: %{
          id: String.t(),
          name: String.t(),
          github_full_name: String.t(),
          default_branch: String.t(),
          settings: map(),
          managed_repo_id: String.t() | nil,
          source_repo_id: String.t() | nil,
          execution_readiness: execution_readiness()
        }

  @type load_error :: %{
          error_type: String.t(),
          detail: String.t(),
          remediation: String.t()
        }

  @spec load(term()) :: {:ok, project_detail()} | {:error, load_error()}
  def load(identifier) do
    with {:ok, normalized_identifier} <- normalize_project_id(identifier),
         {:ok, scope} <- fetch_scope(normalized_identifier) do
      {:ok, to_project_detail(scope)}
    end
  end

  @spec ready_for_execution?(project_detail() | map() | nil) :: boolean()
  def ready_for_execution?(project_detail) when is_map(project_detail) do
    project_detail
    |> map_get(:execution_readiness, "execution_readiness", %{})
    |> map_get(:enabled, "enabled", false)
    |> truthy?()
  end

  def ready_for_execution?(_project_detail), do: false

  defp normalize_project_id(project_id) do
    case normalize_optional_string(project_id) do
      nil ->
        {:error,
         load_error(
           @project_not_found_error_type,
           "Repository identifier is missing.",
           @project_not_found_remediation
         )}

      normalized_project_id ->
        {:ok, normalized_project_id}
    end
  end

  defp fetch_scope(identifier) do
    case RepoBridge.repo_scope(identifier) do
      {:ok, scope} ->
        {:ok, scope}

      {:error, :repo_scope_not_found} ->
        {:error,
         load_error(
           @project_not_found_error_type,
           "Managed repository #{identifier} was not found.",
           @project_not_found_remediation
         )}

      {:error, reason} ->
        {:error,
         load_error(
           @project_load_failed_error_type,
           "Repo detail lookup failed (#{format_reason(reason)}).",
           @project_not_found_remediation
         )}
    end
  end

  defp to_project_detail(scope) when is_map(scope) do
    managed_repo = map_get(scope, :managed_repo, "managed_repo", %{})
    source_repo = map_get(scope, :source_repo, "source_repo", %{})

    workspace_settings =
      managed_repo
      |> map_get(:workspace_settings, "workspace_settings", %{})
      |> normalize_map()

    execution_settings =
      managed_repo
      |> map_get(:execution_settings, "execution_settings", %{})
      |> normalize_map()

    integration_settings =
      managed_repo
      |> map_get(:integration_settings, "integration_settings", %{})
      |> normalize_map()

    workspace_settings =
      workspace_settings
      |> normalize_map()

    github_full_name =
      source_repo
      |> map_get(:full_name, "full_name")
      |> normalize_optional_string()

    name =
      managed_repo
      |> map_get(:display_name, "display_name")
      |> normalize_optional_string() ||
        source_repo
        |> map_get(:name, "name")
        |> normalize_optional_string()

    default_branch =
      source_repo
      |> map_get(:default_branch, "default_branch")
      |> normalize_optional_string() || "main"

    managed_repo_id =
      scope
      |> map_get(:managed_repo_id, "managed_repo_id")
      |> normalize_optional_string()

    source_repo_id =
      scope
      |> map_get(:source_repo_id, "source_repo_id")
      |> normalize_optional_string()

    route_id =
      scope
      |> map_get(:route_id, "route_id")
      |> normalize_optional_string() ||
        managed_repo_id || source_repo_id || "unknown-repo"

    %{
      id: route_id,
      name: name || github_full_name || route_id,
      github_full_name: github_full_name || name || route_id,
      default_branch: default_branch,
      settings:
        %{}
        |> Map.put("workspace", workspace_settings)
        |> Map.put("execution", execution_settings)
        |> Map.merge(integration_settings),
      managed_repo_id: managed_repo_id,
      source_repo_id: source_repo_id,
      execution_readiness: execution_readiness_state(workspace_settings)
    }
  end

  defp execution_readiness_state(workspace_settings) when is_map(workspace_settings) do
    clone_status =
      workspace_settings
      |> map_get(:clone_status, "clone_status")
      |> normalize_clone_status()

    workspace_initialized? =
      workspace_settings
      |> map_get(:workspace_initialized, "workspace_initialized", false)
      |> truthy?()

    baseline_synced? =
      workspace_settings
      |> map_get(:baseline_synced, "baseline_synced", false)
      |> truthy?()

    retry_instructions =
      workspace_settings
      |> map_get(:retry_instructions, "retry_instructions")
      |> normalize_optional_string()

    workspace_error_type =
      workspace_settings
      |> map_get(:last_error_type, "last_error_type")
      |> normalize_optional_string()

    case {clone_status, workspace_initialized?, baseline_synced?} do
      {:ready, true, true} ->
        %{
          status: :ready,
          enabled: true,
          error_type: nil,
          detail: nil,
          remediation: nil
        }

      _other ->
        {detail, fallback_error_type} =
          blocked_readiness_reason(clone_status, workspace_initialized?, baseline_synced?)

        %{
          status: :blocked,
          enabled: false,
          error_type: workspace_error_type || fallback_error_type,
          detail: detail,
          remediation: retry_instructions || @project_not_ready_remediation
        }
    end
  end

  defp execution_readiness_state(_workspace_settings) do
    %{
      status: :blocked,
      enabled: false,
      error_type: @project_not_ready_error_type,
      detail: "Project execution prerequisites are unavailable.",
      remediation: @project_not_ready_remediation
    }
  end

  defp blocked_readiness_reason(:ready, _workspace_initialized?, _baseline_synced?) do
    {
      "Project workspace metadata is incomplete for workflow execution.",
      "project_execution_metadata_incomplete"
    }
  end

  defp blocked_readiness_reason(:cloning, _workspace_initialized?, _baseline_synced?) do
    {"Project workspace clone is still running.", "project_workspace_clone_in_progress"}
  end

  defp blocked_readiness_reason(:pending, _workspace_initialized?, _baseline_synced?) do
    {"Project workspace import has not completed yet.", "project_workspace_clone_pending"}
  end

  defp blocked_readiness_reason(:error, _workspace_initialized?, _baseline_synced?) do
    {"Project workspace clone or baseline sync failed.", @project_not_ready_error_type}
  end

  defp blocked_readiness_reason(_clone_status, _workspace_initialized?, _baseline_synced?) do
    {"Project execution prerequisites are incomplete.", @project_not_ready_error_type}
  end

  defp normalize_clone_status(:pending), do: :pending
  defp normalize_clone_status(:cloning), do: :cloning
  defp normalize_clone_status(:ready), do: :ready
  defp normalize_clone_status(:error), do: :error
  defp normalize_clone_status("pending"), do: :pending
  defp normalize_clone_status("cloning"), do: :cloning
  defp normalize_clone_status("ready"), do: :ready
  defp normalize_clone_status("error"), do: :error
  defp normalize_clone_status(_clone_status), do: nil

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?("TRUE"), do: true
  defp truthy?("1"), do: true
  defp truthy?(1), do: true
  defp truthy?(_value), do: false

  defp load_error(error_type, detail, remediation) do
    %{
      error_type: normalize_optional_string(error_type) || @project_load_failed_error_type,
      detail: normalize_optional_string(detail) || "Repo detail lookup failed.",
      remediation: normalize_optional_string(remediation) || @project_not_found_remediation
    }
  end

  defp format_reason(reason) do
    reason
    |> Exception.message()
  rescue
    _exception -> inspect(reason)
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: normalize_optional_string(Atom.to_string(value))

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
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
