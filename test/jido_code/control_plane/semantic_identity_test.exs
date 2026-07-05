defmodule JidoCode.ControlPlane.SemanticIdentityTest do
  use ExUnit.Case, async: true

  alias JidoCode.ControlPlane.SemanticIdentity

  @concrete_record_types [
    :managed_repo,
    :source_repo,
    :project,
    :intake,
    :external_object,
    :event,
    :observation,
    :assessment,
    :work_item,
    :run,
    :workflow_run,
    :execution_profile,
    :evidence,
    :change_request,
    :decision,
    :policy_set,
    :review_policy,
    :repo_posture,
    :posture_check,
    :conversation,
    :conversation_event,
    :conversation_snapshot,
    :execution_workflow,
    :sandbox_session,
    :runtime_event,
    :checkpoint,
    :exec_session,
    :sprite_spec,
    :user,
    :user_identity,
    :api_key,
    :token,
    :provider_config,
    :github_repo,
    :webhook_delivery,
    :issue_analysis,
    :secret_ref,
    :secret_lifecycle_audit,
    :system_config
  ]

  test "exposes a canonical template and ontology predicates for every concrete record type" do
    assert SemanticIdentity.record_types() == Enum.sort(@concrete_record_types)

    Enum.each(@concrete_record_types, fn record_type ->
      assert {:ok, template} = SemanticIdentity.template(record_type)
      assert String.starts_with?(template, "https://jido.run/control/")

      assert {:ok, class_iri} = SemanticIdentity.class_iri(record_type)
      assert to_string(class_iri) =~ "https://jido.run/ontology/control-plane#"

      assert {:ok, id_predicate_iri} = SemanticIdentity.id_predicate_iri(record_type)
      assert to_string(id_predicate_iri) =~ "https://jido.run/ontology/control-plane#"
    end)
  end

  test "builds product, legacy, repo-scoped, singleton, and external IRIs" do
    assert {:ok, "https://jido.run/control/managed-repos/repo-123"} =
             SemanticIdentity.canonical_iri(:managed_repo, "repo-123")

    assert {:ok, "https://jido.run/control/legacy/projects/project-123"} =
             SemanticIdentity.canonical_iri(:project, "project-123")

    assert {:ok, "https://jido.run/control/managed-repos/repo%201/runs/run%2F42"} =
             SemanticIdentity.canonical_iri(:run, %{managed_repo_id: "repo 1", id: "run/42"})

    assert {:ok, "https://jido.run/control/system-configs/singleton"} =
             SemanticIdentity.canonical_iri(:system_config, %{key: "singleton"})

    assert {:ok, "https://jido.run/control/external/github/github.com/issue/123"} =
             SemanticIdentity.canonical_iri(:external_object, %{
               provider: :github,
               provider_host: "github.com",
               object_type: :issue,
               external_id: 123
             })
  end

  test "rejects incomplete identity inputs with typed errors" do
    assert {:error, {:missing_identity_field, :managed_repo_id}} =
             SemanticIdentity.canonical_iri(:run, %{id: "run-123"})

    assert {:error, {:missing_identity_field, :provider_host}} =
             SemanticIdentity.canonical_iri(:external_object, %{
               provider: :github,
               object_type: :issue,
               external_id: 123
             })

    assert {:error, :unknown_record_type} = SemanticIdentity.template(:unknown)
  end

  test "documents current uniqueness contracts outside Ash metadata" do
    assert {:ok, source_repo_identity} =
             SemanticIdentity.identity_contract(:source_repo, :unique_provider_full_name)

    assert source_repo_identity.fields == [:provider, :full_name]
    assert source_repo_identity.mode == :unique_query

    assert {:ok, external_identity} =
             SemanticIdentity.identity_contract(:external_object, :unique_external_identity)

    assert external_identity.fields == [:provider, :provider_host, :object_type, :external_id]
    assert external_identity.mode == :external_identity

    assert {:ok, system_config_identity} = SemanticIdentity.identity_contract(:system_config, :unique_key)
    assert system_config_identity.mode == :singleton

    assert {:error, {:conflict, :source_repo, :unique_provider_full_name}} =
             SemanticIdentity.conflict_error(:source_repo, :unique_provider_full_name)
  end

  test "exposes idempotent upsert semantics by record family" do
    assert {:ok, :replace_singleton} = SemanticIdentity.upsert_strategy(:system_config)
    assert {:ok, :replace_by_natural_identity} = SemanticIdentity.upsert_strategy(:external_object)
    assert {:ok, :append_only} = SemanticIdentity.upsert_strategy(:secret_lifecycle_audit)
    assert {:ok, :compatibility_only} = SemanticIdentity.upsert_strategy(:workflow_run)
  end
end
