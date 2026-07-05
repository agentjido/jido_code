defmodule JidoCode.WorkflowRuntime.ManualRunKickoff do
  @moduledoc """
  Validates and launches manual workflow runs from `/workflows`.
  """

  alias JidoCode.Control.RepoBridge

  @default_error_type "workflow_manual_run_creation_failed"
  @validation_error_type "workflow_run_validation_failed"
  @workflow_unsupported_error_type "workflow_template_unsupported"
  @repository_lookup_error_type "workflow_repository_lookup_failed"
  @workflow_definition_lookup_error_type "workflow_definition_lookup_failed"
  @workflow_version_pinning_error_type "workflow_version_pinning_failed"

  @validation_remediation """
  Select a workflow template and provide all required inputs, then retry from `/workflows`.
  """

  @launcher_remediation """
  Verify workflow runtime setup and retry kickoff from `/workflows`.
  """

  @repository_lookup_remediation """
  Ensure the repository is imported and available, then retry kickoff from `/workflows`.
  """
  @workflow_definition_remediation """
  Verify workflow definition metadata and retry kickoff from `/workflows`.
  """

  @supported_workflows [
    %{
      name: "implement_task",
      version: 1,
      label: "Implement task",
      description: "Plan and implement an operator-scoped coding task.",
      required_inputs: [
        %{
          name: :task_summary,
          label: "Task summary",
          placeholder: "Describe the task this run should implement."
        }
      ]
    },
    %{
      name: "fix_failing_tests",
      version: 1,
      label: "Fix failing tests",
      description: "Diagnose and repair a known failing test signal.",
      required_inputs: [
        %{
          name: :failure_signal,
          label: "Failure signal",
          placeholder: "Provide the failing test name or error output."
        }
      ]
    },
    %{
      name: "issue_triage",
      version: 1,
      label: "Issue triage and research",
      description: "Run manual issue triage with operator-provided issue context.",
      required_inputs: [
        %{
          name: :issue_reference,
          label: "Issue reference",
          placeholder: "Paste an issue URL or owner/repo#number reference."
        }
      ]
    }
  ]

  @type field_error :: %{
          field: String.t(),
          error_type: String.t(),
          detail: String.t()
        }

  @type kickoff_error :: %{
          error_type: String.t(),
          detail: String.t(),
          remediation: String.t(),
          field_errors: [field_error()]
        }

  @type kickoff_run :: %{
          run_id: String.t(),
          workflow_name: String.t(),
          workflow_version: pos_integer(),
          repo_id: String.t(),
          managed_repo_id: String.t() | nil,
          repository_name: String.t(),
          repository_defaults: map(),
          project_id: String.t(),
          project_name: String.t(),
          project_defaults: map(),
          trigger: map(),
          inputs: map(),
          input_metadata: map(),
          initiating_actor: map(),
          detail_path: String.t(),
          started_at: DateTime.t()
        }

  @spec supported_workflows() :: [map()]
  def supported_workflows do
    Enum.map(@supported_workflows, fn workflow ->
      %{
        name: workflow.name,
        version: workflow.version,
        label: workflow.label,
        description: workflow.description,
        required_inputs:
          Enum.map(workflow.required_inputs, fn input ->
            %{
              name: input.name,
              label: input.label,
              placeholder: input.placeholder
            }
          end)
      }
    end)
  end

  @spec repository_options() :: [map()]
  def repository_options do
    case load_repositories() do
      {:ok, repositories} -> repositories
      {:error, _error} -> []
    end
  end

  @spec project_options() :: [map()]
  def project_options, do: repository_options()

  @spec kickoff(map() | nil, map() | nil) :: {:ok, kickoff_run()} | {:error, kickoff_error()}
  def kickoff(run_params, initiating_actor) do
    with {:ok, workflow_definition} <- workflow_definition(run_params),
         {:ok, repository_scope} <- repository_scope(run_params),
         {:ok, inputs, input_metadata} <- validate_required_inputs(workflow_definition, run_params),
         kickoff_request <-
           build_kickoff_request(
             repository_scope,
             workflow_definition,
             inputs,
             input_metadata,
             initiating_actor
           ),
         {:ok, kickoff_run} <- invoke_launcher(kickoff_request) do
      {:ok, kickoff_run}
    else
      {:error, error} ->
        {:error, normalize_error(error)}

      other ->
        {:error,
         kickoff_error(
           @default_error_type,
           "Workflow run kickoff failed with an unexpected result (#{inspect(other)}).",
           @launcher_remediation
         )}
    end
  end

  @doc false
  @spec default_workflow_definition_loader() :: {:ok, [map()]}
  def default_workflow_definition_loader do
    {:ok, @supported_workflows}
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

  @doc false
  @spec default_repository_loader() :: {:ok, [map()]} | {:error, kickoff_error()}
  def default_repository_loader do
    case RepoBridge.list_repo_scopes() do
      {:ok, repo_scopes} ->
        {:ok,
         repo_scopes
         |> Enum.map(fn managed_repo ->
           to_repository_option(managed_repo)
         end)
         |> Enum.reject(&is_nil/1)}

      {:error, reason} ->
        {:error,
         kickoff_error(
           @repository_lookup_error_type,
           "Repository lookup failed (#{format_reason(reason)}).",
           @repository_lookup_remediation
         )}
    end
  end

  @spec default_project_loader() :: {:ok, [map()]} | {:error, kickoff_error()}
  def default_project_loader, do: default_repository_loader()

  defp workflow_definition(run_params) do
    with {:ok, workflow_definitions} <- load_workflow_definitions() do
      workflow_definition(run_params, workflow_definitions)
    end
  end

  defp workflow_definition(run_params, workflow_definitions) do
    workflow_name =
      run_params
      |> map_get(:workflow_name, "workflow_name")
      |> normalize_optional_string()

    case Enum.find(workflow_definitions, fn workflow ->
           map_get(workflow, :name, "name") == workflow_name
         end) do
      %{} = workflow ->
        with {:ok, workflow_version} <- workflow_version(workflow, workflow_name) do
          {:ok, Map.put(workflow, :version, workflow_version)}
        end

      nil when is_nil(workflow_name) ->
        {:error,
         validation_error(
           "Workflow template is required before starting a run.",
           [field_error("workflow_name", "required", "Select a workflow template.")]
         )}

      nil ->
        {:error,
         kickoff_error(
           @workflow_unsupported_error_type,
           "Workflow template #{inspect(workflow_name)} is not supported.",
           @validation_remediation,
           [field_error("workflow_name", "unsupported", "Choose one of the listed workflow templates.")]
         )}
    end
  end

  defp workflow_version(workflow_definition, workflow_name) do
    workflow_version =
      workflow_definition
      |> map_get(:version, "version")
      |> normalize_optional_positive_integer()

    if is_integer(workflow_version) do
      {:ok, workflow_version}
    else
      {:error,
       kickoff_error(
         @workflow_version_pinning_error_type,
         "Workflow template #{inspect(workflow_name)} is missing a valid version and cannot be pinned.",
         @workflow_definition_remediation
       )}
    end
  end

  defp load_workflow_definitions do
    loader =
      Application.get_env(
        :jido_code,
        :workflow_manual_definition_loader,
        &__MODULE__.default_workflow_definition_loader/0
      )

    if is_function(loader, 0) do
      safe_invoke_workflow_definition_loader(loader)
    else
      {:error,
       kickoff_error(
         @workflow_definition_lookup_error_type,
         "Workflow definition loader configuration is invalid.",
         @workflow_definition_remediation
       )}
    end
  end

  defp safe_invoke_workflow_definition_loader(loader) do
    try do
      case loader.() do
        {:ok, workflow_definitions} when is_list(workflow_definitions) ->
          {:ok, workflow_definitions}

        {:error, error} ->
          {:error, normalize_workflow_definition_error(error)}

        other ->
          {:error,
           kickoff_error(
             @workflow_definition_lookup_error_type,
             "Workflow definition loader returned an invalid result (#{inspect(other)}).",
             @workflow_definition_remediation
           )}
      end
    rescue
      exception ->
        {:error,
         kickoff_error(
           @workflow_definition_lookup_error_type,
           "Workflow definition loader crashed (#{Exception.message(exception)}).",
           @workflow_definition_remediation
         )}
    catch
      kind, reason ->
        {:error,
         kickoff_error(
           @workflow_definition_lookup_error_type,
           "Workflow definition loader threw #{inspect({kind, reason})}.",
           @workflow_definition_remediation
         )}
    end
  end

  defp repository_scope(run_params) do
    case repository_identifier(run_params) do
      nil ->
        {:error,
         validation_error(
           "Repo scope is required before starting a workflow run.",
           [field_error("repo_id", "required", "Select a repository to scope this run.")]
         )}

      repo_id ->
        with {:ok, repositories} <- load_repositories(),
             {:ok, repository_scope} <- find_repository_scope(repositories, repo_id) do
          {:ok, repository_scope}
        end
    end
  end

  defp find_repository_scope(repositories, repo_id) when is_list(repositories) do
    case Enum.find(repositories, fn repository ->
           repository
           |> map_get(:id, "id")
           |> normalize_optional_string() == repo_id
         end) do
      %{} = repository ->
        resolved_repo_id =
          repository
          |> map_get(:id, "id")
          |> normalize_optional_string() || repo_id

        managed_repo_id =
          repository
          |> map_get(:managed_repo_id, "managed_repo_id")
          |> normalize_optional_string() || resolved_repo_id

        repository_name =
          repository
          |> map_get(:name, "name")
          |> normalize_optional_string()

        github_full_name =
          repository
          |> map_get(:github_full_name, "github_full_name")
          |> normalize_optional_string()

        default_branch =
          repository
          |> map_get(:default_branch, "default_branch")
          |> normalize_optional_string() || "main"

        legacy_project_id =
          repository
          |> map_get(:legacy_project_id, "legacy_project_id")
          |> normalize_optional_string() || resolved_repo_id

        {:ok,
         %{
           repo_id: resolved_repo_id,
           managed_repo_id: managed_repo_id,
           repository_name: repository_name || github_full_name || resolved_repo_id,
           project_id: legacy_project_id,
           project_name: repository_name || github_full_name || resolved_repo_id,
           github_full_name: github_full_name,
           default_branch: default_branch
         }}

      nil ->
        {:error,
         validation_error(
           "Repository #{repo_id} was not found.",
           [field_error("repo_id", "not_found", "Select an imported repository and retry kickoff.")]
         )}
    end
  end

  defp find_repository_scope(_repositories, _repo_id) do
    {:error,
     kickoff_error(
       @repository_lookup_error_type,
       "Repository loader returned malformed repository catalog data.",
       @repository_lookup_remediation
     )}
  end

  defp load_repositories do
    loader =
      Application.get_env(
        :jido_code,
        :workflow_manual_repository_loader,
        Application.get_env(:jido_code, :workflow_manual_project_loader, &__MODULE__.default_repository_loader/0)
      )

    if is_function(loader, 0) do
      safe_invoke_repository_loader(loader)
    else
      {:error,
       kickoff_error(
         @repository_lookup_error_type,
         "Workflow manual repository loader configuration is invalid.",
         @repository_lookup_remediation
       )}
    end
  end

  defp safe_invoke_repository_loader(loader) do
    try do
      case loader.() do
        {:ok, repositories} when is_list(repositories) ->
          {:ok, normalize_loaded_repositories(repositories)}

        {:error, error} ->
          {:error, normalize_repository_lookup_error(error)}

        other ->
          {:error,
           kickoff_error(
             @repository_lookup_error_type,
             "Workflow manual repository loader returned an invalid result (#{inspect(other)}).",
             @repository_lookup_remediation
           )}
      end
    rescue
      exception ->
        {:error,
         kickoff_error(
           @repository_lookup_error_type,
           "Workflow manual repository loader crashed (#{Exception.message(exception)}).",
           @repository_lookup_remediation
         )}
    catch
      kind, reason ->
        {:error,
         kickoff_error(
           @repository_lookup_error_type,
           "Workflow manual repository loader threw #{inspect({kind, reason})}.",
           @repository_lookup_remediation
         )}
    end
  end

  defp normalize_loaded_repositories(repositories) do
    repositories
    |> Enum.map(&to_repository_option/1)
    |> Enum.reject(&is_nil/1)
  end

  defp validate_required_inputs(workflow_definition, run_params) do
    required_inputs = Map.fetch!(workflow_definition, :required_inputs)

    {errors, normalized_inputs, input_metadata} =
      Enum.reduce(required_inputs, {[], %{}, %{}}, fn input, {errors, inputs, metadata} ->
        input_name = Map.fetch!(input, :name)
        input_name_string = Atom.to_string(input_name)
        input_label = Map.fetch!(input, :label)

        value =
          run_params
          |> map_get(input_name, input_name_string)
          |> normalize_optional_string()

        metadata_entry = %{
          label: input_label,
          required: true,
          source: "manual_workflows_ui"
        }

        if is_binary(value) do
          {
            errors,
            Map.put(inputs, input_name_string, value),
            Map.put(metadata, input_name_string, metadata_entry)
          }
        else
          {
            [field_error(input_name_string, "required", "#{input_label} is required.") | errors],
            inputs,
            Map.put(metadata, input_name_string, metadata_entry)
          }
        end
      end)

    if errors == [] do
      {:ok, normalized_inputs, input_metadata}
    else
      {:error,
       validation_error(
         "Workflow run validation failed because required inputs are missing.",
         Enum.reverse(errors)
       )}
    end
  end

  defp build_kickoff_request(
         repository_scope,
         workflow_definition,
         inputs,
         input_metadata,
         initiating_actor
       ) do
    workflow_name = Map.fetch!(workflow_definition, :name)
    workflow_version = Map.fetch!(workflow_definition, :version)
    repo_id = Map.fetch!(repository_scope, :repo_id)

    repository_defaults = %{
      default_branch: Map.fetch!(repository_scope, :default_branch),
      github_full_name: Map.get(repository_scope, :github_full_name)
    }

    %{
      workflow_name: workflow_name,
      workflow_version: workflow_version,
      repo_id: repo_id,
      managed_repo_id: Map.get(repository_scope, :managed_repo_id),
      repository_name: Map.fetch!(repository_scope, :repository_name),
      repository_defaults: repository_defaults,
      project_id: Map.fetch!(repository_scope, :project_id),
      project_name: Map.fetch!(repository_scope, :project_name),
      project_defaults: repository_defaults,
      trigger: %{
        source: "workflows",
        mode: "manual",
        source_row: %{
          route: "/workflows",
          repo_id: repo_id,
          project_id: Map.fetch!(repository_scope, :project_id),
          workflow_name: workflow_name,
          workflow_version: workflow_version
        }
      },
      inputs: inputs,
      input_metadata: input_metadata,
      initiating_actor: normalize_initiating_actor(initiating_actor)
    }
  end

  defp invoke_launcher(kickoff_request) do
    launcher =
      Application.get_env(
        :jido_code,
        :workflow_manual_run_launcher,
        &__MODULE__.default_launcher/1
      )

    if is_function(launcher, 1) do
      safe_invoke_launcher(launcher, kickoff_request)
    else
      {:error,
       kickoff_error(
         @default_error_type,
         "Workflow manual run launcher configuration is invalid.",
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
             "Workflow manual run launcher returned an invalid result (#{inspect(other)}).",
             @launcher_remediation
           )}
      end
    rescue
      exception ->
        {:error,
         kickoff_error(
           @default_error_type,
           "Workflow manual run launcher crashed (#{Exception.message(exception)}).",
           @launcher_remediation
         )}
    catch
      kind, reason ->
        {:error,
         kickoff_error(
           @default_error_type,
           "Workflow manual run launcher threw #{inspect({kind, reason})}.",
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

      repo_id = Map.fetch!(kickoff_request, :repo_id)
      project_id = Map.fetch!(kickoff_request, :project_id)

      {:ok,
       %{
         run_id: run_id,
         workflow_name: Map.fetch!(kickoff_request, :workflow_name),
         workflow_version: Map.fetch!(kickoff_request, :workflow_version),
         repo_id: repo_id,
         managed_repo_id: Map.get(kickoff_request, :managed_repo_id),
         repository_name: Map.fetch!(kickoff_request, :repository_name),
         repository_defaults: Map.fetch!(kickoff_request, :repository_defaults),
         project_id: project_id,
         project_name: Map.fetch!(kickoff_request, :project_name),
         project_defaults: Map.fetch!(kickoff_request, :project_defaults),
         trigger: Map.fetch!(kickoff_request, :trigger),
         inputs: Map.fetch!(kickoff_request, :inputs),
         input_metadata: Map.fetch!(kickoff_request, :input_metadata),
         initiating_actor: Map.fetch!(kickoff_request, :initiating_actor),
         detail_path: "/repos/#{URI.encode(repo_id)}/runs/#{URI.encode(run_id)}",
         started_at: started_at
       }}
    else
      {:error,
       kickoff_error(
         @default_error_type,
         "Workflow run kickoff did not return a run identifier.",
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

  defp to_repository_option(repository) when is_map(repository) do
    repo_id =
      repository
      |> map_get(:route_id, "route_id")
      |> normalize_optional_string() ||
        repository
        |> map_get(:managed_repo_id, "managed_repo_id")
        |> normalize_optional_string() ||
        repository
        |> map_get(:id, "id")
        |> normalize_optional_string()

    if is_binary(repo_id) do
      managed_repo = map_get(repository, :managed_repo, "managed_repo", %{})
      source_repo = map_get(repository, :source_repo, "source_repo", %{})

      repository_name =
        managed_repo
        |> map_get(:display_name, "display_name")
        |> normalize_optional_string() ||
          repository
          |> map_get(:name, "name")
          |> normalize_optional_string()

      github_full_name =
        source_repo
        |> map_get(:full_name, "full_name")
        |> normalize_optional_string() ||
          repository
          |> map_get(:github_full_name, "github_full_name")
          |> normalize_optional_string()

      default_branch =
        source_repo
        |> map_get(:default_branch, "default_branch")
        |> normalize_optional_string() ||
          repository
          |> map_get(:default_branch, "default_branch")
          |> normalize_optional_string() || "main"

      legacy_project_id =
        repository
        |> map_get(:project_id, "project_id")
        |> normalize_optional_string() ||
          repository
          |> map_get(:legacy_project_id, "legacy_project_id")
          |> normalize_optional_string()

      %{
        id: repo_id,
        managed_repo_id:
          managed_repo
          |> map_get(:id, "id")
          |> normalize_optional_string() || repo_id,
        legacy_project_id: legacy_project_id,
        name: repository_name || github_full_name || repo_id,
        github_full_name: github_full_name || repository_name || repo_id,
        default_branch: default_branch
      }
    end
  end

  defp to_repository_option(_repository), do: nil

  defp validation_error(detail, field_errors) do
    kickoff_error(@validation_error_type, detail, @validation_remediation, field_errors)
  end

  defp normalize_error(error) do
    kickoff_error(
      map_get(error, :error_type, "error_type", @default_error_type),
      map_get(error, :detail, "detail", "Workflow run kickoff failed."),
      map_get(error, :remediation, "remediation", @launcher_remediation),
      map_get(error, :field_errors, "field_errors", [])
    )
  end

  defp normalize_repository_lookup_error(error) do
    kickoff_error(
      map_get(error, :error_type, "error_type", @repository_lookup_error_type),
      map_get(error, :detail, "detail", "Repository lookup failed."),
      map_get(error, :remediation, "remediation", @repository_lookup_remediation),
      map_get(error, :field_errors, "field_errors", [])
    )
  end

  defp normalize_workflow_definition_error(error) do
    kickoff_error(
      map_get(error, :error_type, "error_type", @workflow_definition_lookup_error_type),
      map_get(error, :detail, "detail", "Workflow definitions could not be loaded."),
      map_get(error, :remediation, "remediation", @workflow_definition_remediation),
      map_get(error, :field_errors, "field_errors", [])
    )
  end

  defp kickoff_error(error_type, detail, remediation, field_errors \\ []) do
    %{
      error_type: normalize_optional_string(error_type) || @default_error_type,
      detail: normalize_optional_string(detail) || "Workflow run kickoff failed.",
      remediation: normalize_optional_string(remediation) || @launcher_remediation,
      field_errors: normalize_field_errors(field_errors)
    }
  end

  defp normalize_field_errors(field_errors) when is_list(field_errors) do
    field_errors
    |> Enum.map(&normalize_field_error/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_field_errors(_field_errors), do: []

  defp normalize_field_error(field_error) when is_map(field_error) do
    field =
      field_error
      |> map_get(:field, "field")
      |> normalize_optional_string()

    if is_binary(field) do
      %{
        field: field,
        error_type:
          field_error
          |> map_get(:error_type, "error_type")
          |> normalize_optional_string() || "invalid",
        detail:
          field_error
          |> map_get(:detail, "detail")
          |> normalize_optional_string() || "Invalid field value."
      }
    end
  end

  defp normalize_field_error(_field_error), do: nil

  defp repository_identifier(run_params) do
    run_params
    |> map_get(:repo_id, "repo_id")
    |> normalize_optional_string()
    |> Kernel.||(
      run_params
      |> map_get(:project_id, "project_id")
      |> normalize_optional_string()
    )
  end

  defp field_error(field, error_type, detail) do
    %{
      field: normalize_optional_string(field) || "unknown",
      error_type: normalize_optional_string(error_type) || "invalid",
      detail: normalize_optional_string(detail) || "Invalid field value."
    }
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

  defp normalize_optional_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp normalize_optional_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed_value, ""} when parsed_value > 0 -> parsed_value
      _other -> nil
    end
  end

  defp normalize_optional_positive_integer(_value), do: nil

  defp format_reason(%{diagnostic: diagnostic}) when is_binary(diagnostic), do: diagnostic
  defp format_reason(reason), do: inspect(reason)

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
