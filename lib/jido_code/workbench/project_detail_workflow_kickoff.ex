defmodule JidoCode.Workbench.ProjectDetailWorkflowKickoff do
  @moduledoc """
  Validates and launches workflow runs from repo detail route controls.
  """

  alias JidoCode.ManagedRepoRoutes
  alias JidoCode.Operations.Ingress
  alias JidoCode.Workbench.ProjectDetail

  @default_error_type "project_detail_workflow_kickoff_failed"
  @validation_error_type "project_detail_workflow_validation_failed"
  @workflow_unsupported_error_type "project_detail_workflow_unsupported"

  @validation_remediation """
  Verify repo detail metadata and retry workflow launch from `/repos/:id`.
  """

  @launcher_remediation """
  Verify workflow runtime setup and retry kickoff from repo detail.
  """

  @supported_workflows [
    %{
      name: "fix_failing_tests",
      label: "Fix failing tests",
      launcher_env: :workbench_fix_workflow_launcher,
      context_item_type: :issue,
      context_item_label: "Repository issue queue"
    },
    %{
      name: "issue_triage",
      label: "Issue triage and research",
      launcher_env: :workbench_issue_triage_workflow_launcher,
      context_item_type: :issue,
      context_item_label: "Repository issue queue"
    }
  ]

  @type kickoff_error :: %{
          error_type: String.t(),
          detail: String.t(),
          remediation: String.t()
        }

  @type kickoff_run :: %{
          run_id: String.t(),
          workflow_name: String.t(),
          project_id: String.t(),
          project_name: String.t(),
          project_defaults: map(),
          trigger: map(),
          initiating_actor: map(),
          detail_path: String.t(),
          started_at: DateTime.t()
        }

  @spec supported_workflows() :: [map()]
  def supported_workflows do
    Enum.map(@supported_workflows, fn workflow ->
      %{
        name: workflow.name,
        label: workflow.label
      }
    end)
  end

  @spec kickoff(map() | nil, term(), map() | nil) ::
          {:ok, kickoff_run()} | {:error, kickoff_error()}
  def kickoff(project_detail, workflow_name, initiating_actor),
    do: kickoff(project_detail, workflow_name, initiating_actor, [])

  @spec kickoff(map() | nil, term(), map() | nil, keyword()) ::
          {:ok, kickoff_run()} | {:error, kickoff_error()}
  def kickoff(project_detail, workflow_name, initiating_actor, opts) when is_list(opts) do
    with {:ok, project_scope} <- normalize_project_scope(project_detail),
         :ok <- ensure_project_ready(project_scope),
         {:ok, workflow_definition} <- workflow_definition(workflow_name),
         kickoff_request <-
           build_kickoff_request(project_scope, workflow_definition, initiating_actor, opts),
         :ok <- record_project_detail_intake(kickoff_request),
         {:ok, kickoff_run} <- invoke_launcher(workflow_definition, kickoff_request) do
      {:ok, kickoff_run}
    else
      {:error, error} ->
        {:error, normalize_error(error)}

      other ->
        {:error,
         kickoff_error(
           @default_error_type,
           "Repository workflow kickoff failed with an unexpected result (#{inspect(other)}).",
           @launcher_remediation
         )}
    end
  end

  @doc false
  @spec default_launcher(map()) :: {:ok, map()}
  def default_launcher(_kickoff_request) do
    {:ok,
     %{
       run_id: generated_run_id(),
       started_at: DateTime.utc_now() |> DateTime.truncate(:second)
     }}
  end

  defp normalize_project_scope(project_detail) when is_map(project_detail) do
    project_id =
      project_detail
      |> map_get(:id, "id")
      |> normalize_optional_string()

    project_name =
      project_detail
      |> map_get(:name, "name")
      |> normalize_optional_string()

    github_full_name =
      project_detail
      |> map_get(:github_full_name, "github_full_name")
      |> normalize_optional_string()

    default_branch =
      project_detail
      |> map_get(:default_branch, "default_branch")
      |> normalize_optional_string() || "main"

    execution_readiness =
      project_detail
      |> map_get(:execution_readiness, "execution_readiness", %{})
      |> normalize_map()

    if is_binary(project_id) do
      {:ok,
       %{
         project_id: project_id,
         project_name: project_name || github_full_name || project_id,
         github_full_name: github_full_name,
         default_branch: default_branch,
         execution_readiness: execution_readiness
       }}
    else
      {:error, validation_error("Repo detail is missing a durable repository identifier.")}
    end
  end

  defp normalize_project_scope(_project_detail) do
    {:error, validation_error("Repo detail context is unavailable for workflow launch.")}
  end

  defp ensure_project_ready(project_scope) do
    execution_readiness = Map.fetch!(project_scope, :execution_readiness)

    if ProjectDetail.ready_for_execution?(%{execution_readiness: execution_readiness}) do
      :ok
    else
      {:error,
       kickoff_error(
         execution_readiness
         |> map_get(:error_type, "error_type")
         |> normalize_optional_string() || "project_execution_not_ready",
         execution_readiness
         |> map_get(:detail, "detail")
         |> normalize_optional_string() || "Repository is not ready for workflow execution.",
         execution_readiness
         |> map_get(:remediation, "remediation")
         |> normalize_optional_string() || @validation_remediation
       )}
    end
  end

  defp workflow_definition(workflow_name) do
    normalized_workflow_name = normalize_optional_string(workflow_name)

    case Enum.find(@supported_workflows, fn workflow ->
           workflow.name == normalized_workflow_name
         end) do
      %{} = workflow ->
        {:ok, workflow}

      nil ->
        {:error,
         kickoff_error(
           @workflow_unsupported_error_type,
           "Workflow #{inspect(workflow_name)} is not supported from repo detail controls.",
           @validation_remediation
         )}
    end
  end

  defp build_kickoff_request(project_scope, workflow_definition, initiating_actor, opts) do
    project_id = Map.fetch!(project_scope, :project_id)
    github_full_name = Map.get(project_scope, :github_full_name)
    return_to = opts |> Keyword.get(:return_to) |> normalize_optional_string()

    trigger =
      workflow_definition
      |> Map.get(:name)
      |> project_detail_trigger(project_id, return_to)

    %{
      workflow_name: Map.fetch!(workflow_definition, :name),
      repo_id: project_id,
      repository_name: Map.fetch!(project_scope, :project_name),
      repository_defaults: %{
        default_branch: Map.fetch!(project_scope, :default_branch),
        github_full_name: github_full_name
      },
      project_id: project_id,
      project_name: Map.fetch!(project_scope, :project_name),
      project_defaults: %{
        default_branch: Map.fetch!(project_scope, :default_branch),
        github_full_name: github_full_name
      },
      return_to: return_to,
      trigger: trigger,
      initiating_actor: normalize_initiating_actor(initiating_actor),
      context_item: %{
        type: Map.fetch!(workflow_definition, :context_item_type),
        label: Map.fetch!(workflow_definition, :context_item_label),
        github_url: context_item_github_url(github_full_name)
      }
    }
  end

  defp record_project_detail_intake(kickoff_request) do
    case Ingress.record_operator_intake(%{
           channel: "project_detail",
           intent: "project_detail_workflow_kickoff",
           project_id: Map.fetch!(kickoff_request, :project_id),
           actor: Map.fetch!(kickoff_request, :initiating_actor),
           payload: %{
             "workflow_name" => Map.fetch!(kickoff_request, :workflow_name),
             "repository_name" => Map.fetch!(kickoff_request, :repository_name),
             "repository_defaults" => Map.fetch!(kickoff_request, :repository_defaults),
             "project_name" => Map.fetch!(kickoff_request, :project_name),
             "project_defaults" => Map.fetch!(kickoff_request, :project_defaults),
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

  defp project_detail_trigger("issue_triage", project_id, return_to) do
    %{
      source: "project_detail",
      mode: "manual",
      source_row: %{
        route: return_to || "/repos/#{project_id}",
        project_id: project_id
      },
      policy: %{
        name: "issue_triage_manual_launch"
      }
    }
  end

  defp project_detail_trigger(_workflow_name, project_id, return_to) do
    %{
      source: "project_detail",
      mode: "manual",
      source_row: %{
        route: return_to || "/repos/#{project_id}",
        project_id: project_id
      }
    }
  end

  defp context_item_github_url(github_full_name) do
    with {:ok, repository_path} <- github_repository_path(github_full_name) do
      "#{repository_path}/issues"
    end
  end

  defp github_repository_path(nil), do: :error

  defp github_repository_path(github_full_name) do
    case String.split(github_full_name, "/", parts: 2) do
      [owner, repository] ->
        owner = String.trim(owner)
        repository = String.trim(repository)

        if owner == "" or repository == "" or String.contains?(owner <> repository, " ") do
          :error
        else
          {:ok, "https://github.com/#{owner}/#{repository}"}
        end

      _other ->
        :error
    end
  end

  defp normalize_initiating_actor(%{} = initiating_actor) do
    %{
      id:
        initiating_actor
        |> map_get(:id, "id")
        |> normalize_optional_string() || "unknown",
      email:
        initiating_actor
        |> map_get(:email, "email")
        |> normalize_optional_string()
    }
  end

  defp normalize_initiating_actor(_initiating_actor), do: %{id: "unknown", email: nil}

  defp invoke_launcher(workflow_definition, kickoff_request) do
    launcher_env = Map.fetch!(workflow_definition, :launcher_env)
    launcher = Application.get_env(:jido_code, launcher_env, &__MODULE__.default_launcher/1)

    if is_function(launcher, 1) do
      safe_invoke_launcher(launcher, kickoff_request)
    else
      {:error,
       kickoff_error(
         @default_error_type,
         "Repo detail launcher configuration is invalid for #{Map.fetch!(workflow_definition, :name)}.",
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
             "Repo detail launcher returned an invalid result (#{inspect(other)}).",
             @launcher_remediation
           )}
      end
    rescue
      exception ->
        {:error,
         kickoff_error(
           @default_error_type,
           "Repo detail launcher crashed (#{Exception.message(exception)}).",
           @launcher_remediation
         )}
    catch
      kind, reason ->
        {:error,
         kickoff_error(
           @default_error_type,
           "Repo detail launcher threw #{inspect({kind, reason})}.",
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

      project_id = Map.fetch!(kickoff_request, :project_id)

      repo_id =
        kickoff_request
        |> Map.get(:repo_id, project_id)
        |> normalize_optional_string() || project_id

      {:ok,
       %{
         run_id: run_id,
         workflow_name: Map.fetch!(kickoff_request, :workflow_name),
         repo_id: repo_id,
         repository_name: Map.fetch!(kickoff_request, :repository_name),
         repository_defaults: Map.fetch!(kickoff_request, :repository_defaults),
         project_id: project_id,
         project_name: Map.fetch!(kickoff_request, :project_name),
         project_defaults: Map.fetch!(kickoff_request, :project_defaults),
         trigger: Map.fetch!(kickoff_request, :trigger),
         initiating_actor: Map.fetch!(kickoff_request, :initiating_actor),
         detail_path:
           ManagedRepoRoutes.run_detail_path(
             repo_id,
             run_id,
             return_to: Map.get(kickoff_request, :return_to)
           ),
         started_at: started_at
       }}
    else
      {:error,
       kickoff_error(
         @default_error_type,
         "Repo detail workflow kickoff did not return a run identifier.",
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

  defp validation_error(detail) do
    kickoff_error(@validation_error_type, detail, @validation_remediation)
  end

  defp normalize_error(error) do
    kickoff_error(
      map_get(error, :error_type, "error_type", @default_error_type),
      map_get(error, :detail, "detail", "Repo detail workflow kickoff failed."),
      map_get(error, :remediation, "remediation", @launcher_remediation)
    )
  end

  defp intake_error(reason) do
    kickoff_error(
      "project_detail_workflow_intake_record_failed",
      "Repo detail workflow kickoff could not be normalized into a durable intake (#{inspect(reason)}).",
      @launcher_remediation
    )
  end

  defp kickoff_error(error_type, detail, remediation) do
    %{
      error_type: normalize_optional_string(error_type) || @default_error_type,
      detail: normalize_optional_string(detail) || "Repo detail workflow kickoff failed.",
      remediation: normalize_optional_string(remediation) || @launcher_remediation
    }
  end

  defp generated_run_id do
    "run-#{System.unique_integer([:positive, :monotonic])}"
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
