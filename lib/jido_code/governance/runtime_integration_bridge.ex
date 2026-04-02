defmodule JidoCode.Governance.RuntimeIntegrationBridge do
  # covers: architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
  # covers: architecture.runtime_service_overlay.integration_service_is_canonical_external_runtime_boundary
  # covers: architecture.factory_control_plane.runtime_overlay_preserves_product_truth
  @moduledoc """
  Projects runtime integration state and outcomes into product-owned governance
  records.

  The bridge keeps runtime integration truth in `jido_os` while materializing
  the subset of binding health, install lifecycle, and invocation evidence that
  should influence managed-repo governance and operator visibility.
  """

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Operations.{Event, Observation}
  alias JidoCode.RuntimeIntegration

  @observer Actor.factory_system_actor(%{
              "id" => "system:runtime-integration",
              "email" => "runtime-integration@system.local"
            })
  @source "runtime_integration"
  @binding_health_category "binding_health"
  @install_category "install_lifecycle"
  @invocation_category "invocation"

  @type binding_health_snapshot :: map()

  @spec sync_managed_repo(ManagedRepo.t() | map()) ::
          {:ok, %{observation: Observation.t(), binding_health: binding_health_snapshot()}}
          | {:error, term()}
  def sync_managed_repo(%{} = managed_repo) do
    managed_repo_id = map_get(managed_repo, :id, "id")

    with true <- is_binary(managed_repo_id) or {:error, :missing_managed_repo_id},
         {:ok, binding_health} <-
           RuntimeIntegration.binding_health_snapshot(@observer["id"], %{managed_repo_id: managed_repo_id}),
         normalized_binding_health = normalize_map(binding_health),
         {:ok, observation} <-
           sync_binding_health_observation(managed_repo_id, normalized_binding_health) do
      {:ok, %{observation: observation, binding_health: normalized_binding_health}}
    else
      false -> {:error, :missing_managed_repo_id}
      {:error, reason} -> {:error, reason}
    end
  end

  def sync_managed_repo(_managed_repo), do: {:error, :invalid_managed_repo}

  @spec record_install_outcome(ManagedRepo.t() | map(), map()) ::
          {:ok, Observation.t()} | {:error, term()}
  def record_install_outcome(%{} = managed_repo, install_session) when is_map(install_session) do
    with {:ok, managed_repo_id} <- managed_repo_id(managed_repo) do
      payload =
        install_session
        |> normalize_map()
        |> Map.put("signal_type", "runtime_integration_install")
        |> Map.put("source", @source)
        |> Map.put("category", @install_category)

      Observation.create(
        %{
          managed_repo_id: managed_repo_id,
          source: @source,
          category: @install_category,
          summary: install_summary(payload),
          payload: payload,
          source_metadata: install_source_metadata(payload),
          captured_by: captured_by(payload),
          observed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        },
        actor: @observer
      )
    end
  end

  def record_install_outcome(_managed_repo, _install_session), do: {:error, :invalid_install_outcome}

  @spec record_invocation_outcome(ManagedRepo.t() | map(), map()) ::
          {:ok, Event.t()} | {:error, term()}
  def record_invocation_outcome(%{} = managed_repo, invocation_result) when is_map(invocation_result) do
    with {:ok, managed_repo_id} <- managed_repo_id(managed_repo) do
      payload =
        invocation_result
        |> normalize_map()
        |> Map.put("signal_type", "runtime_integration_invocation")
        |> Map.put("source", @source)
        |> Map.put("category", @invocation_category)

      Event.create(
        %{
          managed_repo_id: managed_repo_id,
          category: @invocation_category,
          summary: invocation_summary(payload),
          correlation_key: invocation_correlation_key(payload),
          payload: payload,
          source_metadata: invocation_source_metadata(payload),
          occurred_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        },
        actor: @observer
      )
    end
  end

  def record_invocation_outcome(_managed_repo, _invocation_result),
    do: {:error, :invalid_invocation_outcome}

  @spec latest_signal_snapshot(term()) :: {:ok, binding_health_snapshot()}
  def latest_signal_snapshot(managed_repo_id) when is_binary(managed_repo_id) do
    case latest_observation(managed_repo_id, @binding_health_category) do
      %Observation{} = observation -> {:ok, normalize_map(observation.payload)}
      _other -> {:ok, absent_snapshot()}
    end
  end

  def latest_signal_snapshot(_managed_repo_id), do: {:ok, absent_snapshot()}

  @spec source() :: String.t()
  def source, do: @source

  @spec binding_health_category() :: String.t()
  def binding_health_category, do: @binding_health_category

  @spec install_category() :: String.t()
  def install_category, do: @install_category

  @spec invocation_category() :: String.t()
  def invocation_category, do: @invocation_category

  def operator_summary(%{"summary" => summary}) when is_binary(summary), do: summary
  def operator_summary(%{summary: summary}) when is_binary(summary), do: summary
  def operator_summary(_snapshot), do: "Runtime integration state is unavailable."

  defp sync_binding_health_observation(managed_repo_id, binding_health) do
    digest = digest(binding_health)
    latest = latest_observation(managed_repo_id, @binding_health_category)

    if latest && latest.source_metadata["digest"] == digest do
      {:ok, latest}
    else
      Observation.create(
        %{
          managed_repo_id: managed_repo_id,
          source: @source,
          category: @binding_health_category,
          summary:
            Map.get(binding_health, "summary") ||
              "Runtime integration binding health refreshed.",
          payload:
            binding_health
            |> normalize_map()
            |> Map.put("signal_type", "runtime_integration_binding_health")
            |> Map.put("source", @source)
            |> Map.put("category", @binding_health_category),
          source_metadata: %{
            "digest" => digest,
            "status" => Map.get(binding_health, "status"),
            "service_key" =>
              binding_health
              |> Map.get("runtime_capability", %{})
              |> Map.get("service_key", RuntimeIntegration.runtime_service_key()),
            "rollout_source" =>
              binding_health
              |> Map.get("runtime_capability", %{})
              |> Map.get("rollout_source", "product_runtime_gateway")
          },
          captured_by: @observer,
          observed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        },
        actor: @observer
      )
    end
  end

  defp latest_observation(managed_repo_id, category) do
    case Observation.read(
           query: [
             filter: [managed_repo_id: managed_repo_id, source: @source, category: category],
             sort: [observed_at: :desc],
             limit: 1
           ],
           actor: @observer
         ) do
      {:ok, [%Observation{} = observation | _rest]} -> observation
      _other -> nil
    end
  end

  defp managed_repo_id(managed_repo) do
    case map_get(managed_repo, :id, "id") do
      id when is_binary(id) -> {:ok, id}
      _other -> {:error, :missing_managed_repo_id}
    end
  end

  defp install_summary(payload) do
    provider = payload["provider"] || "integration"
    binding_alias = payload["binding_alias"] || "unnamed-binding"
    "Runtime integration install session for #{provider} binding #{binding_alias} was recorded."
  end

  defp install_source_metadata(payload) do
    %{
      "provider" => payload["provider"],
      "binding_alias" => payload["binding_alias"],
      "install_id" => payload["install_id"],
      "runtime_project_id" => payload["runtime_project_id"],
      "actor_id" => get_in(payload, ["context", "actor_id"]),
      "correlation_id" => get_in(payload, ["context", "correlation_id"])
    }
    |> compact_nil_values()
  end

  defp invocation_summary(payload) do
    provider = get_in(payload, ["operation", "provider"]) || "integration"
    operation_id = get_in(payload, ["operation", "operation_id"]) || "unknown-operation"
    binding_alias = get_in(payload, ["project_binding", "binding_alias"]) || "default-binding"
    "Runtime integration invocation #{provider}:#{operation_id} completed through #{binding_alias}."
  end

  defp invocation_source_metadata(payload) do
    %{
      "provider" => get_in(payload, ["operation", "provider"]),
      "operation_id" => get_in(payload, ["operation", "operation_id"]),
      "binding_alias" => get_in(payload, ["project_binding", "binding_alias"]),
      "auth_status" => get_in(payload, ["auth_state", "status"]),
      "runtime_project_id" => payload["runtime_project_id"],
      "actor_id" => get_in(payload, ["context", "actor_id"]),
      "correlation_id" => invocation_correlation_key(payload)
    }
    |> compact_nil_values()
  end

  defp invocation_correlation_key(payload) do
    get_in(payload, ["context", "correlation_id"]) ||
      get_in(payload, ["evidence_ref", "correlation_id"]) ||
      get_in(payload, ["evidence_ref", "event_ref"]) ||
      "runtime-integration-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp captured_by(payload) do
    %{
      "id" => get_in(payload, ["context", "actor_id"]) || @observer["id"],
      "request_id" => get_in(payload, ["context", "request_id"]),
      "correlation_id" => get_in(payload, ["context", "correlation_id"])
    }
    |> compact_nil_values()
  end

  defp absent_snapshot do
    %{
      "signal_type" => "runtime_integration_binding_health",
      "status" => "absent",
      "summary" => "Runtime integration binding health has not been observed yet.",
      "binding_count" => 0,
      "connected_binding_count" => 0,
      "default_binding_count" => 0,
      "providers" => []
    }
  end

  defp digest(payload) do
    payload
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp compact_nil_values(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc -> acc
      {_key, value}, acc when is_map(value) and map_size(value) == 0 -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
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
