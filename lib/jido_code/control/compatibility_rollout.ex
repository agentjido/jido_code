defmodule JidoCode.Control.CompatibilityRollout do
  # covers: architecture.factory_control_plane.compatibility_rollout_backfills_legacy_repo_records
  # covers: architecture.factory_control_plane.compatibility_rollout_exposes_removal_and_rollback_state
  # covers: architecture.execution_pipeline.legacy_workflow_state_projects_forward_without_reexecution
  # covers: architecture.run_governance.legacy_workflow_history_backfills_into_governed_runs
  @moduledoc """
  Reports and backfills the remaining compatibility seam between legacy repo or
  workflow records and the preferred control-plane projections.
  """

  alias JidoCode.Control.{Actor, ManagedRepo, RepoBridge}
  alias JidoCode.Orchestration.{Run, RunBridge, WorkflowRun}
  alias JidoCode.Projects.Project

  @read_actor Actor.operator_actor()
  @report_error_type "compatibility_rollout_report_failed"
  @backfill_error_type "compatibility_rollout_backfill_failed"
  @default_report_remediation """
  Retry compatibility rollout refresh. If this persists, inspect control-plane projection health before retiring legacy shims.
  """

  @type warning :: %{
          error_type: String.t(),
          detail: String.t(),
          remediation: String.t()
        }

  @type failure :: %{
          legacy_id: String.t() | nil,
          error_type: String.t(),
          detail: String.t()
        }

  @type backfill_summary :: %{
          generated_at: DateTime.t(),
          projects_total: non_neg_integer(),
          projects_backfilled: non_neg_integer(),
          projects_already_projected: non_neg_integer(),
          project_failures: [failure()],
          workflow_runs_total: non_neg_integer(),
          workflow_runs_backfilled: non_neg_integer(),
          workflow_runs_already_projected: non_neg_integer(),
          workflow_run_failures: [failure()],
          rollback_safe: boolean()
        }

  @type report :: %{
          generated_at: DateTime.t(),
          summary: String.t(),
          counts: map(),
          compatibility_surfaces: [map()],
          removal_criteria: [map()],
          rollback_procedures: [map()]
        }

  @spec report() :: {:ok, report()} | {:error, warning()}
  def report do
    with {:ok, snapshot} <- snapshot() do
      {:ok, build_report(snapshot)}
    end
  end

  @spec backfill() :: {:ok, backfill_summary()} | {:error, warning()}
  def backfill do
    with {:ok, projects} <- read_projects(),
         {:ok, workflow_runs} <- read_workflow_runs() do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      project_summary = backfill_projects(projects)
      workflow_summary = backfill_workflow_runs(workflow_runs)

      {:ok,
       %{
         generated_at: now,
         projects_total: length(projects),
         projects_backfilled: project_summary.backfilled,
         projects_already_projected: project_summary.already_projected,
         project_failures: Enum.reverse(project_summary.failures),
         workflow_runs_total: length(workflow_runs),
         workflow_runs_backfilled: workflow_summary.backfilled,
         workflow_runs_already_projected: workflow_summary.already_projected,
         workflow_run_failures: Enum.reverse(workflow_summary.failures),
         rollback_safe: project_summary.failures == [] and workflow_summary.failures == []
       }}
    end
  end

  @spec backfill_and_report() :: {:ok, %{backfill: backfill_summary(), report: report()}} | {:error, warning()}
  def backfill_and_report do
    with {:ok, backfill_summary} <- backfill(),
         {:ok, rollout_report} <- report() do
      {:ok, %{backfill: backfill_summary, report: rollout_report}}
    end
  end

  defp snapshot do
    with {:ok, projects} <- read_projects(),
         {:ok, managed_repos} <- read_managed_repos(),
         {:ok, workflow_runs} <- read_workflow_runs(),
         {:ok, runs} <- read_runs() do
      {:ok,
       %{
         projects: projects,
         managed_repos: managed_repos,
         workflow_runs: workflow_runs,
         runs: runs
       }}
    end
  end

  defp build_report(snapshot) do
    projects = Map.get(snapshot, :projects, [])
    managed_repos = Map.get(snapshot, :managed_repos, [])
    workflow_runs = Map.get(snapshot, :workflow_runs, [])
    runs = Map.get(snapshot, :runs, [])

    managed_project_ids =
      managed_repos
      |> Enum.map(&normalize_optional_string(map_get(&1, :legacy_project_id, "legacy_project_id")))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    governed_workflow_run_ids =
      runs
      |> Enum.map(&normalize_optional_string(map_get(&1, :workflow_run_id, "workflow_run_id")))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    projects_missing_managed_repo =
      Enum.filter(projects, fn project ->
        project_id = project |> map_get(:id, "id") |> normalize_optional_string()
        project_id && not MapSet.member?(managed_project_ids, project_id)
      end)

    workflow_runs_missing_governed_run =
      Enum.filter(workflow_runs, fn workflow_run ->
        workflow_run_id = workflow_run |> map_get(:id, "id") |> normalize_optional_string()
        workflow_run_id && not MapSet.member?(governed_workflow_run_ids, workflow_run_id)
      end)

    counts = %{
      projects_total: length(projects),
      managed_repos_total: length(managed_repos),
      projects_missing_managed_repo: length(projects_missing_managed_repo),
      workflow_runs_total: length(workflow_runs),
      governed_runs_total: length(runs),
      workflow_runs_missing_governed_run: length(workflow_runs_missing_governed_run)
    }

    compatibility_surfaces =
      compatibility_surfaces(
        counts.projects_missing_managed_repo,
        counts.workflow_runs_missing_governed_run
      )

    removal_criteria =
      removal_criteria(
        counts.projects_missing_managed_repo,
        counts.workflow_runs_missing_governed_run
      )

    %{
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      summary: rollout_summary(counts, compatibility_surfaces),
      counts: counts,
      compatibility_surfaces: compatibility_surfaces,
      removal_criteria: removal_criteria,
      rollback_procedures: rollback_procedures()
    }
  end

  defp backfill_projects(projects) do
    Enum.reduce(projects, %{backfilled: 0, already_projected: 0, failures: []}, fn project, acc ->
      project_id = project |> map_get(:id, "id") |> normalize_optional_string()

      case ManagedRepo.get_by_legacy_project_id(project_id, actor: Actor.factory_system_actor()) do
        {:ok, %ManagedRepo{}} ->
          %{acc | already_projected: acc.already_projected + 1}

        {:ok, nil} ->
          case RepoBridge.sync_project(project) do
            {:ok, %ManagedRepo{}} ->
              %{acc | backfilled: acc.backfilled + 1}

            {:error, reason} ->
              Map.update!(acc, :failures, fn failures ->
                [failure_entry(project_id, reason, "project_projection_backfill_failed") | failures]
              end)
          end

        {:error, _reason} ->
          case RepoBridge.sync_project(project) do
            {:ok, %ManagedRepo{}} ->
              %{acc | backfilled: acc.backfilled + 1}

            {:error, reason} ->
              Map.update!(acc, :failures, fn failures ->
                [failure_entry(project_id, reason, "project_projection_backfill_failed") | failures]
              end)
          end
      end
    end)
  end

  defp backfill_workflow_runs(workflow_runs) do
    Enum.reduce(workflow_runs, %{backfilled: 0, already_projected: 0, failures: []}, fn workflow_run, acc ->
      workflow_run_id = workflow_run |> map_get(:id, "id") |> normalize_optional_string()

      case Run.get_by_workflow_run_id(workflow_run_id, actor: Actor.factory_system_actor()) do
        {:ok, %Run{}} ->
          %{acc | already_projected: acc.already_projected + 1}

        {:ok, nil} ->
          case RunBridge.projected_run_for_workflow_run(workflow_run) do
            {:ok, %Run{}} ->
              %{acc | backfilled: acc.backfilled + 1}

            {:error, reason} ->
              Map.update!(acc, :failures, fn failures ->
                [failure_entry(workflow_run_id, reason, "governed_run_backfill_failed") | failures]
              end)
          end

        {:error, _reason} ->
          case RunBridge.projected_run_for_workflow_run(workflow_run) do
            {:ok, %Run{}} ->
              %{acc | backfilled: acc.backfilled + 1}

            {:error, reason} ->
              Map.update!(acc, :failures, fn failures ->
                [failure_entry(workflow_run_id, reason, "governed_run_backfill_failed") | failures]
              end)
          end
      end
    end)
  end

  defp compatibility_surfaces(project_gap_count, workflow_gap_count) do
    [
      %{
        id: "workbench_inventory_fallback",
        label: "Workbench legacy project inventory fallback",
        dependency: "Project",
        status: if(project_gap_count > 0, do: "legacy_dependency_present", else: "ready_to_retire"),
        remaining_count: project_gap_count,
        detail:
          if(project_gap_count > 0,
            do: "#{project_gap_count} project records still need managed-repo projections.",
            else: "All current project records have managed-repo projections."
          )
      },
      %{
        id: "project_route_aliases",
        label: "Project route aliases",
        dependency: "Project",
        status: "coexistence_active",
        remaining_count: 0,
        detail:
          "Route aliases stay on /projects/:id until downstream launch and conversation entrypoints stop relying on legacy project ids."
      },
      %{
        id: "dashboard_run_summary_fallback",
        label: "Dashboard workflow-run summary fallback",
        dependency: "WorkflowRun",
        status: if(workflow_gap_count > 0, do: "legacy_dependency_present", else: "ready_to_retire"),
        remaining_count: workflow_gap_count,
        detail:
          if(workflow_gap_count > 0,
            do: "#{workflow_gap_count} workflow runs still need governed run projections.",
            else: "All current workflow runs have governed run projections."
          )
      },
      %{
        id: "workbench_run_outcome_fallback",
        label: "Workbench workflow-run outcome fallback",
        dependency: "WorkflowRun",
        status: if(workflow_gap_count > 0, do: "legacy_dependency_present", else: "ready_to_retire"),
        remaining_count: workflow_gap_count,
        detail:
          if(workflow_gap_count > 0,
            do: "Recent run outcome loaders still need workflow-run fallback for #{workflow_gap_count} runs.",
            else: "Recent run outcomes can resolve through governed runs without workflow-run fallback."
          )
      },
      %{
        id: "run_detail_workflow_actions",
        label: "Run detail approval and retry seam",
        dependency: "WorkflowRun",
        status: "coexistence_active",
        remaining_count: 0,
        detail:
          "Run detail still uses WorkflowRun lifecycle actions for approval and retry while Run remains the preferred read model."
      }
    ]
  end

  defp removal_criteria(project_gap_count, workflow_gap_count) do
    [
      %{
        id: "retire_project_projection_fallbacks",
        label: "Retire project-to-managed-repo fallback loaders",
        status: if(project_gap_count == 0, do: "ready", else: "pending"),
        detail:
          if(project_gap_count == 0,
            do: "No current project records are missing managed-repo projections.",
            else:
              "Backfill the remaining #{project_gap_count} project records before removing project fallback loaders."
          )
      },
      %{
        id: "retire_workflow_run_projection_fallbacks",
        label: "Retire workflow-run to governed-run fallback loaders",
        status: if(workflow_gap_count == 0, do: "ready", else: "pending"),
        detail:
          if(workflow_gap_count == 0,
            do: "No current workflow runs are missing governed run projections.",
            else:
              "Backfill the remaining #{workflow_gap_count} workflow runs before removing dashboard and workbench fallback readers."
          )
      },
      %{
        id: "retire_project_route_aliases",
        label: "Retire /projects route aliases",
        status: "pending",
        detail:
          "Keep route aliases until operator deep links, launch entrypoints, and conversation entry surfaces stop depending on legacy project ids."
      },
      %{
        id: "retire_workflow_run_action_seam",
        label: "Retire WorkflowRun approval and retry actions",
        status: "pending",
        detail:
          "Introduce first-class Run mutation commands before removing WorkflowRun-backed approval and retry handling from run detail."
      }
    ]
  end

  defp rollback_procedures do
    [
      %{
        id: "project_projection_recovery",
        label: "Project projection recovery",
        trigger: "Repo detail or workbench rows disappear after compatibility changes.",
        procedure:
          "Keep /projects/:id aliases enabled, rerun compatibility backfill, and confirm RepoBridge can still resolve each legacy project id."
      },
      %{
        id: "workflow_projection_recovery",
        label: "Workflow run projection recovery",
        trigger: "Dashboard, workbench, or run detail loses historical run continuity.",
        procedure:
          "Restore workflow-run fallback readers, rerun governed run backfill, and verify every WorkflowRun maps to a Run projection before removing the seam again."
      },
      %{
        id: "policy_recovery",
        label: "Policy hardening recovery",
        trigger: "Operator workflows fail because new actor-aware policies deny expected rollout operations.",
        procedure:
          "Keep named machine-actor entrypoints in place, inspect the denied actor class, and rollback only the affected control-plane mutation path instead of reintroducing anonymous authorization bypasses."
      }
    ]
  end

  defp rollout_summary(counts, compatibility_surfaces) do
    active_dependencies =
      compatibility_surfaces
      |> Enum.count(&(Map.get(&1, :status) == "legacy_dependency_present"))

    cond do
      counts.projects_missing_managed_repo == 0 and
        counts.workflow_runs_missing_governed_run == 0 and
          active_dependencies == 0 ->
        "Legacy data is fully projected into the preferred control-plane model."

      true ->
        "Compatibility rollout is still active while #{counts.projects_missing_managed_repo} project projections and #{counts.workflow_runs_missing_governed_run} governed run projections remain to backfill."
    end
  end

  defp failure_entry(legacy_id, reason, error_type) do
    %{
      legacy_id: normalize_optional_string(legacy_id),
      error_type: normalize_optional_string(error_type) || @backfill_error_type,
      detail: format_reason(reason)
    }
  end

  defp read_projects do
    case Project.read(query: [sort: [inserted_at: :asc]], actor: @read_actor) do
      {:ok, projects} -> {:ok, projects}
      {:error, reason} -> {:error, warning(@report_error_type, reason)}
    end
  end

  defp read_managed_repos do
    case ManagedRepo.read(query: [sort: [inserted_at: :asc]], actor: @read_actor) do
      {:ok, managed_repos} -> {:ok, managed_repos}
      {:error, reason} -> {:error, warning(@report_error_type, reason)}
    end
  end

  defp read_workflow_runs do
    case WorkflowRun.read(query: [sort: [inserted_at: :asc]], actor: @read_actor) do
      {:ok, workflow_runs} -> {:ok, workflow_runs}
      {:error, reason} -> {:error, warning(@report_error_type, reason)}
    end
  end

  defp read_runs do
    case Run.read(query: [sort: [inserted_at: :asc]], actor: @read_actor) do
      {:ok, runs} -> {:ok, runs}
      {:error, reason} -> {:error, warning(@report_error_type, reason)}
    end
  end

  defp warning(error_type, reason) do
    %{
      error_type: error_type,
      detail: "Compatibility rollout data could not be loaded (#{format_reason(reason)}).",
      remediation: @default_report_remediation
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

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_boolean(value), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil
end
