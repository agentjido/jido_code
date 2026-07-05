defmodule JidoCode.ControlPlane.ValidationPolicyTest do
  use ExUnit.Case, async: true

  alias JidoCode.ControlPlane.Policy
  alias JidoCode.ControlPlane.Store.Errors.ValidationError
  alias JidoCode.ControlPlane.Validation
  alias JidoCode.ControlPlane.Validation.Validator

  test "reusable validators return structured field errors" do
    record = %{
      status: "paused",
      metadata: %{source: "test"},
      updated_at: "2026-01-01T00:00:00Z",
      managed_repo_id: "repo-1"
    }

    assert [] = Validator.required_string(record, :managed_repo_id)
    assert [%{field: :missing, reason: :required, detail: nil}] = Validator.required_string(record, :missing)
    assert [] = Validator.atom_enum(record, :status, [:queued, :paused])

    assert [%{field: :status, reason: :invalid_enum, detail: [:queued]}] =
             Validator.atom_enum(%{status: "bad"}, :status, [:queued])

    assert [] = Validator.map_field(record, :metadata)
    assert [] = Validator.datetime_field(record, :updated_at)
    assert [] = Validator.relationship_field(record, :managed_repo_id)
  end

  test "record family coverage accounts for every semantic identity type" do
    coverage = Validation.family_coverage()

    assert coverage.missing_record_types == []
    assert coverage.extra_record_types == []
    assert {:ok, :setup} = Validation.record_family(:system_config)
    assert {:ok, :control} = Validation.record_family(:managed_repo)
    assert {:ok, :operations} = Validation.record_family(:work_item)
    assert {:ok, :governance} = Validation.record_family(:decision)
    assert {:ok, :orchestration} = Validation.record_family(:run)
    assert {:ok, :conversations} = Validation.record_family(:conversation)
    assert {:ok, :execution_runtime} = Validation.record_family(:runtime_event)
    assert {:ok, :auth} = Validation.record_family(:user)
    assert {:ok, :security} = Validation.record_family(:secret_ref)
  end

  test "record validation returns LiveView and workflow friendly errors" do
    assert :ok =
             Validation.validate(:managed_repo, %{
               managed_repo_id: "repo-1",
               updated_at: ~U[2026-01-01 00:00:00Z],
               metadata: %{source: "test"}
             })

    assert {:error, %ValidationError{} = error} =
             Validation.validate(:work_item, %{
               work_item_id: "work-1",
               title: "Missing relationship",
               updated_at: "not-a-date",
               metadata: "bad"
             })

    assert %{field: :managed_repo_id, reason: :required, detail: nil} in error.errors
    assert %{field: :updated_at, reason: :invalid_datetime, detail: nil} in error.errors
    assert %{field: :metadata, reason: :invalid_map, detail: nil} in error.errors

    assert {:error, %ValidationError{errors: secret_errors}} =
             Validation.validate(:secret_ref, %{secret_ref_id: "secret-1"})

    assert %{field: :scope, reason: :required, detail: nil} in secret_errors
    assert %{field: :name, reason: :required, detail: nil} in secret_errors
  end

  test "policy exposes actor contexts and authorizes read and mutation paths" do
    system = Policy.system_actor()
    admin = Policy.human_operator("user:admin", [:admin])
    operator = Policy.human_operator("user:operator", [:operator])
    viewer = Policy.human_operator("user:viewer", [:viewer])
    machine = Policy.machine_actor("machine:events", [:event_writer])
    setup = Policy.setup_bootstrap()

    assert Policy.authorize_mutation(:upsert, :secret_ref, system).allowed?
    assert Policy.authorize_mutation(:upsert, :secret_ref, admin).allowed?
    assert Policy.authorize_read(:managed_repo, viewer).allowed?
    assert Policy.authorize_mutation(:upsert, :work_item, operator).allowed?
    assert Policy.authorize_mutation(:append_event, :event, machine).allowed?
    assert Policy.authorize_mutation(:upsert, :system_config, setup).allowed?

    refute Policy.authorize_mutation(:upsert, :secret_ref, operator).allowed?
    refute Policy.authorize_mutation(:delete, :managed_repo, viewer).allowed?
  end

  test "policy decisions include audit metadata for allow and deny outcomes" do
    operator = Policy.human_operator("user:operator", [:operator])

    allowed = Policy.authorize_mutation(:upsert, :work_item, operator)
    denied = Policy.authorize_mutation(:upsert, :secret_ref, operator)

    assert allowed.metadata.audit.operation == :upsert
    assert allowed.metadata.audit.record_type == :work_item
    assert allowed.metadata.audit.actor_id == "user:operator"
    assert allowed.metadata.audit.decision == :allow
    assert %DateTime{} = allowed.metadata.audit.decided_at

    assert denied.reason == :missing_human_operator_scope
    assert denied.metadata.audit.decision == {:deny, :missing_human_operator_scope}
    assert denied.metadata.audit.record_type == :secret_ref
  end
end
