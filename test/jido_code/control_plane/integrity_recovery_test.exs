defmodule JidoCode.ControlPlane.IntegrityRecoveryTest do
  use ExUnit.Case, async: true

  alias JidoCode.ControlPlane.{
    Integrity,
    Recovery,
    SemanticIdentity,
    StoreCommand,
    StoreQuery,
    StoreServer
  }

  @jcp SemanticIdentity.ontology_namespace()

  setup do
    name = :"control_plane_integrity_recovery_#{System.unique_integer([:positive])}"

    path =
      Path.join([
        System.tmp_dir!(),
        "jido_code_control_plane_integrity_recovery_test",
        Atom.to_string(name)
      ])

    export_path = Path.join(path <> "_exports", "control-plane.nq")

    on_exit(fn ->
      File.rm_rf(path)
      File.rm_rf(path <> "_exports")
    end)

    start_supervised!({StoreServer, name: name, id: name, path: path, reset_policy: :reset_on_start})

    {:ok, store_name: name, path: path, export_path: export_path}
  end

  test "integrity passes on a bootstrapped empty store", %{store_name: store_name} do
    assert {:ok, report} = Integrity.check(store_name)

    assert report.status == :ok
    assert report.issues == []
    assert report.ontology.expected_version == "2026-07-05"
    assert report.ontology.stored_versions == ["2026-07-05"]

    assert Enum.any?(report.topology.graphs, &(&1.graph_name == :control_plane and &1.present?))
    assert :managed_repo in report.identities.checked_record_types
  end

  test "integrity detects duplicate canonical identity values", %{store_name: store_name} do
    insert_managed_repo!(store_name, "repo-a", managed_repo_id_value: "shared-repo-id")
    insert_managed_repo!(store_name, "repo-b", managed_repo_id_value: "shared-repo-id")

    assert {:ok, report} = Integrity.check(store_name)

    assert report.status == :failed

    assert Enum.any?(report.issues, fn issue ->
             issue.code == :duplicate_record_identity and issue.metadata.record_type == :managed_repo and
               issue.metadata.identity_value == "shared-repo-id"
           end)
  end

  test "export omits auth and security graphs unless redaction is disabled", %{
    store_name: store_name,
    export_path: export_path
  } do
    insert_user!(store_name, "user-redacted", "secret-user@example.test")

    assert {:ok, redacted_report} = StoreServer.export(store_name, export_path)
    redacted_content = File.read!(export_path)

    assert redacted_report.redacted_graphs == [:auth, :security]
    assert redacted_report.omitted_quad_count > 0
    refute redacted_content =~ "secret-user@example.test"

    assert {:ok, full_report} = StoreServer.export(store_name, export_path, redact?: false)
    full_content = File.read!(export_path)

    assert full_report.redacted_graphs == []
    assert full_content =~ "secret-user@example.test"
  end

  test "restore validates an exported graph file and reopens the target store", %{
    store_name: source_store_name,
    export_path: export_path
  } do
    insert_managed_repo!(source_store_name, "repo-restore")

    assert {:ok, _export_report} = StoreServer.export(source_store_name, export_path)

    target_name = :"control_plane_restore_target_#{System.unique_integer([:positive])}"
    target_path = export_path <> "_target_store"
    on_exit(fn -> File.rm_rf(target_path) end)

    start_supervised!(
      {StoreServer, name: target_name, id: target_name, path: target_path, reset_policy: :reset_on_start}
    )

    assert {:ok, restore_report} = StoreServer.restore(target_name, export_path)

    assert restore_report.restored_quad_count > 0
    assert restore_report.integrity.status == :ok
    assert restore_report.health.ready?

    assert {:ok, projection} = StoreQuery.get_by_id(:managed_repo, "repo-restore", server: target_name)
    assert projection.subject_iri == managed_repo_iri("repo-restore")
  end

  test "reset clears product records and reloads ontology graphs", %{store_name: store_name} do
    insert_managed_repo!(store_name, "repo-reset")

    assert {:ok, _projection} = StoreQuery.get_by_id(:managed_repo, "repo-reset", server: store_name)
    assert {:ok, health} = Recovery.reset(store_name)

    assert health.ready?
    assert health.ontology_bootstrap.loaded_triple_count > 0
    assert {:ok, nil} = StoreQuery.get_by_id(:managed_repo, "repo-reset", server: store_name)
  end

  defp insert_managed_repo!(store_name, id, opts \\ []) do
    subject_iri = managed_repo_iri(id)
    managed_repo_id_value = Keyword.get(opts, :managed_repo_id_value, id)

    assert {:ok, _outcome} =
             StoreCommand.execute(
               StoreCommand.insert(
                 graph_name: :control_plane,
                 subject_iri: subject_iri,
                 triples: [
                   {RDF.iri(subject_iri), RDF.type(), control_iri("ManagedRepo")},
                   {RDF.iri(subject_iri), control_iri("managedRepoId"), RDF.literal(managed_repo_id_value)},
                   {RDF.iri(subject_iri), control_iri("sourceKey"), RDF.literal("source:#{id}")}
                 ]
               ),
               store_name
             )

    subject_iri
  end

  defp insert_user!(store_name, id, email) do
    subject_iri = user_iri(id)

    assert {:ok, _outcome} =
             StoreCommand.execute(
               StoreCommand.insert(
                 graph_name: :auth,
                 subject_iri: subject_iri,
                 triples: [
                   {RDF.iri(subject_iri), RDF.type(), control_iri("User")},
                   {RDF.iri(subject_iri), control_iri("userId"), RDF.literal(id)},
                   {RDF.iri(subject_iri), control_iri("email"), RDF.literal(email)}
                 ]
               ),
               store_name
             )
  end

  defp managed_repo_iri(id) do
    {:ok, iri} = SemanticIdentity.canonical_iri(:managed_repo, id)
    iri
  end

  defp user_iri(id) do
    {:ok, iri} = SemanticIdentity.canonical_iri(:user, id)
    iri
  end

  defp control_iri(local), do: RDF.iri(@jcp <> local)
end
