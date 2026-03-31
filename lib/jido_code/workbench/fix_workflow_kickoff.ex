defmodule JidoCode.Workbench.FixWorkflowKickoff do
  @moduledoc """
  Validates and launches fix-oriented workflow runs from workbench issue/PR quick actions.
  """

  alias JidoCode.Operations.Ingress

  @fallback_row_id_prefix "workbench-row-"
  @workflow_name "fix_failing_tests"

  @default_error_type "workbench_fix_workflow_kickoff_failed"
  @validation_error_type "workbench_fix_workflow_validation_failed"

  @validation_remediation """
  Select a valid imported project row and retry from the issue or PR quick action.
  """

  @launcher_remediation """
  Verify workflow runtime setup and retry kickoff from workbench.
  """

  @type kickoff_error :: %{
          error_type: String.t(),
          detail: String.t(),
          remediation: String.t(),
          run_creation_state: :created | :not_created | nil,
          run_id: String.t() | nil
        }

  @type kickoff_run :: %{
          run_id: String.t(),
          workflow_name: String.t(),
          project_id: String.t(),
          project_name: String.t(),
          context_item_type: :issue | :pull_request,
          context_item_label: String.t(),
          context_item_url: String.t() | nil,
          detail_path: String.t(),
          started_at: DateTime.t()
        }

  @spec kickoff(map() | nil, term(), map() | nil) :: {:ok, kickoff_run()} | {:error, kickoff_error()}
  def kickoff(project_row, context_item_type, initiating_actor \\ nil) do
    with {:ok, project_scope} <- normalize_project_scope(project_row),
         {:ok, normalized_context_item_type} <- normalize_context_item_type(context_item_type),
         kickoff_request <-
           build_kickoff_request(project_scope, normalized_context_item_type, initiating_actor),
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
           "Fix workflow kickoff failed with an unexpected result (#{inspect(other)}).",
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

  defp invoke_launcher(kickoff_request) do
    launcher =
      Application.get_env(
        :jido_code,
        :workbench_fix_workflow_launcher,
        &__MODULE__.default_launcher/1
      )

    if is_function(launcher, 1) do
      safe_invoke_launcher(launcher, kickoff_request)
    else
      {:error,
       kickoff_error(
         @default_error_type,
         "Workbench fix workflow launcher configuration is invalid.",
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
             "Fix workflow launcher returned an invalid result (#{inspect(other)}).",
             @launcher_remediation
           )}
      end
    rescue
      exception ->
        {:error,
         kickoff_error(
           @default_error_type,
           "Fix workflow launcher crashed (#{Exception.message(exception)}).",
           @launcher_remediation
         )}
    catch
      kind, reason ->
        {:error,
         kickoff_error(
           @default_error_type,
           "Fix workflow launcher threw #{inspect({kind, reason})}.",
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
         detail_path: "/projects/#{URI.encode(project_id)}/runs/#{URI.encode(run_id)}",
         started_at: started_at
       }}
    else
      {:error,
       kickoff_error(
         @default_error_type,
         "Fix workflow kickoff did not return a run identifier.",
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

  defp build_kickoff_request(project_scope, context_item_type, initiating_actor) do
    %{
      workflow_name: @workflow_name,
      project_id: Map.fetch!(project_scope, :project_id),
      project_name: Map.fetch!(project_scope, :project_name),
      trigger: %{
        source: "workbench",
        mode: "manual"
      },
      initiating_actor: normalize_initiating_actor(initiating_actor),
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
           intent: "fix_workflow_kickoff",
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
  defp context_item_label(:pull_request), do: "PR row"

  defp context_item_github_url(nil, _context_item_type), do: nil

  defp context_item_github_url(github_full_name, :issue) do
    with {:ok, repository_path} <- github_repository_path(github_full_name) do
      "#{repository_path}/issues"
    end
  end

  defp context_item_github_url(github_full_name, :pull_request) do
    with {:ok, repository_path} <- github_repository_path(github_full_name) do
      "#{repository_path}/pulls"
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
        {:error, validation_error("Workbench row is missing a durable project identifier for kickoff.")}

      String.starts_with?(project_id, @fallback_row_id_prefix) ->
        {:error, validation_error("Workbench row #{project_id} is synthetic and cannot scope a workflow run.")}

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
    {:error, validation_error("Workbench row is unavailable for kickoff.")}
  end

  defp normalize_context_item_type(:issue), do: {:ok, :issue}
  defp normalize_context_item_type("issue"), do: {:ok, :issue}
  defp normalize_context_item_type(:pull_request), do: {:ok, :pull_request}
  defp normalize_context_item_type("pull_request"), do: {:ok, :pull_request}

  defp normalize_context_item_type(other) do
    {:error, validation_error("Workbench kickoff context #{inspect(other)} is invalid. Use issue or pull_request.")}
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

  defp validation_error(detail) do
    kickoff_error(@validation_error_type, detail, @validation_remediation)
  end

  defp intake_error(reason) do
    kickoff_error(
      "workbench_fix_workflow_intake_record_failed",
      "Fix workflow kickoff could not be normalized into a durable intake (#{inspect(reason)}).",
      @launcher_remediation
    )
  end

  defp normalize_error(error) do
    kickoff_error(
      map_get(error, :error_type, "error_type", @default_error_type),
      map_get(error, :detail, "detail", "Fix workflow kickoff failed."),
      map_get(error, :remediation, "remediation", @launcher_remediation),
      map_get(error, :run_creation_state, "run_creation_state"),
      map_get(error, :run_id, "run_id")
    )
  end

  defp kickoff_error(error_type, detail, remediation, run_creation_state \\ nil, run_id \\ nil) do
    %{
      error_type: normalize_optional_string(error_type) || @default_error_type,
      detail: normalize_optional_string(detail) || "Fix workflow kickoff failed.",
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
end
