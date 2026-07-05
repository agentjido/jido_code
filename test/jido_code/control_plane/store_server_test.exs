defmodule JidoCode.ControlPlane.StoreServerTest do
  use ExUnit.Case, async: true

  alias JidoCode.ControlPlane.{GraphTopology, StoreServer}

  test "starts a supervised quad store and bootstraps ontologies" do
    {name, path} = isolated_store()

    start_supervised!({StoreServer, name: name, id: name, path: path, reset_policy: :reset_on_start})

    health = StoreServer.health(name)
    {:ok, control_plane_graph_iri} = GraphTopology.graph_iri(:control_plane)

    assert health.ready?
    assert health.path == path
    assert health.schema == :quad
    assert health.reset_policy == :reset_on_start
    assert health.ontology_bootstrap.state == :ready
    assert health.ontology_bootstrap.loaded_triple_count > 0
    assert health.graph_counts[control_plane_graph_iri] == health.ontology_bootstrap.loaded_triple_count

    assert {:ok, graph_count} =
             StoreServer.with_store(name, fn store ->
               {:ok, summary} = TripleStore.QuadOperations.graphs_summary(store.db, include_default: false)
               map_size(summary)
             end)

    assert graph_count == 1
  end

  test "reset reopens the same store path and reloads ontology graphs" do
    {name, path} = isolated_store()

    start_supervised!({StoreServer, name: name, id: name, path: path, reset_policy: :reset_on_start})
    before_reset = StoreServer.health(name)

    assert {:ok, after_reset} = StoreServer.reset(name)

    assert after_reset.ready?
    assert after_reset.path == before_reset.path
    assert after_reset.ontology_bootstrap.loaded_triple_count > 0
  end

  test "supervised shutdown closes the underlying store handle" do
    {name, path} = isolated_store()

    start_supervised!({StoreServer, name: name, id: name, path: path, reset_policy: :reset_on_start})
    assert :ok = stop_supervised(name)

    assert {:ok, reopened} = TripleStore.open(path, create_if_missing: false, schema: :quad)
    assert :ok = TripleStore.close(reopened)
  end

  defp isolated_store do
    name = :"control_plane_store_#{System.unique_integer([:positive])}"

    path =
      Path.join([
        System.tmp_dir!(),
        "jido_code_store_server_test",
        Atom.to_string(name)
      ])

    on_exit(fn -> File.rm_rf!(path) end)

    {name, path}
  end
end
