defmodule JidoCode.ControlPlane.ObservabilityDiagnosticsTest do
  use ExUnit.Case, async: false

  alias JidoCode.ControlPlane.{
    Diagnostics,
    GraphTopology,
    Health,
    Integrity,
    SemanticIdentity,
    StoreCommand,
    StoreQuery,
    StoreServer
  }

  @jcp SemanticIdentity.ontology_namespace()

  setup do
    handler_id = "control-plane-observability-#{System.unique_integer([:positive])}"
    test_pid = self()

    events = [
      [:jido_code, :control_plane, :open, :stop],
      [:jido_code, :control_plane, :update, :stop],
      [:jido_code, :control_plane, :query, :stop],
      [:jido_code, :control_plane, :integrity, :stop],
      [:jido_code, :control_plane, :export, :stop],
      [:jido_code, :control_plane, :restore, :stop],
      [:jido_code, :control_plane, :health, :stop],
      [:jido_code, :control_plane, :graph_size]
    ]

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        fn event, measurements, metadata, pid ->
          send(pid, {:control_plane_telemetry, event, measurements, metadata})
        end,
        test_pid
      )

    name = :"control_plane_observability_#{System.unique_integer([:positive])}"

    path =
      Path.join([
        System.tmp_dir!(),
        "jido_code_control_plane_observability_test",
        Atom.to_string(name)
      ])

    export_path = Path.join(path <> "_exports", "control-plane.nq")

    on_exit(fn ->
      :telemetry.detach(handler_id)
      File.rm_rf(path)
      File.rm_rf(path <> "_exports")
    end)

    start_supervised!({StoreServer, name: name, id: name, path: path, reset_policy: :reset_on_start})

    {:ok, store_name: name, path: path, export_path: export_path}
  end

  test "store operations emit bounded control-plane telemetry", %{store_name: store_name, export_path: export_path} do
    {measurements, metadata} = assert_telemetry([:jido_code, :control_plane, :open, :stop])
    assert is_integer(measurements.duration)
    assert metadata.status == :ok

    insert_managed_repo!(store_name, "repo-telemetry")
    {_measurements, metadata} = assert_telemetry([:jido_code, :control_plane, :update, :stop])
    assert metadata.command == :insert
    assert metadata.graph_name == :control_plane

    assert {:ok, _result} = StoreQuery.list_by_class(:managed_repo, server: store_name)
    {_measurements, metadata} = assert_telemetry([:jido_code, :control_plane, :query, :stop])
    assert metadata.stage == :list_by_class

    assert {:ok, %{status: :ok}} = Integrity.check(store_name)
    {_measurements, metadata} = assert_telemetry([:jido_code, :control_plane, :integrity, :stop])
    assert metadata.status == :ok

    projection = Health.status(store_name)
    assert projection.state == :ready
    assert projection.graph_count > 0

    {measurements, metadata} = assert_telemetry([:jido_code, :control_plane, :graph_size])
    assert measurements.graph_count == projection.graph_count
    assert metadata.state == :ready

    {_measurements, metadata} = assert_telemetry([:jido_code, :control_plane, :health, :stop])
    assert metadata.status == :ok

    assert {:ok, _report} = StoreServer.export(store_name, export_path)
    {_measurements, metadata} = assert_telemetry([:jido_code, :control_plane, :export, :stop])
    assert metadata.exported_quad_count > 0

    target_name = :"control_plane_observability_restore_#{System.unique_integer([:positive])}"
    target_path = export_path <> "_target"
    on_exit(fn -> File.rm_rf(target_path) end)

    start_supervised!(
      {StoreServer, name: target_name, id: target_name, path: target_path, reset_policy: :reset_on_start}
    )

    assert {:ok, _report} = StoreServer.restore(target_name, export_path)
    {_measurements, metadata} = assert_telemetry([:jido_code, :control_plane, :restore, :stop])
    assert metadata.restored_quad_count > 0
  end

  test "diagnostics expose safe named queries and gate raw SPARQL", %{store_name: store_name} do
    insert_managed_repo!(store_name, "repo-diagnostics")

    assert {:ok, health} = Diagnostics.safe_query(:health, server: store_name)
    assert health.state == :ready

    assert {:ok, graph_counts} = Diagnostics.safe_query(:graph_counts, server: store_name)
    assert graph_counts.graph_count > 0

    assert {:ok, records} = Diagnostics.safe_query(:list_records, server: store_name, record_type: :managed_repo)
    assert records.row_count == 1

    {:ok, control_plane_graph} = GraphTopology.graph_iri(:control_plane)

    sparql = """
    SELECT ?s WHERE {
      GRAPH <#{control_plane_graph}> {
        ?s <#{@jcp}managedRepoId> ?id .
      }
    }
    """

    assert {:error, :raw_sparql_requires_allow_raw} = Diagnostics.raw_sparql(sparql, server: store_name)

    assert {:ok, raw_result} =
             Diagnostics.raw_sparql(
               sparql,
               server: store_name,
               allow_raw?: true,
               allowed_graphs: [:control_plane],
               limit: 1
             )

    assert raw_result.query == :diagnostics_query
    assert raw_result.row_count == 1
  end

  defp insert_managed_repo!(store_name, id) do
    subject_iri = managed_repo_iri(id)

    assert {:ok, _outcome} =
             StoreCommand.execute(
               StoreCommand.insert(
                 graph_name: :control_plane,
                 subject_iri: subject_iri,
                 triples: [
                   {RDF.iri(subject_iri), RDF.type(), control_iri("ManagedRepo")},
                   {RDF.iri(subject_iri), control_iri("managedRepoId"), RDF.literal(id)}
                 ]
               ),
               store_name
             )
  end

  defp managed_repo_iri(id) do
    {:ok, iri} = SemanticIdentity.canonical_iri(:managed_repo, id)
    iri
  end

  defp control_iri(local), do: RDF.iri(@jcp <> local)

  defp assert_telemetry(event) do
    receive do
      {:control_plane_telemetry, ^event, measurements, metadata} ->
        {measurements, metadata}

      {:control_plane_telemetry, _other_event, _measurements, _metadata} ->
        assert_telemetry(event)
    after
      1_000 -> flunk("expected telemetry event #{inspect(event)}")
    end
  end
end
