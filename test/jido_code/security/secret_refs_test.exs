defmodule JidoCode.Security.SecretRefsTest do
  use ExUnit.Case, async: false

  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.Security.{Encryption, SecretRefStore, SecretRefs}

  @valid_test_encryption_key "MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE="

  setup do
    setup_store!()

    original_key = Application.get_env(:jido_code, :secret_ref_encryption_key, :__missing__)

    original_rotation_validator =
      Application.get_env(:jido_code, :provider_credential_rotation_validator, :__missing__)

    original_audit_persister =
      Application.get_env(:jido_code, :secret_lifecycle_audit_persister, :__missing__)

    on_exit(fn ->
      restore_env(:secret_ref_encryption_key, original_key)
      restore_env(:provider_credential_rotation_validator, original_rotation_validator)
      restore_env(:secret_lifecycle_audit_persister, original_audit_persister)
    end)

    Application.put_env(:jido_code, :secret_ref_encryption_key, @valid_test_encryption_key)
    :ok
  end

  test "persist_operational_secret stores encrypted ciphertext and metadata remains queryable" do
    name = "github/webhook_secret_#{System.unique_integer([:positive])}"
    plaintext_value = "super-secret-#{System.unique_integer([:positive])}"

    assert {:ok, metadata} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: name,
               value: plaintext_value,
               source: :onboarding
             })

    assert {:ok, stored_secret_ref} = SecretRefStore.get_by_scope_name(:integration, name)
    assert stored_secret_ref.name == name
    assert stored_secret_ref.scope == :integration
    assert is_binary(stored_secret_ref.ciphertext)
    refute stored_secret_ref.ciphertext == plaintext_value
    assert %DateTime{} = stored_secret_ref.last_rotated_at

    assert {:ok, metadata_list} = SecretRefs.list_secret_metadata()
    metadata_id = metadata.id

    assert %{
             id: ^metadata_id,
             scope: :integration,
             name: ^name,
             source: :onboarding,
             key_version: 1
           } = Enum.find(metadata_list, &(&1.id == metadata_id))

    metadata_row = Enum.find(metadata_list, &(&1.id == metadata_id))
    assert %DateTime{} = metadata_row.last_rotated_at
    refute Map.has_key?(metadata_row, :ciphertext)
    refute Enum.any?(Map.values(metadata_row), &(&1 == plaintext_value))
  end

  test "secret lifecycle actions persist actor timestamp action target and outcome audit metadata" do
    name = "providers/audit_secret_#{System.unique_integer([:positive])}"
    actor = %{id: "owner-123", email: "owner@example.com"}

    assert {:ok, created_secret} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: name,
               value: "initial-secret-#{System.unique_integer([:positive])}",
               actor: actor
             })

    assert {:ok, _rotated_secret} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: name,
               value: "rotated-secret-#{System.unique_integer([:positive])}",
               actor: actor
             })

    assert {:ok, _revoked_secret} =
             SecretRefs.revoke_operational_secret(%{
               id: created_secret.id,
               actor: actor
             })

    assert {:ok, audits} = SecretRefs.list_secret_lifecycle_audits()

    create_audit =
      Enum.find(audits, fn audit ->
        audit.action_type == :create and audit.name == name and audit.scope == :integration
      end)

    rotate_audit =
      Enum.find(audits, fn audit ->
        audit.action_type == :rotate and audit.name == name and audit.scope == :integration
      end)

    revoke_audit =
      Enum.find(audits, fn audit ->
        audit.action_type == :revoke and audit.name == name and audit.scope == :integration
      end)

    for audit <- [create_audit, rotate_audit, revoke_audit] do
      assert audit.outcome_status == :succeeded
      assert audit.actor_id == actor.id
      assert audit.actor_email == actor.email
      assert %DateTime{} = audit.occurred_at
      assert audit.secret_ref_id == created_secret.id
    end
  end

  test "persist_operational_secret rotation increments key_version and refreshes last_rotated_at" do
    name = "github/rotation_secret_#{System.unique_integer([:positive])}"
    initial_last_rotated_at = ~U[2024-01-01 00:00:00Z]
    initial_value = "initial-secret-#{System.unique_integer([:positive])}"
    rotated_value = "rotated-secret-#{System.unique_integer([:positive])}"

    assert {:ok, initial_ciphertext} = Encryption.encrypt(initial_value)

    assert {:ok, initial_secret_ref} =
             SecretRefStore.upsert_secret_ref(%{
               scope: :integration,
               name: name,
               ciphertext: initial_ciphertext,
               key_version: 1,
               source: :onboarding,
               last_rotated_at: initial_last_rotated_at
             })

    assert {:ok, rotated_metadata} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: name,
               value: rotated_value
             })

    assert rotated_metadata.id == initial_secret_ref.id
    assert rotated_metadata.key_version == 2
    assert rotated_metadata.source == :rotation
    assert DateTime.compare(rotated_metadata.last_rotated_at, initial_last_rotated_at) == :gt

    assert {:ok, rotated_secret_ref} = SecretRefStore.get_by_scope_name(:integration, name)
    assert rotated_secret_ref.id == initial_secret_ref.id
    assert rotated_secret_ref.key_version == 2
    assert rotated_secret_ref.source == :rotation
    assert rotated_secret_ref.ciphertext != initial_ciphertext
    assert DateTime.compare(rotated_secret_ref.last_rotated_at, initial_last_rotated_at) == :gt
  end

  test "persist_operational_secret keeps prior secret active when rotation metadata write fails" do
    name = "github/rotation_overflow_#{System.unique_integer([:positive])}"
    initial_last_rotated_at = ~U[2024-01-01 00:00:00Z]
    max_bigint = 9_223_372_036_854_775_807
    initial_value = "overflow-initial-#{System.unique_integer([:positive])}"

    assert {:ok, initial_ciphertext} = Encryption.encrypt(initial_value)

    assert {:ok, initial_secret_ref} =
             SecretRefStore.upsert_secret_ref(%{
               scope: :integration,
               name: name,
               ciphertext: initial_ciphertext,
               key_version: max_bigint,
               source: :onboarding,
               last_rotated_at: initial_last_rotated_at
             })

    assert {:error, typed_error} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: name,
               value: "overflow-rotated-#{System.unique_integer([:positive])}"
             })

    assert typed_error.error_type == "secret_persistence_failed"
    assert typed_error.message == "Secret persistence failed and no secret was persisted."
    assert typed_error.recovery_instruction =~ "Retry the save."

    assert {:ok, persisted_secret_ref} = SecretRefStore.get_by_scope_name(:integration, name)
    assert persisted_secret_ref.id == initial_secret_ref.id
    assert persisted_secret_ref.ciphertext == initial_ciphertext
    assert persisted_secret_ref.source == :onboarding
    assert persisted_secret_ref.key_version == max_bigint
    assert DateTime.compare(persisted_secret_ref.last_rotated_at, initial_last_rotated_at) == :eq
  end

  test "persist_operational_secret treats audit persistence failure as failed and keeps prior state active" do
    name = "github/audit_failure_#{System.unique_integer([:positive])}"

    assert {:ok, initial_metadata} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: name,
               value: "initial-secret-#{System.unique_integer([:positive])}",
               source: :onboarding
             })

    assert {:ok, initial_secret_ref} = SecretRefStore.get_by_scope_name(:integration, name)

    Application.put_env(:jido_code, :secret_lifecycle_audit_persister, fn _attributes ->
      {:error, :forced_audit_failure}
    end)

    assert {:error, typed_error} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: name,
               value: "rotated-secret-#{System.unique_integer([:positive])}"
             })

    assert typed_error.error_type == "secret_audit_persistence_failed"

    assert {:ok, persisted_secret_ref} = SecretRefStore.get_by_scope_name(:integration, name)
    assert persisted_secret_ref.id == initial_metadata.id
    assert persisted_secret_ref.ciphertext == initial_secret_ref.ciphertext
    assert persisted_secret_ref.key_version == initial_secret_ref.key_version
  end

  test "persist_operational_secret blocks writes with typed remediation when encryption is unavailable" do
    Application.delete_env(:jido_code, :secret_ref_encryption_key)

    name = "github/encryption_missing_#{System.unique_integer([:positive])}"

    assert {:error, typed_error} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: name,
               value: "must-not-store"
             })

    assert typed_error.error_type == "secret_encryption_unavailable"
    assert typed_error.message == "Secret encryption is unavailable and no secret was persisted."
    assert typed_error.recovery_instruction =~ "JIDO_CODE_SECRET_REF_ENCRYPTION_KEY"

    assert {:ok, nil} = SecretRefStore.get_by_scope_name(:integration, name)
  end

  test "rotate_provider_credential swaps versions atomically while in-flight context keeps prior version" do
    provider_name = SecretRefs.provider_secret_ref_name(:anthropic)
    initial_value = "sk-ant-initial-#{System.unique_integer([:positive])}"
    rotated_value = "sk-ant-rotated-#{System.unique_integer([:positive])}"

    assert {:ok, _metadata} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: provider_name,
               value: initial_value,
               source: :onboarding
             })

    assert {:ok, in_flight_context} = SecretRefs.provider_credential_context(:anthropic)

    Application.put_env(:jido_code, :provider_credential_rotation_validator, fn
      %{stage: :before} ->
        {:ok, "Existing credential context validated."}

      %{stage: :after} ->
        {:ok, "Rotated credential validated."}
    end)

    assert {:ok, rotation_report} =
             SecretRefs.rotate_provider_credential(%{
               provider: :anthropic,
               value: rotated_value
             })

    assert rotation_report.before.key_version == in_flight_context.key_version
    assert rotation_report.after.key_version == in_flight_context.key_version + 1
    assert rotation_report.before.verification.status == :passed
    assert rotation_report.after.verification.status == :passed
    assert rotation_report.rollback_performed == false
    assert rotation_report.continuity_alarm == false

    assert {:ok, new_context} = SecretRefs.provider_credential_context(:anthropic)
    assert new_context.key_version == in_flight_context.key_version + 1
    assert new_context.ciphertext != in_flight_context.ciphertext
    assert in_flight_context.key_version == 1
  end

  test "rotate_provider_credential rolls references back when post-rotation validation fails" do
    provider_name = SecretRefs.provider_secret_ref_name(:openai)
    initial_value = "sk-initial-#{System.unique_integer([:positive])}"
    rotated_value = "sk-rotated-#{System.unique_integer([:positive])}"

    assert {:ok, _metadata} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: provider_name,
               value: initial_value,
               source: :onboarding
             })

    assert {:ok, context_before_rotation} = SecretRefs.provider_credential_context(:openai)

    Application.put_env(:jido_code, :provider_credential_rotation_validator, fn
      %{stage: :before} ->
        {:ok, "Existing credential context validated."}

      %{stage: :after} ->
        {:error, :provider_health_check_failed}
    end)

    assert {:error, typed_error} =
             SecretRefs.rotate_provider_credential(%{
               provider: :openai,
               value: rotated_value
             })

    assert typed_error.error_type == "provider_rotation_validation_failed"
    assert typed_error.message =~ "rolled back to the prior version"
    assert typed_error.recovery_instruction =~ "rolled back"
    assert typed_error.rotation_report.rollback_performed == true
    assert typed_error.rotation_report.before.verification.status == :passed
    assert typed_error.rotation_report.after.verification.status == :failed
    assert typed_error.rotation_report.continuity_alarm == false

    assert {:ok, context_after_rotation} = SecretRefs.provider_credential_context(:openai)
    assert context_after_rotation.key_version == context_before_rotation.key_version
    assert context_after_rotation.ciphertext == context_before_rotation.ciphertext
    assert context_after_rotation.source == context_before_rotation.source
  end

  test "rotate_provider_credential treats audit persistence failure as failed and keeps prior credential active" do
    provider_name = SecretRefs.provider_secret_ref_name(:anthropic)
    initial_value = "sk-ant-initial-#{System.unique_integer([:positive])}"
    rotated_value = "sk-ant-rotated-#{System.unique_integer([:positive])}"

    assert {:ok, _metadata} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: provider_name,
               value: initial_value,
               source: :onboarding
             })

    assert {:ok, context_before_rotation} = SecretRefs.provider_credential_context(:anthropic)

    Application.put_env(:jido_code, :provider_credential_rotation_validator, fn
      %{stage: :before} -> {:ok, "Existing credential context validated."}
      %{stage: :after} -> {:ok, "Rotated credential validated."}
    end)

    Application.put_env(:jido_code, :secret_lifecycle_audit_persister, fn _attributes ->
      {:error, :forced_audit_failure}
    end)

    assert {:error, typed_error} =
             SecretRefs.rotate_provider_credential(%{
               provider: :anthropic,
               value: rotated_value
             })

    assert typed_error.error_type == "secret_audit_persistence_failed"

    assert {:ok, context_after_rotation} = SecretRefs.provider_credential_context(:anthropic)
    assert context_after_rotation.key_version == context_before_rotation.key_version
    assert context_after_rotation.ciphertext == context_before_rotation.ciphertext
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)

  defp setup_store! do
    store_name = :"secret_refs_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_secret_refs/#{store_name}")

    start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    original = Application.get_env(:jido_code, :control_plane_product_store_server, :__missing__)
    Application.put_env(:jido_code, :control_plane_product_store_server, store_name)

    on_exit(fn ->
      restore_env(:control_plane_product_store_server, original)
      File.rm_rf!(path)
    end)

    :ok
  end
end
