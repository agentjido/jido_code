defmodule JidoCode.ControlPlane.Codecs.Registry do
  @moduledoc """
  Registry for control-plane RDF projection codecs.
  """

  alias JidoCode.ControlPlane.SemanticIdentity

  alias JidoCode.ControlPlane.Codecs.{
    ApiKeyCodec,
    AssessmentCodec,
    ChangeRequestCodec,
    ConversationCodec,
    ConversationEventCodec,
    ConversationSnapshotCodec,
    CheckpointCodec,
    DecisionCodec,
    EventCodec,
    EvidenceCodec,
    ExecSessionCodec,
    ExecutionWorkflowCodec,
    ExternalObjectCodec,
    ExecutionProfileCodec,
    IntakeCodec,
    ManagedRepoCodec,
    ObservationCodec,
    PolicySetCodec,
    PostureCheckCodec,
    ProviderConfigCodec,
    RepoPostureCodec,
    RunCodec,
    RuntimeEventCodec,
    SandboxSessionCodec,
    SecretLifecycleAuditCodec,
    SecretRefCodec,
    SourceRepoCodec,
    SpriteSpecCodec,
    SystemConfigCodec,
    TokenCodec,
    UserCodec,
    UserIdentityCodec,
    WebhookDeliveryCodec,
    WorkflowRunCodec,
    WorkItemCodec
  }

  @codec_modules %{
    system_config: SystemConfigCodec,
    source_repo: SourceRepoCodec,
    managed_repo: ManagedRepoCodec,
    intake: IntakeCodec,
    external_object: ExternalObjectCodec,
    observation: ObservationCodec,
    assessment: AssessmentCodec,
    work_item: WorkItemCodec,
    decision: DecisionCodec,
    evidence: EvidenceCodec,
    change_request: ChangeRequestCodec,
    policy_set: PolicySetCodec,
    repo_posture: RepoPostureCodec,
    posture_check: PostureCheckCodec,
    run: RunCodec,
    workflow_run: WorkflowRunCodec,
    execution_profile: ExecutionProfileCodec,
    conversation: ConversationCodec,
    conversation_event: ConversationEventCodec,
    conversation_snapshot: ConversationSnapshotCodec,
    execution_workflow: ExecutionWorkflowCodec,
    sandbox_session: SandboxSessionCodec,
    runtime_event: RuntimeEventCodec,
    checkpoint: CheckpointCodec,
    exec_session: ExecSessionCodec,
    sprite_spec: SpriteSpecCodec,
    user: UserCodec,
    user_identity: UserIdentityCodec,
    api_key: ApiKeyCodec,
    token: TokenCodec,
    provider_config: ProviderConfigCodec,
    webhook_delivery: WebhookDeliveryCodec,
    event: EventCodec,
    secret_ref: SecretRefCodec,
    secret_lifecycle_audit: SecretLifecycleAuditCodec
  }

  @spec codec(atom()) :: {:ok, module()} | {:error, {:excluded, atom()}} | {:error, :unknown_record_type}
  def codec(record_type) when is_atom(record_type) do
    cond do
      Map.has_key?(@codec_modules, record_type) ->
        {:ok, Map.fetch!(@codec_modules, record_type)}

      Map.has_key?(explicit_exclusions(), record_type) ->
        {:error, {:excluded, Map.fetch!(explicit_exclusions(), record_type)}}

      true ->
        {:error, :unknown_record_type}
    end
  end

  def codec(_record_type), do: {:error, :unknown_record_type}

  @spec codecs() :: %{atom() => module()}
  def codecs, do: @codec_modules

  @spec explicit_exclusions() :: %{atom() => atom()}
  def explicit_exclusions do
    SemanticIdentity.record_types()
    |> Enum.reject(&Map.has_key?(@codec_modules, &1))
    |> Map.new(&{&1, :codec_not_promoted_yet})
  end

  @spec planned_coverage() :: map()
  def planned_coverage do
    codec_types = @codec_modules |> Map.keys() |> MapSet.new()
    excluded_types = explicit_exclusions() |> Map.keys() |> MapSet.new()
    planned_types = SemanticIdentity.record_types() |> MapSet.new()
    covered_types = MapSet.union(codec_types, excluded_types)

    %{
      planned_record_types: Enum.sort(MapSet.to_list(planned_types)),
      codec_record_types: Enum.sort(MapSet.to_list(codec_types)),
      explicitly_excluded_record_types: Enum.sort(MapSet.to_list(excluded_types)),
      missing_record_types: Enum.sort(MapSet.to_list(MapSet.difference(planned_types, covered_types))),
      extra_record_types: Enum.sort(MapSet.to_list(MapSet.difference(covered_types, planned_types)))
    }
  end

  @spec coverage_complete?() :: boolean()
  def coverage_complete? do
    coverage = planned_coverage()
    coverage.missing_record_types == [] and coverage.extra_record_types == []
  end

  @spec encode(atom(), map()) :: {:ok, map()} | {:error, term()}
  def encode(record_type, record) do
    with {:ok, codec} <- codec(record_type) do
      codec.encode(record)
    end
  end

  @spec decode(atom(), map()) :: {:ok, map()} | {:error, term()}
  def decode(record_type, projection) do
    with {:ok, codec} <- codec(record_type) do
      codec.decode(projection)
    end
  end
end
