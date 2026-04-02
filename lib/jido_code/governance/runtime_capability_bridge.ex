defmodule JidoCode.Governance.RuntimeCapabilityBridge do
  # covers: architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
  # covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
  # covers: architecture.repo_posture.runtime_capability_observations_can_inform_posture
  @moduledoc """
  Projects runtime capability posture into product-owned observations.
  """

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Operations.Observation
  alias JidoCode.RuntimeGateway

  @observer Actor.factory_system_actor(%{
              "id" => "system:runtime-capability",
              "email" => "runtime-capability@system.local"
            })
  @source "runtime_gateway"
  @category "runtime_capability_state"
  @default_service_refs [JidoCode.CodingAssistance]

  @type capability_snapshot :: map()

  @spec sync_managed_repo(ManagedRepo.t() | map()) ::
          {:ok, %{observation: Observation.t(), capability_posture: capability_snapshot()}}
          | {:error, term()}
  def sync_managed_repo(%{} = managed_repo) do
    managed_repo_id = map_get(managed_repo, :id, "id")

    with true <- is_binary(managed_repo_id) or {:error, :missing_managed_repo_id},
         {:ok, capability_posture} <- capability_posture_snapshot(managed_repo),
         {:ok, observation} <- sync_observation(managed_repo_id, capability_posture) do
      {:ok, %{observation: observation, capability_posture: capability_posture}}
    else
      false -> {:error, :missing_managed_repo_id}
      {:error, reason} -> {:error, reason}
    end
  end

  def sync_managed_repo(_managed_repo), do: {:error, :invalid_managed_repo}

  @spec latest_signal_snapshot(term()) :: {:ok, capability_snapshot()}
  def latest_signal_snapshot(managed_repo_id) when is_binary(managed_repo_id) do
    case latest_observation(managed_repo_id) do
      %Observation{} = observation -> {:ok, normalize_map(observation.payload)}
      _other -> {:ok, absent_snapshot()}
    end
  end

  def latest_signal_snapshot(_managed_repo_id), do: {:ok, absent_snapshot()}

  @spec source() :: String.t()
  def source, do: @source

  @spec category() :: String.t()
  def category, do: @category

  def operator_summary(%{"summary" => summary}) when is_binary(summary), do: summary
  def operator_summary(%{summary: summary}) when is_binary(summary), do: summary
  def operator_summary(_snapshot), do: "Runtime capability posture is unavailable."

  defp capability_posture_snapshot(managed_repo) do
    attrs = runtime_context(managed_repo)
    actor_id = @observer["id"]

    with {:ok, snapshot} <-
           RuntimeGateway.capability_posture_snapshot(
             configured_service_refs(managed_repo),
             actor_id,
             attrs
           ) do
      {:ok,
       snapshot
       |> normalize_map()
       |> Map.put("signal_type", "runtime_capability")
       |> Map.put("source", @source)
       |> Map.put("category", @category)}
    end
  end

  defp sync_observation(managed_repo_id, capability_posture) do
    digest = digest(capability_posture)
    latest = latest_observation(managed_repo_id)

    if latest && latest.source_metadata["digest"] == digest do
      {:ok, latest}
    else
      Observation.create(
        %{
          managed_repo_id: managed_repo_id,
          source: @source,
          category: @category,
          summary: capability_posture["summary"] || "Runtime capability posture refreshed.",
          payload: capability_posture,
          source_metadata: %{
            "digest" => digest,
            "service_keys" => Enum.map(capability_posture["services"] || [], &Map.get(&1, "service_key")),
            "rollout_source" => capability_posture["rollout_source"] || "product_runtime_gateway"
          },
          captured_by: @observer,
          observed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        },
        actor: @observer
      )
    end
  end

  defp latest_observation(managed_repo_id) do
    case Observation.read(
           query: [
             filter: [managed_repo_id: managed_repo_id, source: @source, category: @category],
             sort: [observed_at: :desc],
             limit: 1
           ],
           actor: @observer
         ) do
      {:ok, [%Observation{} = observation | _rest]} -> observation
      _other -> nil
    end
  end

  defp configured_service_refs(managed_repo) do
    integration_settings =
      managed_repo
      |> map_get(:integration_settings, "integration_settings", %{})
      |> normalize_map()

    configured =
      integration_settings
      |> Map.get("runtime_capabilities", %{})
      |> normalize_runtime_capability_refs()

    if configured == [], do: @default_service_refs, else: configured
  end

  defp normalize_runtime_capability_refs(value) when is_list(value) do
    value
    |> Enum.map(&normalize_runtime_capability_ref/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_runtime_capability_refs(%{} = value) do
    value
    |> Map.get("required_services", Map.get(value, :required_services, []))
    |> normalize_runtime_capability_refs()
  end

  defp normalize_runtime_capability_refs(_value), do: []

  defp normalize_runtime_capability_ref(value) when is_binary(value) and value != "", do: value
  defp normalize_runtime_capability_ref(value) when is_atom(value), do: value
  defp normalize_runtime_capability_ref(_value), do: nil

  defp runtime_context(managed_repo) do
    workspace_settings =
      managed_repo
      |> map_get(:workspace_settings, "workspace_settings", %{})
      |> normalize_map()

    %{
      project_id: map_get(managed_repo, :legacy_project_id, "legacy_project_id"),
      workspace_id: Map.get(workspace_settings, "workspace_path")
    }
  end

  defp absent_snapshot do
    %{
      "signal_type" => "runtime_capability",
      "status" => "absent",
      "rollout_source" => "product_runtime_gateway",
      "summary" => "Runtime capability posture has not been observed yet.",
      "services" => [],
      "service_count" => 0,
      "available_service_count" => 0,
      "review_required_service_count" => 0,
      "blocked_service_count" => 0
    }
  end

  defp digest(payload) do
    payload
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

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
end
