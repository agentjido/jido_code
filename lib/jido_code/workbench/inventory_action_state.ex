defmodule JidoCode.Workbench.InventoryActionState do
  @moduledoc """
  Shared workflow-action feedback helpers for managed-repository inventory
  surfaces.
  """

  @spec find_row([map()], term()) :: map() | nil
  def find_row(rows, project_id) when is_list(rows) do
    normalized_project_id = normalize_optional_string(project_id)

    Enum.find(rows, fn row ->
      row
      |> map_get("id", :id)
      |> normalize_optional_string() == normalized_project_id
    end)
  end

  def find_row(_rows, _project_id), do: nil

  @spec put_fix_feedback(map(), term(), term(), term()) :: map()
  def put_fix_feedback(states, project_id, context_item_type, kickoff_result)
      when is_map(states) do
    Map.put(
      states,
      feedback_state_key(project_id, context_item_type),
      kickoff_feedback_state(kickoff_result, project_id)
    )
  end

  def put_fix_feedback(_states, project_id, context_item_type, kickoff_result) do
    put_fix_feedback(%{}, project_id, context_item_type, kickoff_result)
  end

  @spec put_issue_triage_feedback(map(), term(), term(), term()) :: map()
  def put_issue_triage_feedback(states, project_id, context_item_type, kickoff_result)
      when is_map(states) do
    Map.put(
      states,
      feedback_state_key(project_id, context_item_type),
      kickoff_feedback_state(kickoff_result, project_id)
    )
  end

  def put_issue_triage_feedback(_states, project_id, context_item_type, kickoff_result) do
    put_issue_triage_feedback(%{}, project_id, context_item_type, kickoff_result)
  end

  @spec put_recent_run_outcome(map(), term(), term()) :: map()
  def put_recent_run_outcome(outcomes, project_id, kickoff_result) when is_map(outcomes) do
    normalized_project_id = normalize_optional_string(project_id)

    if is_binary(normalized_project_id) do
      case kickoff_run_outcome(kickoff_result, normalized_project_id) do
        %{} = outcome -> Map.put(outcomes, normalized_project_id, outcome)
        _other -> outcomes
      end
    else
      outcomes
    end
  end

  def put_recent_run_outcome(_outcomes, project_id, kickoff_result) do
    put_recent_run_outcome(%{}, project_id, kickoff_result)
  end

  @spec fix_feedback(map(), term(), term()) :: map() | nil
  def fix_feedback(states, project_id, context_item_type) when is_map(states) do
    Map.get(states, feedback_state_key(project_id, context_item_type))
  end

  def fix_feedback(_states, _project_id, _context_item_type), do: nil

  @spec issue_triage_feedback(map(), term(), term()) :: map() | nil
  def issue_triage_feedback(states, project_id, context_item_type) when is_map(states) do
    Map.get(states, feedback_state_key(project_id, context_item_type))
  end

  def issue_triage_feedback(_states, _project_id, _context_item_type), do: nil

  @spec run_detail_path(term(), term()) :: String.t()
  def run_detail_path(project_id, run_id) do
    normalized_project_id = normalize_optional_string(project_id) || "unknown-project"
    normalized_run_id = normalize_optional_string(run_id) || "unknown-run"
    "/repos/#{URI.encode(normalized_project_id)}/runs/#{URI.encode(normalized_run_id)}"
  end

  defp feedback_state_key(project_id, context_item_type) do
    normalized_project_id = normalize_optional_string(project_id) || "unknown-project"
    normalized_context_item_type = normalize_context_item_type_for_state_key(context_item_type)
    "#{normalized_project_id}:#{normalized_context_item_type}"
  end

  defp kickoff_run_outcome({:ok, kickoff_run}, project_id) when is_map(kickoff_run) do
    run_id =
      kickoff_run
      |> map_get("run_id", :run_id)
      |> normalize_optional_string()

    detail_path =
      kickoff_run
      |> map_get("detail_path", :detail_path)
      |> normalize_optional_string() || run_detail_path(project_id, run_id)

    if run_id && detail_path do
      %{
        status: "pending",
        run_id: run_id,
        detail_path: detail_path,
        error_type: nil,
        detail: nil,
        guidance: nil
      }
    end
  end

  defp kickoff_run_outcome({:error, kickoff_error}, project_id) when is_map(kickoff_error) do
    run_creation_state =
      kickoff_error
      |> map_get("run_creation_state", :run_creation_state)
      |> normalize_run_creation_state()

    run_id =
      kickoff_error
      |> map_get("run_id", :run_id)
      |> normalize_optional_string()

    case {run_creation_state, run_id} do
      {:created, resolved_run_id} when is_binary(resolved_run_id) ->
        %{
          status: "pending",
          run_id: resolved_run_id,
          detail_path: run_detail_path(project_id, resolved_run_id),
          error_type: nil,
          detail: nil,
          guidance: nil
        }

      _other ->
        nil
    end
  end

  defp kickoff_run_outcome(_kickoff_result, _project_id), do: nil

  defp kickoff_feedback_state({:ok, kickoff_run}, _project_id) when is_map(kickoff_run) do
    %{status: :ok, run: kickoff_run, confirmation_state: :confirmed}
  end

  defp kickoff_feedback_state({:error, kickoff_error}, project_id) when is_map(kickoff_error) do
    run_creation_state =
      kickoff_error
      |> map_get("run_creation_state", :run_creation_state)
      |> normalize_run_creation_state()

    run_id =
      kickoff_error
      |> map_get("run_id", :run_id)
      |> normalize_optional_string()

    case {run_creation_state, run_id} do
      {:created, resolved_run_id} when is_binary(resolved_run_id) ->
        %{
          status: :ok,
          run: %{
            run_id: resolved_run_id,
            detail_path: run_detail_path(project_id, resolved_run_id)
          },
          confirmation_state: :confirmed_after_interruption
        }

      {:not_created, _resolved_run_id} ->
        %{
          status: :error,
          error: kickoff_error,
          confirmation_state: :not_created_after_interruption
        }

      _other ->
        %{status: :error, error: kickoff_error, confirmation_state: :failed}
    end
  end

  defp kickoff_feedback_state(_kickoff_result, _project_id) do
    %{
      status: :error,
      error: %{
        error_type: "workbench_workflow_kickoff_invalid_result",
        detail: "Workflow kickoff returned an invalid response shape.",
        remediation: "Retry workflow kickoff from this row.",
        run_creation_state: nil,
        run_id: nil
      },
      confirmation_state: :failed
    }
  end

  defp normalize_context_item_type_for_state_key(:issue), do: :issue
  defp normalize_context_item_type_for_state_key("issue"), do: :issue
  defp normalize_context_item_type_for_state_key(:pull_request), do: :pull_request
  defp normalize_context_item_type_for_state_key("pull_request"), do: :pull_request
  defp normalize_context_item_type_for_state_key(_context_item_type), do: :unknown

  defp normalize_run_creation_state(:created), do: :created
  defp normalize_run_creation_state("created"), do: :created
  defp normalize_run_creation_state(:not_created), do: :not_created
  defp normalize_run_creation_state("not_created"), do: :not_created
  defp normalize_run_creation_state(_run_creation_state), do: nil

  defp map_get(map, string_key, atom_key, default \\ nil)

  defp map_get(%{} = map, string_key, atom_key, default) do
    cond do
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      true -> default
    end
  end

  defp map_get(_map, _string_key, _atom_key, default), do: default

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
