defmodule JidoCode.ControlPlane.StoreQueryTest do
  use ExUnit.Case, async: true

  alias JidoCode.Actions.QueryControlPlaneDiagnostics
  alias JidoCode.ControlPlane.{GraphTopology, SemanticIdentity, StoreCommand, StoreQuery, StoreServer}

  @jcp "https://jido.run/ontology/control-plane#"

  setup do
    name = :"control_plane_query_store_#{System.unique_integer([:positive])}"

    path =
      Path.join([
        System.tmp_dir!(),
        "jido_code_store_query_test",
        Atom.to_string(name)
      ])

    start_supervised!({StoreServer, name: name, id: name, path: path, reset_policy: :reset_on_start})

    on_exit(fn -> File.rm_rf!(path) end)

    {:ok, store_name: name}
  end

  test "get-by-id, list-by-class, list-by-repo, and lookup-by-identity return shaped projections", %{
    store_name: store_name
  } do
    repo_1 = managed_repo_iri("repo-query-1")
    repo_2 = managed_repo_iri("repo-query-2")
    work_item = work_item_iri("repo-query-1", "work-query-1")

    insert!(store_name, :control_plane, repo_1, managed_repo_triples(repo_1, "repo-query-1", "repo:query-1"))
    insert!(store_name, :control_plane, repo_2, managed_repo_triples(repo_2, "repo-query-2", "repo:query-2"))
    insert!(store_name, :control_plane, work_item, work_item_triples(work_item, "repo-query-1", "work-query-1"))

    assert {:ok, projection} = StoreQuery.get_by_id(:managed_repo, "repo-query-1", server: store_name)
    assert projection.subject_iri == repo_1
    assert [%{value: "repo-query-1"}] = projection.attributes["managedRepoId"]

    assert {:ok, page} = StoreQuery.list_by_class(:managed_repo, server: store_name, limit: 1)
    assert page.total_count == 2
    assert page.row_count == 1
    assert page.next_offset == 1

    assert {:ok, by_identity} =
             StoreQuery.lookup_by_identity(
               :managed_repo,
               %{identity: :unique_source_key, predicate_iri: control_iri("sourceKey"), value: "repo:query-1"},
               server: store_name
             )

    assert by_identity.subject_iri == repo_1

    assert {:ok, by_repo} = StoreQuery.list_by_repo(:work_item, "repo-query-1", server: store_name)
    assert by_repo.total_count == 1
    assert [work_projection] = by_repo.results
    assert work_projection.subject_iri == work_item
  end

  test "query helpers shape missing store and invalid query failures" do
    missing_name = :"missing_control_plane_store_#{System.unique_integer([:positive])}"

    assert {:error, :control_plane_store_unavailable, diagnostics} =
             StoreQuery.list_by_class(:managed_repo, server: missing_name)

    assert diagnostics.status == :degraded
    assert diagnostics.stage == :list_by_class

    assert {:error, :control_plane_invalid_query, invalid_diagnostics} =
             StoreQuery.list_by_class(:not_a_record)

    assert invalid_diagnostics.reason == :unknown_record_type
  end

  test "diagnostics query enforces graph allow-list and row limits", %{store_name: store_name} do
    repo_1 = managed_repo_iri("repo-diagnostics-1")
    repo_2 = managed_repo_iri("repo-diagnostics-2")
    {:ok, control_plane_graph} = GraphTopology.graph_iri(:control_plane)
    {:ok, security_graph} = GraphTopology.graph_iri(:security)

    insert!(
      store_name,
      :control_plane,
      repo_1,
      managed_repo_triples(repo_1, "repo-diagnostics-1", "repo:diagnostics-1")
    )

    insert!(
      store_name,
      :control_plane,
      repo_2,
      managed_repo_triples(repo_2, "repo-diagnostics-2", "repo:diagnostics-2")
    )

    assert {:ok, result} =
             StoreQuery.diagnostics_query(
               """
               SELECT ?repo WHERE {
                 GRAPH <#{control_plane_graph}> {
                   ?repo <#{@jcp}managedRepoId> ?id .
                 }
               }
               ORDER BY ?repo
               """,
               server: store_name,
               allowed_graphs: [:control_plane],
               limit: 1
             )

    assert result.row_count == 1
    assert result.truncated?

    assert {:error, :control_plane_invalid_query, diagnostics} =
             StoreQuery.diagnostics_query(
               "SELECT ?s WHERE { GRAPH <#{security_graph}> { ?s ?p ?o } }",
               server: store_name
             )

    assert {:graph_not_allowed, ^security_graph} = diagnostics.reason
  end

  test "diagnostics query redacts auth and security graph literals", %{store_name: store_name} do
    secret_ref = secret_ref_iri("secret-query-1")
    {:ok, security_graph} = GraphTopology.graph_iri(:security)

    insert!(
      store_name,
      :security,
      secret_ref,
      [
        {RDF.iri(secret_ref), RDF.type(), control_iri("SecretRef")},
        {RDF.iri(secret_ref), control_iri("secretRefId"), RDF.literal("secret-query-1")},
        {RDF.iri(secret_ref), control_iri("displayName"), RDF.literal("super-secret")}
      ]
    )

    assert {:ok, result} =
             StoreQuery.diagnostics_query(
               """
               SELECT ?name WHERE {
                 GRAPH <#{security_graph}> {
                   ?s <#{@jcp}displayName> ?name .
                 }
               }
               """,
               server: store_name,
               allowed_graphs: [:security],
               limit: 5
             )

    assert result.redacted?
    assert [%{"name" => %{type: :literal, value: "[REDACTED]", redacted?: true}}] = result.bindings
  end

  test "diagnostics action routes raw SPARQL through the named product boundary", %{store_name: store_name} do
    repo = managed_repo_iri("repo-action-query")
    {:ok, control_plane_graph} = GraphTopology.graph_iri(:control_plane)

    insert!(
      store_name,
      :control_plane,
      repo,
      managed_repo_triples(repo, "repo-action-query", "repo:action-query")
    )

    assert {:ok, result} =
             QueryControlPlaneDiagnostics.run(
               %{
                 sparql: """
                 SELECT ?id WHERE {
                   GRAPH <#{control_plane_graph}> {
                     ?repo <#{@jcp}managedRepoId> ?id .
                   }
                 }
                 """,
                 allowed_graphs: ["control_plane"],
                 limit: 10,
                 timeout: 5_000
               },
               %{control_plane_store: store_name}
             )

    assert result.query == :diagnostics_query
    assert [%{"id" => %{value: "repo-action-query"}}] = result.bindings
  end

  defp insert!(store_name, graph_name, subject_iri, triples) do
    assert {:ok, _outcome} =
             StoreCommand.execute(
               StoreCommand.insert(graph_name: graph_name, subject_iri: subject_iri, triples: triples),
               store_name
             )
  end

  defp managed_repo_iri(id) do
    {:ok, iri} = SemanticIdentity.canonical_iri(:managed_repo, id)
    iri
  end

  defp work_item_iri(managed_repo_id, id) do
    {:ok, iri} = SemanticIdentity.canonical_iri(:work_item, managed_repo_id: managed_repo_id, id: id)
    iri
  end

  defp secret_ref_iri(id) do
    {:ok, iri} = SemanticIdentity.canonical_iri(:secret_ref, id)
    iri
  end

  defp managed_repo_triples(subject_iri, repo_id, source_key) do
    [
      {RDF.iri(subject_iri), RDF.type(), control_iri("ManagedRepo")},
      {RDF.iri(subject_iri), control_iri("managedRepoId"), RDF.literal(repo_id)},
      {RDF.iri(subject_iri), control_iri("sourceKey"), RDF.literal(source_key)}
    ]
  end

  defp work_item_triples(subject_iri, managed_repo_id, work_item_id) do
    [
      {RDF.iri(subject_iri), RDF.type(), control_iri("WorkItem")},
      {RDF.iri(subject_iri), control_iri("managedRepoId"), RDF.literal(managed_repo_id)},
      {RDF.iri(subject_iri), control_iri("workItemId"), RDF.literal(work_item_id)}
    ]
  end

  defp control_iri(local), do: RDF.iri(@jcp <> local)
end
