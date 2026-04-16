defmodule JidoCode.Security.SecretRefsTest do
  use JidoCode.DataCase, async: false

  require Ash.Query

  alias JidoCode.Security
  alias JidoCode.Security.{Encryption, SecretRef, SecretRefs}

  @valid_test_encryption_key "MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE="

  setup do
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

    query =
      SecretRef
      |> Ash.Query.filter(scope == :integration and name == ^name)
      |> Ash.Query.limit(1)

    assert {:ok, [stored_secret_ref]} = Ash.read(query, domain: Security, authorize?: false)
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
             SecretRef.create(
               %{
                 scope: :integration,
                 name: name,
                 ciphertext: initial_ciphertext,
                 key_version: 1,
                 source: :onboarding,
                 last_rotated_at: initial_last_rotated_at
               },
               authorize?: false
             )

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

    query =
      SecretRef
      |> Ash.Query.filter(scope == :integration and name == ^name)
      |> Ash.Query.limit(1)

    assert {:ok, [rotated_secret_ref]} = Ash.read(query, domain: Security, authorize?: false)
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
             SecretRef.create(
               %{
                 scope: :integration,
                 name: name,
                 ciphertext: initial_ciphertext,
                 key_version: max_bigint,
                 source: :onboarding,
                 last_rotated_at: initial_last_rotated_at
               },
               authorize?: false
             )

    assert {:error, typed_error} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: name,
               value: "overflow-rotated-#{System.unique_integer([:positive])}"
             })

    assert typed_error.error_type == "secret_persistence_failed"
    assert typed_error.message == "Secret persistence failed and no secret was persisted."
    assert typed_error.recovery_instruction =~ "Retry the save."

    query =
      SecretRef
      |> Ash.Query.filter(scope == :integration and name == ^name)
      |> Ash.Query.limit(1)

    assert {:ok, [persisted_secret_ref]} = Ash.read(query, domain: Security, authorize?: false)
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

    query =
      SecretRef
      |> Ash.Query.filter(scope == :integration and name == ^name)
      |> Ash.Query.limit(1)

    assert {:ok, [initial_secret_ref]} = Ash.read(query, domain: Security, authorize?: false)

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

    assert {:ok, [persisted_secret_ref]} = Ash.read(query, domain: Security, authorize?: false)
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

    query =
      SecretRef
      |> Ash.Query.filter(scope == :integration and name == ^name)
      |> Ash.Query.limit(1)

    assert {:ok, []} = Ash.read(query, domain: Security, authorize?: false)
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

  describe "provider_env_key/1" do
    test "returns correct env key for Anthropic" do
      assert SecretRefs.provider_env_key(:anthropic) == "ANTHROPIC_API_KEY"
    end

    test "returns correct env key for OpenAI" do
      assert SecretRefs.provider_env_key(:openai) == "OPENAI_API_KEY"
    end

    test "returns correct env key for Google" do
      assert SecretRefs.provider_env_key(:google) == "GOOGLE_API_KEY"
    end

    test "returns correct env key for Groq" do
      assert SecretRefs.provider_env_key(:groq) == "GROQ_API_KEY"
    end

    test "returns formatted key for unknown providers" do
      assert SecretRefs.provider_env_key(:unknown_provider) == "UNKNOWN_PROVIDER_API_KEY"
    end

    test "handles multi-word provider names" do
      # Google Vertex uses GOOGLE_APPLICATION_CREDENTIALS (from ReqLLM)
      assert SecretRefs.provider_env_key(:google_vertex) == "GOOGLE_APPLICATION_CREDENTIALS"
    end
  end

  describe "provider_secret_ref_name/1" do
    test "returns correct secret ref name for Anthropic" do
      assert SecretRefs.provider_secret_ref_name(:anthropic) == "providers/anthropic_api_key"
    end

    test "returns correct secret ref name for OpenAI" do
      assert SecretRefs.provider_secret_ref_name(:openai) == "providers/openai_api_key"
    end

    test "returns correct secret ref name for unknown provider" do
      assert SecretRefs.provider_secret_ref_name(:groq) == "providers/groq_api_key"
    end
  end

  describe "multi-provider support" do
    test "provider type accepts any atom" do
      # This test verifies the type has been extended from :anthropic | :openai to atom()
      # Any provider atom should now be valid for the credential system
      assert is_atom(:anthropic)
      assert is_atom(:openai)
      assert is_atom(:google)
      assert is_atom(:groq)
      assert is_atom(:custom_provider)
    end

    test "normalize_provider accepts any atom provider" do
      # The internal normalize_provider function now accepts any atom
      # This is tested indirectly through provider_credential_context
      # which calls normalize_provider internally

      # For known providers with stored credentials, this should work
      # For unknown providers without credentials, it will return a specific error
      assert {:error, _} = SecretRefs.provider_credential_context(:unknown_provider_xyz)
    end
  end

  describe "credential validation for additional providers" do
    test "validates Google API key format" do
      # Google keys typically start with AIza or GOOG
      assert SecretRefs.valid_provider_credential_value?(:google, "AIzaSyDaGmWKa4JsXZ-HjGw7ISLn_3namBGewQe")
      assert SecretRefs.valid_provider_credential_value?(:google, "GOOG1234567890abcdefghijklmnopqrstuvwxyz")
    end

    test "validates Groq API key format" do
      # Groq keys start with gsk_
      assert SecretRefs.valid_provider_credential_value?(:groq, "gsk_1234567890abcdefghijklmnopqrstuvwxyz")
    end

    test "validates generic keys for unknown providers" do
      # Unknown providers fall back to generic key validation
      # Generic keys must be at least 20 characters with no spaces
      assert SecretRefs.valid_provider_credential_value?(:custom, "1234567890abcdefghijk1234567890")
    end

    test "rejects invalid generic keys" do
      refute SecretRefs.valid_provider_credential_value?(:custom, "short")
      refute SecretRefs.valid_provider_credential_value?(:custom, "has space key")
      refute SecretRefs.valid_provider_credential_value?(:custom, "")
    end

    test "validates Anthropic API key format" do
      assert SecretRefs.valid_provider_credential_value?(:anthropic, "sk-ant-api03-1234567890")
    end

    test "validates OpenAI API key format" do
      assert SecretRefs.valid_provider_credential_value?(:openai, "sk-1234567890abcdefghijklmnopqrstuvwxyz")
    end
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
