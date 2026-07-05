defmodule JidoCode.Governance.RecordStore do
  @moduledoc """
  Store-backed governance records for evidence, policy, decisions, and posture.
  """

  alias JidoCode.ControlPlane.RecordStore, as: Store

  alias JidoCode.Governance.{
    ChangeRequest,
    Decision,
    Evidence,
    PolicySet,
    PostureCheck,
    RepoPosture,
    ReviewPolicy
  }

  @record_modules %{
    evidence: Evidence,
    change_request: ChangeRequest,
    decision: Decision,
    policy_set: PolicySet,
    repo_posture: RepoPosture,
    posture_check: PostureCheck
  }

  @change_statuses %{
    "open" => :open,
    "approved" => :approved,
    "rejected" => :rejected,
    "deferred" => :deferred
  }

  @decisions %{
    "approve" => :approve,
    "reject" => :reject,
    "defer" => :defer
  }

  @atom_key_aliases %{
    id: :id
  }

  @top_level_key_aliases %{
    "id" => :id,
    "managed_repo_id" => :managed_repo_id,
    "managedRepoId" => :managed_repo_id,
    "evidence_id" => :evidence_id,
    "evidenceId" => :evidence_id,
    "change_request_id" => :change_request_id,
    "changeRequestId" => :change_request_id,
    "decision_id" => :decision_id,
    "decisionId" => :decision_id,
    "policy_set_id" => :policy_set_id,
    "policySetId" => :policy_set_id,
    "repo_posture_id" => :repo_posture_id,
    "repoPostureId" => :repo_posture_id,
    "posture_check_id" => :posture_check_id,
    "postureCheckId" => :posture_check_id,
    "run_id" => :run_id,
    "runId" => :run_id,
    "work_item_id" => :work_item_id,
    "workItemId" => :work_item_id,
    "key" => :key,
    "evidence_key" => :key,
    "evidenceKey" => :key,
    "source_key" => :source_key,
    "sourceKey" => :source_key,
    "evidenceSourceKey" => :source_key,
    "changeRequestSourceKey" => :source_key,
    "policySetSourceKey" => :source_key,
    "repoPostureSourceKey" => :source_key,
    "postureCheckSourceKey" => :source_key,
    "evidence_type" => :evidence_type,
    "evidenceType" => :evidence_type,
    "summary" => :summary,
    "evidence_details" => :evidence_details,
    "evidenceDetailsJson" => :evidence_details,
    "source" => :source,
    "recorded_at" => :recorded_at,
    "recordedAt" => :recorded_at,
    "status" => :status,
    "recordStatus" => :status,
    "review_context" => :review_context,
    "reviewContextJson" => :review_context,
    "request_metadata" => :request_metadata,
    "requestMetadataJson" => :request_metadata,
    "evidence_ids" => :evidence_ids,
    "evidenceIdsJson" => :evidence_ids,
    "requested_at" => :requested_at,
    "requestedAt" => :requested_at,
    "resolved_at" => :resolved_at,
    "resolvedAt" => :resolved_at,
    "decision_key" => :decision_key,
    "decisionKey" => :decision_key,
    "decision" => :decision,
    "decisionOutcome" => :decision,
    "actor" => :actor,
    "actorJson" => :actor,
    "rationale" => :rationale,
    "decision_metadata" => :decision_metadata,
    "decisionMetadataJson" => :decision_metadata,
    "decided_at" => :decided_at,
    "decidedAt" => :decided_at,
    "name" => :name,
    "review_policy" => :review_policy,
    "reviewPolicyJson" => :review_policy,
    "policy_metadata" => :policy_metadata,
    "policyMetadataJson" => :policy_metadata,
    "overall_trust" => :overall_trust,
    "overallTrust" => :overall_trust,
    "execution_readiness" => :execution_readiness,
    "executionReadiness" => :execution_readiness,
    "validation_reliability" => :validation_reliability,
    "validationReliability" => :validation_reliability,
    "review_burden" => :review_burden,
    "reviewBurden" => :review_burden,
    "drift_rate" => :drift_rate,
    "driftRate" => :drift_rate,
    "recovery_resilience" => :recovery_resilience,
    "recoveryResilience" => :recovery_resilience,
    "requirements_confidence" => :requirements_confidence,
    "requirementsConfidence" => :requirements_confidence,
    "supervision_mode" => :supervision_mode,
    "supervisionMode" => :supervision_mode,
    "escalation_status" => :escalation_status,
    "escalationStatus" => :escalation_status,
    "algedonic_check_id" => :algedonic_check_id,
    "algedonicCheckId" => :algedonic_check_id,
    "contributing_check_ids" => :contributing_check_ids,
    "contributingCheckIdsJson" => :contributing_check_ids,
    "posture_metadata" => :posture_metadata,
    "postureMetadataJson" => :posture_metadata,
    "observation_id" => :observation_id,
    "observationId" => :observation_id,
    "assessment_id" => :assessment_id,
    "assessmentId" => :assessment_id,
    "dimension" => :dimension,
    "value" => :value,
    "details" => :details,
    "detailsJson" => :details,
    "threat_level" => :threat_level,
    "threatLevel" => :threat_level,
    "escalation_mode" => :escalation_mode,
    "escalationMode" => :escalation_mode,
    "checked_at" => :checked_at,
    "checkedAt" => :checked_at,
    "inserted_at" => :inserted_at,
    "insertedAt" => :inserted_at,
    "updated_at" => :updated_at,
    "updatedAt" => :updated_at,
    "metadata" => :metadata,
    "metadataJson" => :metadata
  }

  @map_fields [
    :evidence_details,
    :review_context,
    :request_metadata,
    :actor,
    :decision_metadata,
    :review_policy,
    :policy_metadata,
    :posture_metadata,
    :details,
    :metadata
  ]

  @list_fields [
    :evidence_ids,
    :contributing_check_ids
  ]

  @spec upsert_evidence(map(), keyword()) :: {:ok, Evidence.t()} | {:error, term()}
  def upsert_evidence(attrs, opts \\ []), do: upsert_record(:evidence, attrs, opts)

  @spec list_evidence(map(), keyword()) :: {:ok, [Evidence.t()]} | {:error, term()}
  def list_evidence(filters \\ %{}, opts \\ []), do: list(:evidence, filters, opts)

  @spec upsert_change_request(map(), keyword()) :: {:ok, ChangeRequest.t()} | {:error, term()}
  def upsert_change_request(attrs, opts \\ []), do: upsert_record(:change_request, attrs, opts)

  @spec get_change_request_by_run_id(String.t(), keyword()) :: {:ok, ChangeRequest.t() | nil} | {:error, term()}
  def get_change_request_by_run_id(run_id, opts \\ []) do
    with {:ok, record} <- Store.get_by_identity(:change_request, :unique_run, "changeRequestSourceKey", run_id, opts) do
      {:ok, record && to_struct(:change_request, record)}
    end
  end

  @spec list_change_requests(map(), keyword()) :: {:ok, [ChangeRequest.t()]} | {:error, term()}
  def list_change_requests(filters \\ %{}, opts \\ []), do: list(:change_request, filters, opts)

  @spec upsert_decision(map(), keyword()) :: {:ok, Decision.t()} | {:error, term()}
  def upsert_decision(attrs, opts \\ []), do: upsert_record(:decision, attrs, opts)

  @spec list_decisions(map(), keyword()) :: {:ok, [Decision.t()]} | {:error, term()}
  def list_decisions(filters \\ %{}, opts \\ []), do: list(:decision, filters, opts)

  @spec upsert_policy_set(map(), keyword()) :: {:ok, PolicySet.t()} | {:error, term()}
  def upsert_policy_set(attrs, opts \\ []), do: upsert_record(:policy_set, attrs, opts)

  @spec get_policy_set_by_managed_repo_name(String.t(), String.t(), keyword()) ::
          {:ok, PolicySet.t() | nil} | {:error, term()}
  def get_policy_set_by_managed_repo_name(managed_repo_id, name, opts \\ []) do
    source_key = policy_set_source_key(%{managed_repo_id: managed_repo_id, name: name})

    with {:ok, record} <-
           Store.get_by_identity(:policy_set, :unique_managed_repo_name, "policySetSourceKey", source_key, opts) do
      {:ok, record && to_struct(:policy_set, record)}
    end
  end

  @spec upsert_repo_posture(map(), keyword()) :: {:ok, RepoPosture.t()} | {:error, term()}
  def upsert_repo_posture(attrs, opts \\ []), do: upsert_record(:repo_posture, attrs, opts)

  @spec get_repo_posture_by_managed_repo_id(String.t(), keyword()) :: {:ok, RepoPosture.t() | nil} | {:error, term()}
  def get_repo_posture_by_managed_repo_id(managed_repo_id, opts \\ []) do
    with {:ok, record} <-
           Store.get_by_identity(:repo_posture, :unique_managed_repo, "repoPostureSourceKey", managed_repo_id, opts) do
      {:ok, record && to_struct(:repo_posture, record)}
    end
  end

  @spec list_repo_postures(map(), keyword()) :: {:ok, [RepoPosture.t()]} | {:error, term()}
  def list_repo_postures(filters \\ %{}, opts \\ []), do: list(:repo_posture, filters, opts)

  @spec upsert_posture_check(map(), keyword()) :: {:ok, PostureCheck.t()} | {:error, term()}
  def upsert_posture_check(attrs, opts \\ []), do: upsert_record(:posture_check, attrs, opts)

  @spec list_posture_checks(map(), keyword()) :: {:ok, [PostureCheck.t()]} | {:error, term()}
  def list_posture_checks(filters \\ %{}, opts \\ []), do: list(:posture_check, filters, opts)

  def to_struct(record_type, record) when is_atom(record_type) and is_map(record) do
    struct!(Map.fetch!(@record_modules, record_type), struct_attrs(record_type, normalize_record_map(record)))
    |> Map.put(:__metadata__, %{control_plane_record: record})
  end

  defp upsert_record(record_type, attrs, opts) when is_map(attrs) do
    attrs = normalize_record_map(attrs)

    with {:ok, existing} <- existing_record(record_type, attrs, opts),
         record <- record(record_type, attrs, existing),
         {:ok, saved_record} <- Store.upsert(record_type, record, opts) do
      {:ok, to_struct(record_type, saved_record)}
    end
  end

  defp upsert_record(_record_type, _attrs, _opts), do: {:error, :invalid_governance_record_attrs}

  defp existing_record(:evidence, attrs, opts),
    do: Store.get_by_identity(:evidence, :unique_run_key, "evidenceSourceKey", evidence_source_key(attrs), opts)

  defp existing_record(:change_request, attrs, opts),
    do:
      Store.get_by_identity(
        :change_request,
        :unique_run,
        "changeRequestSourceKey",
        change_request_source_key(attrs),
        opts
      )

  defp existing_record(:decision, attrs, opts),
    do: Store.get_by_identity(:decision, :unique_decision_key, "decisionKey", map_get(attrs, :decision_key), opts)

  defp existing_record(:policy_set, attrs, opts),
    do:
      Store.get_by_identity(
        :policy_set,
        :unique_managed_repo_name,
        "policySetSourceKey",
        policy_set_source_key(attrs),
        opts
      )

  defp existing_record(:repo_posture, attrs, opts),
    do:
      Store.get_by_identity(
        :repo_posture,
        :unique_managed_repo,
        "repoPostureSourceKey",
        repo_posture_source_key(attrs),
        opts
      )

  defp existing_record(:posture_check, attrs, opts),
    do:
      Store.get_by_identity(
        :posture_check,
        :unique_managed_repo_dimension,
        "postureCheckSourceKey",
        posture_check_source_key(attrs),
        opts
      )

  defp record(:evidence, attrs, existing) do
    now = now()

    %{
      evidence_id:
        existing_id(existing, :evidence_id) ||
          normalize_optional_string(map_get(attrs, :evidence_id) || map_get(attrs, :id)) || Ecto.UUID.generate(),
      managed_repo_id: normalize_optional_string(map_get(attrs, :managed_repo_id)),
      run_id: normalize_optional_string(map_get(attrs, :run_id)),
      work_item_id: normalize_optional_string(map_get(attrs, :work_item_id)),
      key: normalize_string(map_get(attrs, :key), "evidence"),
      source_key: evidence_source_key(attrs),
      evidence_type: normalize_string(map_get(attrs, :evidence_type), "workflow_run"),
      summary: normalize_string(map_get(attrs, :summary), "Evidence captured."),
      evidence_details: decode_json_map(map_get(attrs, :evidence_details, %{})),
      source: normalize_string(map_get(attrs, :source), "workflow_run"),
      recorded_at: normalize_datetime(map_get(attrs, :recorded_at)) || now,
      inserted_at: existing_datetime(existing, :inserted_at) || normalize_datetime(map_get(attrs, :inserted_at)) || now,
      updated_at: now,
      metadata: decode_json_map(map_get(attrs, :metadata, %{}))
    }
  end

  defp record(:change_request, attrs, existing) do
    now = now()

    %{
      change_request_id:
        existing_id(existing, :change_request_id) ||
          normalize_optional_string(map_get(attrs, :change_request_id) || map_get(attrs, :id)) ||
          Ecto.UUID.generate(),
      managed_repo_id: normalize_optional_string(map_get(attrs, :managed_repo_id)),
      run_id: normalize_optional_string(map_get(attrs, :run_id)),
      source_key: change_request_source_key(attrs),
      work_item_id: normalize_optional_string(map_get(attrs, :work_item_id)),
      status: normalize_atom(map_get(attrs, :status), @change_statuses, :open),
      summary: normalize_string(map_get(attrs, :summary), "Review requested."),
      review_context: decode_json_map(map_get(attrs, :review_context, %{})),
      request_metadata: decode_json_map(map_get(attrs, :request_metadata, %{})),
      evidence_ids: decode_json_list(map_get(attrs, :evidence_ids, []), []),
      requested_at: normalize_datetime(map_get(attrs, :requested_at)) || now,
      resolved_at: normalize_datetime(map_get(attrs, :resolved_at)),
      inserted_at: existing_datetime(existing, :inserted_at) || normalize_datetime(map_get(attrs, :inserted_at)) || now,
      updated_at: now,
      metadata: decode_json_map(map_get(attrs, :metadata, %{}))
    }
  end

  defp record(:decision, attrs, existing) do
    now = now()
    decided_at = normalize_datetime(map_get(attrs, :decided_at)) || now
    decision = normalize_atom(map_get(attrs, :decision), @decisions, :defer)
    decision_key = normalize_string(map_get(attrs, :decision_key), default_decision_key(attrs, decision, decided_at))

    %{
      decision_id:
        existing_id(existing, :decision_id) ||
          normalize_optional_string(map_get(attrs, :decision_id) || map_get(attrs, :id)) ||
          Ecto.UUID.generate(),
      managed_repo_id: normalize_optional_string(map_get(attrs, :managed_repo_id)),
      decision_key: decision_key,
      run_id: normalize_optional_string(map_get(attrs, :run_id)),
      change_request_id: normalize_optional_string(map_get(attrs, :change_request_id)),
      work_item_id: normalize_optional_string(map_get(attrs, :work_item_id)),
      decision: decision,
      actor: decode_json_map(map_get(attrs, :actor, %{})),
      rationale: normalize_optional_string(map_get(attrs, :rationale)),
      evidence_ids: decode_json_list(map_get(attrs, :evidence_ids, []), []),
      decision_metadata: decode_json_map(map_get(attrs, :decision_metadata, %{})),
      decided_at: decided_at,
      inserted_at: existing_datetime(existing, :inserted_at) || normalize_datetime(map_get(attrs, :inserted_at)) || now,
      updated_at: now,
      metadata: decode_json_map(map_get(attrs, :metadata, %{}))
    }
  end

  defp record(:policy_set, attrs, existing) do
    now = now()

    %{
      policy_set_id:
        existing_id(existing, :policy_set_id) ||
          normalize_optional_string(map_get(attrs, :policy_set_id) || map_get(attrs, :id)) ||
          Ecto.UUID.generate(),
      managed_repo_id: normalize_optional_string(map_get(attrs, :managed_repo_id)),
      name: normalize_string(map_get(attrs, :name), "default"),
      source_key: policy_set_source_key(attrs),
      review_policy: review_policy_attrs(map_get(attrs, :review_policy, %{})),
      policy_metadata: decode_json_map(map_get(attrs, :policy_metadata, %{})),
      inserted_at: existing_datetime(existing, :inserted_at) || normalize_datetime(map_get(attrs, :inserted_at)) || now,
      updated_at: now,
      metadata: decode_json_map(map_get(attrs, :metadata, %{}))
    }
  end

  defp record(:repo_posture, attrs, existing) do
    now = now()

    %{
      repo_posture_id:
        existing_id(existing, :repo_posture_id) ||
          normalize_optional_string(map_get(attrs, :repo_posture_id) || map_get(attrs, :id)) ||
          Ecto.UUID.generate(),
      managed_repo_id: normalize_optional_string(map_get(attrs, :managed_repo_id)),
      source_key: repo_posture_source_key(attrs),
      summary: normalize_string(map_get(attrs, :summary), "Repo posture is pending."),
      overall_trust: normalize_level(map_get(attrs, :overall_trust), "medium"),
      execution_readiness: normalize_level(map_get(attrs, :execution_readiness), "medium"),
      validation_reliability: normalize_level(map_get(attrs, :validation_reliability), "medium"),
      review_burden: normalize_level(map_get(attrs, :review_burden), "medium"),
      drift_rate: normalize_level(map_get(attrs, :drift_rate), "medium"),
      recovery_resilience: normalize_level(map_get(attrs, :recovery_resilience), "medium"),
      requirements_confidence: normalize_level(map_get(attrs, :requirements_confidence), "medium"),
      supervision_mode: normalize_string(map_get(attrs, :supervision_mode), "guided"),
      escalation_status: normalize_string(map_get(attrs, :escalation_status), "normal"),
      algedonic_check_id: normalize_optional_string(map_get(attrs, :algedonic_check_id)),
      contributing_check_ids: decode_json_list(map_get(attrs, :contributing_check_ids, []), []),
      posture_metadata: decode_json_map(map_get(attrs, :posture_metadata, %{})),
      inserted_at: existing_datetime(existing, :inserted_at) || normalize_datetime(map_get(attrs, :inserted_at)) || now,
      updated_at: now,
      metadata: decode_json_map(map_get(attrs, :metadata, %{}))
    }
  end

  defp record(:posture_check, attrs, existing) do
    now = now()

    %{
      posture_check_id:
        existing_id(existing, :posture_check_id) ||
          normalize_optional_string(map_get(attrs, :posture_check_id) || map_get(attrs, :id)) ||
          Ecto.UUID.generate(),
      managed_repo_id: normalize_optional_string(map_get(attrs, :managed_repo_id)),
      source_key: posture_check_source_key(attrs),
      repo_posture_id: normalize_optional_string(map_get(attrs, :repo_posture_id)),
      observation_id: normalize_optional_string(map_get(attrs, :observation_id)),
      assessment_id: normalize_optional_string(map_get(attrs, :assessment_id)),
      evidence_id: normalize_optional_string(map_get(attrs, :evidence_id)),
      dimension: normalize_string(map_get(attrs, :dimension), "execution_readiness"),
      value: normalize_level(map_get(attrs, :value), "medium"),
      summary: normalize_string(map_get(attrs, :summary), "Posture check captured."),
      details: decode_json_map(map_get(attrs, :details, %{})),
      source: normalize_string(map_get(attrs, :source), "posture_bridge"),
      threat_level: normalize_string(map_get(attrs, :threat_level), "none"),
      escalation_mode: normalize_string(map_get(attrs, :escalation_mode), "none"),
      checked_at: normalize_datetime(map_get(attrs, :checked_at)) || now,
      inserted_at: existing_datetime(existing, :inserted_at) || normalize_datetime(map_get(attrs, :inserted_at)) || now,
      updated_at: now,
      metadata: decode_json_map(map_get(attrs, :metadata, %{}))
    }
  end

  defp list(record_type, filters, opts) do
    query = Keyword.get(opts, :query)
    merged_filters = Map.merge(query_filter(query), normalize_filter_map(filters))
    store_opts = opts |> Keyword.delete(:query) |> Keyword.put(:query, %{limit: 500, offset: 0})

    with {:ok, records} <- Store.list(record_type, %{}, store_opts) do
      results =
        records
        |> Enum.map(&to_struct(record_type, &1))
        |> Enum.filter(&matches_filters?(&1, merged_filters))
        |> sort_records(query_sort(query))
        |> limit_records(query_limit(query))

      {:ok, results}
    end
  end

  defp struct_attrs(:evidence, record) do
    %{
      id: map_get(record, :evidence_id),
      managed_repo_id: map_get(record, :managed_repo_id),
      run_id: map_get(record, :run_id),
      work_item_id: map_get(record, :work_item_id),
      key: normalize_string(map_get(record, :key), "evidence"),
      evidence_type: normalize_string(map_get(record, :evidence_type), "workflow_run"),
      summary: normalize_string(map_get(record, :summary), "Evidence captured."),
      evidence_details: decode_json_map(map_get(record, :evidence_details, %{})),
      source: normalize_string(map_get(record, :source), "workflow_run"),
      recorded_at: normalize_datetime(map_get(record, :recorded_at)),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
  end

  defp struct_attrs(:change_request, record) do
    %{
      id: map_get(record, :change_request_id),
      managed_repo_id: map_get(record, :managed_repo_id),
      run_id: map_get(record, :run_id),
      work_item_id: map_get(record, :work_item_id),
      status: normalize_atom(map_get(record, :status), @change_statuses, :open),
      summary: normalize_string(map_get(record, :summary), "Review requested."),
      review_context: decode_json_map(map_get(record, :review_context, %{})),
      request_metadata: decode_json_map(map_get(record, :request_metadata, %{})),
      evidence_ids: decode_json_list(map_get(record, :evidence_ids, []), []),
      requested_at: normalize_datetime(map_get(record, :requested_at)),
      resolved_at: normalize_datetime(map_get(record, :resolved_at)),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
  end

  defp struct_attrs(:decision, record) do
    %{
      id: map_get(record, :decision_id),
      managed_repo_id: map_get(record, :managed_repo_id),
      decision_key: map_get(record, :decision_key),
      run_id: map_get(record, :run_id),
      change_request_id: map_get(record, :change_request_id),
      work_item_id: map_get(record, :work_item_id),
      decision: normalize_atom(map_get(record, :decision), @decisions, :defer),
      actor: decode_json_map(map_get(record, :actor, %{})),
      rationale: normalize_optional_string(map_get(record, :rationale)),
      evidence_ids: decode_json_list(map_get(record, :evidence_ids, []), []),
      decision_metadata: decode_json_map(map_get(record, :decision_metadata, %{})),
      decided_at: normalize_datetime(map_get(record, :decided_at)),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
  end

  defp struct_attrs(:policy_set, record) do
    %{
      id: map_get(record, :policy_set_id),
      managed_repo_id: map_get(record, :managed_repo_id),
      name: normalize_string(map_get(record, :name), "default"),
      review_policy: review_policy_struct(map_get(record, :review_policy, %{})),
      policy_metadata: decode_json_map(map_get(record, :policy_metadata, %{})),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
  end

  defp struct_attrs(:repo_posture, record) do
    %{
      id: map_get(record, :repo_posture_id),
      managed_repo_id: map_get(record, :managed_repo_id),
      summary: normalize_string(map_get(record, :summary), "Repo posture is pending."),
      overall_trust: normalize_level(map_get(record, :overall_trust), "medium"),
      execution_readiness: normalize_level(map_get(record, :execution_readiness), "medium"),
      validation_reliability: normalize_level(map_get(record, :validation_reliability), "medium"),
      review_burden: normalize_level(map_get(record, :review_burden), "medium"),
      drift_rate: normalize_level(map_get(record, :drift_rate), "medium"),
      recovery_resilience: normalize_level(map_get(record, :recovery_resilience), "medium"),
      requirements_confidence: normalize_level(map_get(record, :requirements_confidence), "medium"),
      supervision_mode: normalize_string(map_get(record, :supervision_mode), "guided"),
      escalation_status: normalize_string(map_get(record, :escalation_status), "normal"),
      algedonic_check_id: normalize_optional_string(map_get(record, :algedonic_check_id)),
      contributing_check_ids: decode_json_list(map_get(record, :contributing_check_ids, []), []),
      posture_metadata: decode_json_map(map_get(record, :posture_metadata, %{})),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
  end

  defp struct_attrs(:posture_check, record) do
    %{
      id: map_get(record, :posture_check_id),
      repo_posture_id: map_get(record, :repo_posture_id),
      managed_repo_id: map_get(record, :managed_repo_id),
      observation_id: map_get(record, :observation_id),
      assessment_id: map_get(record, :assessment_id),
      evidence_id: map_get(record, :evidence_id),
      dimension: normalize_string(map_get(record, :dimension), "execution_readiness"),
      value: normalize_level(map_get(record, :value), "medium"),
      summary: normalize_string(map_get(record, :summary), "Posture check captured."),
      details: decode_json_map(map_get(record, :details, %{})),
      source: normalize_string(map_get(record, :source), "posture_bridge"),
      threat_level: normalize_string(map_get(record, :threat_level), "none"),
      escalation_mode: normalize_string(map_get(record, :escalation_mode), "none"),
      checked_at: normalize_datetime(map_get(record, :checked_at)),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
  end

  defp evidence_source_key(record) do
    normalize_optional_string(map_get(record, :source_key)) ||
      compact_join([map_get(record, :run_id), normalize_string(map_get(record, :key), "evidence")])
  end

  defp change_request_source_key(record) do
    normalize_optional_string(map_get(record, :source_key)) ||
      normalize_optional_string(map_get(record, :run_id))
  end

  defp policy_set_source_key(record) do
    normalize_optional_string(map_get(record, :source_key)) ||
      compact_join([map_get(record, :managed_repo_id), normalize_string(map_get(record, :name), "default")])
  end

  defp repo_posture_source_key(record) do
    normalize_optional_string(map_get(record, :source_key)) ||
      normalize_optional_string(map_get(record, :managed_repo_id))
  end

  defp posture_check_source_key(record) do
    normalize_optional_string(map_get(record, :source_key)) ||
      compact_join([
        map_get(record, :managed_repo_id),
        normalize_string(map_get(record, :dimension), "execution_readiness")
      ])
  end

  defp default_decision_key(attrs, decision, decided_at) do
    compact_join([map_get(attrs, :run_id), decision, DateTime.to_iso8601(decided_at)])
  end

  defp compact_join(values) do
    values
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(":")
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp existing_id(nil, _field), do: nil
  defp existing_id(existing, field), do: normalize_optional_string(map_get(existing, field) || map_get(existing, :id))

  defp existing_datetime(nil, _field), do: nil
  defp existing_datetime(existing, field), do: normalize_datetime(map_get(existing, field))

  defp review_policy_struct(review_policy), do: struct!(ReviewPolicy, review_policy_attrs(review_policy))

  defp review_policy_attrs(value) do
    value = decode_json_map(value)

    %{
      mode: normalize_string(map_get(value, :mode), "approval_required"),
      requires_human_approval: normalize_boolean(map_get(value, :requires_human_approval), true),
      change_request_required: normalize_boolean(map_get(value, :change_request_required), true),
      review_threshold: normalize_string(map_get(value, :review_threshold), "human_approval"),
      required_stage: normalize_string(map_get(value, :required_stage), "approval"),
      source: normalize_string(map_get(value, :source), "policy_set.review_policy.default")
    }
  end

  defp query_filter(query) when is_list(query), do: query |> Keyword.get(:filter, %{}) |> normalize_filter_map()
  defp query_filter(query) when is_map(query), do: query |> map_get(:filter, %{}) |> normalize_filter_map()
  defp query_filter(_query), do: %{}

  defp query_sort(query) when is_list(query), do: Keyword.get(query, :sort, [])
  defp query_sort(query) when is_map(query), do: map_get(query, :sort, [])
  defp query_sort(_query), do: []

  defp query_limit(query) when is_list(query), do: Keyword.get(query, :limit)
  defp query_limit(query) when is_map(query), do: map_get(query, :limit)
  defp query_limit(_query), do: nil

  defp normalize_filter_map(filters) when is_list(filters), do: Map.new(filters)
  defp normalize_filter_map(filters) when is_map(filters), do: filters
  defp normalize_filter_map(_filters), do: %{}

  defp sort_records(records, [{field, direction} | _rest]) do
    sorter = if direction == :desc or direction == "desc", do: :desc, else: :asc
    Enum.sort_by(records, &sort_value(Map.get(&1, field)), sorter)
  rescue
    _error -> records
  end

  defp sort_records(records, _sort), do: records

  defp sort_value(%DateTime{} = value), do: DateTime.to_unix(value, :microsecond)
  defp sort_value(nil), do: -1
  defp sort_value(value) when is_atom(value), do: Atom.to_string(value)
  defp sort_value(value), do: value

  defp limit_records(records, limit) when is_integer(limit) and limit >= 0, do: Enum.take(records, limit)
  defp limit_records(records, _limit), do: records

  defp matches_filters?(record, filters) do
    Enum.all?(filters, fn {key, expected} ->
      actual = Map.get(record, key) || Map.get(record, to_string(key))
      values_equal?(actual, expected)
    end)
  end

  defp values_equal?(actual, expected) when is_list(expected), do: Enum.any?(expected, &values_equal?(actual, &1))
  defp values_equal?(actual, expected), do: normalize_comparable(actual) == normalize_comparable(expected)

  defp normalize_comparable(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize_comparable(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_comparable(value), do: value

  defp normalize_record_map(%Ash.NotLoaded{}), do: %{}

  defp normalize_record_map(%_{} = value) do
    value
    |> Map.from_struct()
    |> Map.drop([:__meta__, :__metadata__])
    |> normalize_record_map()
  end

  defp normalize_record_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key = normalize_key(key)
      normalized_value = normalize_record_value(normalized_key, nested_value)
      Map.put(acc, normalized_key, normalized_value)
    end)
  end

  defp normalize_key(key) when is_atom(key), do: Map.get(@atom_key_aliases, key, key)

  defp normalize_key(key) when is_binary(key) do
    Map.get(@top_level_key_aliases, key) ||
      Map.get(@top_level_key_aliases, Macro.underscore(key)) ||
      key
  end

  defp normalize_key(key), do: key |> to_string() |> normalize_key()

  defp normalize_record_value(key, value) when key in @map_fields, do: decode_json_map(value)
  defp normalize_record_value(key, value) when key in @list_fields, do: decode_json_list(value, [])
  defp normalize_record_value(_key, %Ash.NotLoaded{}), do: nil
  defp normalize_record_value(_key, %Ecto.Schema.Metadata{}), do: nil
  defp normalize_record_value(_key, %DateTime{} = value), do: DateTime.truncate(value, :microsecond)
  defp normalize_record_value(_key, %NaiveDateTime{} = value), do: value
  defp normalize_record_value(_key, value) when is_map(value), do: normalize_map(value)
  defp normalize_record_value(_key, value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_record_value(_key, value), do: value

  defp decode_json_map(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> normalize_map(decoded)
      _other -> %{}
    end
  end

  defp decode_json_map(%Ash.NotLoaded{}), do: %{}
  defp decode_json_map(%Ecto.Schema.Metadata{}), do: %{}
  defp decode_json_map(%_{} = value), do: value |> Map.from_struct() |> normalize_map()
  defp decode_json_map(value) when is_map(value), do: normalize_map(value)
  defp decode_json_map(_value), do: %{}

  defp decode_json_list(value, default) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_list(decoded) -> Enum.map(decoded, &normalize_nested_value/1)
      _other -> default
    end
  end

  defp decode_json_list(value, _default) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp decode_json_list(_value, default), do: default

  defp normalize_map(%Ash.NotLoaded{}), do: %{}
  defp normalize_map(%Ecto.Schema.Metadata{}), do: %{}

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      Map.put(acc, to_string(key), normalize_nested_value(nested_value))
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(%Ash.NotLoaded{}), do: nil
  defp normalize_nested_value(%Ecto.Schema.Metadata{}), do: nil

  defp normalize_nested_value(%DateTime{} = value),
    do: value |> DateTime.truncate(:microsecond) |> DateTime.to_iso8601()

  defp normalize_nested_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp normalize_nested_value(%_{} = value), do: value |> Map.from_struct() |> normalize_map()
  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :microsecond)

  defp normalize_datetime(%NaiveDateTime{} = datetime) do
    case DateTime.from_naive(datetime, "Etc/UTC") do
      {:ok, parsed_datetime} -> normalize_datetime(parsed_datetime)
      _other -> nil
    end
  end

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> normalize_datetime(datetime)
      _other -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp normalize_string(value, default) do
    case normalize_optional_string(value) do
      nil -> default
      normalized -> normalized
    end
  end

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

  defp normalize_atom(value, known_atoms, default) when is_atom(value) do
    if value in Map.values(known_atoms), do: value, else: default
  end

  defp normalize_atom(value, known_atoms, default) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> default
      normalized -> Map.get(known_atoms, normalized, default)
    end
  end

  defp normalize_atom(_value, _known_atoms, default), do: default

  defp normalize_level(value, default) do
    case normalize_optional_string(value) do
      level when level in ["low", "medium", "high"] -> level
      _other -> default
    end
  end

  defp normalize_boolean(value, _default) when is_boolean(value), do: value

  defp normalize_boolean(value, default) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "true" -> true
      "false" -> false
      _other -> default
    end
  end

  defp normalize_boolean(_value, default), do: default

  defp map_get(map, key, default \\ nil)
  defp map_get(map, key, default) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  defp map_get(_map, _key, default), do: default

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
