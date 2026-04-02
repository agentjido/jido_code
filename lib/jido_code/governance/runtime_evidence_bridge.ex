defmodule JidoCode.Governance.RuntimeEvidenceBridge do
  # covers: package.jido_code.primary_implementation_repo
  # covers: architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
  # covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
  # covers: architecture.repo_posture.runtime_capability_observations_can_inform_posture
  # covers: architecture.repo_posture.governed_turn_evidence_can_inform_posture
  # covers: architecture.factory_control_plane.runtime_overlay_preserves_product_truth
  # covers: architecture.run_governance.governed_turn_evidence_can_inform_posture
  @moduledoc """
  Converges bounded runtime-service facts into product-owned observations.

  The product keeps durable governance truth in its own control-plane records,
  while this bridge gathers the subset of runtime capability, integration, and
  coding-delivery evidence that should remain explainable to posture and
  operator surfaces.
  """

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.{Evidence, RuntimeCapabilityBridge, RuntimeIntegrationBridge}
  alias JidoCode.Operations.{Event, Observation}

  @observer Actor.factory_system_actor(%{
              "id" => "system:runtime-evidence",
              "email" => "runtime-evidence@system.local"
            })
  @source "runtime_service_overlay"
  @category "runtime_evidence"
  @runtime_delivery_key "runtime_service_delivery"

  @type runtime_evidence_snapshot :: map()

  @spec sync_managed_repo(ManagedRepo.t() | map(), keyword()) ::
          {:ok, %{observation: Observation.t(), runtime_evidence: runtime_evidence_snapshot()}}
          | {:error, term()}
  def sync_managed_repo(managed_repo, opts \\ [])

  def sync_managed_repo(%{} = managed_repo, opts) when is_list(opts) do
    managed_repo_id = map_get(managed_repo, :id, "id")

    with true <- is_binary(managed_repo_id) or {:error, :missing_managed_repo_id},
         snapshot <- runtime_evidence_snapshot(managed_repo_id, opts),
         {:ok, observation} <- sync_observation(managed_repo_id, snapshot) do
      {:ok, %{observation: observation, runtime_evidence: snapshot}}
    else
      false -> {:error, :missing_managed_repo_id}
      {:error, reason} -> {:error, reason}
    end
  end

  def sync_managed_repo(_managed_repo, _opts), do: {:error, :invalid_managed_repo}

  @spec latest_signal_snapshot(term()) :: {:ok, runtime_evidence_snapshot()}
  def latest_signal_snapshot(managed_repo_id) when is_binary(managed_repo_id) do
    case latest_observation(managed_repo_id, @source, @category) do
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
  def operator_summary(_snapshot), do: "Runtime service evidence is unavailable."

  defp runtime_evidence_snapshot(managed_repo_id, opts) do
    runtime_capability_observation =
      Keyword.get(opts, :runtime_capability_observation) ||
        latest_observation(
          managed_repo_id,
          RuntimeCapabilityBridge.source(),
          RuntimeCapabilityBridge.category()
        )

    runtime_capability_state =
      opts
      |> Keyword.get(:runtime_capability_state)
      |> normalize_runtime_capability_state(runtime_capability_observation)

    integration_binding_health =
      managed_repo_id
      |> RuntimeIntegrationBridge.latest_signal_snapshot()
      |> unwrap_ok_or(absent_integration_snapshot())
      |> normalize_integration_binding_health()

    latest_install =
      managed_repo_id
      |> latest_observation(RuntimeIntegrationBridge.source(), RuntimeIntegrationBridge.install_category())
      |> normalize_install_record()

    latest_invocation =
      managed_repo_id
      |> latest_event(RuntimeIntegrationBridge.invocation_category())
      |> normalize_invocation_record()

    latest_runtime_delivery =
      managed_repo_id
      |> latest_runtime_delivery_evidence()
      |> normalize_runtime_delivery()

    status =
      snapshot_status(
        runtime_capability_state,
        integration_binding_health,
        latest_runtime_delivery
      )

    %{
      "signal_type" => "runtime_service_evidence",
      "source" => @source,
      "category" => @category,
      "status" => status,
      "summary" =>
        snapshot_summary(
          status,
          runtime_capability_state,
          integration_binding_health,
          latest_runtime_delivery,
          latest_invocation
        ),
      "review_required" => review_required?(status),
      "runtime_capability" => runtime_capability_state,
      "integration_binding_health" => integration_binding_health,
      "runtime_delivery" => latest_runtime_delivery,
      "integration_outcomes" => %{
        "latest_install" => latest_install,
        "latest_invocation" => latest_invocation
      },
      "latest_refs" =>
        compact_nil_values(%{
          "runtime_capability_observation_id" => runtime_capability_observation && runtime_capability_observation.id,
          "integration_binding_health_observation_id" =>
            latest_observation(
              managed_repo_id,
              RuntimeIntegrationBridge.source(),
              RuntimeIntegrationBridge.binding_health_category()
            )
            |> then(&(&1 && &1.id)),
          "integration_install_observation_id" => latest_install["record_id"],
          "integration_invocation_event_id" => latest_invocation["record_id"],
          "runtime_delivery_evidence_id" => latest_runtime_delivery["evidence_id"]
        })
    }
  end

  defp sync_observation(managed_repo_id, snapshot) do
    digest = digest(snapshot)
    latest = latest_observation(managed_repo_id, @source, @category)

    if latest && latest.source_metadata["digest"] == digest do
      {:ok, latest}
    else
      Observation.create(
        %{
          managed_repo_id: managed_repo_id,
          source: @source,
          category: @category,
          summary: snapshot["summary"] || "Runtime service evidence refreshed.",
          payload: snapshot,
          source_metadata: %{
            "digest" => digest,
            "status" => snapshot["status"],
            "review_required" => snapshot["review_required"] == true
          },
          captured_by: @observer,
          observed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        },
        actor: @observer
      )
    end
  end

  defp normalize_runtime_capability_state(nil, observation), do: normalize_runtime_capability_state(%{}, observation)

  defp normalize_runtime_capability_state(state, %Observation{} = observation) when state in [%{}, nil] do
    observation.payload
    |> normalize_map()
    |> normalize_runtime_capability_state(nil)
  end

  defp normalize_runtime_capability_state(state, _observation) do
    normalized = normalize_map(state)

    services =
      normalized
      |> Map.get("services", [])
      |> normalize_map_list()
      |> Enum.map(fn service ->
        compact_nil_values(%{
          "service_key" => Map.get(service, "service_key"),
          "status" => Map.get(service, "status"),
          "governance_effect" => Map.get(service, "governance_effect"),
          "denial_reason" => Map.get(service, "denial_reason"),
          "rollout_source" => Map.get(service, "rollout_source"),
          "summary" => Map.get(service, "summary")
        })
      end)

    compact_nil_values(%{
      "status" => Map.get(normalized, "status", "absent"),
      "summary" => Map.get(normalized, "summary", absent_capability_summary()),
      "rollout_source" => Map.get(normalized, "rollout_source"),
      "service_count" => Map.get(normalized, "service_count", length(services)),
      "available_service_count" => Map.get(normalized, "available_service_count", 0),
      "review_required_service_count" => Map.get(normalized, "review_required_service_count", 0),
      "blocked_service_count" => Map.get(normalized, "blocked_service_count", 0),
      "services" => services
    })
  end

  defp normalize_integration_binding_health(binding_health) do
    normalized = normalize_map(binding_health)

    providers =
      normalized
      |> Map.get("providers", [])
      |> normalize_map_list()
      |> Enum.map(fn provider ->
        compact_nil_values(%{
          "provider" => Map.get(provider, "provider"),
          "binding_count" => Map.get(provider, "binding_count"),
          "connected_binding_count" => Map.get(provider, "connected_binding_count"),
          "default_binding_aliases" => Map.get(provider, "default_binding_aliases", []),
          "summary" => Map.get(provider, "summary")
        })
      end)

    compact_nil_values(%{
      "status" => Map.get(normalized, "status", "absent"),
      "summary" => Map.get(normalized, "summary", absent_integration_summary()),
      "binding_count" => Map.get(normalized, "binding_count", 0),
      "connected_binding_count" => Map.get(normalized, "connected_binding_count", 0),
      "default_binding_count" => Map.get(normalized, "default_binding_count", 0),
      "providers" => providers,
      "runtime_capability" =>
        normalized
        |> Map.get("runtime_capability", %{})
        |> normalize_runtime_capability_state(nil)
    })
  end

  defp normalize_install_record(%Observation{} = observation) do
    payload = normalize_map(observation.payload)

    compact_nil_values(%{
      "record_id" => observation.id,
      "provider" => Map.get(payload, "provider"),
      "binding_alias" => Map.get(payload, "binding_alias"),
      "actor_id" => get_in(payload, ["context", "actor_id"]),
      "correlation_id" => get_in(payload, ["context", "correlation_id"]),
      "summary" => observation.summary,
      "observed_at" => format_datetime(observation.observed_at)
    })
  end

  defp normalize_install_record(_observation), do: %{}

  defp normalize_invocation_record(%Event{} = event) do
    payload = normalize_map(event.payload)

    compact_nil_values(%{
      "record_id" => event.id,
      "provider" => get_in(payload, ["operation", "provider"]) || get_in(payload, ["source_metadata", "provider"]),
      "operation_id" => get_in(payload, ["operation", "operation_id"]),
      "binding_alias" => get_in(payload, ["project_binding", "binding_alias"]),
      "actor_id" => get_in(payload, ["context", "actor_id"]),
      "correlation_id" => get_in(payload, ["context", "correlation_id"]) || event.correlation_key,
      "summary" => event.summary,
      "occurred_at" => format_datetime(event.occurred_at)
    })
  end

  defp normalize_invocation_record(_event), do: %{}

  defp normalize_runtime_delivery(%Evidence{} = evidence) do
    details = normalize_map(evidence.evidence_details)
    status = delivery_status(details)

    compact_nil_values(%{
      "status" => status,
      "delivery_mode" => Map.get(details, "delivery_mode", "unknown"),
      "live_delivery_status" => Map.get(details, "live_delivery_status"),
      "reason_code" => Map.get(details, "reason_code"),
      "terminal_handoff_kind" => Map.get(details, "terminal_handoff_kind"),
      "terminal_state" => Map.get(details, "terminal_state"),
      "summary" => evidence.summary,
      "evidence_id" => evidence.id,
      "run_id" => evidence.run_id,
      "work_item_id" => evidence.work_item_id,
      "turn_id" => Map.get(details, "turn_id"),
      "session_id" => Map.get(details, "session_id"),
      "conversation_id" => Map.get(details, "conversation_id"),
      "correlation_id" => Map.get(details, "correlation_id"),
      "recorded_at" => format_datetime(evidence.recorded_at)
    })
  end

  defp normalize_runtime_delivery(_evidence), do: absent_runtime_delivery()

  defp delivery_status(details) do
    live_delivery_status = Map.get(details, "live_delivery_status")
    delivery_mode = Map.get(details, "delivery_mode")

    cond do
      live_delivery_status in ["withheld", "denied", "unavailable"] ->
        "blocked"

      delivery_mode in ["replay_fallback", "replay_recovery"] ->
        "degraded"

      Map.get(details, "terminal_handoff_kind") == "replay_terminal_lookup" ->
        "degraded"

      live_delivery_status == "subscribed" or delivery_mode == "live_subscription" ->
        "available"

      true ->
        "degraded"
    end
  end

  defp snapshot_status(runtime_capability, integration_binding_health, runtime_delivery) do
    cond do
      Map.get(runtime_capability, "status") in ["blocked", "unavailable"] ->
        "blocked"

      Map.get(integration_binding_health, "status") == "blocked" ->
        "blocked"

      Map.get(runtime_delivery, "status") == "blocked" ->
        "blocked"

      Map.get(runtime_capability, "status") == "degraded" ->
        "degraded"

      Map.get(integration_binding_health, "status") in ["needs_binding", "degraded"] ->
        "degraded"

      Map.get(runtime_delivery, "status") == "degraded" ->
        "degraded"

      runtime_capability == %{} and integration_binding_health == %{} and runtime_delivery == %{} ->
        "absent"

      runtime_capability["status"] == "absent" and integration_binding_health["status"] == "absent" and
          runtime_delivery["status"] == "absent" ->
        "absent"

      true ->
        "available"
    end
  end

  defp snapshot_summary(status, runtime_capability, integration_binding_health, runtime_delivery, latest_invocation) do
    detail_summaries =
      [
        runtime_capability["summary"],
        integration_binding_health["summary"],
        runtime_delivery_summary(runtime_delivery),
        invocation_summary(latest_invocation)
      ]
      |> Enum.filter(&(is_binary(&1) and String.trim(&1) != ""))
      |> Enum.uniq()

    base =
      case status do
        "blocked" -> "Runtime service evidence requires explicit operator review."
        "degraded" -> "Runtime service evidence indicates degraded execution trust."
        "available" -> "Runtime service evidence is stable."
        _other -> "Runtime service evidence has not been observed yet."
      end

    case detail_summaries do
      [] -> base
      summaries -> Enum.join([base | summaries], " ")
    end
  end

  defp runtime_delivery_summary(%{"status" => "absent"}), do: nil

  defp runtime_delivery_summary(runtime_delivery) do
    runtime_delivery["summary"] ||
      case runtime_delivery["delivery_mode"] do
        "replay_fallback" ->
          "Coding turn delivery fell back to replay."

        "replay_recovery" ->
          "Coding turn delivery repaired through replay recovery."

        "live_subscription" ->
          "Coding turn delivery completed through live runtime delivery."

        _other ->
          nil
      end
  end

  defp invocation_summary(%{"summary" => summary}) when is_binary(summary), do: summary
  defp invocation_summary(_latest_invocation), do: nil

  defp review_required?(status), do: status in ["blocked", "degraded"]

  defp latest_runtime_delivery_evidence(managed_repo_id) do
    case Evidence.read(
           query: [
             filter: [managed_repo_id: managed_repo_id, key: @runtime_delivery_key],
             sort: [recorded_at: :desc],
             limit: 1
           ],
           actor: @observer
         ) do
      {:ok, [%Evidence{} = evidence | _rest]} -> evidence
      _other -> nil
    end
  end

  defp latest_observation(managed_repo_id, source, category) do
    case Observation.read(
           query: [
             filter: [managed_repo_id: managed_repo_id, source: source, category: category],
             sort: [observed_at: :desc],
             limit: 1
           ],
           actor: @observer
         ) do
      {:ok, [%Observation{} = observation | _rest]} -> observation
      _other -> nil
    end
  end

  defp latest_event(managed_repo_id, category) do
    case Event.read(
           query: [
             filter: [managed_repo_id: managed_repo_id, category: category],
             sort: [occurred_at: :desc],
             limit: 1
           ],
           actor: @observer
         ) do
      {:ok, [%Event{} = event | _rest]} -> event
      _other -> nil
    end
  end

  defp absent_snapshot do
    %{
      "signal_type" => "runtime_service_evidence",
      "source" => @source,
      "category" => @category,
      "status" => "absent",
      "summary" => "Runtime service evidence has not been observed yet.",
      "review_required" => false,
      "runtime_capability" => normalize_runtime_capability_state(%{}, nil),
      "integration_binding_health" => normalize_integration_binding_health(absent_integration_snapshot()),
      "runtime_delivery" => absent_runtime_delivery(),
      "integration_outcomes" => %{"latest_install" => %{}, "latest_invocation" => %{}},
      "latest_refs" => %{}
    }
  end

  defp absent_capability_summary, do: "Runtime capability posture has not been observed yet."
  defp absent_integration_summary, do: "Runtime integration binding health has not been observed yet."

  defp absent_integration_snapshot do
    %{
      "status" => "absent",
      "summary" => absent_integration_summary(),
      "binding_count" => 0,
      "connected_binding_count" => 0,
      "default_binding_count" => 0,
      "providers" => [],
      "runtime_capability" => %{}
    }
  end

  defp absent_runtime_delivery do
    %{
      "status" => "absent",
      "delivery_mode" => "absent",
      "summary" => "Runtime delivery fallback or replay evidence has not been observed yet."
    }
  end

  defp digest(payload) do
    payload
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp unwrap_ok_or({:ok, value}, _default), do: value
  defp unwrap_ok_or(_other, default), do: default

  defp compact_nil_values(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc -> acc
      {_key, value}, acc when is_map(value) and map_size(value) == 0 -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_datetime(_value), do: nil

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

  defp normalize_map_list(value) when is_list(value), do: Enum.map(value, &normalize_map/1)
  defp normalize_map_list(_value), do: []

  defp normalize_nested(%{} = value), do: normalize_map(value)
  defp normalize_nested(value), do: value
end
