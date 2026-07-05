defmodule JidoCode.ControlPlane.StoreCommandTest do
  use ExUnit.Case, async: true

  alias JidoCode.ControlPlane.{GraphTopology, SemanticIdentity, StoreCommand, StoreServer}

  @jcp "https://jido.run/ontology/control-plane#"

  setup do
    name = :"control_plane_command_store_#{System.unique_integer([:positive])}"

    path =
      Path.join([
        System.tmp_dir!(),
        "jido_code_store_command_test",
        Atom.to_string(name)
      ])

    start_supervised!({StoreServer, name: name, id: name, path: path, reset_policy: :reset_on_start})

    on_exit(fn -> File.rm_rf!(path) end)

    {:ok, store_name: name}
  end

  test "insert writes typed subject triples through the store owner", %{store_name: store_name} do
    subject_iri = managed_repo_iri("repo-command-1")

    assert {:ok, outcome} =
             StoreCommand.execute(
               StoreCommand.insert(
                 graph_name: :control_plane,
                 subject_iri: subject_iri,
                 triples: managed_repo_triples(subject_iri, "repo-command-1"),
                 actor: %{id: "system:test"},
                 correlation_id: "corr-insert"
               ),
               store_name
             )

    assert outcome.command == :insert
    assert outcome.subject_iri == subject_iri
    assert outcome.written_triple_count == 3
    assert quad_exists?(store_name, :control_plane, {RDF.iri(subject_iri), RDF.type(), control_iri("ManagedRepo")})
  end

  test "append-event writes only to append-heavy graphs", %{store_name: store_name} do
    subject_iri = event_iri("event-1")

    assert {:ok, outcome} =
             StoreCommand.execute(
               StoreCommand.append_event(
                 graph_name: :control_plane_events,
                 subject_iri: subject_iri,
                 triples: event_triples(subject_iri, "event-1")
               ),
               store_name
             )

    assert outcome.event_iri == subject_iri

    assert {:error, {:invalid_append_graph, :control_plane}} =
             StoreCommand.execute(
               StoreCommand.append_event(
                 graph_name: :control_plane,
                 subject_iri: event_iri("event-2"),
                 triples: event_triples(event_iri("event-2"), "event-2")
               ),
               store_name
             )
  end

  test "upsert-by-identity replaces same subject and rejects conflicting subjects", %{store_name: store_name} do
    first_subject = managed_repo_iri("repo-upsert-1")
    second_subject = managed_repo_iri("repo-upsert-2")
    identity = source_key_identity("repo:upsert")

    assert {:ok, first_outcome} =
             StoreCommand.execute(
               StoreCommand.upsert_by_identity(
                 graph_name: :control_plane,
                 subject_iri: first_subject,
                 identity: identity,
                 triples: managed_repo_triples(first_subject, "repo-upsert-1", source_key: "repo:upsert")
               ),
               store_name
             )

    assert first_outcome.deleted_triple_count == 0

    assert {:ok, replace_outcome} =
             StoreCommand.execute(
               StoreCommand.upsert_by_identity(
                 graph_name: :control_plane,
                 subject_iri: first_subject,
                 identity: identity,
                 triples: managed_repo_triples(first_subject, "repo-upsert-1b", source_key: "repo:upsert")
               ),
               store_name
             )

    assert replace_outcome.deleted_triple_count > 0

    assert {:error, {:conflict, :unique_source_key, ^first_subject}} =
             StoreCommand.execute(
               StoreCommand.upsert_by_identity(
                 graph_name: :control_plane,
                 subject_iri: second_subject,
                 identity: identity,
                 triples: managed_repo_triples(second_subject, "repo-upsert-2", source_key: "repo:upsert")
               ),
               store_name
             )
  end

  test "replace-subject enforces expected updated-at checks", %{store_name: store_name} do
    subject_iri = managed_repo_iri("repo-stale")
    old_timestamp = RDF.XSD.dateTime(~U[2026-01-01 00:00:00Z])
    new_timestamp = RDF.XSD.dateTime(~U[2026-01-02 00:00:00Z])

    assert {:ok, _outcome} =
             StoreCommand.execute(
               StoreCommand.insert(
                 graph_name: :control_plane,
                 subject_iri: subject_iri,
                 triples: managed_repo_triples(subject_iri, "repo-stale", updated_at: old_timestamp)
               ),
               store_name
             )

    assert {:error, {:stale_write, ^subject_iri}} =
             StoreCommand.execute(
               StoreCommand.replace_subject(
                 graph_name: :control_plane,
                 subject_iri: subject_iri,
                 expected_updated_at: new_timestamp,
                 triples: managed_repo_triples(subject_iri, "repo-stale", updated_at: new_timestamp)
               ),
               store_name
             )

    assert {:ok, outcome} =
             StoreCommand.execute(
               StoreCommand.replace_subject(
                 graph_name: :control_plane,
                 subject_iri: subject_iri,
                 expected_updated_at: old_timestamp,
                 triples: managed_repo_triples(subject_iri, "repo-stale", updated_at: new_timestamp)
               ),
               store_name
             )

    assert outcome.deleted_triple_count > 0
    assert outcome.written_triple_count == 3
  end

  defp managed_repo_iri(id) do
    {:ok, iri} = SemanticIdentity.canonical_iri(:managed_repo, id)
    iri
  end

  defp event_iri(id) do
    {:ok, iri} = SemanticIdentity.canonical_iri(:event, managed_repo_id: "repo-command", id: id)
    iri
  end

  defp managed_repo_triples(subject_iri, repo_id, opts \\ []) do
    updated_at = Keyword.get(opts, :updated_at, RDF.XSD.dateTime(~U[2026-01-01 00:00:00Z]))
    source_key = Keyword.get(opts, :source_key)

    [
      {RDF.iri(subject_iri), RDF.type(), control_iri("ManagedRepo")},
      {RDF.iri(subject_iri), control_iri("managedRepoId"), RDF.literal(repo_id)},
      {RDF.iri(subject_iri), control_iri("updatedAt"), updated_at},
      maybe_source_key(subject_iri, source_key)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp event_triples(subject_iri, event_id) do
    [
      {RDF.iri(subject_iri), RDF.type(), control_iri("Event")},
      {RDF.iri(subject_iri), control_iri("eventId"), RDF.literal(event_id)}
    ]
  end

  defp maybe_source_key(_subject_iri, nil), do: nil

  defp maybe_source_key(subject_iri, source_key),
    do: {RDF.iri(subject_iri), control_iri("sourceKey"), RDF.literal(source_key)}

  defp source_key_identity(value) do
    %{
      identity: :unique_source_key,
      predicate_iri: control_iri("sourceKey"),
      value: value
    }
  end

  defp quad_exists?(store_name, graph_name, triple) do
    {:ok, graph_resource} = GraphTopology.graph_resource(graph_name)

    StoreServer.with_store(store_name, fn store ->
      with {:ok, graph_id} <- TripleStore.Adapter.lookup_term_id(store.db, graph_resource),
           {:ok, subject_id} <- TripleStore.Adapter.lookup_term_id(store.db, elem(triple, 0)),
           {:ok, predicate_id} <- TripleStore.Adapter.lookup_term_id(store.db, elem(triple, 1)),
           {:ok, object_id} <- TripleStore.Adapter.lookup_term_id(store.db, elem(triple, 2)) do
        TripleStore.QuadOperations.quad_exists?(store.db, {subject_id, predicate_id, object_id, graph_id})
      else
        _other -> false
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, _reason} -> false
    end
  end

  defp control_iri(local), do: RDF.iri(@jcp <> local)
end
