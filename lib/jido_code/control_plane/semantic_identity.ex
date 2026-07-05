defmodule JidoCode.ControlPlane.SemanticIdentity do
  @moduledoc """
  Canonical semantic identity templates for product control-plane records.

  The registry is intentionally data-oriented: later store adapters can use it
  for deterministic subject IRIs, ontology class IRIs, id predicates, and
  uniqueness checks without depending on Ash resource metadata.
  """

  @control_base_iri "https://jido.run/control"
  @control_plane_ns "https://jido.run/ontology/control-plane#"

  @type record_type :: atom()
  @type record_spec :: %{
          class_name: String.t(),
          segment: String.t(),
          id_predicate: String.t(),
          scope: :product | :repo_scoped | :legacy | :external | :singleton,
          id_field: atom(),
          upsert: atom()
        }
  @type identity_contract :: %{
          record_type: record_type(),
          identity: atom(),
          fields: [atom()],
          mode: :unique_query | :singleton | :external_identity,
          conflict: atom()
        }

  defp record_specs do
    %{
      managed_repo: %{
        class_name: "ManagedRepo",
        segment: "managed-repos",
        id_predicate: "managedRepoId",
        scope: :product,
        id_field: :id,
        upsert: :replace_by_canonical_iri
      },
      source_repo: %{
        class_name: "SourceRepo",
        segment: "source-repos",
        id_predicate: "sourceRepoId",
        scope: :product,
        id_field: :id,
        upsert: :replace_by_natural_identity
      },
      project: %{
        class_name: "Project",
        segment: "projects",
        id_predicate: "projectId",
        scope: :legacy,
        id_field: :id,
        upsert: :compatibility_only
      },
      intake: record_spec("Intake", "intakes", "intakeId", :repo_scoped),
      external_object: %{
        class_name: "ExternalObject",
        segment: "external-objects",
        id_predicate: "externalObjectId",
        scope: :external,
        id_field: :id,
        upsert: :replace_by_natural_identity
      },
      event: record_spec("Event", "events", "eventId", :repo_scoped),
      observation: record_spec("Observation", "observations", "observationId", :repo_scoped),
      assessment: record_spec("Assessment", "assessments", "assessmentId", :repo_scoped),
      work_item: record_spec("WorkItem", "work-items", "workItemId", :repo_scoped),
      run: record_spec("Run", "runs", "runId", :repo_scoped),
      workflow_run: %{
        class_name: "WorkflowRun",
        segment: "workflow-runs",
        id_predicate: "workflowRunId",
        scope: :legacy,
        id_field: :id,
        upsert: :compatibility_only
      },
      execution_profile: record_spec("ExecutionProfile", "execution-profiles", "executionProfileId", :repo_scoped),
      evidence: record_spec("Evidence", "evidence", "evidenceId", :repo_scoped),
      change_request: record_spec("ChangeRequest", "change-requests", "changeRequestId", :repo_scoped),
      decision: record_spec("Decision", "decisions", "decisionId", :repo_scoped),
      policy_set: record_spec("PolicySet", "policy-sets", "policySetId", :repo_scoped),
      review_policy: record_spec("ReviewPolicy", "review-policies", "reviewPolicyId", :repo_scoped),
      repo_posture: record_spec("RepoPosture", "repo-postures", "repoPostureId", :repo_scoped),
      posture_check: record_spec("PostureCheck", "posture-checks", "postureCheckId", :repo_scoped),
      conversation: record_spec("Conversation", "conversations", "conversationId", :repo_scoped),
      conversation_event: record_spec("ConversationEvent", "conversation-events", "conversationEventId", :repo_scoped),
      conversation_snapshot:
        record_spec(
          "ConversationSnapshot",
          "conversation-snapshots",
          "conversationSnapshotId",
          :repo_scoped
        ),
      execution_workflow: %{
        class_name: "ExecutionWorkflow",
        segment: "execution-workflows",
        id_predicate: "executionWorkflowId",
        scope: :product,
        id_field: :id,
        upsert: :replace_by_natural_identity
      },
      sandbox_session: record_spec("SandboxSession", "sandbox-sessions", "sandboxSessionId", :repo_scoped),
      runtime_event: record_spec("RuntimeEvent", "runtime-events", "runtimeEventId", :repo_scoped),
      checkpoint: record_spec("Checkpoint", "checkpoints", "checkpointId", :repo_scoped),
      exec_session: record_spec("ExecSession", "exec-sessions", "execSessionId", :repo_scoped),
      sprite_spec: %{
        class_name: "SpriteSpec",
        segment: "sprite-specs",
        id_predicate: "spriteSpecId",
        scope: :product,
        id_field: :id,
        upsert: :replace_by_natural_identity
      },
      user: %{
        class_name: "User",
        segment: "users",
        id_predicate: "userId",
        scope: :product,
        id_field: :id,
        upsert: :replace_by_natural_identity
      },
      user_identity: %{
        class_name: "UserIdentity",
        segment: "user-identities",
        id_predicate: "userIdentityId",
        scope: :product,
        id_field: :id,
        upsert: :replace_by_natural_identity
      },
      api_key: %{
        class_name: "ApiKey",
        segment: "api-keys",
        id_predicate: "apiKeyId",
        scope: :product,
        id_field: :id,
        upsert: :replace_by_canonical_iri
      },
      token: %{
        class_name: "Token",
        segment: "tokens",
        id_predicate: "tokenId",
        scope: :product,
        id_field: :id,
        upsert: :replace_by_canonical_iri
      },
      provider_config: %{
        class_name: "ProviderConfig",
        segment: "provider-configs",
        id_predicate: "providerConfigId",
        scope: :product,
        id_field: :id,
        upsert: :replace_by_natural_identity
      },
      github_repo: %{
        class_name: "GitHubRepo",
        segment: "github-repos",
        id_predicate: "githubRepoId",
        scope: :product,
        id_field: :id,
        upsert: :replace_by_natural_identity
      },
      webhook_delivery: record_spec("WebhookDelivery", "webhook-deliveries", "webhookDeliveryId", :repo_scoped),
      issue_analysis: record_spec("IssueAnalysis", "issue-analyses", "issueAnalysisId", :repo_scoped),
      secret_ref: %{
        class_name: "SecretRef",
        segment: "secret-refs",
        id_predicate: "secretRefId",
        scope: :product,
        id_field: :id,
        upsert: :replace_by_natural_identity
      },
      secret_lifecycle_audit: %{
        class_name: "SecretLifecycleAudit",
        segment: "secret-lifecycle-audits",
        id_predicate: "secretLifecycleAuditId",
        scope: :product,
        id_field: :id,
        upsert: :append_only
      },
      system_config: %{
        class_name: "SystemConfig",
        segment: "system-configs",
        id_predicate: "systemConfigId",
        scope: :singleton,
        id_field: :key,
        upsert: :replace_singleton
      }
    }
  end

  defp identity_contracts_data do
    [
      contract(:managed_repo, :unique_legacy_project_id, [:legacy_project_id]),
      contract(:managed_repo, :unique_source_repo, [:source_repo_id]),
      contract(:source_repo, :unique_provider_full_name, [:provider, :full_name]),
      contract(:project, :unique_source_identity, [:source_kind, :source_identifier]),
      contract(:project, :unique_github_full_name, [:github_full_name]),
      contract(:external_object, :unique_canonical_key, [:canonical_key]),
      contract(
        :external_object,
        :unique_external_identity,
        [:provider, :provider_host, :object_type, :external_id],
        :external_identity
      ),
      contract(:workflow_run, :unique_run_per_project, [:project_id, :run_id]),
      contract(:execution_profile, :unique_managed_repo_name, [:managed_repo_id, :name]),
      contract(:run, :unique_workflow_run, [:workflow_run_id]),
      contract(:run, :unique_managed_repo_run_id, [:managed_repo_id, :run_id]),
      contract(:evidence, :unique_run_key, [:run_id, :key]),
      contract(:change_request, :unique_run, [:run_id]),
      contract(:decision, :unique_decision_key, [:decision_key]),
      contract(:policy_set, :unique_managed_repo_name, [:managed_repo_id, :name]),
      contract(:repo_posture, :unique_managed_repo, [:managed_repo_id]),
      contract(:posture_check, :unique_managed_repo_dimension, [:managed_repo_id, :dimension]),
      contract(:conversation_event, :unique_conversation_sequence, [:conversation_id, :sequence]),
      contract(:conversation_snapshot, :unique_conversation, [:conversation_id]),
      contract(:execution_workflow, :unique_name, [:name]),
      contract(:sandbox_session, :unique_name, [:name]),
      contract(:sprite_spec, :unique_name, [:name]),
      contract(:user, :unique_email, [:email]),
      contract(:user_identity, :unique_provider_subject, [:provider, :provider_host, :provider_subject]),
      contract(:api_key, :unique_api_key_id, [:api_key_id]),
      contract(:token, :unique_token_id, [:token_id]),
      contract(:provider_config, :unique_provider_host, [:provider, :provider_host]),
      contract(:github_repo, :unique_full_name, [:full_name]),
      contract(:webhook_delivery, :unique_github_delivery, [:github_delivery_id]),
      contract(:issue_analysis, :unique_issue_per_repo, [:repo_id, :issue_number]),
      contract(:secret_ref, :unique_scope_name, [:scope, :name]),
      contract(:system_config, :unique_key, [:key], :singleton)
    ]
  end

  @spec base_iri() :: String.t()
  def base_iri, do: @control_base_iri

  @spec ontology_namespace() :: String.t()
  def ontology_namespace, do: @control_plane_ns

  @spec record_types() :: [record_type()]
  def record_types, do: record_specs() |> Map.keys() |> Enum.sort()

  @spec record_spec(record_type()) :: {:ok, record_spec()} | {:error, :unknown_record_type}
  def record_spec(record_type) when is_atom(record_type) do
    case Map.fetch(record_specs(), record_type) do
      {:ok, spec} -> {:ok, spec}
      :error -> {:error, :unknown_record_type}
    end
  end

  def record_spec(_record_type), do: {:error, :unknown_record_type}

  @spec record_spec!(record_type()) :: record_spec()
  def record_spec!(record_type), do: Map.fetch!(record_specs(), record_type)

  @spec class_iri(record_type()) :: {:ok, RDF.IRI.t()} | {:error, :unknown_record_type}
  def class_iri(record_type) do
    with {:ok, spec} <- record_spec(record_type) do
      {:ok, RDF.iri(@control_plane_ns <> spec.class_name)}
    end
  end

  @spec id_predicate_iri(record_type()) :: {:ok, RDF.IRI.t()} | {:error, :unknown_record_type}
  def id_predicate_iri(record_type) do
    with {:ok, spec} <- record_spec(record_type) do
      {:ok, RDF.iri(@control_plane_ns <> spec.id_predicate)}
    end
  end

  @spec template(record_type()) :: {:ok, String.t()} | {:error, :unknown_record_type}
  def template(record_type) do
    with {:ok, spec} <- record_spec(record_type) do
      {:ok, template_for(spec)}
    end
  end

  @spec canonical_iri(record_type(), map() | keyword() | String.t()) ::
          {:ok, String.t()} | {:error, atom() | {:missing_identity_field, atom()}}
  def canonical_iri(record_type, id) when is_binary(id), do: canonical_iri(record_type, %{id: id})

  def canonical_iri(record_type, attrs) when is_list(attrs), do: canonical_iri(record_type, Map.new(attrs))

  def canonical_iri(record_type, attrs) when is_map(attrs) do
    with {:ok, spec} <- record_spec(record_type),
         {:ok, segments} <- canonical_segments(spec, attrs) do
      {:ok, Enum.join([@control_base_iri | segments], "/")}
    end
  end

  def canonical_iri(_record_type, _attrs), do: {:error, :invalid_identity_attributes}

  @spec canonical_resource(record_type(), map() | keyword() | String.t()) ::
          {:ok, RDF.IRI.t()} | {:error, atom() | {:missing_identity_field, atom()}}
  def canonical_resource(record_type, attrs) do
    with {:ok, iri} <- canonical_iri(record_type, attrs) do
      {:ok, RDF.iri(iri)}
    end
  end

  @spec upsert_strategy(record_type()) :: {:ok, atom()} | {:error, :unknown_record_type}
  def upsert_strategy(record_type) do
    with {:ok, spec} <- record_spec(record_type), do: {:ok, spec.upsert}
  end

  @spec identity_contracts() :: [identity_contract()]
  def identity_contracts, do: identity_contracts_data()

  @spec identity_contracts(record_type()) :: [identity_contract()]
  def identity_contracts(record_type) when is_atom(record_type) do
    Enum.filter(identity_contracts_data(), &(&1.record_type == record_type))
  end

  def identity_contracts(_record_type), do: []

  @spec identity_contract(record_type(), atom()) :: {:ok, identity_contract()} | {:error, :unknown_identity_contract}
  def identity_contract(record_type, identity) when is_atom(record_type) and is_atom(identity) do
    case Enum.find(identity_contracts_data(), &(&1.record_type == record_type and &1.identity == identity)) do
      nil -> {:error, :unknown_identity_contract}
      contract -> {:ok, contract}
    end
  end

  def identity_contract(_record_type, _identity), do: {:error, :unknown_identity_contract}

  @spec conflict_error(record_type(), atom()) :: {:error, {:conflict, record_type(), atom()}}
  def conflict_error(record_type, identity), do: {:error, {:conflict, record_type, identity}}

  defp record_spec(class_name, segment, id_predicate, scope) do
    %{
      class_name: class_name,
      segment: segment,
      id_predicate: id_predicate,
      scope: scope,
      id_field: :id,
      upsert: :replace_by_canonical_iri
    }
  end

  defp contract(record_type, identity, fields, mode \\ :unique_query) do
    %{
      record_type: record_type,
      identity: identity,
      fields: fields,
      mode: mode,
      conflict: :"duplicate_#{record_type}"
    }
  end

  defp template_for(%{scope: :product, segment: segment}), do: "#{@control_base_iri}/#{segment}/{id}"
  defp template_for(%{scope: :legacy, segment: segment}), do: "#{@control_base_iri}/legacy/#{segment}/{id}"
  defp template_for(%{scope: :singleton, segment: segment}), do: "#{@control_base_iri}/#{segment}/{key}"

  defp template_for(%{scope: :repo_scoped, segment: segment}),
    do: "#{@control_base_iri}/managed-repos/{managed_repo_id}/#{segment}/{id}"

  defp template_for(%{scope: :external}),
    do: "#{@control_base_iri}/external/{provider}/{provider_host}/{object_type}/{external_id}"

  defp canonical_segments(%{scope: :product, segment: segment, id_field: id_field}, attrs) do
    with {:ok, id} <- required_segment(attrs, id_field) do
      {:ok, [segment, id]}
    end
  end

  defp canonical_segments(%{scope: :legacy, segment: segment, id_field: id_field}, attrs) do
    with {:ok, id} <- required_segment(attrs, id_field) do
      {:ok, ["legacy", segment, id]}
    end
  end

  defp canonical_segments(%{scope: :singleton, segment: segment, id_field: id_field}, attrs) do
    with {:ok, key} <- required_segment(attrs, id_field) do
      {:ok, [segment, key]}
    end
  end

  defp canonical_segments(%{scope: :repo_scoped, segment: segment, id_field: id_field}, attrs) do
    with {:ok, managed_repo_id} <- required_segment(attrs, :managed_repo_id),
         {:ok, id} <- required_segment(attrs, id_field) do
      {:ok, ["managed-repos", managed_repo_id, segment, id]}
    end
  end

  defp canonical_segments(%{scope: :external}, attrs) do
    with {:ok, provider} <- required_segment(attrs, :provider),
         {:ok, provider_host} <- required_segment(attrs, :provider_host),
         {:ok, object_type} <- required_segment(attrs, :object_type),
         {:ok, external_id} <- required_segment(attrs, :external_id) do
      {:ok, ["external", provider, provider_host, object_type, external_id]}
    end
  end

  defp required_segment(attrs, key) do
    case get_attr(attrs, key) do
      nil -> {:error, {:missing_identity_field, key}}
      value when is_atom(value) -> encode_segment(Atom.to_string(value), key)
      value when is_binary(value) -> encode_segment(value, key)
      value when is_integer(value) -> encode_segment(Integer.to_string(value), key)
      value -> encode_segment(to_string(value), key)
    end
  end

  defp encode_segment(value, key) do
    value = String.trim(value)

    if value == "" do
      {:error, {:missing_identity_field, key}}
    else
      {:ok, URI.encode(value, &URI.char_unreserved?/1)}
    end
  end

  defp get_attr(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end
end
