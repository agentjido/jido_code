defmodule JidoCode.Governance.RuntimeEvidenceFeed do
  # covers: package.jido_code.primary_implementation_repo
  # covers: architecture.factory_control_plane.runtime_overlay_preserves_product_truth
  # covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
  # covers: architecture.repo_posture.runtime_capability_observations_can_inform_posture
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
  # covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
  @moduledoc """
  Loads operator-facing runtime evidence summaries from governed repo posture.
  """

  alias JidoCode.Control.{ManagedRepo, ManagedRepoStore}
  alias JidoCode.Governance.{RecordStore, RepoPosture}

  @default_limit 6
  @default_error_type "dashboard_runtime_evidence_feed_fetch_failed"

  @default_remediation """
  Retry runtime posture refresh. If this persists, inspect repo posture projection health before treating runtime rollout status as stale.
  """

  @type stale_warning :: %{
          error_type: String.t(),
          detail: String.t(),
          remediation: String.t()
        }

  @type runtime_evidence_summary :: %{
          id: String.t(),
          managed_repo_id: String.t(),
          repo_label: String.t(),
          status: String.t(),
          summary: String.t(),
          delivery_mode: String.t() | nil,
          reason_code: String.t() | nil,
          latest_provider: String.t() | nil,
          supervision_mode: String.t() | nil,
          review_required: boolean(),
          updated_at: DateTime.t() | nil
        }

  @spec load() :: {:ok, [runtime_evidence_summary()], stale_warning() | nil} | {:error, stale_warning()}
  def load do
    loader =
      Application.get_env(:jido_code, :dashboard_runtime_evidence_loader, &__MODULE__.default_loader/0)

    if is_function(loader, 0) do
      safe_invoke_loader(loader)
    else
      {:error,
       stale_warning(
         @default_error_type,
         "Dashboard runtime evidence loader is invalid.",
         @default_remediation
       )}
    end
  end

  @doc false
  @spec default_loader() :: {:ok, [runtime_evidence_summary()], stale_warning() | nil} | {:error, stale_warning()}
  def default_loader do
    case RecordStore.list_repo_postures(%{}, query: [sort: [updated_at: :desc], limit: @default_limit]) do
      {:ok, repo_postures} ->
        summaries =
          repo_postures
          |> Enum.map(&to_summary/1)
          |> Enum.reject(&(&1.status == "absent"))

        {:ok, summaries, nil}

      {:error, reason} ->
        {:error,
         stale_warning(
           @default_error_type,
           "Dashboard runtime evidence fetch failed (#{format_reason(reason)}).",
           @default_remediation
         )}
    end
  end

  defp safe_invoke_loader(loader) do
    try do
      case loader.() do
        {:ok, summaries, warning} when is_list(summaries) ->
          {:ok, Enum.map(summaries, &normalize_summary/1), normalize_warning(warning)}

        {:error, warning} ->
          {:error,
           normalize_warning(warning) ||
             stale_warning(
               @default_error_type,
               "Dashboard runtime evidence may be stale.",
               @default_remediation
             )}

        other ->
          {:error,
           stale_warning(
             @default_error_type,
             "Dashboard runtime evidence loader returned an invalid result (#{inspect(other)}).",
             @default_remediation
           )}
      end
    rescue
      exception ->
        {:error,
         stale_warning(
           @default_error_type,
           "Dashboard runtime evidence loader crashed (#{Exception.message(exception)}).",
           @default_remediation
         )}
    catch
      kind, reason ->
        {:error,
         stale_warning(
           @default_error_type,
           "Dashboard runtime evidence loader threw #{inspect({kind, reason})}.",
           @default_remediation
         )}
    end
  end

  defp to_summary(%RepoPosture{} = repo_posture) do
    posture_metadata = normalize_map(repo_posture.posture_metadata)

    runtime_state =
      posture_metadata
      |> Map.get("runtime_service_evidence_state", posture_metadata["runtime_capability_state"] || %{})
      |> normalize_map()

    latest_invocation =
      runtime_state
      |> get_in(["integration_outcomes", "latest_invocation"])
      |> normalize_map()

    %{
      id: repo_posture.id,
      managed_repo_id: repo_posture.managed_repo_id,
      repo_label: managed_repo_label(repo_posture.managed_repo_id),
      status: Map.get(runtime_state, "status", "absent"),
      summary:
        posture_metadata["runtime_service_evidence_summary"] ||
          posture_metadata["runtime_capability_summary"] ||
          repo_posture.summary,
      delivery_mode: get_in(runtime_state, ["runtime_delivery", "delivery_mode"]),
      reason_code: get_in(runtime_state, ["runtime_delivery", "reason_code"]),
      latest_provider: Map.get(latest_invocation, "provider"),
      supervision_mode: normalize_optional_string(repo_posture.supervision_mode),
      review_required:
        Map.get(runtime_state, "review_required") == true or
          normalize_optional_string(repo_posture.review_burden) == "high",
      updated_at: repo_posture.updated_at
    }
  end

  defp managed_repo_label(managed_repo_id) when is_binary(managed_repo_id) do
    case ManagedRepoStore.get_by_id(managed_repo_id) do
      {:ok, %ManagedRepo{} = managed_repo} ->
        normalize_optional_string(managed_repo.display_name) || managed_repo_id

      _other ->
        managed_repo_id
    end
  end

  defp managed_repo_label(_managed_repo_id), do: "Unknown managed repo"

  defp normalize_summary(summary) when is_map(summary) do
    %{
      id: map_get(summary, :id, "id") || "runtime-evidence-summary",
      managed_repo_id: map_get(summary, :managed_repo_id, "managed_repo_id") || "unknown-managed-repo",
      repo_label: map_get(summary, :repo_label, "repo_label") || "Unknown managed repo",
      status: map_get(summary, :status, "status") || "absent",
      summary: map_get(summary, :summary, "summary") || "Runtime service evidence is unavailable.",
      delivery_mode:
        summary
        |> map_get(:delivery_mode, "delivery_mode")
        |> normalize_optional_string(),
      reason_code:
        summary
        |> map_get(:reason_code, "reason_code")
        |> normalize_optional_string(),
      latest_provider:
        summary
        |> map_get(:latest_provider, "latest_provider")
        |> normalize_optional_string(),
      supervision_mode:
        summary
        |> map_get(:supervision_mode, "supervision_mode")
        |> normalize_optional_string(),
      review_required: truthy?(map_get(summary, :review_required, "review_required")),
      updated_at:
        summary
        |> map_get(:updated_at, "updated_at")
        |> normalize_datetime()
    }
  end

  defp normalize_summary(_summary) do
    %{
      id: "runtime-evidence-summary",
      managed_repo_id: "unknown-managed-repo",
      repo_label: "Unknown managed repo",
      status: "absent",
      summary: "Runtime service evidence is unavailable.",
      delivery_mode: nil,
      reason_code: nil,
      latest_provider: nil,
      supervision_mode: nil,
      review_required: false,
      updated_at: nil
    }
  end

  defp normalize_warning(warning) when is_map(warning) do
    %{
      error_type:
        warning
        |> map_get(:error_type, "error_type")
        |> normalize_optional_string() || @default_error_type,
      detail:
        warning
        |> map_get(:detail, "detail")
        |> normalize_optional_string() || "Runtime evidence may be stale.",
      remediation:
        warning
        |> map_get(:remediation, "remediation")
        |> normalize_optional_string() || @default_remediation
    }
  end

  defp normalize_warning(_warning), do: nil

  defp stale_warning(error_type, detail, remediation) do
    %{error_type: error_type, detail: detail, remediation: remediation}
  end

  defp normalize_datetime(%DateTime{} = datetime), do: datetime

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _other -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp truthy?(value) when value in [true, "true", 1, "1"], do: true
  defp truthy?(_value), do: false

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(%{} = map, atom_key, string_key, default) do
    case Map.fetch(map, atom_key) do
      {:ok, value} -> value
      :error -> Map.get(map, string_key, default)
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp normalize_map(%_{} = value) do
    value
    |> Map.from_struct()
    |> Map.delete(:__meta__)
    |> normalize_map()
  end

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      normalized_value =
        cond do
          is_map(nested_value) -> normalize_map(nested_value)
          is_list(nested_value) -> Enum.map(nested_value, &normalize_nested/1)
          true -> nested_value
        end

      Map.put(acc, normalized_key, normalized_value)
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested(%{} = value), do: normalize_map(value)
  defp normalize_nested(value), do: value

  defp normalize_optional_string(nil), do: nil

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

  defp format_reason(reason) do
    reason
    |> inspect(limit: 6, printable_limit: 200)
    |> String.replace(~r/\s+/, " ")
  end
end
