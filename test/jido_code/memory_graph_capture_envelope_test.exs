defmodule JidoCode.MemoryGraphCaptureEnvelopeTest do
  # covers: architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
  # covers: architecture.memory_capture_plane.typed_governed_reference_contract_is_canonical
  # covers: architecture.memory_capture_plane.memory_capture_requires_explicit_repo_work_and_actor_context
  use ExUnit.Case, async: true

  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.{CaptureEnvelope, DurableMemoryEnvelope, DurableMemoryUpdateEnvelope}

  test "workflow provenance envelopes normalize typed governed references" do
    assert {:ok, envelope} =
             CaptureEnvelope.normalize(
               CaptureEnvelope.review(
                 session_id: "session-36",
                 actor_id: "system:test",
                 workflow: :review,
                 revision: "rev-36",
                 governed_references: [
                   %{kind: :run, id: "run-36"},
                   %{kind: :work_item, id: "work-36"}
                 ]
               ),
               graph_context("repo-36", "rev-36")
             )

    assert envelope.governed_references |> Enum.map(& &1.kind) |> Enum.sort() == [:run, :work_item]

    assert Enum.map(envelope.governed_artifacts, &{&1.kind, &1.id}) == [
             {:run, "run-36"},
             {:work_item, "work-36"}
           ]
  end

  test "durable memory envelopes keep governed references distinct from support and evidence artifacts" do
    assert {:ok, envelope} =
             DurableMemoryEnvelope.normalize(
               DurableMemoryEnvelope.known_issue(
                 session_id: "session-36-memory",
                 actor_id: "system:test",
                 revision: "rev-36",
                 content: "Known issue for typed governed references.",
                 classification: %{source: "test", reason: "Section 36 envelope normalization."},
                 governed_references: [%{kind: :decision, id: "decision-36"}],
                 supported_by: [%{id: "review-36", label: "review support"}],
                 evidence_artifacts: [%{id: "artifact-36", label: "artifact evidence"}]
               ),
               graph_context("repo-36", "rev-36")
             )

    assert Enum.map(envelope.governed_references, & &1.kind) == [:decision]
    assert Enum.map(envelope.supported_by_artifacts, & &1.label) == ["review support"]
    assert Enum.map(envelope.evidence_artifacts, & &1.label) == ["artifact evidence"]
  end

  test "durable memory update envelopes normalize both typed and legacy governed link inputs" do
    assert {:ok, typed_envelope} =
             DurableMemoryUpdateEnvelope.normalize(
               DurableMemoryUpdateEnvelope.memory_validation(
                 memory_iri: "https://jido.run/managed_repos/repo-36/memory#fact/fact-36",
                 actor_id: "system:test",
                 session_id: "session-36-update",
                 revision: "rev-36",
                 freshness_score: 1.0,
                 governed_references: [%{kind: :evidence, id: "evidence-36"}]
               ),
               graph_context("repo-36", "rev-36")
             )

    assert Enum.map(typed_envelope.governed_references, & &1.kind) == [:evidence]

    assert {:ok, legacy_envelope} =
             DurableMemoryUpdateEnvelope.normalize(
               DurableMemoryUpdateEnvelope.memory_invalidation(
                 memory_iri: "https://jido.run/managed_repos/repo-36/memory#fact/fact-36",
                 actor_id: "system:test",
                 session_id: "session-36-update",
                 revision: "rev-36",
                 stale_reason: :workspace_revision_changed,
                 governed_context: %{run_id: "run-36", decision_id: "decision-36"}
               ),
               graph_context("repo-36", "rev-36")
             )

    assert legacy_envelope.governed_references |> Enum.map(& &1.kind) |> Enum.sort() == [:decision, :run]
  end

  defp graph_context(managed_repo_id, revision) do
    %{
      managed_repo_id: managed_repo_id,
      workspace_path: "/tmp/jido_code_phase_36",
      selected_graph_name: MemoryGraph.memory_graph_name(),
      revision_metadata: %{current_revision: revision, requested_revision: revision}
    }
  end
end
