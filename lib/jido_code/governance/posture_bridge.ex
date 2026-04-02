defmodule JidoCode.Governance.PostureBridge do
  # covers: architecture.factory_control_plane.repo_native_state_layers_inform_control_plane
  # covers: architecture.repo_posture.repo_posture_summarizes_trust_dimensions
  # covers: architecture.repo_posture.posture_checks_preserve_explainable_links
  # covers: architecture.repo_posture.supervision_modes_are_explicit_and_reversible
  # covers: architecture.repo_posture.algedonic_escalation_is_typed_and_evidence_rich
  # covers: architecture.repo_posture.runtime_capability_observations_can_inform_posture
  # covers: architecture.repo_posture.governed_turn_evidence_can_inform_posture
  # covers: architecture.vsm_recursion.algedonic_escalation
  @moduledoc """
  Projects explainable repo posture records from repo-native state, assessments,
  evidence, and repo governance policy.
  """

  alias JidoCode.Control.{Actor, ManagedRepo}

  alias JidoCode.Governance.{
    Evidence,
    PolicyBridge,
    PostureCheck,
    RepoPosture,
    RuntimeCapabilityBridge,
    RuntimeEvidenceBridge
  }

  alias JidoCode.Operations.{Assessment, Observation, RepoNativeState}

  @actor Actor.factory_system_actor(%{"id" => "system:repo-posture", "email" => "repo-posture@system.local"})
  @dimensions [
    "execution_readiness",
    "validation_reliability",
    "review_burden",
    "drift_rate",
    "recovery_resilience",
    "requirements_confidence"
  ]
  @algedonic_dimension "algedonic_escalation"

  @type sync_result :: {:ok, %{repo_posture: RepoPosture.t(), posture_checks: [PostureCheck.t()]}} | {:error, term()}

  @spec sync_managed_repo(ManagedRepo.t() | map()) :: sync_result()
  def sync_managed_repo(%{} = managed_repo) do
    managed_repo_id = map_get(managed_repo, :id, "id")

    with true <- is_binary(managed_repo_id) or {:error, :missing_managed_repo_id},
         {:ok, repo_native_state} <- RepoNativeState.latest_signal_snapshot(managed_repo_id),
         {:ok, runtime_capability_signal} <- RuntimeCapabilityBridge.sync_managed_repo(managed_repo),
         {:ok, runtime_evidence_signal} <-
           RuntimeEvidenceBridge.sync_managed_repo(
             managed_repo,
             runtime_capability_observation: runtime_capability_signal.observation,
             runtime_capability_state: runtime_capability_signal.capability_posture
           ),
         {:ok, review_policy} <- PolicyBridge.configured_review_policy_for_managed_repo(managed_repo_id),
         context <-
           posture_context(
             managed_repo,
             repo_native_state,
             runtime_capability_signal,
             runtime_evidence_signal,
             review_policy
           ),
         {:ok, repo_posture} <- upsert_repo_posture(context, []),
         {:ok, posture_checks} <- sync_posture_checks(repo_posture, context),
         {:ok, repo_posture} <- upsert_repo_posture(context, posture_checks) do
      {:ok, %{repo_posture: repo_posture, posture_checks: posture_checks}}
    else
      false -> {:error, :missing_managed_repo_id}
      {:error, reason} -> {:error, reason}
    end
  end

  def sync_managed_repo(_managed_repo), do: {:error, :invalid_managed_repo}

  @spec sync_managed_repo_id(term()) :: sync_result()
  def sync_managed_repo_id(managed_repo_id) when is_binary(managed_repo_id) do
    case ManagedRepo.read(query: [filter: [id: managed_repo_id], limit: 1], actor: @actor) do
      {:ok, [%ManagedRepo{} = managed_repo | _rest]} -> sync_managed_repo(managed_repo)
      {:ok, []} -> {:error, :managed_repo_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def sync_managed_repo_id(_managed_repo_id), do: {:error, :invalid_managed_repo_id}

  defp sync_posture_checks(repo_posture, context) do
    context.dimension_checks
    |> Enum.reduce_while({:ok, []}, fn attrs, {:ok, acc} ->
      attrs =
        attrs
        |> Map.put(:repo_posture_id, repo_posture.id)
        |> Map.put_new(:checked_at, DateTime.utc_now() |> DateTime.truncate(:microsecond))

      case PostureCheck.upsert_for_managed_repo_dimension(attrs, actor: @actor) do
        {:ok, posture_check} -> {:cont, {:ok, [posture_check | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, posture_checks} -> {:ok, posture_checks |> Enum.reverse() |> Enum.sort_by(& &1.dimension)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp upsert_repo_posture(context, posture_checks) do
    algedonic_check =
      Enum.find(posture_checks, &(&1.dimension == @algedonic_dimension))

    RepoPosture.upsert_for_managed_repo(
      %{
        managed_repo_id: context.managed_repo_id,
        summary: posture_summary(context.dimensions, context.repo_native_state),
        overall_trust: overall_trust(context.dimensions),
        execution_readiness: Map.fetch!(context.dimensions, "execution_readiness"),
        validation_reliability: Map.fetch!(context.dimensions, "validation_reliability"),
        review_burden: Map.fetch!(context.dimensions, "review_burden"),
        drift_rate: Map.fetch!(context.dimensions, "drift_rate"),
        recovery_resilience: Map.fetch!(context.dimensions, "recovery_resilience"),
        requirements_confidence: Map.fetch!(context.dimensions, "requirements_confidence"),
        supervision_mode: context.supervision_state.mode,
        escalation_status: context.supervision_state.escalation_status,
        algedonic_check_id: algedonic_check && algedonic_check.id,
        contributing_check_ids: Enum.map(posture_checks, & &1.id),
        posture_metadata: %{
          "repo_native_state" => context.repo_native_state,
          "review_policy" => context.review_policy,
          "runtime_capability_state" => context.runtime_capability_state,
          "runtime_capability_summary" => RuntimeCapabilityBridge.operator_summary(context.runtime_capability_state),
          "runtime_service_evidence_state" => context.runtime_service_evidence_state,
          "runtime_service_evidence_summary" =>
            RuntimeEvidenceBridge.operator_summary(context.runtime_service_evidence_state),
          "supervision_state" => context.supervision_state,
          "latest_observation_ids" => %{
            "spec_led" => context.spec_observation && context.spec_observation.id,
            "beadwork" => context.beadwork_observation && context.beadwork_observation.id,
            "runtime_capability" => context.runtime_capability_observation && context.runtime_capability_observation.id,
            "runtime_service_evidence" =>
              context.runtime_service_evidence_observation && context.runtime_service_evidence_observation.id
          },
          "latest_assessment_id" => context.latest_assessment && context.latest_assessment.id,
          "latest_failure_evidence_id" => context.latest_failure_evidence && context.latest_failure_evidence.id,
          "latest_runtime_delivery_evidence_id" =>
            get_in(context.runtime_service_evidence_state, ["latest_refs", "runtime_delivery_evidence_id"])
        }
      },
      actor: @actor
    )
  end

  defp posture_context(
         managed_repo,
         repo_native_state,
         runtime_capability_signal,
         runtime_evidence_signal,
         review_policy
       ) do
    managed_repo_id = map_get(managed_repo, :id, "id")
    spec_observation = latest_repo_native_observation(managed_repo_id, "spec_led_state")
    beadwork_observation = latest_repo_native_observation(managed_repo_id, "beadwork_state")
    runtime_capability_observation = runtime_capability_signal.observation
    runtime_capability_state = normalize_map(runtime_capability_signal.capability_posture)
    runtime_service_evidence_observation = runtime_evidence_signal.observation
    runtime_service_evidence_state = normalize_map(runtime_evidence_signal.runtime_evidence)
    latest_assessment = latest_assessment(managed_repo_id)
    latest_failure_evidence = latest_failure_evidence(managed_repo_id)

    dimensions = %{
      "execution_readiness" => execution_readiness(managed_repo, runtime_capability_state),
      "validation_reliability" => validation_reliability(repo_native_state),
      "review_burden" => review_burden(review_policy, runtime_capability_state),
      "drift_rate" => drift_rate(repo_native_state),
      "recovery_resilience" => recovery_resilience(latest_failure_evidence, runtime_service_evidence_state),
      "requirements_confidence" => requirements_confidence(repo_native_state, latest_assessment)
    }

    supervision_state =
      supervision_state(
        dimensions,
        review_policy,
        repo_native_state,
        runtime_capability_state,
        latest_assessment,
        latest_failure_evidence
      )

    %{
      managed_repo_id: managed_repo_id,
      managed_repo: managed_repo,
      repo_native_state: repo_native_state,
      review_policy: review_policy,
      spec_observation: spec_observation,
      beadwork_observation: beadwork_observation,
      runtime_capability_observation: runtime_capability_observation,
      runtime_capability_state: runtime_capability_state,
      runtime_service_evidence_observation: runtime_service_evidence_observation,
      runtime_service_evidence_state: runtime_service_evidence_state,
      latest_assessment: latest_assessment,
      latest_failure_evidence: latest_failure_evidence,
      dimensions: dimensions,
      supervision_state: supervision_state,
      dimension_checks:
        build_dimension_checks(
          managed_repo_id,
          managed_repo,
          repo_native_state,
          review_policy,
          spec_observation,
          beadwork_observation,
          runtime_capability_observation,
          runtime_capability_state,
          runtime_service_evidence_observation,
          runtime_service_evidence_state,
          latest_assessment,
          latest_failure_evidence,
          dimensions,
          supervision_state
        )
    }
  end

  defp build_dimension_checks(
         managed_repo_id,
         managed_repo,
         repo_native_state,
         review_policy,
         spec_observation,
         beadwork_observation,
         runtime_capability_observation,
         runtime_capability_state,
         runtime_service_evidence_observation,
         runtime_service_evidence_state,
         latest_assessment,
         latest_failure_evidence,
         dimensions,
         supervision_state
       ) do
    workspace_settings =
      managed_repo
      |> map_get(:workspace_settings, "workspace_settings", %{})
      |> normalize_map()

    [
      %{
        managed_repo_id: managed_repo_id,
        observation_id:
          runtime_capability_observation_id(
            runtime_capability_state,
            runtime_capability_observation,
            spec_observation
          ),
        dimension: "execution_readiness",
        value: Map.fetch!(dimensions, "execution_readiness"),
        summary:
          "Workspace execution readiness is #{Map.fetch!(dimensions, "execution_readiness")} based on clone and baseline state.",
        details: %{
          "workspace_settings" => workspace_settings,
          "spec_status" => get_in(repo_native_state, ["spec_led", "status"]),
          "runtime_capability_state" => runtime_capability_state,
          "runtime_service_evidence_state" => runtime_service_evidence_state
        },
        source: execution_readiness_source(runtime_capability_state)
      },
      %{
        managed_repo_id: managed_repo_id,
        observation_id: spec_observation && spec_observation.id,
        dimension: "validation_reliability",
        value: Map.fetch!(dimensions, "validation_reliability"),
        summary:
          "Validation reliability is #{Map.fetch!(dimensions, "validation_reliability")} from observed `.spec` verification health.",
        details: Map.get(repo_native_state, "spec_led", %{}),
        source: "repo_native.spec_led"
      },
      %{
        managed_repo_id: managed_repo_id,
        observation_id:
          runtime_capability_observation_id(
            runtime_capability_state,
            runtime_capability_observation,
            nil
          ),
        assessment_id: latest_assessment && latest_assessment.id,
        dimension: "review_burden",
        value: Map.fetch!(dimensions, "review_burden"),
        summary:
          "Review burden is #{Map.fetch!(dimensions, "review_burden")} based on the repo's active governance policy.",
        details: %{
          "review_policy" => normalize_map(review_policy),
          "runtime_capability_state" => runtime_capability_state
        },
        source: review_burden_source(runtime_capability_state)
      },
      %{
        managed_repo_id: managed_repo_id,
        observation_id: (beadwork_observation && beadwork_observation.id) || (spec_observation && spec_observation.id),
        dimension: "drift_rate",
        value: Map.fetch!(dimensions, "drift_rate"),
        summary:
          "Drift rate is #{Map.fetch!(dimensions, "drift_rate")} from `.spec` verification and optional Beadwork alignment state.",
        details: %{
          "spec_led" => Map.get(repo_native_state, "spec_led", %{}),
          "beadwork" => Map.get(repo_native_state, "beadwork", %{})
        },
        source: "repo_native.drift"
      },
      %{
        managed_repo_id: managed_repo_id,
        evidence_id: latest_failure_evidence && latest_failure_evidence.id,
        dimension: "recovery_resilience",
        value: Map.fetch!(dimensions, "recovery_resilience"),
        summary:
          "Recovery resilience is #{Map.fetch!(dimensions, "recovery_resilience")} based on recent governed run evidence.",
        observation_id:
          runtime_service_evidence_observation_id(
            runtime_service_evidence_state,
            runtime_service_evidence_observation
          ),
        details:
          %{}
          |> maybe_put(
            "failure_evidence",
            latest_failure_evidence &&
              %{
                "evidence_type" => latest_failure_evidence.evidence_type,
                "summary" => latest_failure_evidence.summary,
                "details" => latest_failure_evidence.evidence_details
              }
          )
          |> maybe_put(
            "runtime_service_evidence",
            if(runtime_service_evidence_state == %{}, do: nil, else: runtime_service_evidence_state)
          ),
        source: recovery_resilience_source(runtime_service_evidence_state, latest_failure_evidence)
      },
      %{
        managed_repo_id: managed_repo_id,
        observation_id: spec_observation && spec_observation.id,
        assessment_id: latest_assessment && latest_assessment.id,
        dimension: "requirements_confidence",
        value: Map.fetch!(dimensions, "requirements_confidence"),
        summary:
          "Requirements confidence is #{Map.fetch!(dimensions, "requirements_confidence")} based on repo-native current truth and recent assessment flow.",
        details: %{
          "spec_led" => Map.get(repo_native_state, "spec_led", %{}),
          "latest_assessment_id" => latest_assessment && latest_assessment.id
        },
        source: "repo_native.requirements"
      },
      %{
        managed_repo_id: managed_repo_id,
        observation_id: (spec_observation && spec_observation.id) || (beadwork_observation && beadwork_observation.id),
        assessment_id: latest_assessment && latest_assessment.id,
        evidence_id: latest_failure_evidence && latest_failure_evidence.id,
        dimension: @algedonic_dimension,
        value: supervision_value(supervision_state),
        summary: supervision_state.summary,
        details: supervision_state.details,
        source: "posture.supervision",
        threat_level: supervision_state.threat_level,
        escalation_mode: check_escalation_mode(supervision_state.escalation_status)
      }
    ]
  end

  defp execution_readiness(managed_repo, runtime_capability_state) do
    workspace_settings =
      managed_repo
      |> map_get(:workspace_settings, "workspace_settings", %{})
      |> normalize_map()

    clone_status = Map.get(workspace_settings, "clone_status")
    initialized? = truthy?(Map.get(workspace_settings, "workspace_initialized"))
    baseline_synced? = truthy?(Map.get(workspace_settings, "baseline_synced"))
    has_workspace_path? = present?(Map.get(workspace_settings, "workspace_path"))

    workspace_level =
      cond do
        clone_status == "ready" and initialized? and baseline_synced? -> "high"
        has_workspace_path? -> "medium"
        true -> "low"
      end

    case Map.get(runtime_capability_state, "status") do
      status when status in ["blocked", "unavailable"] -> "low"
      "degraded" -> min_level(workspace_level, "medium")
      _other -> workspace_level
    end
  end

  defp validation_reliability(repo_native_state) do
    case get_in(repo_native_state, ["spec_led", "status"]) do
      "verified" -> "high"
      "drift" -> "medium"
      "blocked" -> "low"
      "state_missing" -> "low"
      _other -> "medium"
    end
  end

  defp review_burden(review_policy, runtime_capability_state) do
    normalized_review_policy = normalize_map(review_policy)

    base_review_burden =
      cond do
        Map.get(normalized_review_policy, "change_request_required", true) -> "high"
        Map.get(normalized_review_policy, "requires_human_approval", true) -> "medium"
        true -> "low"
      end

    case Map.get(runtime_capability_state, "status") do
      status when status in ["blocked", "degraded", "unavailable"] ->
        max_level(base_review_burden, "high")

      _other ->
        base_review_burden
    end
  end

  defp drift_rate(repo_native_state) do
    spec_status = get_in(repo_native_state, ["spec_led", "status"])
    beadwork_status = get_in(repo_native_state, ["beadwork", "status"])

    cond do
      spec_status in ["blocked", "state_missing"] -> "high"
      beadwork_status == "needs_alignment" or spec_status == "drift" -> "medium"
      true -> "low"
    end
  end

  defp recovery_resilience(failure_evidence, runtime_service_evidence_state) do
    cond do
      not is_nil(failure_evidence) ->
        "low"

      runtime_service_evidence_state_impacts_recovery?(runtime_service_evidence_state) ->
        runtime_service_evidence_recovery_level(runtime_service_evidence_state)

      true ->
        "high"
    end
  end

  defp requirements_confidence(repo_native_state, latest_assessment) do
    spec_status = get_in(repo_native_state, ["spec_led", "status"])

    cond do
      spec_status == "verified" and not is_nil(latest_assessment) -> "high"
      spec_status in ["verified", "drift"] -> "medium"
      is_nil(spec_status) or spec_status == "absent" -> "medium"
      true -> "low"
    end
  end

  defp overall_trust(dimensions) do
    trust_score =
      @dimensions
      |> Enum.map(fn dimension ->
        value = Map.fetch!(dimensions, dimension)

        case dimension do
          negative when negative in ["review_burden", "drift_rate"] -> inverse_level_score(value)
          _positive -> level_score(value)
        end
      end)
      |> Enum.sum()
      |> Kernel./(length(@dimensions))

    cond do
      trust_score >= 1.5 -> "high"
      trust_score >= 0.75 -> "medium"
      true -> "low"
    end
  end

  defp posture_summary(dimensions, repo_native_state) do
    spec_status = get_in(repo_native_state, ["spec_led", "status"]) || "absent"
    beadwork_status = get_in(repo_native_state, ["beadwork", "status"]) || "absent"

    "Repo posture is #{overall_trust(dimensions)} trust with #{Map.fetch!(dimensions, "execution_readiness")} execution readiness, #{Map.fetch!(dimensions, "validation_reliability")} validation reliability, and repo-native signals at spec=#{spec_status} beadwork=#{beadwork_status}."
  end

  defp supervision_state(
         dimensions,
         review_policy,
         repo_native_state,
         runtime_capability_state,
         latest_assessment,
         latest_failure_evidence
       ) do
    spec_status = get_in(repo_native_state, ["spec_led", "status"]) || "absent"
    runtime_capability_status = Map.get(runtime_capability_state, "status") || "absent"

    cond do
      dimensions["validation_reliability"] == "low" ->
        %{
          mode: "directed",
          escalation_status: "algedonic",
          threat_level: "viability",
          reason_code: "repo_viability_threat",
          summary: "Viability-threatening posture triggered directed supervision and algedonic escalation.",
          details: %{
            "spec_status" => spec_status,
            "dimensions" => dimensions,
            "latest_assessment_id" => latest_assessment && latest_assessment.id,
            "latest_failure_evidence_id" => latest_failure_evidence && latest_failure_evidence.id
          }
        }

      runtime_capability_status in ["blocked", "degraded", "unavailable"] ->
        %{
          mode: "guided",
          escalation_status: "review",
          threat_level: "watch",
          reason_code: "runtime_capability_review_required",
          summary: "Runtime capability posture requires guided supervision and explicit operator review.",
          details: %{
            "spec_status" => spec_status,
            "runtime_capability_status" => runtime_capability_status,
            "runtime_capability_state" => runtime_capability_state,
            "dimensions" => dimensions,
            "review_policy" => normalize_map(review_policy)
          }
        }

      dimensions["recovery_resilience"] == "low" or dimensions["requirements_confidence"] == "low" or
          dimensions["drift_rate"] == "high" ->
        %{
          mode: "guided",
          escalation_status: "review",
          threat_level: "watch",
          reason_code: "confidence_drop_requires_review",
          summary: "Confidence dropped enough to require guided supervision and operator review.",
          details: %{
            "spec_status" => spec_status,
            "dimensions" => dimensions,
            "review_policy" => normalize_map(review_policy)
          }
        }

      dimensions["review_burden"] == "low" and dimensions["execution_readiness"] == "high" and
        dimensions["validation_reliability"] == "high" and dimensions["drift_rate"] == "low" and
        dimensions["recovery_resilience"] == "high" and dimensions["requirements_confidence"] == "high" ->
        %{
          mode: "autonomous",
          escalation_status: "normal",
          threat_level: "none",
          reason_code: "high_confidence_autonomy",
          summary: "Strong posture signals allow autonomous supervision without added review burden.",
          details: %{
            "spec_status" => spec_status,
            "dimensions" => dimensions,
            "review_policy" => normalize_map(review_policy)
          }
        }

      dimensions["execution_readiness"] == "high" and dimensions["validation_reliability"] == "high" and
          dimensions["requirements_confidence"] in ["medium", "high"] ->
        %{
          mode: "delegated",
          escalation_status: "normal",
          threat_level: "none",
          reason_code: "stable_delegation",
          summary: "Stable posture signals allow delegated supervision while preserving explicit review policy.",
          details: %{
            "spec_status" => spec_status,
            "dimensions" => dimensions,
            "review_policy" => normalize_map(review_policy)
          }
        }

      true ->
        %{
          mode: "delegated",
          escalation_status: "normal",
          threat_level: "none",
          reason_code: "delegated_by_default",
          summary: "The repository remains in delegated supervision while posture signals stay stable.",
          details: %{
            "spec_status" => spec_status,
            "dimensions" => dimensions,
            "review_policy" => normalize_map(review_policy)
          }
        }
    end
  end

  defp supervision_value(%{escalation_status: "algedonic"}), do: "high"
  defp supervision_value(%{escalation_status: "review"}), do: "medium"
  defp supervision_value(_supervision_state), do: "low"

  defp check_escalation_mode("algedonic"), do: "algedonic"
  defp check_escalation_mode("review"), do: "review"
  defp check_escalation_mode(_status), do: "none"

  defp runtime_capability_observation_id(runtime_capability_state, runtime_capability_observation, fallback_observation) do
    case Map.get(runtime_capability_state, "status") do
      status when status in ["blocked", "degraded", "unavailable"] ->
        runtime_capability_observation && runtime_capability_observation.id

      _other ->
        fallback_observation && fallback_observation.id
    end
  end

  defp execution_readiness_source(runtime_capability_state) do
    case Map.get(runtime_capability_state, "status") do
      status when status in ["blocked", "degraded", "unavailable"] ->
        "runtime_capability.execution"

      _other ->
        "workspace_settings"
    end
  end

  defp review_burden_source(runtime_capability_state) do
    case Map.get(runtime_capability_state, "status") do
      status when status in ["blocked", "degraded", "unavailable"] ->
        "governance.review_policy+runtime_capability"

      _other ->
        "governance.review_policy"
    end
  end

  defp runtime_service_evidence_observation_id(runtime_service_evidence_state, runtime_service_evidence_observation) do
    if runtime_service_evidence_state_impacts_recovery?(runtime_service_evidence_state) do
      runtime_service_evidence_observation && runtime_service_evidence_observation.id
    end
  end

  defp runtime_service_evidence_state_impacts_recovery?(runtime_service_evidence_state) do
    status = Map.get(runtime_service_evidence_state, "status")
    delivery_mode = get_in(runtime_service_evidence_state, ["runtime_delivery", "delivery_mode"])
    terminal_handoff_kind = get_in(runtime_service_evidence_state, ["runtime_delivery", "terminal_handoff_kind"])

    status in ["blocked", "degraded"] or
      delivery_mode in ["replay_fallback", "replay_recovery"] or
      terminal_handoff_kind == "replay_terminal_lookup"
  end

  defp runtime_service_evidence_recovery_level(runtime_service_evidence_state) do
    case Map.get(runtime_service_evidence_state, "status") do
      "blocked" -> "low"
      _other -> "medium"
    end
  end

  defp recovery_resilience_source(runtime_service_evidence_state, failure_evidence) do
    cond do
      not is_nil(failure_evidence) ->
        "governance.evidence"

      runtime_service_evidence_state_impacts_recovery?(runtime_service_evidence_state) ->
        "governance.evidence+runtime_service"

      true ->
        "governance.evidence"
    end
  end

  defp latest_repo_native_observation(managed_repo_id, category) do
    case Observation.read(
           query: [
             filter: [managed_repo_id: managed_repo_id, source: "repo_native", category: category],
             sort: [observed_at: :desc],
             limit: 1
           ],
           actor: @actor
         ) do
      {:ok, [%Observation{} = observation | _rest]} -> observation
      _other -> nil
    end
  end

  defp latest_assessment(managed_repo_id) do
    case Assessment.read(
           query: [filter: [managed_repo_id: managed_repo_id], sort: [assessed_at: :desc], limit: 1],
           actor: @actor
         ) do
      {:ok, [%Assessment{} = assessment | _rest]} -> assessment
      _other -> nil
    end
  end

  defp latest_failure_evidence(managed_repo_id) do
    case Evidence.read(
           query: [
             filter: [managed_repo_id: managed_repo_id, key: "failure_context"],
             sort: [recorded_at: :desc],
             limit: 1
           ],
           actor: @actor
         ) do
      {:ok, [%Evidence{} = evidence | _rest]} -> evidence
      _other -> nil
    end
  end

  defp level_score("high"), do: 2
  defp level_score("medium"), do: 1
  defp level_score(_value), do: 0

  defp min_level(left, right), do: if(level_score(left) <= level_score(right), do: left, else: right)

  defp inverse_level_score("low"), do: 2
  defp inverse_level_score("medium"), do: 1
  defp inverse_level_score(_value), do: 0

  defp max_level(left, right),
    do: if(inverse_level_score(left) <= inverse_level_score(right), do: left, else: right)

  defp truthy?(value) when value in [true, "true", 1, "1"], do: true
  defp truthy?(_value), do: false

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

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

      Map.put(acc, normalized_key, normalize_nested_value(nested_value))
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(%_{} = value) do
    value
    |> Map.from_struct()
    |> Map.delete(:__meta__)
    |> normalize_map()
  end

  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value
end
