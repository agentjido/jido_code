defmodule JidoCode.ControlPlane.CodecsTest do
  use ExUnit.Case, async: true

  alias JidoCode.ControlPlane.Codecs.Registry
  alias JidoCode.ControlPlane.Codecs.Scalar
  alias JidoCode.ControlPlane.SemanticIdentity

  @jcp SemanticIdentity.ontology_namespace()

  test "scalar mapping normalizes ids, atoms, datetimes, and canonical JSON strings" do
    assert {:ok, "repo-1"} = Scalar.normalize_id(" repo-1 ")
    assert {:ok, "42"} = Scalar.normalize_id(42)
    assert {:ok, "queued"} = Scalar.normalize_atom(:queued)

    assert {:ok, datetime_literal} = Scalar.literal(~U[2026-01-01 00:00:00Z])
    assert to_string(RDF.Literal.datatype_id(datetime_literal)) == "http://www.w3.org/2001/XMLSchema#dateTime"

    assert {:ok, metadata_literal} = Scalar.literal(%{b: 2, a: %{d: 4, c: 3}})
    assert RDF.Literal.value(metadata_literal) == ~s({"a":{"c":3,"d":4},"b":2})
  end

  test "registry accounts for every planned record type with a codec or explicit exclusion" do
    coverage = Registry.planned_coverage()

    assert Registry.coverage_complete?()
    assert coverage.missing_record_types == []
    assert coverage.extra_record_types == []
    assert :managed_repo in coverage.codec_record_types
    assert :secret_ref in coverage.codec_record_types
    assert :user in coverage.explicitly_excluded_record_types
    assert {:error, {:excluded, :codec_not_promoted_yet}} = Registry.codec(:user)
  end

  test "managed repo codec emits deterministic graph, class, subject, identity, and field triples" do
    record = %{
      managed_repo_id: "repo-codec",
      source_key: "github:agentjido/jido_code",
      display_name: "jido_code",
      workspace_path: "/workspace/jido_code",
      updated_at: ~U[2026-01-01 00:00:00Z],
      metadata: %{b: 2, a: 1}
    }

    assert {:ok, encoded} = Registry.encode(:managed_repo, record)

    assert encoded.graph_name == :control_plane
    assert encoded.graph_iri == "https://jido.run/graphs/control_plane"
    assert encoded.class_iri == @jcp <> "ManagedRepo"
    assert encoded.subject_iri == "https://jido.run/control/managed-repos/repo-codec"

    assert %{identity: :unique_source_key, predicate: "sourceKey", value: "github:agentjido/jido_code"} in encoded.identity_queries

    assert triple_value(encoded, "managedRepoId") == "repo-codec"
    assert triple_value(encoded, "sourceKey") == "github:agentjido/jido_code"
    assert triple_value(encoded, "metadataJson") == ~s({"a":1,"b":2})
    assert has_type_triple?(encoded, "ManagedRepo")
  end

  test "repo-scoped work item and append event codecs place records in expected graphs" do
    assert {:ok, work_item} =
             Registry.encode(:work_item, %{
               managed_repo_id: "repo-codec",
               work_item_id: "work-1",
               title: "Replace persistence",
               priority: :high
             })

    assert work_item.graph_name == :control_plane
    assert work_item.subject_iri == "https://jido.run/control/managed-repos/repo-codec/work-items/work-1"
    assert triple_value(work_item, "priority") == "high"

    assert {:ok, event} =
             Registry.encode(:event, %{
               managed_repo_id: "repo-codec",
               event_id: "event-1",
               source_kind: :github,
               occurred_at: ~U[2026-01-01 00:00:00Z],
               payload: %{action: "opened", number: 1}
             })

    assert event.graph_name == :control_plane_events
    assert event.subject_iri == "https://jido.run/control/managed-repos/repo-codec/events/event-1"
    assert triple_value(event, "sourceKind") == "github"
    assert triple_value(event, "payloadJson") == ~s({"action":"opened","number":1})
  end

  test "secret ref codec projects metadata and rejects secret material" do
    assert {:ok, encoded} =
             Registry.encode(:secret_ref, %{
               secret_ref_id: "secret-1",
               scope: "integration",
               name: "github-token",
               display_name: "GitHub token",
               provider: "github"
             })

    assert encoded.graph_name == :security
    assert encoded.subject_iri == "https://jido.run/control/secret-refs/secret-1"
    assert triple_value(encoded, "sourceKey") == "github-token"
    assert triple_value(encoded, "provider") == "github"

    assert {:error, {:sensitive_field_not_projectable, :plaintext}} =
             Registry.encode(:secret_ref, %{
               secret_ref_id: "secret-2",
               scope: "integration",
               name: "bad",
               plaintext: "never-project"
             })
  end

  test "codecs decode shaped store projections back into product maps" do
    projection = %{
      subject_iri: "https://jido.run/control/managed-repos/repo-codec",
      attributes: %{
        "managedRepoId" => [%{type: :literal, value: "repo-codec"}],
        "displayName" => [%{type: :literal, value: "jido_code"}]
      }
    }

    assert {:ok, decoded} = Registry.decode(:managed_repo, projection)
    assert decoded.record_type == :managed_repo
    assert decoded.subject_iri == projection.subject_iri
    assert decoded.managed_repo_id == "repo-codec"
    assert decoded.display_name == "jido_code"
  end

  defp triple_value(encoded, predicate_local) do
    encoded.triples
    |> Enum.find_value(fn {_subject, predicate, object} ->
      if to_string(predicate) == @jcp <> predicate_local do
        RDF.Literal.value(object)
      end
    end)
  end

  defp has_type_triple?(encoded, class_local) do
    Enum.any?(encoded.triples, fn {_subject, predicate, object} ->
      predicate == RDF.type() and to_string(object) == @jcp <> class_local
    end)
  end
end
