defmodule JidoCode.Setup.ProjectImport do
  # covers: setup.onboarding.repo_source_per_project
  # covers: setup.onboarding.deferred_integrations
  # covers: architecture.demand_ingress.trusted_ingress_uses_explicit_actor_classes
  @moduledoc """
  Imports the selected repository during setup step 7 and initializes baseline project metadata.
  """

  alias JidoCode.Control.Actor
  alias JidoCode.Projects.Project
  alias JidoCode.Operations.Ingress

  @default_selection_remediation "Select one of the repositories validated in step 4 and retry import."
  @default_importer_remediation "Verify project import configuration and retry step 7."
  @default_clone_retry_remediation "Retry step 7 after confirming workspace provisioning and repository access."
  @default_sync_retry_remediation "Retry step 7 after confirming baseline sync can target the configured default branch."
  @default_branch "main"
  @project_actor Actor.operator_actor(%{
                   "id" => "system:project-import",
                   "email" => "project-import@system.local"
                 })
  @clone_stage_error_type "project_clone_failed"
  @baseline_sync_stage_error_type "project_baseline_sync_failed"
  @clone_status_update_error_type "project_clone_status_update_failed"

  @type status :: :ready | :blocked
  @type import_mode :: :created | :existing
  @type clone_status :: :pending | :cloning | :ready | :error

  @type project_record :: %{
          id: String.t(),
          name: String.t(),
          source_kind: :github | :local,
          source_identifier: String.t(),
          github_full_name: String.t() | nil,
          local_path: String.t() | nil,
          default_branch: String.t(),
          import_mode: import_mode(),
          imported_at: DateTime.t(),
          clone_status: clone_status(),
          clone_status_history: [map()],
          last_synced_at: DateTime.t() | nil
        }

  @type baseline_metadata :: %{
          workspace_initialized: boolean(),
          baseline_synced: boolean(),
          default_workflow_registered: boolean(),
          agent_configuration_registered: boolean(),
          status: :ready,
          initialized_at: DateTime.t(),
          synced_branch: String.t(),
          last_synced_at: DateTime.t(),
          workspace_environment: :sprite | :local,
          workspace_path: String.t() | nil
        }

  @type report :: %{
          checked_at: DateTime.t(),
          status: status(),
          selected_repository: String.t() | nil,
          project_record: project_record() | nil,
          baseline_metadata: baseline_metadata() | nil,
          detail: String.t(),
          remediation: String.t(),
          error_type: String.t() | nil
        }

  @spec run(map() | nil, String.t() | nil, map() | nil) :: report()
  def run(previous_state \\ nil, selected_repository \\ nil, onboarding_state \\ %{}) do
    checked_at = DateTime.utc_now() |> DateTime.truncate(:second)
    available_repositories = available_repositories(onboarding_state)

    selected_repository =
      selected_repository
      |> normalize_repository(previous_selected_repository(previous_state))

    importer =
      Application.get_env(:jido_code, :setup_project_importer, &__MODULE__.default_importer/1)

    importer
    |> safe_invoke_importer(%{
      checked_at: checked_at,
      selected_repository: selected_repository,
      available_repositories: available_repositories,
      onboarding_state: onboarding_state
    })
    |> normalize_report(checked_at, selected_repository)
  end

  @spec available_repositories(map() | nil) :: [String.t()]
  def available_repositories(onboarding_state) when is_map(onboarding_state) do
    installation_sync =
      onboarding_state
      |> fetch_step_state(7)
      |> map_get(:installation_sync, "installation_sync", %{})
      |> normalize_installation_sync_state()

    case installation_sync do
      %{status: :ready, repositories: repositories} ->
        repositories
        |> Enum.uniq()
        |> Enum.sort()

      _other ->
        onboarding_state
        |> fetch_step_state(4)
        |> map_get(:github_credentials, "github_credentials", %{})
        |> map_get(:paths, "paths", [])
        |> normalize_paths()
        |> Enum.flat_map(fn path ->
          path_status =
            path
            |> map_get(:status, "status", nil)
            |> normalize_path_status(:blocked)

          repositories =
            path
            |> map_get(:repositories, "repositories", [])
            |> normalize_repositories()

          if path_status == :ready, do: repositories, else: []
        end)
        |> Enum.uniq()
        |> Enum.sort()
    end
  end

  def available_repositories(_onboarding_state), do: []

  @spec blocked?(report() | nil) :: boolean()
  def blocked?(%{status: :ready}), do: false
  def blocked?(_), do: true

  @spec selected_repository(report() | nil) :: String.t() | nil
  def selected_repository(%{selected_repository: selected_repository})
      when is_binary(selected_repository),
      do: selected_repository

  def selected_repository(_report), do: nil

  @spec serialize_for_state(report() | nil) :: map()
  def serialize_for_state(%{
        checked_at: checked_at,
        status: status,
        selected_repository: selected_repository,
        project_record: project_record,
        baseline_metadata: baseline_metadata,
        detail: detail,
        remediation: remediation,
        error_type: error_type
      }) do
    %{
      "checked_at" => DateTime.to_iso8601(checked_at),
      "status" => Atom.to_string(status),
      "selected_repository" => selected_repository,
      "project_record" => serialize_project_record(project_record),
      "baseline_metadata" => serialize_baseline_metadata(baseline_metadata),
      "detail" => detail,
      "remediation" => remediation,
      "error_type" => error_type
    }
  end

  def serialize_for_state(_report), do: %{}

  @spec from_state(map() | nil) :: report() | nil
  def from_state(nil), do: nil

  def from_state(state) when is_map(state) do
    checked_at =
      state
      |> map_get(:checked_at, "checked_at")
      |> normalize_datetime(DateTime.utc_now() |> DateTime.truncate(:second))

    selected_repository =
      state
      |> map_get(:selected_repository, "selected_repository")
      |> normalize_repository(nil)

    project_record =
      state
      |> map_get(:project_record, "project_record", nil)
      |> normalize_project_record(checked_at)

    baseline_metadata =
      state
      |> map_get(:baseline_metadata, "baseline_metadata", nil)
      |> normalize_baseline_metadata(checked_at)

    status =
      state
      |> map_get(:status, "status", nil)
      |> normalize_status(default_status(project_record, baseline_metadata))

    error_type =
      state
      |> map_get(:error_type, "error_type", nil)
      |> normalize_error_type()

    detail =
      state
      |> map_get(:detail, "detail", nil)
      |> normalize_detail(status)

    remediation =
      state
      |> map_get(:remediation, "remediation", nil)
      |> normalize_remediation(status)

    normalized_status =
      if status == :ready and (is_nil(project_record) or is_nil(baseline_metadata)) do
        :blocked
      else
        status
      end

    retain_project_record? =
      normalized_status == :ready or clone_or_sync_error?(error_type)

    %{
      checked_at: checked_at,
      status: normalized_status,
      selected_repository: selected_repository,
      project_record: if(retain_project_record?, do: project_record, else: nil),
      baseline_metadata: if(normalized_status == :ready, do: baseline_metadata, else: nil),
      detail: detail,
      remediation: remediation,
      error_type: if(normalized_status == :ready, do: nil, else: error_type)
    }
  end

  def from_state(_state), do: nil

  @doc false
  def default_importer(%{
        checked_at: checked_at,
        selected_repository: selected_repository,
        available_repositories: available_repositories,
        onboarding_state: onboarding_state
      })
      when is_list(available_repositories) and is_map(onboarding_state) do
    cond do
      is_nil(selected_repository) ->
        blocked_report(
          checked_at,
          nil,
          "repository_selection_missing",
          "Select a repository before importing your first project.",
          @default_selection_remediation
        )

      available_repositories != [] and selected_repository not in available_repositories ->
        blocked_report(
          checked_at,
          selected_repository,
          "repository_selection_unavailable",
          "Selected repository is not in the validated repository access list.",
          @default_selection_remediation
        )

      true ->
        default_branch =
          resolve_default_branch(selected_repository, onboarding_state, @default_branch)

        with {:ok, _owner, name} <- split_repository(selected_repository),
             {:ok, project, import_mode} <-
               ensure_project_record(name, selected_repository, default_branch),
             :ok <-
               record_project_import_intake(
                 project,
                 selected_repository,
                 default_branch,
                 available_repositories
               ),
             {:ok, synced_project, baseline_metadata} <-
               provision_clone_and_sync(
                 project,
                 selected_repository,
                 default_branch,
                 checked_at,
                 onboarding_state,
                 import_mode
               ) do
          synced_branch =
            baseline_metadata
            |> map_get(:synced_branch, "synced_branch", default_branch)
            |> normalize_branch_name(default_branch)

          %{
            checked_at: checked_at,
            status: :ready,
            selected_repository: selected_repository,
            project_record: project_record(synced_project, import_mode, checked_at),
            baseline_metadata: baseline_metadata,
            detail:
              "Repository import is complete. Workspace clone is ready and baseline synced to `#{synced_branch}`.",
            remediation: "Project import is ready.",
            error_type: nil
          }
        else
          {:error, %{} = clone_or_sync_report} ->
            clone_or_sync_report

          {:error, {error_type, detail}} ->
            blocked_report(
              checked_at,
              selected_repository,
              error_type,
              detail,
              @default_importer_remediation
            )
        end
    end
  end

  def default_importer(_context) do
    blocked_report(
      DateTime.utc_now() |> DateTime.truncate(:second),
      nil,
      "project_import_context_invalid",
      "Project importer context is invalid.",
      @default_importer_remediation
    )
  end

  defp record_project_import_intake(project, selected_repository, default_branch, available_repositories)
       when is_map(project) and is_binary(selected_repository) and is_list(available_repositories) do
    case Ingress.record_operator_intake(%{
           channel: "setup",
           intent: "project_import",
           project_id: map_get(project, :id, "id"),
           payload: %{
             "selected_repository" => selected_repository,
             "project_name" => map_get(project, :name, "name"),
             "default_branch" => default_branch
           },
           source_metadata: %{
             "available_repositories" => available_repositories,
             "source_step" => "setup.project_import"
           }
         }) do
      {:ok, _intake} ->
        :ok

      {:error, reason} ->
        {:error,
         {"project_import_intake_record_failed", "Project import intake could not be recorded (#{inspect(reason)})."}}
    end
  end

  defp record_project_import_intake(_project, _selected_repository, _default_branch, _available_repositories) do
    {:error, {"project_import_intake_record_failed", "Project import intake context is invalid."}}
  end

  defp provision_clone_and_sync(
         project,
         selected_repository,
         default_branch,
         checked_at,
         onboarding_state,
         import_mode
       ) do
    workspace_context =
      onboarding_state
      |> workspace_context(selected_repository)
      |> Map.put(:default_branch, default_branch)
      |> Map.put(:checked_at, checked_at)

    with {:ok, pending_project} <-
           persist_clone_status(
             project,
             :pending,
             checked_at,
             default_branch,
             workspace_context
           ),
         {:ok, cloning_project} <-
           persist_clone_status(
             pending_project,
             :cloning,
             checked_at,
             default_branch,
             workspace_context
           ) do
      clone_context = %{
        checked_at: checked_at,
        selected_repository: selected_repository,
        project: cloning_project,
        default_branch: default_branch,
        workspace_context: workspace_context,
        onboarding_state: onboarding_state
      }

      with {:ok, clone_result} <- run_clone_provisioner(clone_context),
           {:ok, normalized_clone_result} <- normalize_clone_result(clone_result, workspace_context),
           {:ok, baseline_sync_result} <-
             run_baseline_syncer(Map.put(clone_context, :clone_result, normalized_clone_result)),
           {:ok, normalized_baseline_sync} <-
             normalize_baseline_sync_result(
               baseline_sync_result,
               checked_at,
               default_branch,
               workspace_context
             ),
           baseline_metadata <-
             baseline_metadata(
               checked_at,
               default_branch,
               normalized_clone_result,
               normalized_baseline_sync
             ),
           ready_settings_context <-
             workspace_context
             |> Map.merge(normalized_clone_result)
             |> Map.merge(normalized_baseline_sync),
           {:ok, ready_project} <-
             persist_clone_status(
               cloning_project,
               :ready,
               checked_at,
               default_branch,
               ready_settings_context
             ) do
        {:ok, ready_project, baseline_metadata}
      else
        {:error, {error_type, detail, remediation}} ->
          {:error,
           clone_or_sync_error_report(
             cloning_project,
             checked_at,
             selected_repository,
             default_branch,
             import_mode,
             error_type,
             detail,
             remediation,
             workspace_context
           )}

        {:error, {error_type, detail}} ->
          {:error,
           clone_or_sync_error_report(
             cloning_project,
             checked_at,
             selected_repository,
             default_branch,
             import_mode,
             error_type,
             detail,
             @default_importer_remediation,
             workspace_context
           )}

        {:error, reason} ->
          {:error,
           clone_or_sync_error_report(
             cloning_project,
             checked_at,
             selected_repository,
             default_branch,
             import_mode,
             @clone_stage_error_type,
             "Clone or baseline sync failed (#{inspect(reason)}).",
             @default_importer_remediation,
             workspace_context
           )}
      end
    else
      {:error, {error_type, detail}} ->
        {:error, {error_type, detail}}
    end
  end

  defp clone_or_sync_error_report(
         project,
         checked_at,
         selected_repository,
         default_branch,
         import_mode,
         error_type,
         detail,
         remediation,
         workspace_context
       ) do
    clone_error_type = normalize_error_type(error_type) || @clone_stage_error_type
    clone_error_detail = normalize_error_detail(detail)

    failed_project =
      case persist_clone_status(
             project,
             :error,
             checked_at,
             default_branch,
             Map.merge(workspace_context, %{
               error_type: clone_error_type,
               error_detail: clone_error_detail,
               remediation: remediation
             })
           ) do
        {:ok, updated_project} -> updated_project
        {:error, _reason} -> project
      end

    blocked_report(
      checked_at,
      selected_repository,
      clone_error_type,
      clone_error_detail,
      remediation,
      project_record(failed_project, import_mode, checked_at)
    )
  end

  @doc false
  def default_clone_provisioner(%{
        selected_repository: selected_repository,
        workspace_context: workspace_context,
        checked_at: checked_at
      }) do
    workspace_environment =
      workspace_context
      |> map_get(:workspace_environment, "workspace_environment", :sprite)
      |> normalize_workspace_environment(:sprite)

    workspace_root =
      workspace_context
      |> map_get(:workspace_root, "workspace_root")
      |> normalize_workspace_root()

    case workspace_environment do
      :sprite ->
        {:ok,
         %{
           workspace_initialized: true,
           workspace_environment: :sprite,
           workspace_root: nil,
           workspace_path: nil,
           cloned_at: checked_at
         }}

      :local ->
        cond do
          is_nil(workspace_root) ->
            {:error, {"workspace_root_missing", "Local workspace root is missing for clone provisioning."}}

          Path.type(workspace_root) != :absolute ->
            {:error, {"workspace_root_invalid", "Local workspace root must be an absolute path."}}

          not File.dir?(workspace_root) ->
            {:error, {"workspace_root_not_found", "Local workspace root directory does not exist."}}

          true ->
            workspace_path =
              Path.join(workspace_root, repository_workspace_dir(selected_repository))

            case File.mkdir_p(workspace_path) do
              :ok ->
                {:ok,
                 %{
                   workspace_initialized: true,
                   workspace_environment: :local,
                   workspace_root: workspace_root,
                   workspace_path: workspace_path,
                   cloned_at: checked_at
                 }}

              {:error, reason} ->
                {:error,
                 {"workspace_clone_provision_failed", "Failed to provision workspace path: #{inspect(reason)}."}}
            end
        end
    end
  end

  def default_clone_provisioner(_context) do
    {:error, {"workspace_clone_context_invalid", "Clone provisioning context is invalid."}}
  end

  @doc false
  def default_baseline_syncer(%{
        checked_at: checked_at,
        default_branch: default_branch,
        clone_result: clone_result,
        workspace_context: workspace_context
      }) do
    workspace_environment =
      clone_result
      |> map_get(:workspace_environment, "workspace_environment")
      |> normalize_workspace_environment(
        workspace_context
        |> map_get(:workspace_environment, "workspace_environment", :sprite)
        |> normalize_workspace_environment(:sprite)
      )

    workspace_path =
      clone_result
      |> map_get(:workspace_path, "workspace_path")
      |> normalize_workspace_root()

    cond do
      not is_binary(default_branch) or String.trim(default_branch) == "" ->
        {:error, {"baseline_sync_branch_missing", "Configured default branch is missing for baseline sync."}}

      workspace_environment == :local and (is_nil(workspace_path) or not File.dir?(workspace_path)) ->
        {:error, {"baseline_sync_workspace_missing", "Local workspace path is unavailable for baseline sync."}}

      true ->
        {:ok,
         %{
           baseline_synced: true,
           synced_branch: default_branch,
           last_synced_at: checked_at
         }}
    end
  end

  def default_baseline_syncer(_context) do
    {:error, {"baseline_sync_context_invalid", "Baseline sync context is invalid."}}
  end

  defp run_clone_provisioner(context) do
    provisioner =
      Application.get_env(
        :jido_code,
        :setup_project_clone_provisioner,
        &__MODULE__.default_clone_provisioner/1
      )

    invoke_stage(
      provisioner,
      context,
      @clone_stage_error_type,
      "Workspace clone provisioning failed during project import.",
      @default_clone_retry_remediation
    )
  end

  defp run_baseline_syncer(context) do
    syncer =
      Application.get_env(
        :jido_code,
        :setup_project_baseline_syncer,
        &__MODULE__.default_baseline_syncer/1
      )

    invoke_stage(
      syncer,
      context,
      @baseline_sync_stage_error_type,
      "Baseline sync failed during project import.",
      @default_sync_retry_remediation
    )
  end

  defp invoke_stage(stage, context, default_error_type, default_detail, default_remediation)
       when is_function(stage, 1) do
    try do
      case stage.(context) do
        {:ok, %{} = result} ->
          {:ok, result}

        %{} = result ->
          {:ok, result}

        {:error, {error_type, detail, remediation}} ->
          {:error,
           {
             normalize_error_type(error_type) || default_error_type,
             normalize_error_detail(detail),
             normalize_remediation(remediation, :blocked)
           }}

        {:error, {error_type, detail}} ->
          {:error,
           {
             normalize_error_type(error_type) || default_error_type,
             normalize_error_detail(detail),
             default_remediation
           }}

        {:error, detail} ->
          {:error, {default_error_type, normalize_error_detail(detail), default_remediation}}

        other ->
          {:error,
           {
             default_error_type,
             "#{default_detail} Invalid stage result: #{inspect(other)}.",
             default_remediation
           }}
      end
    rescue
      exception ->
        {:error,
         {
           default_error_type,
           "#{default_detail} Stage raised #{Exception.message(exception)}.",
           default_remediation
         }}
    catch
      kind, reason ->
        {:error,
         {
           default_error_type,
           "#{default_detail} Stage threw #{inspect({kind, reason})}.",
           default_remediation
         }}
    end
  end

  defp invoke_stage(_stage, _context, default_error_type, default_detail, default_remediation) do
    {:error, {default_error_type, default_detail, default_remediation}}
  end

  defp safe_invoke_importer(importer, context) when is_function(importer, 1) do
    try do
      case importer.(context) do
        %{} = report -> {:ok, report}
        {:ok, %{} = report} -> {:ok, report}
        {:error, reason} -> {:error, reason}
        other -> {:error, {:invalid_importer_result, other}}
      end
    rescue
      exception ->
        {:error, {:importer_exception, Exception.message(exception)}}
    catch
      kind, reason ->
        {:error, {:importer_throw, {kind, reason}}}
    end
  end

  defp safe_invoke_importer(_importer, _context), do: {:error, :invalid_importer}

  defp normalize_report({:ok, report}, checked_at, selected_repository) do
    case from_state(report) do
      nil ->
        blocked_report(
          checked_at,
          selected_repository,
          "project_import_invalid_report",
          "Project import returned an invalid report.",
          @default_importer_remediation
        )

      normalized_report ->
        %{
          normalized_report
          | selected_repository: normalized_report.selected_repository || selected_repository
        }
    end
  end

  defp normalize_report({:error, {error_type, detail}}, checked_at, selected_repository) do
    blocked_report(
      checked_at,
      selected_repository,
      normalize_error_type(error_type) || "project_import_failed",
      normalize_error_detail(detail),
      @default_importer_remediation
    )
  end

  defp normalize_report({:error, reason}, checked_at, selected_repository) do
    blocked_report(
      checked_at,
      selected_repository,
      "project_import_failed",
      "Project import failed (#{inspect(reason)}).",
      @default_importer_remediation
    )
  end

  defp blocked_report(
         checked_at,
         selected_repository,
         error_type,
         detail,
         remediation,
         project_record \\ nil,
         baseline_metadata \\ nil
       ) do
    %{
      checked_at: checked_at,
      status: :blocked,
      selected_repository: selected_repository,
      project_record: project_record,
      baseline_metadata: baseline_metadata,
      detail: detail,
      remediation: remediation,
      error_type: error_type
    }
  end

  defp ensure_project_record(name, selected_repository, default_branch) do
    case Project.read(
           query: [filter: [source_kind: :github, source_identifier: selected_repository], limit: 1],
           actor: @project_actor
         ) do
      {:ok, [existing_project | _]} ->
        update_attributes = %{
          name: name,
          default_branch: default_branch
        }

        case Project.update(existing_project, update_attributes, actor: @project_actor) do
          {:ok, updated_project} ->
            {:ok, updated_project, :existing}

          {:error, reason} ->
            {:error, {"project_persistence_update_failed", format_reason(reason)}}
        end

      {:ok, []} ->
        create_attributes = %{
          name: name,
          source_kind: :github,
          source_identifier: selected_repository,
          github_full_name: selected_repository,
          default_branch: default_branch
        }

        case Project.create(create_attributes, actor: @project_actor) do
          {:ok, project} ->
            {:ok, project, :created}

          {:error, reason} ->
            {:error, {"project_persistence_create_failed", format_reason(reason)}}
        end

      {:error, reason} ->
        {:error, {"project_persistence_lookup_failed", format_reason(reason)}}
    end
  end

  defp baseline_metadata(checked_at, default_branch, clone_result, baseline_sync_result) do
    synced_branch =
      baseline_sync_result
      |> map_get(:synced_branch, "synced_branch", default_branch)
      |> normalize_branch_name(default_branch)

    workspace_environment =
      clone_result
      |> map_get(:workspace_environment, "workspace_environment", :sprite)
      |> normalize_workspace_environment(:sprite)

    %{
      workspace_initialized: map_get(clone_result, :workspace_initialized, "workspace_initialized", false) == true,
      baseline_synced: map_get(baseline_sync_result, :baseline_synced, "baseline_synced", false) == true,
      default_workflow_registered: true,
      agent_configuration_registered: true,
      status: :ready,
      initialized_at: checked_at,
      synced_branch: synced_branch,
      last_synced_at:
        baseline_sync_result
        |> map_get(:last_synced_at, "last_synced_at", checked_at)
        |> normalize_datetime(checked_at),
      workspace_environment: workspace_environment,
      workspace_path:
        clone_result
        |> map_get(:workspace_path, "workspace_path")
        |> normalize_workspace_root()
    }
  end

  defp project_record(project, import_mode, imported_at) when is_map(project) do
    workspace_settings = project_workspace_settings(project)
    github_full_name = project |> map_get(:github_full_name, "github_full_name") |> normalize_optional_string()
    local_path = project |> map_get(:local_path, "local_path") |> normalize_optional_string()
    source_kind = project |> map_get(:source_kind, "source_kind", :github) |> normalize_source_kind(:github)

    source_identifier =
      project
      |> map_get(:source_identifier, "source_identifier")
      |> normalize_optional_string()
      |> case do
        nil -> github_full_name || local_path || project |> map_get(:id, "id") |> to_string()
        identifier -> identifier
      end

    %{
      id: project |> map_get(:id, "id") |> to_string(),
      name: project |> map_get(:name, "name") |> to_string(),
      source_kind: source_kind,
      source_identifier: source_identifier,
      github_full_name: github_full_name,
      local_path: local_path,
      default_branch:
        project
        |> map_get(:default_branch, "default_branch", @default_branch)
        |> to_string(),
      import_mode: normalize_import_mode(import_mode, :existing),
      imported_at: imported_at,
      clone_status:
        workspace_settings
        |> map_get(:clone_status, "clone_status", :pending)
        |> normalize_clone_status(:pending),
      clone_status_history:
        workspace_settings
        |> map_get(:clone_status_history, "clone_status_history", [])
        |> normalize_clone_status_history(imported_at),
      last_synced_at:
        workspace_settings
        |> map_get(:last_synced_at, "last_synced_at")
        |> normalize_optional_datetime()
    }
  end

  defp persist_clone_status(project, clone_status, checked_at, default_branch, context)
       when is_map(project) do
    clone_status_history =
      project
      |> project_workspace_settings()
      |> map_get(:clone_status_history, "clone_status_history", [])
      |> normalize_clone_status_history(checked_at)
      |> Kernel.++([
        %{status: clone_status, transitioned_at: checked_at}
      ])

    workspace_settings =
      project
      |> project_workspace_settings()
      |> normalize_keyed_map()
      |> Map.put("clone_status", Atom.to_string(clone_status))
      |> Map.put("default_branch", default_branch)
      |> Map.put("clone_status_history", serialize_clone_status_history(clone_status_history))
      |> Map.put("workspace_initialized", context_flag(context, :workspace_initialized, clone_status == :ready))
      |> Map.put("baseline_synced", context_flag(context, :baseline_synced, clone_status == :ready))
      |> put_if_present("workspace_environment", context_environment(context))
      |> put_if_present(
        "workspace_root",
        context |> map_get(:workspace_root, "workspace_root") |> normalize_workspace_root()
      )
      |> put_if_present(
        "workspace_path",
        context |> map_get(:workspace_path, "workspace_path") |> normalize_workspace_root()
      )
      |> put_if_present(
        "last_synced_at",
        context
        |> map_get(:last_synced_at, "last_synced_at")
        |> normalize_optional_datetime()
        |> serialize_optional_datetime()
      )
      |> put_if_present(
        "synced_branch",
        context
        |> map_get(:synced_branch, "synced_branch")
        |> case do
          nil -> nil
          synced_branch -> normalize_branch_name(synced_branch, default_branch)
        end
      )

    workspace_settings =
      if clone_status == :error do
        workspace_settings
        |> put_if_present("last_error_type", context |> map_get(:error_type, "error_type"))
        |> put_if_present("last_error_detail", context |> map_get(:error_detail, "error_detail"))
        |> put_if_present("retry_instructions", context |> map_get(:remediation, "remediation"))
      else
        Map.drop(
          workspace_settings,
          ["last_error_type", "last_error_detail", "retry_instructions"]
        )
      end

    updated_settings =
      project
      |> map_get(:settings, "settings", %{})
      |> normalize_keyed_map()
      |> Map.put("workspace", workspace_settings)

    case Project.update(project, %{settings: updated_settings}, actor: @project_actor) do
      {:ok, updated_project} ->
        {:ok, updated_project}

      {:error, reason} ->
        {:error, {@clone_status_update_error_type, "Failed to persist clone status: #{format_reason(reason)}"}}
    end
  end

  defp persist_clone_status(_project, _clone_status, _checked_at, _default_branch, _context) do
    {:error, {@clone_status_update_error_type, "Project context is unavailable."}}
  end

  defp project_workspace_settings(project) do
    project
    |> map_get(:settings, "settings", %{})
    |> normalize_keyed_map()
    |> Map.get("workspace", %{})
    |> normalize_keyed_map()
  end

  defp normalize_clone_result(clone_result, workspace_context) when is_map(clone_result) do
    workspace_environment =
      clone_result
      |> map_get(:workspace_environment, "workspace_environment")
      |> normalize_workspace_environment(context_environment(workspace_context))

    workspace_root =
      clone_result
      |> map_get(:workspace_root, "workspace_root")
      |> normalize_workspace_root()
      |> case do
        nil ->
          workspace_context
          |> map_get(:workspace_root, "workspace_root")
          |> normalize_workspace_root()

        normalized_workspace_root ->
          normalized_workspace_root
      end

    workspace_path =
      clone_result
      |> map_get(:workspace_path, "workspace_path")
      |> normalize_workspace_root()

    workspace_initialized =
      map_get(clone_result, :workspace_initialized, "workspace_initialized", false) == true

    cond do
      workspace_environment == :local and is_nil(workspace_path) ->
        {:error,
         {
           @clone_stage_error_type,
           "Local clone provisioning did not return a workspace path.",
           @default_clone_retry_remediation
         }}

      workspace_initialized != true ->
        {:error,
         {
           @clone_stage_error_type,
           "Clone provisioning did not initialize the workspace.",
           @default_clone_retry_remediation
         }}

      true ->
        {:ok,
         %{
           workspace_environment: workspace_environment,
           workspace_root: workspace_root,
           workspace_path: workspace_path,
           workspace_initialized: true
         }}
    end
  end

  defp normalize_clone_result(_clone_result, _workspace_context) do
    {:error,
     {
       @clone_stage_error_type,
       "Clone provisioning returned invalid metadata.",
       @default_clone_retry_remediation
     }}
  end

  defp normalize_baseline_sync_result(
         baseline_sync_result,
         checked_at,
         default_branch,
         workspace_context
       )
       when is_map(baseline_sync_result) do
    synced_branch =
      baseline_sync_result
      |> map_get(:synced_branch, "synced_branch", default_branch)
      |> normalize_branch_name(default_branch)

    baseline_synced =
      map_get(baseline_sync_result, :baseline_synced, "baseline_synced", false) == true

    workspace_environment =
      baseline_sync_result
      |> map_get(:workspace_environment, "workspace_environment")
      |> normalize_workspace_environment(context_environment(workspace_context))

    cond do
      baseline_synced != true ->
        {:error,
         {
           @baseline_sync_stage_error_type,
           "Baseline sync did not report a successful synchronization.",
           @default_sync_retry_remediation
         }}

      synced_branch != default_branch ->
        {:error,
         {
           @baseline_sync_stage_error_type,
           "Baseline sync aligned to `#{synced_branch}` instead of configured default `#{default_branch}`.",
           @default_sync_retry_remediation
         }}

      true ->
        {:ok,
         %{
           baseline_synced: true,
           synced_branch: synced_branch,
           last_synced_at:
             baseline_sync_result
             |> map_get(:last_synced_at, "last_synced_at", checked_at)
             |> normalize_datetime(checked_at),
           workspace_environment: workspace_environment
         }}
    end
  end

  defp normalize_baseline_sync_result(
         _baseline_sync_result,
         _checked_at,
         _default_branch,
         _workspace_context
       ) do
    {:error,
     {
       @baseline_sync_stage_error_type,
       "Baseline sync returned invalid metadata.",
       @default_sync_retry_remediation
     }}
  end

  defp workspace_context(onboarding_state, selected_repository) do
    environment_defaults =
      onboarding_state
      |> fetch_step_state(5)
      |> map_get(:environment_defaults, "environment_defaults", %{})

    workspace_environment =
      environment_defaults
      |> map_get(
        :default_environment,
        "default_environment",
        environment_defaults |> map_get(:mode, "mode", :sprite)
      )
      |> normalize_workspace_environment(:sprite)

    workspace_root =
      environment_defaults
      |> map_get(:workspace_root, "workspace_root")
      |> normalize_workspace_root()

    %{
      workspace_environment: workspace_environment,
      workspace_root: workspace_root,
      repository_workspace_dir: repository_workspace_dir(selected_repository)
    }
  end

  defp repository_workspace_dir(selected_repository) when is_binary(selected_repository) do
    selected_repository
    |> String.downcase()
    |> String.replace("/", "__")
    |> String.replace(~r/[^a-z0-9._-]/, "-")
    |> String.trim("-")
    |> case do
      "" -> "project-import"
      sanitized_repository -> sanitized_repository
    end
  end

  defp repository_workspace_dir(_selected_repository), do: "project-import"

  defp split_repository(selected_repository) when is_binary(selected_repository) do
    case String.split(selected_repository, "/", parts: 2) do
      [owner, name] when owner != "" and name != "" ->
        {:ok, owner, name}

      _parts ->
        {:error, {"repository_selection_invalid", "Repository must use `owner/name` format."}}
    end
  end

  defp split_repository(_selected_repository),
    do: {:error, {"repository_selection_invalid", "Repository must use `owner/name` format."}}

  defp serialize_project_record(nil), do: nil

  defp serialize_project_record(project_record) when is_map(project_record) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      "id" => map_get(project_record, :id, "id"),
      "name" => map_get(project_record, :name, "name"),
      "source_kind" =>
        project_record
        |> map_get(:source_kind, "source_kind", :github)
        |> normalize_source_kind(:github)
        |> Atom.to_string(),
      "source_identifier" =>
        map_get(project_record, :source_identifier, "source_identifier") ||
          map_get(project_record, :github_full_name, "github_full_name") ||
          map_get(project_record, :full_name, "full_name"),
      "github_full_name" =>
        map_get(project_record, :github_full_name, "github_full_name") ||
          map_get(project_record, :full_name, "full_name"),
      "full_name" =>
        map_get(project_record, :github_full_name, "github_full_name") ||
          map_get(project_record, :full_name, "full_name"),
      "local_path" => map_get(project_record, :local_path, "local_path"),
      "default_branch" => map_get(project_record, :default_branch, "default_branch", @default_branch),
      "import_mode" =>
        project_record
        |> map_get(:import_mode, "import_mode")
        |> normalize_import_mode(:existing)
        |> Atom.to_string(),
      "imported_at" =>
        project_record
        |> map_get(:imported_at, "imported_at")
        |> normalize_datetime(now)
        |> DateTime.to_iso8601(),
      "clone_status" =>
        project_record
        |> map_get(:clone_status, "clone_status", :pending)
        |> normalize_clone_status(:pending)
        |> Atom.to_string(),
      "clone_status_history" =>
        project_record
        |> map_get(:clone_status_history, "clone_status_history", [])
        |> normalize_clone_status_history(now)
        |> serialize_clone_status_history(),
      "last_synced_at" =>
        project_record
        |> map_get(:last_synced_at, "last_synced_at")
        |> normalize_optional_datetime()
        |> serialize_optional_datetime()
    }
  end

  defp serialize_project_record(_project_record), do: nil

  defp serialize_baseline_metadata(nil), do: nil

  defp serialize_baseline_metadata(baseline_metadata) when is_map(baseline_metadata) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      "workspace_initialized" => map_get(baseline_metadata, :workspace_initialized, "workspace_initialized", false),
      "baseline_synced" => map_get(baseline_metadata, :baseline_synced, "baseline_synced", false),
      "default_workflow_registered" =>
        map_get(
          baseline_metadata,
          :default_workflow_registered,
          "default_workflow_registered",
          false
        ),
      "agent_configuration_registered" =>
        map_get(
          baseline_metadata,
          :agent_configuration_registered,
          "agent_configuration_registered",
          false
        ),
      "status" =>
        baseline_metadata
        |> map_get(:status, "status", :blocked)
        |> normalize_status(:blocked)
        |> Atom.to_string(),
      "initialized_at" =>
        baseline_metadata
        |> map_get(:initialized_at, "initialized_at")
        |> normalize_datetime(now)
        |> DateTime.to_iso8601(),
      "synced_branch" =>
        baseline_metadata
        |> map_get(:synced_branch, "synced_branch", @default_branch)
        |> normalize_branch_name(@default_branch),
      "last_synced_at" =>
        baseline_metadata
        |> map_get(:last_synced_at, "last_synced_at")
        |> normalize_optional_datetime()
        |> serialize_optional_datetime(),
      "workspace_environment" =>
        baseline_metadata
        |> map_get(:workspace_environment, "workspace_environment", :sprite)
        |> normalize_workspace_environment(:sprite)
        |> Atom.to_string(),
      "workspace_path" =>
        baseline_metadata
        |> map_get(:workspace_path, "workspace_path")
        |> normalize_workspace_root()
    }
  end

  defp serialize_baseline_metadata(_baseline_metadata), do: nil

  defp normalize_project_record(project_record, default_imported_at)
       when is_map(project_record) do
    id = project_record |> map_get(:id, "id") |> normalize_optional_string()
    name = project_record |> map_get(:name, "name") |> normalize_optional_string()
    source_kind = project_record |> map_get(:source_kind, "source_kind", :github) |> normalize_source_kind(:github)

    source_identifier =
      project_record |> map_get(:source_identifier, "source_identifier") |> normalize_optional_string()

    github_full_name =
      project_record
      |> map_get(:github_full_name, "github_full_name")
      |> case do
        nil -> map_get(project_record, :full_name, "full_name")
        github_full_name -> github_full_name
      end
      |> normalize_optional_string()

    local_path =
      project_record
      |> map_get(:local_path, "local_path")
      |> normalize_optional_string()

    default_branch =
      project_record
      |> map_get(:default_branch, "default_branch", @default_branch)
      |> normalize_optional_string()
      |> case do
        nil -> @default_branch
        normalized_default_branch -> normalized_default_branch
      end

    resolved_source_identifier = source_identifier || github_full_name || local_path

    if Enum.all?([id, name, default_branch], &is_binary/1) and
         source_kind in [:github, :local] and
         is_binary(resolved_source_identifier) do
      %{
        id: id,
        name: name,
        source_kind: source_kind,
        source_identifier: resolved_source_identifier,
        github_full_name: github_full_name,
        local_path: local_path,
        default_branch: default_branch,
        import_mode:
          project_record
          |> map_get(:import_mode, "import_mode")
          |> normalize_import_mode(:existing),
        imported_at:
          project_record
          |> map_get(:imported_at, "imported_at")
          |> normalize_datetime(default_imported_at),
        clone_status:
          project_record
          |> map_get(:clone_status, "clone_status", :pending)
          |> normalize_clone_status(:pending),
        clone_status_history:
          project_record
          |> map_get(:clone_status_history, "clone_status_history", [])
          |> normalize_clone_status_history(default_imported_at),
        last_synced_at:
          project_record
          |> map_get(:last_synced_at, "last_synced_at")
          |> normalize_optional_datetime()
      }
    else
      nil
    end
  end

  defp normalize_project_record(_project_record, _default_imported_at), do: nil

  defp normalize_source_kind(source_kind, _default) when source_kind in [:github, :local],
    do: source_kind

  defp normalize_source_kind(source_kind, default) when is_binary(source_kind) do
    case String.trim(source_kind) do
      "github" -> :github
      "local" -> :local
      _other -> default
    end
  end

  defp normalize_source_kind(_source_kind, default), do: default

  defp normalize_baseline_metadata(baseline_metadata, default_initialized_at)
       when is_map(baseline_metadata) do
    workspace_initialized =
      map_get(baseline_metadata, :workspace_initialized, "workspace_initialized", false) == true

    baseline_synced =
      map_get(baseline_metadata, :baseline_synced, "baseline_synced", false) == true

    default_workflow_registered =
      map_get(
        baseline_metadata,
        :default_workflow_registered,
        "default_workflow_registered",
        false
      ) == true

    agent_configuration_registered =
      map_get(
        baseline_metadata,
        :agent_configuration_registered,
        "agent_configuration_registered",
        false
      ) == true

    status =
      baseline_metadata
      |> map_get(:status, "status", nil)
      |> normalize_status(
        default_baseline_status(
          workspace_initialized,
          baseline_synced,
          default_workflow_registered,
          agent_configuration_registered
        )
      )

    initialized_at =
      baseline_metadata
      |> map_get(:initialized_at, "initialized_at")
      |> normalize_datetime(default_initialized_at)

    synced_branch =
      baseline_metadata
      |> map_get(:synced_branch, "synced_branch", @default_branch)
      |> normalize_branch_name(@default_branch)

    last_synced_at =
      baseline_metadata
      |> map_get(:last_synced_at, "last_synced_at")
      |> normalize_optional_datetime()
      |> case do
        nil -> initialized_at
        datetime -> datetime
      end

    workspace_environment =
      baseline_metadata
      |> map_get(:workspace_environment, "workspace_environment", :sprite)
      |> normalize_workspace_environment(:sprite)

    workspace_path =
      baseline_metadata
      |> map_get(:workspace_path, "workspace_path")
      |> normalize_workspace_root()

    if status == :ready do
      %{
        workspace_initialized: workspace_initialized,
        baseline_synced: baseline_synced,
        default_workflow_registered: default_workflow_registered,
        agent_configuration_registered: agent_configuration_registered,
        status: :ready,
        initialized_at: initialized_at,
        synced_branch: synced_branch,
        last_synced_at: last_synced_at,
        workspace_environment: workspace_environment,
        workspace_path: workspace_path
      }
    else
      nil
    end
  end

  defp normalize_baseline_metadata(_baseline_metadata, _default_initialized_at), do: nil

  defp normalize_paths(paths) when is_list(paths), do: paths
  defp normalize_paths(_paths), do: []

  defp normalize_installation_sync_state(installation_sync) when is_map(installation_sync) do
    status =
      installation_sync
      |> map_get(:status, "status", nil)
      |> normalize_installation_sync_status()

    repositories =
      installation_sync
      |> map_get(:accessible_repositories, "accessible_repositories", [])
      |> normalize_repositories()

    if status == :ready do
      %{status: :ready, repositories: repositories}
    else
      nil
    end
  end

  defp normalize_installation_sync_state(_installation_sync), do: nil

  defp normalize_installation_sync_status(:ready), do: :ready
  defp normalize_installation_sync_status("ready"), do: :ready
  defp normalize_installation_sync_status(:stale), do: :stale
  defp normalize_installation_sync_status("stale"), do: :stale
  defp normalize_installation_sync_status(_status), do: nil

  defp normalize_repositories(repositories) when is_list(repositories) do
    repositories
    |> Enum.map(&repository_full_name/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_repositories(_repositories), do: []

  defp resolve_default_branch(selected_repository, onboarding_state, fallback)
       when is_binary(selected_repository) and is_map(onboarding_state) do
    selected_repository
    |> repository_metadata(onboarding_state)
    |> map_get(:default_branch, "default_branch", fallback)
    |> normalize_branch_name(fallback)
  end

  defp resolve_default_branch(_selected_repository, _onboarding_state, fallback), do: fallback

  defp repository_metadata(selected_repository, onboarding_state)
       when is_binary(selected_repository) and is_map(onboarding_state) do
    repository_sources(onboarding_state)
    |> Enum.find(%{}, fn repository ->
      repository
      |> repository_full_name()
      |> normalize_repository(nil) == selected_repository
    end)
  end

  defp repository_metadata(_selected_repository, _onboarding_state), do: %{}

  defp repository_sources(onboarding_state) when is_map(onboarding_state) do
    step_7_repositories =
      onboarding_state
      |> fetch_step_state(7)
      |> map_get(:repository_listing, "repository_listing", %{})
      |> map_get(:repositories, "repositories", [])
      |> normalize_paths()

    step_4_repositories =
      onboarding_state
      |> fetch_step_state(4)
      |> map_get(:github_credentials, "github_credentials", %{})
      |> map_get(:paths, "paths", [])
      |> normalize_paths()
      |> Enum.flat_map(fn path ->
        path
        |> map_get(:repositories, "repositories", [])
        |> normalize_paths()
      end)

    step_7_repositories ++ step_4_repositories
  end

  defp repository_sources(_onboarding_state), do: []

  defp default_status(project_record, baseline_metadata) do
    if is_map(project_record) and is_map(baseline_metadata), do: :ready, else: :blocked
  end

  defp clone_or_sync_error?(error_type) do
    normalized_error_type = normalize_error_type(error_type)

    normalized_error_type in [
      @clone_stage_error_type,
      @baseline_sync_stage_error_type,
      @clone_status_update_error_type
    ] or
      (is_binary(normalized_error_type) and
         String.starts_with?(normalized_error_type, "workspace_")) or
      (is_binary(normalized_error_type) and
         String.starts_with?(normalized_error_type, "baseline_sync_"))
  end

  defp default_baseline_status(true, true, true, true), do: :ready
  defp default_baseline_status(_, _, _, _), do: :blocked

  defp previous_selected_repository(previous_state) do
    previous_state
    |> from_state()
    |> selected_repository()
  end

  defp normalize_import_mode(:created, _default), do: :created
  defp normalize_import_mode(:existing, _default), do: :existing
  defp normalize_import_mode("created", _default), do: :created
  defp normalize_import_mode("existing", _default), do: :existing
  defp normalize_import_mode(_import_mode, default), do: default

  defp normalize_clone_status(:pending, _default), do: :pending
  defp normalize_clone_status(:cloning, _default), do: :cloning
  defp normalize_clone_status(:ready, _default), do: :ready
  defp normalize_clone_status(:error, _default), do: :error
  defp normalize_clone_status("pending", _default), do: :pending
  defp normalize_clone_status("cloning", _default), do: :cloning
  defp normalize_clone_status("ready", _default), do: :ready
  defp normalize_clone_status("error", _default), do: :error
  defp normalize_clone_status(_clone_status, default), do: default

  defp normalize_status(:ready, _default), do: :ready
  defp normalize_status(:blocked, _default), do: :blocked
  defp normalize_status("ready", _default), do: :ready
  defp normalize_status("blocked", _default), do: :blocked
  defp normalize_status(_status, default), do: default

  defp normalize_path_status(:ready, _default), do: :ready
  defp normalize_path_status("ready", _default), do: :ready
  defp normalize_path_status(_status, default), do: default

  defp normalize_clone_status_history(history, fallback_datetime) when is_list(history) do
    history
    |> Enum.flat_map(fn
      %{} = entry ->
        status =
          entry
          |> map_get(:status, "status", :pending)
          |> normalize_clone_status(:pending)

        transitioned_at =
          entry
          |> map_get(:transitioned_at, "transitioned_at")
          |> normalize_datetime(fallback_datetime)

        [%{status: status, transitioned_at: transitioned_at}]

      _other ->
        []
    end)
  end

  defp normalize_clone_status_history(_history, _fallback_datetime), do: []

  defp serialize_clone_status_history(history) when is_list(history) do
    Enum.map(history, fn entry ->
      %{
        "status" =>
          entry
          |> map_get(:status, "status", :pending)
          |> normalize_clone_status(:pending)
          |> Atom.to_string(),
        "transitioned_at" =>
          entry
          |> map_get(:transitioned_at, "transitioned_at")
          |> normalize_datetime(DateTime.utc_now() |> DateTime.truncate(:second))
          |> DateTime.to_iso8601()
      }
    end)
  end

  defp serialize_clone_status_history(_history), do: []

  defp normalize_datetime(%DateTime{} = datetime, _default), do: datetime

  defp normalize_datetime(datetime, default) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, parsed_datetime, _offset} -> parsed_datetime
      _other -> default
    end
  end

  defp normalize_datetime(_datetime, default), do: default

  defp normalize_optional_datetime(nil), do: nil

  defp normalize_optional_datetime(value) do
    case normalize_datetime(value, nil) do
      %DateTime{} = datetime -> datetime
      _other -> nil
    end
  end

  defp serialize_optional_datetime(nil), do: nil
  defp serialize_optional_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp serialize_optional_datetime(_datetime), do: nil

  defp normalize_repository(repository, fallback) when is_binary(repository) do
    case String.trim(repository) do
      "" -> fallback
      normalized_repository -> normalized_repository
    end
  end

  defp normalize_repository(_repository, fallback), do: fallback

  defp repository_full_name(repository) when is_binary(repository),
    do: normalize_repository(repository, nil)

  defp repository_full_name(repository) when is_map(repository) do
    repository
    |> map_get(:full_name, "full_name")
    |> normalize_repository(nil)
  end

  defp repository_full_name(_repository), do: nil

  defp normalize_branch_name(value, fallback) when is_binary(value) do
    case String.trim(value) do
      "" -> fallback
      normalized_branch -> normalized_branch
    end
  end

  defp normalize_branch_name(_value, fallback), do: fallback

  defp normalize_workspace_environment(:sprite, _default), do: :sprite
  defp normalize_workspace_environment(:local, _default), do: :local
  defp normalize_workspace_environment(:cloud, _default), do: :sprite
  defp normalize_workspace_environment("sprite", _default), do: :sprite
  defp normalize_workspace_environment("local", _default), do: :local
  defp normalize_workspace_environment("cloud", _default), do: :sprite
  defp normalize_workspace_environment(_workspace_environment, default), do: default

  defp normalize_workspace_root(workspace_root) when is_binary(workspace_root) do
    workspace_root
    |> String.trim()
    |> case do
      "" -> nil
      normalized_workspace_root -> normalized_workspace_root
    end
  end

  defp normalize_workspace_root(_workspace_root), do: nil

  defp context_environment(context) do
    context
    |> map_get(:workspace_environment, "workspace_environment", :sprite)
    |> normalize_workspace_environment(:sprite)
  end

  defp context_flag(context, key, default) do
    context
    |> map_get(key, Atom.to_string(key), default)
    |> case do
      true -> true
      _other -> false
    end
  end

  defp normalize_keyed_map(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {key, value}, acc when is_atom(key) ->
        Map.put(acc, Atom.to_string(key), value)

      {key, value}, acc when is_binary(key) ->
        Map.put(acc, key, value)

      {key, value}, acc ->
        Map.put(acc, to_string(key), value)
    end)
  end

  defp normalize_keyed_map(_map), do: %{}

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  defp normalize_detail(nil, :ready),
    do: "Repository import is complete. Workspace clone and baseline sync are ready."

  defp normalize_detail(nil, :blocked),
    do: "Repository import is blocked until a valid repository is selected and import succeeds."

  defp normalize_detail(detail, _status) when is_binary(detail) and detail != "", do: detail
  defp normalize_detail(_detail, _status), do: "Project import status is unavailable."

  defp normalize_remediation(nil, :ready), do: "Project import is ready."

  defp normalize_remediation(nil, :blocked),
    do: "Resolve clone or baseline sync failures and retry step 7."

  defp normalize_remediation(remediation, _status)
       when is_binary(remediation) and remediation != "",
       do: remediation

  defp normalize_remediation(_remediation, _status), do: @default_importer_remediation

  defp normalize_error_type(error_type) when is_atom(error_type), do: Atom.to_string(error_type)

  defp normalize_error_type(error_type) when is_binary(error_type) do
    case String.trim(error_type) do
      "" -> nil
      normalized_error_type -> normalized_error_type
    end
  end

  defp normalize_error_type(_error_type), do: nil

  defp normalize_error_detail(detail) when is_binary(detail) and detail != "", do: detail
  defp normalize_error_detail(detail), do: inspect(detail)

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: normalize_optional_string(Atom.to_string(value))

  defp normalize_optional_string(_value), do: nil

  defp fetch_step_state(onboarding_state, onboarding_step) when is_map(onboarding_state) do
    step_key = Integer.to_string(onboarding_step)
    Map.get(onboarding_state, step_key) || Map.get(onboarding_state, onboarding_step) || %{}
  end

  defp fetch_step_state(_onboarding_state, _onboarding_step), do: %{}

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp format_reason(reason) do
    reason
    |> Exception.message()
  rescue
    _exception -> inspect(reason)
  end
end
