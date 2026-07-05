defmodule JidoCode.ControlPlane.Validation do
  @moduledoc """
  Product-owned command validation for control-plane records.
  """

  alias JidoCode.ControlPlane.SemanticIdentity
  alias JidoCode.ControlPlane.Store.Errors.ValidationError
  alias JidoCode.ControlPlane.Validation.Validator

  @record_families %{
    system_config: :setup,
    provider_config: :setup,
    managed_repo: :control,
    source_repo: :control,
    project: :control,
    intake: :control,
    external_object: :control,
    observation: :operations,
    assessment: :operations,
    repo_posture: :operations,
    posture_check: :operations,
    work_item: :operations,
    evidence: :operations,
    change_request: :governance,
    decision: :governance,
    policy_set: :governance,
    review_policy: :governance,
    run: :orchestration,
    workflow_run: :orchestration,
    execution_profile: :orchestration,
    conversation: :conversations,
    conversation_event: :conversations,
    conversation_snapshot: :conversations,
    execution_workflow: :execution_runtime,
    sandbox_session: :execution_runtime,
    runtime_event: :execution_runtime,
    checkpoint: :execution_runtime,
    exec_session: :execution_runtime,
    sprite_spec: :execution_runtime,
    user: :auth,
    user_identity: :auth,
    api_key: :auth,
    token: :auth,
    github_repo: :control,
    webhook_delivery: :control,
    issue_analysis: :control,
    secret_ref: :security,
    secret_lifecycle_audit: :security,
    event: :control_events
  }

  @spec record_families() :: %{atom() => atom()}
  def record_families, do: @record_families

  @spec record_family(atom()) :: {:ok, atom()} | {:error, :unknown_record_type}
  def record_family(record_type) when is_atom(record_type) do
    case Map.fetch(@record_families, record_type) do
      {:ok, family} -> {:ok, family}
      :error -> {:error, :unknown_record_type}
    end
  end

  def record_family(_record_type), do: {:error, :unknown_record_type}

  @spec family_coverage() :: map()
  def family_coverage do
    planned = SemanticIdentity.record_types() |> MapSet.new()
    covered = @record_families |> Map.keys() |> MapSet.new()

    %{
      missing_record_types: planned |> MapSet.difference(covered) |> MapSet.to_list() |> Enum.sort(),
      extra_record_types: covered |> MapSet.difference(planned) |> MapSet.to_list() |> Enum.sort()
    }
  end

  @spec validate(atom(), map(), keyword()) :: :ok | {:error, ValidationError.t()}
  def validate(record_type, record, opts \\ [])

  def validate(record_type, record, opts) when is_map(record) do
    with {:ok, family} <- record_family(record_type),
         {:ok, spec} <- SemanticIdentity.record_spec(record_type) do
      errors =
        []
        |> Kernel.++(validate_id(record, spec))
        |> Kernel.++(validate_scope(spec, record))
        |> Kernel.++(validate_family(family, record_type, record, opts))
        |> Kernel.++(Validator.datetime_field(record, :updated_at))
        |> Kernel.++(Validator.map_field(record, :metadata))

      case errors do
        [] ->
          :ok

        errors ->
          {:error,
           ValidationError.exception(
             stage: :validate_record,
             field: nil,
             reason: :invalid_record,
             errors: errors
           )}
      end
    else
      {:error, reason} ->
        {:error,
         ValidationError.exception(
           stage: :validate_record,
           field: :record_type,
           reason: reason,
           errors: [%{field: :record_type, reason: reason}]
         )}
    end
  end

  def validate(record_type, _record, _opts) do
    {:error,
     ValidationError.exception(
       stage: :validate_record,
       field: :record,
       reason: :invalid_record,
       errors: [%{field: :record, reason: :invalid_record, record_type: record_type}]
     )}
  end

  defp validate_id(record, spec) do
    fields = [spec.id_field, Macro.underscore(spec.id_predicate), spec.id_predicate, :id, "id"]
    Validator.required_string(record, fields)
  end

  defp validate_scope(%{scope: :repo_scoped}, record) do
    Validator.relationship_field(record, [:managed_repo_id, "managed_repo_id", "managedRepoId"])
  end

  defp validate_scope(_spec, _record), do: []

  defp validate_family(:setup, :system_config, record, _opts) do
    Validator.required_string(record, [:key, "key"])
  end

  defp validate_family(:setup, _record_type, record, _opts) do
    Validator.required_string(record, [:provider, "provider"])
  end

  defp validate_family(:auth, :user, record, _opts) do
    Validator.required_string(record, [:email, "email"])
  end

  defp validate_family(:auth, _record_type, _record, _opts), do: []

  defp validate_family(:security, :secret_ref, record, _opts) do
    Validator.required_string(record, [:scope, "scope"]) ++ Validator.required_string(record, [:name, "name"])
  end

  defp validate_family(:security, _record_type, _record, _opts), do: []
  defp validate_family(_family, _record_type, _record, _opts), do: []
end
