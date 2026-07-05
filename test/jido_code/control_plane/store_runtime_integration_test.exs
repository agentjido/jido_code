defmodule JidoCode.ControlPlane.StoreRuntimeIntegrationTest do
  use ExUnit.Case, async: true

  alias JidoCode.ControlPlane.{GraphTopology, SemanticIdentity, StoreCommand, StoreQuery, StoreServer}

  @jcp "https://jido.run/ontology/control-plane#"

  setup do
    name = :"control_plane_runtime_store_#{System.unique_integer([:positive])}"

    path =
      Path.join([
        System.tmp_dir!(),
        "jido_code_store_runtime_integration_test",
        Atom.to_string(name)
      ])

    on_exit(fn -> File.rm_rf!(path) end)

    {:ok, store_name: name, path: path}
  end

  test "supervised store bootstraps ontology graphs and reopens the same path", %{store_name: store_name, path: path} do
    first_pid =
      start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    health = StoreServer.health(store_name)
    {:ok, control_plane_graph} = GraphTopology.graph_iri(:control_plane)

    assert health.ready?
    assert health.path == path
    assert health.schema == :quad
    assert health.ontology_bootstrap.state == :ready
    assert Map.fetch!(health.graph_counts, control_plane_graph) > 0

    subject_iri = managed_repo_iri("repo-restart")

    insert!(
      store_name,
      StoreCommand.insert(
        graph_name: :control_plane,
        subject_iri: subject_iri,
        triples: managed_repo_triples(subject_iri, "repo-restart", "repo:restart")
      )
    )

    assert :ok = stop_supervised(store_name)

    second_pid =
      start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :bootstrap_if_empty})

    assert second_pid != first_pid
    assert {:ok, projection} = StoreQuery.get_by_id(:managed_repo, "repo-restart", server: store_name)
    assert projection.subject_iri == subject_iri
  end

  test "command writes, replacement, identity conflicts, and query projections share one store", %{
    store_name: store_name,
    path: path
  } do
    start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    subject_iri = managed_repo_iri("repo-transaction")
    conflict_iri = managed_repo_iri("repo-transaction-conflict")
    old_timestamp = RDF.XSD.dateTime(~U[2026-01-01 00:00:00Z])
    new_timestamp = RDF.XSD.dateTime(~U[2026-01-02 00:00:00Z])
    identity = source_key_identity("repo:transaction")

    assert {:ok, insert_outcome} =
             StoreCommand.execute(
               StoreCommand.upsert_by_identity(
                 graph_name: :control_plane,
                 subject_iri: subject_iri,
                 identity: identity,
                 triples:
                   managed_repo_triples(
                     subject_iri,
                     "repo-transaction",
                     "repo:transaction",
                     updated_at: old_timestamp
                   )
               ),
               store_name
             )

    assert insert_outcome.deleted_triple_count == 0

    assert {:ok, replace_outcome} =
             StoreCommand.execute(
               StoreCommand.replace_subject(
                 graph_name: :control_plane,
                 subject_iri: subject_iri,
                 expected_updated_at: old_timestamp,
                 triples:
                   managed_repo_triples(
                     subject_iri,
                     "repo-transaction",
                     "repo:transaction",
                     updated_at: new_timestamp
                   )
               ),
               store_name
             )

    assert replace_outcome.deleted_triple_count > 0

    assert {:error, {:conflict, :unique_source_key, ^subject_iri}} =
             StoreCommand.execute(
               StoreCommand.upsert_by_identity(
                 graph_name: :control_plane,
                 subject_iri: conflict_iri,
                 identity: identity,
                 triples: managed_repo_triples(conflict_iri, "repo-transaction-conflict", "repo:transaction")
               ),
               store_name
             )

    assert {:ok, projection} = StoreQuery.lookup_by_identity(:managed_repo, identity, server: store_name)
    assert projection.subject_iri == subject_iri
    assert [%{value: "repo-transaction"}] = projection.attributes["managedRepoId"]
  end

  test "diagnostic SPARQL observes graph allow-lists and bounded execution options", %{
    store_name: store_name,
    path: path
  } do
    start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    subject_iri = managed_repo_iri("repo-diagnostic-runtime")
    {:ok, control_plane_graph} = GraphTopology.graph_iri(:control_plane)
    {:ok, security_graph} = GraphTopology.graph_iri(:security)

    insert!(
      store_name,
      StoreCommand.insert(
        graph_name: :control_plane,
        subject_iri: subject_iri,
        triples: managed_repo_triples(subject_iri, "repo-diagnostic-runtime", "repo:diagnostic-runtime")
      )
    )

    diagnostics_sparql = """
    SELECT ?repo WHERE {
      GRAPH <#{control_plane_graph}> {
        ?repo <#{@jcp}managedRepoId> ?id .
      }
    }
    """

    timeout_sparql = """
    SELECT ?a ?b ?c WHERE {
      GRAPH <#{control_plane_graph}> {
        ?a ?pa ?oa .
        ?b ?pb ?ob .
        ?c ?pc ?oc .
      }
    }
    ORDER BY ?a ?b ?c
    """

    assert {:error, :control_plane_query_timeout, timeout_diagnostics} =
             StoreQuery.diagnostics_query(
               timeout_sparql,
               server: store_name,
               allowed_graphs: [:control_plane],
               limit: 1,
               timeout: 1
             )

    assert timeout_diagnostics.timeout_ms == 1

    assert {:ok, result} =
             StoreQuery.diagnostics_query(
               diagnostics_sparql,
               server: store_name,
               allowed_graphs: [:control_plane],
               limit: 1,
               timeout: 5_000
             )

    assert result.row_count == 1
    assert result.limit == 1
    assert result.timeout_ms == 5_000

    assert {:error, :control_plane_invalid_query, diagnostics} =
             StoreQuery.diagnostics_query(
               "SELECT ?s WHERE { GRAPH <#{security_graph}> { ?s ?p ?o } }",
               server: store_name,
               allowed_graphs: [:control_plane],
               timeout: 10
             )

    assert {:graph_not_allowed, ^security_graph} = diagnostics.reason
  end

  defp insert!(store_name, command) do
    assert {:ok, _outcome} = StoreCommand.execute(command, store_name)
  end

  defp managed_repo_iri(id) do
    {:ok, iri} = SemanticIdentity.canonical_iri(:managed_repo, id)
    iri
  end

  defp managed_repo_triples(subject_iri, repo_id, source_key, opts \\ []) do
    updated_at = Keyword.get(opts, :updated_at, RDF.XSD.dateTime(~U[2026-01-01 00:00:00Z]))

    [
      {RDF.iri(subject_iri), RDF.type(), control_iri("ManagedRepo")},
      {RDF.iri(subject_iri), control_iri("managedRepoId"), RDF.literal(repo_id)},
      {RDF.iri(subject_iri), control_iri("sourceKey"), RDF.literal(source_key)},
      {RDF.iri(subject_iri), control_iri("updatedAt"), updated_at}
    ]
  end

  defp source_key_identity(value) do
    %{
      identity: :unique_source_key,
      predicate_iri: control_iri("sourceKey"),
      value: value
    }
  end

  defp control_iri(local), do: RDF.iri(@jcp <> local)
end
