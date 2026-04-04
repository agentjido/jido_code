defmodule JidoCode.Orchestration.Run do
  # covers: architecture.execution_pipeline.run_is_projection_of_workflow_state
  # covers: architecture.execution_pipeline.governed_run_interfaces_hide_workflow_state
  # covers: architecture.run_governance.run_is_preferred_execution_record
  # covers: architecture.run_governance.execution_projection_stays_internal_to_canonical_run_model
  # covers: architecture.run_governance.run_launch_resolves_effective_execution_profile
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Orchestration,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Control.{Actor, Checks.ActorClassIn}
  alias JidoCode.Orchestration.WorkflowRun

  @approval_action_error_type "workflow_run_approval_action_failed"
  @retry_action_error_type "workflow_run_retry_action_failed"

  @statuses [:pending, :running, :awaiting_approval, :completed, :failed, :cancelled]

  postgres do
    table "runs"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :upsert_projection, action: :upsert_projection
    define :get_by_workflow_run_id, action: :read, get_by: [:workflow_run_id]
    define :get_by_managed_repo_and_run_id, action: :read, get_by: [:managed_repo_id, :run_id]
  end

  actions do
    defaults [:destroy]

    create :create do
      primary? true

      accept [
        :workflow_run_id,
        :managed_repo_id,
        :work_item_id,
        :execution_profile_id,
        :legacy_project_id,
        :run_id,
        :workflow_name,
        :workflow_version,
        :status,
        :current_step,
        :current_stage,
        :governed_stages,
        :stage_statuses,
        :trigger,
        :inputs,
        :input_metadata,
        :initiating_actor,
        :execution_engine,
        :workflow_state_ref,
        :run_metadata,
        :retry_of_run_id,
        :retry_attempt,
        :retry_lineage,
        :started_at,
        :completed_at
      ]

      change &normalize_projection_defaults/2
    end

    create :upsert_projection do
      accept [
        :workflow_run_id,
        :managed_repo_id,
        :work_item_id,
        :execution_profile_id,
        :legacy_project_id,
        :run_id,
        :workflow_name,
        :workflow_version,
        :status,
        :current_step,
        :current_stage,
        :governed_stages,
        :stage_statuses,
        :trigger,
        :inputs,
        :input_metadata,
        :initiating_actor,
        :execution_engine,
        :workflow_state_ref,
        :run_metadata,
        :retry_of_run_id,
        :retry_attempt,
        :retry_lineage,
        :started_at,
        :completed_at
      ]

      upsert? true
      upsert_identity :unique_workflow_run

      upsert_fields [
        :managed_repo_id,
        :work_item_id,
        :execution_profile_id,
        :legacy_project_id,
        :run_id,
        :workflow_name,
        :workflow_version,
        :status,
        :current_step,
        :current_stage,
        :governed_stages,
        :stage_statuses,
        :trigger,
        :inputs,
        :input_metadata,
        :initiating_actor,
        :execution_engine,
        :workflow_state_ref,
        :run_metadata,
        :retry_of_run_id,
        :retry_attempt,
        :retry_lineage,
        :started_at,
        :completed_at
      ]

      change &normalize_projection_defaults/2
    end

    read :read do
      primary? true
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {ActorClassIn,
                    classes: [
                      :admin,
                      :operator,
                      :factory_system,
                      :managed_repo_orchestrator,
                      :run_worker
                    ]}
    end

    policy action_type(:create) do
      authorize_if {ActorClassIn,
                    classes: [
                      :admin,
                      :operator,
                      :factory_system,
                      :managed_repo_orchestrator,
                      :run_worker
                    ]}
    end

    policy action_type(:destroy) do
      authorize_if {ActorClassIn, classes: [:admin, :factory_system, :managed_repo_orchestrator]}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :legacy_project_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :run_id, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :workflow_name, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :workflow_version, :integer do
      allow_nil? false
      constraints min: 1
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :pending
      constraints one_of: @statuses
      public? true
    end

    attribute :current_step, :string do
      allow_nil? false
      default "unknown"
      public? true
    end

    attribute :current_stage, :string do
      allow_nil? false
      default "repo_attach"
      public? true
    end

    attribute :governed_stages, {:array, :string} do
      allow_nil? false
      default JidoCode.Orchestration.ExecutionProfile.default_governed_stages()
      public? true
    end

    attribute :stage_statuses, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :trigger, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :inputs, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :input_metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :initiating_actor, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :execution_engine, :string do
      allow_nil? false
      default "jido_runic"
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :workflow_state_ref, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :run_metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :work_item_id, :uuid do
      allow_nil? true
      public? true
    end

    attribute :retry_of_run_id, :string do
      allow_nil? true
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :retry_attempt, :integer do
      allow_nil? false
      default 1
      constraints min: 1
      public? true
    end

    attribute :retry_lineage, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :started_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :completed_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :workflow_run, JidoCode.Orchestration.WorkflowRun do
      allow_nil? false
      public? true
      attribute_type :uuid
    end

    belongs_to :managed_repo, JidoCode.Control.ManagedRepo do
      allow_nil? false
      public? true
      attribute_type :uuid
    end

    belongs_to :execution_profile, JidoCode.Orchestration.ExecutionProfile do
      allow_nil? true
      public? true
      attribute_type :uuid
    end
  end

  identities do
    identity :unique_workflow_run, [:workflow_run_id]
    identity :unique_managed_repo_run_id, [:managed_repo_id, :run_id]
  end

  @spec approve(t(), map() | nil) :: {:ok, t()} | {:error, map()}
  def approve(run, params \\ nil)

  def approve(run, params) do
    if run_record?(run) do
      params = normalize_params(params)

      with {:ok, workflow_run} <- workflow_run_for_action(run, @approval_action_error_type),
           {:ok, %WorkflowRun{} = updated_workflow_run} <- WorkflowRun.approve(workflow_run, params),
           {:ok, updated_run} <-
             refresh_projected_run(updated_workflow_run, params, @approval_action_error_type) do
        {:ok, updated_run}
      end
    else
      {:error,
       action_failure(
         @approval_action_error_type,
         "Governed run reference is invalid and cannot be approved.",
         "Reload run detail and retry approval."
       )}
    end
  end

  @spec reject(t(), map() | nil) :: {:ok, t()} | {:error, map()}
  def reject(run, params \\ nil)

  def reject(run, params) do
    if run_record?(run) do
      params = normalize_params(params)

      with {:ok, workflow_run} <- workflow_run_for_action(run, @approval_action_error_type),
           {:ok, %WorkflowRun{} = updated_workflow_run} <- WorkflowRun.reject(workflow_run, params),
           {:ok, updated_run} <-
             refresh_projected_run(updated_workflow_run, params, @approval_action_error_type) do
        {:ok, updated_run}
      end
    else
      {:error,
       action_failure(
         @approval_action_error_type,
         "Governed run reference is invalid and cannot be rejected.",
         "Reload run detail and retry rejection."
       )}
    end
  end

  @spec retry(t(), map() | nil) :: {:ok, t()} | {:error, map()}
  def retry(run, params \\ nil)

  def retry(run, params) do
    if run_record?(run) do
      params = normalize_params(params)

      with {:ok, workflow_run} <- workflow_run_for_action(run, @retry_action_error_type),
           {:ok, %WorkflowRun{} = retried_workflow_run} <- WorkflowRun.retry(workflow_run, params),
           {:ok, retried_run} <-
             refresh_projected_run(retried_workflow_run, params, @retry_action_error_type) do
        {:ok, retried_run}
      end
    else
      {:error,
       action_failure(
         @retry_action_error_type,
         "Governed run reference is invalid and cannot be retried.",
         "Reload run detail and retry once the failed run is available."
       )}
    end
  end

  @spec step_retry_contract(t()) :: {:ok, map()} | {:error, map()}
  def step_retry_contract(run)

  def step_retry_contract(run) do
    if run_record?(run) do
      with {:ok, workflow_run} <- workflow_run_for_action(run, @retry_action_error_type) do
        WorkflowRun.step_retry_contract(workflow_run)
      end
    else
      {:error,
       action_failure(
         @retry_action_error_type,
         "Governed run reference is invalid and step-level retry is unavailable.",
         "Reload run detail and retry once the failed run is available."
       )}
    end
  end

  @spec retry_step(t(), map() | nil) :: {:ok, t()} | {:error, map()}
  def retry_step(run, params \\ nil)

  def retry_step(run, params) do
    if run_record?(run) do
      params = normalize_params(params)

      with {:ok, workflow_run} <- workflow_run_for_action(run, @retry_action_error_type),
           {:ok, %WorkflowRun{} = retried_workflow_run} <- WorkflowRun.retry_step(workflow_run, params),
           {:ok, retried_run} <-
             refresh_projected_run(retried_workflow_run, params, @retry_action_error_type) do
        {:ok, retried_run}
      end
    else
      {:error,
       action_failure(
         @retry_action_error_type,
         "Governed run reference is invalid and step-level retry cannot start.",
         "Reload run detail and retry once the failed run is available."
       )}
    end
  end

  defp normalize_projection_defaults(changeset, _context) do
    current_step =
      changeset
      |> Ash.Changeset.get_attribute(:current_step)
      |> normalize_string("unknown")

    governed_stages =
      changeset
      |> Ash.Changeset.get_attribute(:governed_stages)
      |> normalize_string_list(JidoCode.Orchestration.ExecutionProfile.default_governed_stages())

    current_stage =
      changeset
      |> Ash.Changeset.get_attribute(:current_stage)
      |> normalize_string(List.first(governed_stages) || "repo_attach")

    stage_statuses =
      changeset
      |> Ash.Changeset.get_attribute(:stage_statuses)
      |> normalize_map()

    changeset
    |> Ash.Changeset.force_change_attribute(:current_step, current_step)
    |> Ash.Changeset.force_change_attribute(:current_stage, current_stage)
    |> Ash.Changeset.force_change_attribute(:governed_stages, governed_stages)
    |> Ash.Changeset.force_change_attribute(:stage_statuses, stage_statuses)
    |> Ash.Changeset.force_change_attribute(
      :trigger,
      changeset |> Ash.Changeset.get_attribute(:trigger) |> normalize_map()
    )
    |> Ash.Changeset.force_change_attribute(
      :inputs,
      changeset |> Ash.Changeset.get_attribute(:inputs) |> normalize_map()
    )
    |> Ash.Changeset.force_change_attribute(
      :input_metadata,
      changeset |> Ash.Changeset.get_attribute(:input_metadata) |> normalize_map()
    )
    |> Ash.Changeset.force_change_attribute(
      :initiating_actor,
      changeset |> Ash.Changeset.get_attribute(:initiating_actor) |> normalize_map()
    )
    |> Ash.Changeset.force_change_attribute(
      :workflow_state_ref,
      changeset |> Ash.Changeset.get_attribute(:workflow_state_ref) |> normalize_map()
    )
    |> Ash.Changeset.force_change_attribute(
      :run_metadata,
      changeset |> Ash.Changeset.get_attribute(:run_metadata) |> normalize_map()
    )
  end

  defp workflow_run_for_action(run, error_type) when is_binary(error_type) do
    workflow_run_id =
      run
      |> Map.get(:workflow_run_id)
      |> normalize_optional_string()

    if is_nil(workflow_run_id) do
      {:error,
       action_failure(
         error_type,
         "Governed run is missing workflow audit state and cannot perform this action.",
         "Refresh run projections and retry from run detail."
       )}
    else
      case WorkflowRun.read(query: [filter: [id: workflow_run_id], limit: 1], actor: Actor.operator_actor()) do
        {:ok, [%WorkflowRun{} = workflow_run | _rest]} ->
          {:ok, workflow_run}

        {:ok, []} ->
          {:error,
           action_failure(
             error_type,
             "Underlying workflow audit state is unavailable for this governed run.",
             "Refresh run projections and retry from run detail."
           )}

        {:error, reason} ->
          {:error,
           action_failure(
             error_type,
             "Underlying workflow audit state could not be loaded (#{format_reason(reason)}).",
             "Refresh run projections and retry from run detail."
           )}
      end
    end
  end

  defp refresh_projected_run(%WorkflowRun{id: workflow_run_id}, params, error_type) do
    actor =
      params
      |> Map.get("actor")
      |> Actor.effective_actor()
      |> case do
        nil -> Actor.operator_actor()
        resolved_actor -> resolved_actor
      end

    case get_by_workflow_run_id(workflow_run_id, actor: actor) do
      {:ok, run} when is_map(run) ->
        {:ok, run}

      {:ok, nil} ->
        {:error,
         action_failure(
           error_type,
           "Governed run projection is unavailable after workflow state changed.",
           "Refresh run projections and retry from run detail."
         )}

      {:error, reason} ->
        {:error,
         action_failure(
           error_type,
           "Governed run projection could not be refreshed (#{format_reason(reason)}).",
           "Refresh run projections and retry from run detail."
         )}
    end
  end

  defp run_record?(%{__struct__: module}) when module == __MODULE__, do: true
  defp run_record?(_run), do: false

  defp normalize_params(params) when is_map(params), do: normalize_map(params)
  defp normalize_params(_params), do: %{}

  defp action_failure(error_type, detail, remediation) do
    %{
      error_type: error_type,
      detail: detail,
      remediation: remediation
    }
  end

  defp normalize_string(value, default) do
    case normalize_optional_string(value) do
      nil -> default
      normalized -> normalized
    end
  end

  defp normalize_string_list(value, default) when is_list(value) do
    normalized =
      value
      |> Enum.map(&normalize_optional_string/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if normalized == [], do: default, else: normalized
  end

  defp normalize_string_list(_value, default), do: default

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

  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

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

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)
end
