defmodule JidoCode.ControlPlane.StoreContractIntegrationTest do
  use ExUnit.Case, async: true

  alias JidoCode.ControlPlane.Codecs.Registry
  alias JidoCode.ControlPlane.{EmbeddedStore, FakeStore, Policy, StoreServer}
  alias JidoCode.ControlPlane.Store.{AuthorizationContext, Request}
  alias JidoCode.ControlPlane.Store.Errors.{NotFoundError, UnauthorizedError, ValidationError}

  @representative_records %{
    setup: {:system_config, %{key: "owner", display_name: "Owner setup", metadata: %{source: "test"}}},
    control: {:managed_repo, %{managed_repo_id: "repo-family", source_key: "repo:family"}},
    operations: {:work_item, %{managed_repo_id: "repo-family", work_item_id: "work-family", title: "Family work"}},
    governance:
      {:decision, %{managed_repo_id: "repo-family", decision_id: "decision-family", source_key: "decision:family"}},
    orchestration:
      {:run,
       %{
         managed_repo_id: "repo-family",
         run_record_id: "run-family",
         run_id: "source-run-family",
         source_key: "run:family"
       }},
    conversations: {:conversation, %{managed_repo_id: "repo-family", conversation_id: "conversation-family"}},
    execution_runtime:
      {:runtime_event,
       %{managed_repo_id: "repo-family", runtime_event_id: "runtime-event-family", source_kind: "runner"}},
    auth: {:user, %{user_id: "user-family", email: "operator@example.com"}},
    security: {:secret_ref, %{secret_ref_id: "secret-family", scope: "integration", name: "token"}},
    control_events:
      {:event,
       %{
         managed_repo_id: "repo-family",
         event_id: "event-family",
         source_kind: "test",
         occurred_at: ~U[2026-01-01 00:00:00Z]
       }}
  }

  test "representative product families round-trip through codecs without leaking secret fields" do
    Enum.each(@representative_records, fn {family, {record_type, record}} ->
      assert {:ok, encoded} = Registry.encode(record_type, record)
      assert encoded.triples != []
      assert encoded.subject_iri =~ "https://jido.run/control"

      projection = projection_from_encoded(encoded)
      assert {:ok, decoded} = Registry.decode(record_type, projection)
      assert decoded.record_type == record_type
      assert decoded.subject_iri == encoded.subject_iri

      assert family in [
               :setup,
               :control,
               :operations,
               :governance,
               :orchestration,
               :conversations,
               :execution_runtime,
               :auth,
               :security,
               :control_events
             ]
    end)

    assert {:error, {:sensitive_field_not_projectable, :api_key_hash}} =
             Registry.encode(:secret_ref, %{
               secret_ref_id: "secret-bad",
               scope: "integration",
               name: "token",
               api_key_hash: "do-not-project"
             })
  end

  test "fake store and embedded store satisfy the shared product contract", context do
    fake_store = start_supervised!({FakeStore, name: :"fake_contract_#{System.unique_integer([:positive])}"})
    embedded_name = :"embedded_contract_#{System.unique_integer([:positive])}"
    embedded_path = Path.join(System.tmp_dir!(), "jido_code_embedded_contract/#{embedded_name}")

    start_supervised!(
      {StoreServer, name: embedded_name, id: embedded_name, path: embedded_path, reset_policy: :reset_on_start}
    )

    on_exit(fn -> File.rm_rf!(embedded_path) end)

    adapters = [
      {:fake, FakeStore, fake_store},
      {:embedded, EmbeddedStore, embedded_name}
    ]

    Enum.each(adapters, fn {adapter_name, module, store} ->
      run_store_contract(adapter_name, module, store, context.test)
    end)
  end

  test "fake and embedded stores return matching authorization and validation error categories" do
    fake_store = start_supervised!({FakeStore, name: :"fake_errors_#{System.unique_integer([:positive])}"})
    embedded_name = :"embedded_errors_#{System.unique_integer([:positive])}"
    embedded_path = Path.join(System.tmp_dir!(), "jido_code_embedded_errors/#{embedded_name}")

    start_supervised!(
      {StoreServer, name: embedded_name, id: embedded_name, path: embedded_path, reset_policy: :reset_on_start}
    )

    on_exit(fn -> File.rm_rf!(embedded_path) end)

    denied_auth = AuthorizationContext.deny(:human_operator, :missing_scope)

    Enum.each([{FakeStore, fake_store}, {EmbeddedStore, embedded_name}], fn {module, store} ->
      assert {:error, %UnauthorizedError{reason: :missing_scope}} =
               module.upsert(
                 managed_repo_request(store, "repo-denied",
                   authorization: denied_auth,
                   source_key: "repo:denied"
                 )
               )

      assert {:error, %ValidationError{}} =
               module.upsert(
                 Request.new(
                   store: store,
                   record_type: :managed_repo,
                   record: %{updated_at: ~U[2026-01-01 00:00:00Z]},
                   authorization: Policy.authorize_mutation(:upsert, :managed_repo, Policy.system_actor())
                 )
               )
    end)
  end

  defp run_store_contract(adapter_name, module, store, test_name) do
    suffix = "#{adapter_name}-#{test_name}" |> String.replace(~r/[^a-zA-Z0-9_-]/, "-")
    repo_id = "repo-contract-#{suffix}"
    source_key = "repo:contract:#{suffix}"

    create_request = managed_repo_request(store, repo_id, source_key: source_key)
    assert {:ok, created} = module.upsert(create_request)
    assert created.status in [:created, :updated]
    assert created.record_type == :managed_repo

    assert {:ok, found} = module.get(%{create_request | record: nil})
    assert found.status == :found
    assert found.subject_iri == created.subject_iri

    updated_record = %{
      create_request.record
      | display_name: "Updated #{adapter_name}",
        updated_at: ~U[2026-01-02 00:00:00Z]
    }

    assert {:ok, updated} =
             module.update(%{
               create_request
               | record: updated_record,
                 expected_updated_at: ~U[2026-01-01 00:00:00Z]
             })

    assert updated.status == :updated

    assert {:ok, listed} =
             module.list(
               Request.new(
                 store: store,
                 record_type: :managed_repo,
                 query: %{limit: 10, offset: 0},
                 authorization: Policy.authorize_read(:managed_repo, Policy.system_actor())
               )
             )

    assert listed.metadata.total_count >= 1

    assert {:ok, event} =
             module.append_event(
               Request.new(
                 store: store,
                 record_type: :event,
                 event: %{
                   id: "event-#{suffix}",
                   managed_repo_id: repo_id,
                   event_id: "event-#{suffix}",
                   source_kind: "contract",
                   occurred_at: ~U[2026-01-01 00:00:00Z]
                 },
                 authorization: Policy.authorize_mutation(:append_event, :event, Policy.system_actor())
               )
             )

    assert event.event_iri

    assert {:ok, deleted} = module.delete(%{create_request | record: nil})
    assert deleted.status == :deleted

    assert {:error, %NotFoundError{}} = module.get(%{create_request | record: nil})
  end

  defp managed_repo_request(store, repo_id, opts) do
    source_key = Keyword.get(opts, :source_key, "repo:#{repo_id}")

    authorization =
      Keyword.get(opts, :authorization, Policy.authorize_mutation(:upsert, :managed_repo, Policy.system_actor()))

    Request.new(
      store: store,
      record_type: :managed_repo,
      subject_iri: "https://jido.run/control/managed-repos/#{repo_id}",
      identity: %{identity: :unique_source_key, predicate_iri: control_iri("managedSourceKey"), value: source_key},
      record: %{
        managed_repo_id: repo_id,
        source_key: source_key,
        display_name: repo_id,
        updated_at: ~U[2026-01-01 00:00:00Z]
      },
      authorization: authorization
    )
  end

  defp projection_from_encoded(encoded) do
    attributes =
      encoded.triples
      |> Enum.reject(fn {_subject, predicate, _object} -> predicate == RDF.type() end)
      |> Enum.group_by(
        fn {_subject, predicate, _object} -> predicate |> to_string() |> String.split(["#", "/"]) |> List.last() end,
        fn {_subject, _predicate, object} -> %{type: :literal, value: RDF.Literal.value(object)} end
      )

    %{subject_iri: encoded.subject_iri, attributes: attributes}
  end

  defp control_iri(local), do: RDF.iri(JidoCode.ControlPlane.SemanticIdentity.ontology_namespace() <> local)
end
