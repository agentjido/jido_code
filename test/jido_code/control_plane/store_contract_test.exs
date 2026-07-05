defmodule JidoCode.ControlPlane.StoreContractTest do
  use ExUnit.Case, async: true

  alias JidoCode.ControlPlane.FakeStore
  alias JidoCode.ControlPlane.Store
  alias JidoCode.ControlPlane.Store.{ActorContext, AuthorizationContext, Outcome, Request}

  alias JidoCode.ControlPlane.Store.Errors.{
    ConflictError,
    NotFoundError,
    UnauthorizedError,
    UnavailableError,
    ValidationError
  }

  test "store behaviour exposes product persistence callbacks and dispatch" do
    callbacks = Store.behaviour_info(:callbacks)

    assert {:create, 1} in callbacks
    assert {:update, 1} in callbacks
    assert {:upsert, 1} in callbacks
    assert {:delete, 1} in callbacks
    assert {:get, 1} in callbacks
    assert {:list, 1} in callbacks
    assert {:append_event, 1} in callbacks
    assert {:query, 1} in callbacks

    assert {:error, %UnavailableError{stage: :dispatch}} =
             Store.dispatch(String, :create, Request.new(store: self()))
  end

  test "request, actor, authorization, outcome, and error structs are explicit" do
    actor = ActorContext.system("system:test", %{source: :unit})
    auth = AuthorizationContext.allow(:system, [:control_plane_write])
    request = Request.new(record_type: :managed_repo, subject_iri: "urn:test:repo", actor: actor, authorization: auth)

    assert request.actor.id == "system:test"
    assert request.authorization.allowed?
    assert request.record_type == :managed_repo

    outcome = %Outcome{operation: :create, status: :created, subject_iri: request.subject_iri}
    assert outcome.written_subject_iris == []

    assert %ValidationError{field: :name}.field == :name
    assert %ConflictError{identity: :unique_name}.identity == :unique_name
    assert %NotFoundError{subject_iri: "urn:test:missing"}.subject_iri == "urn:test:missing"
    assert %UnauthorizedError{operation: :create}.operation == :create
  end

  test "fake store creates, reads, lists, updates, deletes, and records events" do
    store = start_supervised!({FakeStore, name: :"fake_store_#{System.unique_integer([:positive])}"})
    subject_iri = "https://jido.run/control/managed-repos/repo-contract"

    create_request =
      request(
        store,
        record_type: :managed_repo,
        subject_iri: subject_iri,
        identity: identity(:unique_source_key, "repo:contract"),
        record: %{managed_repo_id: "repo-contract", source_key: "repo:contract", updated_at: ~U[2026-01-01 00:00:00Z]}
      )

    assert {:ok, created} = FakeStore.create(create_request)
    assert created.status == :created
    assert created.written_subject_iris == [subject_iri]

    assert {:ok, found} = FakeStore.get(request(store, record_type: :managed_repo, subject_iri: subject_iri))
    assert found.record.managed_repo_id == "repo-contract"

    assert {:ok, listed} =
             FakeStore.list(
               request(store, record_type: :managed_repo, query: %{limit: 10, managed_repo_id: "repo-contract"})
             )

    assert listed.metadata.total_count == 1

    update_request =
      request(
        store,
        record_type: :managed_repo,
        subject_iri: subject_iri,
        identity: identity(:unique_source_key, "repo:contract"),
        expected_updated_at: ~U[2026-01-01 00:00:00Z],
        record: %{managed_repo_id: "repo-contract", source_key: "repo:contract", updated_at: ~U[2026-01-02 00:00:00Z]}
      )

    assert {:ok, updated} = FakeStore.update(update_request)
    assert updated.status == :updated

    assert {:ok, event_outcome} =
             FakeStore.append_event(
               request(
                 store,
                 record_type: :event,
                 subject_iri: "urn:event:1",
                 event: %{id: "urn:event:1", type: "repo.updated"}
               )
             )

    assert event_outcome.event_iri == "urn:event:1"
    assert [%{type: "repo.updated"}] = FakeStore.events(store)

    assert {:ok, deleted} = FakeStore.delete(request(store, record_type: :managed_repo, subject_iri: subject_iri))
    assert deleted.deleted_subject_iris == [subject_iri]

    assert {:error, %NotFoundError{}} =
             FakeStore.get(request(store, record_type: :managed_repo, subject_iri: subject_iri))
  end

  test "fake store enforces identity conflicts, validation, and authorization" do
    store = start_supervised!({FakeStore, name: :"fake_store_#{System.unique_integer([:positive])}"})
    first_subject = "urn:repo:first"
    second_subject = "urn:repo:second"

    first_request =
      request(
        store,
        record_type: :managed_repo,
        subject_iri: first_subject,
        identity: identity(:unique_source_key, "repo:conflict"),
        record: %{managed_repo_id: "repo-conflict", updated_at: ~U[2026-01-01 00:00:00Z]}
      )

    assert {:ok, _created} = FakeStore.upsert(first_request)

    assert {:error, %ConflictError{identity: :unique_source_key, conflicting_subject_iri: ^first_subject}} =
             FakeStore.upsert(%{first_request | subject_iri: second_subject})

    assert {:error, %ValidationError{field: :subject_iri, reason: :missing}} =
             FakeStore.create(request(store, record_type: :managed_repo, record: %{}))

    denied =
      request(
        store,
        record_type: :managed_repo,
        subject_iri: "urn:repo:denied",
        record: %{},
        authorization: AuthorizationContext.deny(:human_operator, :missing_scope)
      )

    assert {:error, %UnauthorizedError{reason: :missing_scope}} = FakeStore.create(denied)
  end

  test "fake store supports deterministic seeding and query snapshots" do
    store =
      start_supervised!(
        {FakeStore,
         name: :"fake_store_#{System.unique_integer([:positive])}",
         records: [
           %{
             record_type: :managed_repo,
             subject_iri: "urn:repo:seeded",
             identity: identity(:unique_source_key, "repo:seeded"),
             record: %{managed_repo_id: "repo-seeded", updated_at: ~U[2026-01-01 00:00:00Z]}
           }
         ]}
      )

    assert %{records: %{"urn:repo:seeded" => _entry}} = FakeStore.snapshot(store)

    assert {:ok, queried} =
             FakeStore.query(request(store, query: %{record_type: :managed_repo, limit: 5, offset: 0}))

    assert queried.status == :query_succeeded
    assert [%{managed_repo_id: "repo-seeded"}] = queried.records
  end

  defp request(store, attrs) do
    attrs
    |> Keyword.put(:store, store)
    |> Request.new()
  end

  defp identity(name, value), do: %{identity: name, value: value}
end
