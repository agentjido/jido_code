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
    assert :user in coverage.codec_record_types
    assert :api_key in coverage.codec_record_types
    assert :token in coverage.codec_record_types
    assert :user_identity in coverage.codec_record_types
    assert :provider_config in coverage.codec_record_types
    assert :secret_lifecycle_audit in coverage.codec_record_types
    refute :api_key in coverage.explicitly_excluded_record_types
    assert {:ok, _codec} = Registry.codec(:api_key)
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
               canonical_key: "integration:github-token",
               scope: "integration",
               name: "github-token",
               display_name: "GitHub token",
               provider: "github",
               source: "onboarding",
               key_version: 1,
               last_rotated_at: ~U[2026-01-01 00:00:00Z]
             })

    assert encoded.graph_name == :security
    assert encoded.subject_iri == "https://jido.run/control/secret-refs/secret-1"

    assert %{identity: :unique_scope_name, predicate: "canonicalKey", value: "integration:github-token"} in encoded.identity_queries

    assert triple_value(encoded, "sourceKey") == "github-token"
    assert triple_value(encoded, "provider") == "github"
    assert triple_value(encoded, "credentialSource") == "onboarding"
    assert triple_value(encoded, "keyVersion") == 1

    refute Enum.any?(encoded.triples, fn
             {_subject, _predicate, %RDF.Literal{} = object} -> RDF.Literal.value(object) == "ciphertext"
             _triple -> false
           end)

    assert {:error, {:sensitive_field_not_projectable, :plaintext}} =
             Registry.encode(:secret_ref, %{
               secret_ref_id: "secret-2",
               scope: "integration",
               name: "bad",
               plaintext: "never-project"
             })

    assert {:error, {:sensitive_field_not_projectable, :ciphertext}} =
             Registry.encode(:secret_ref, %{
               secret_ref_id: "secret-3",
               scope: "integration",
               name: "bad",
               ciphertext: "ciphertext"
             })
  end

  test "secret lifecycle audit codec projects append-only audit facts" do
    assert {:ok, encoded} =
             Registry.encode(:secret_lifecycle_audit, %{
               secret_lifecycle_audit_id: "audit-1",
               secret_ref_id: "secret-1",
               scope: "integration",
               name: "github-token",
               action_type: "rotate",
               outcome_status: "succeeded",
               actor_id: "owner-1",
               actor_email: "owner@example.com",
               occurred_at: ~U[2026-01-01 00:00:00Z]
             })

    assert encoded.graph_name == :security
    assert encoded.subject_iri == "https://jido.run/control/secret-lifecycle-audits/audit-1"
    assert triple_value(encoded, "secretRefId") == "secret-1"
    assert triple_value(encoded, "actionType") == "rotate"
    assert triple_value(encoded, "outcomeStatus") == "succeeded"
    assert triple_value(encoded, "actorId") == "owner-1"
  end

  test "token and API key codecs reject credential material" do
    assert {:ok, token} =
             Registry.encode(:token, %{
               token_id: "token-1",
               user_id: "user-1",
               subject: "owner@example.com",
               purpose: "session",
               expires_at: ~U[2026-01-01 00:00:00Z],
               status: "active"
             })

    assert token.graph_name == :auth
    assert token.subject_iri == "https://jido.run/control/tokens/token-1"
    assert triple_value(token, "purpose") == "session"

    assert {:error, {:sensitive_field_not_projectable, :token}} =
             Registry.encode(:token, %{token_id: "token-2", token: "never-project"})

    assert {:ok, api_key} =
             Registry.encode(:api_key, %{
               api_key_id: "api-key-1",
               user_id: "user-1",
               name: "Automation",
               expires_at: ~U[2026-01-01 00:00:00Z],
               status: "active"
             })

    assert api_key.graph_name == :auth
    assert api_key.subject_iri == "https://jido.run/control/api-keys/api-key-1"
    assert triple_value(api_key, "displayName") == "Automation"

    assert {:error, {:sensitive_field_not_projectable, :api_key}} =
             Registry.encode(:api_key, %{api_key_id: "api-key-2", api_key: "never-project"})
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
