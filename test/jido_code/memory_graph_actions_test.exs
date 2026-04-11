defmodule JidoCode.MemoryGraphActionsTest do
  # covers: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  # covers: architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary
  # covers: architecture.memory_capture_plane.memory_capture_requires_explicit_repo_work_and_actor_context
  # covers: architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
  # covers: architecture.memory_capture_plane.transient_llm_output_is_not_inserted_as_memory_without_adoption
  # covers: architecture.memory_capture_plane.validation_and_invalidation_follow_revision_and_test_evidence
  # covers: architecture.memory_ontology.change_and_revision_provenance_is_explicit
  # covers: architecture.memory_ontology.decision_structure_supports_supersession_and_consequence
  # covers: architecture.memory_ontology.freshness_evidence_and_validation_metadata_are_explicit
  # covers: package.jido_code.version_controlled_quality_surfaces
  use ExUnit.Case, async: true

  alias JidoCode.Actions.{
    GetMemoryGraphStatus,
    InvalidateMemoryGraph,
    QueryMemoryGraph,
    RecordMemoryGraph,
    RefreshMemoryGraph,
    ValidateMemoryGraph
  }

  alias JidoCode.MemoryGraph

  setup do
    workspace_path = create_workspace_path!()
    %{context: %{managed_repo_id: "repo-123", workspace_path: workspace_path}}
  end

  describe "Refresh and validate actions" do
    test "bootstrap the shared store foundation and report ready validation state", %{context: context} do
      assert {:ok, refresh_result} = RefreshMemoryGraph.run(%{revision: "abc123"}, context)

      assert refresh_result.status == :memory_graph_refreshed
      assert refresh_result.store.backend == :triple_store
      assert refresh_result.store.schema == :quad
      assert File.dir?(refresh_result.store.path)
      assert refresh_result.load_counts.memory > 0
      assert refresh_result.load_counts.workflow_provenance > 0
      assert refresh_result.latest_validation_status.state == :validated
      assert refresh_result.latest_validation_status.ready? == true

      assert {:ok, validate_result} =
               ValidateMemoryGraph.run(
                 %{revision: "abc123"},
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status
                 }
               )

      assert validate_result.status == :memory_graph_validated
      assert validate_result.latest_validation_status.ready? == true
      assert validate_result.graph_stats.memory.present? == true
      assert validate_result.graph_stats.workflow_provenance.present? == true
    end

    test "returns explicit not-ready status before the shared store is bootstrapped", %{context: context} do
      assert {:ok, status_result} = GetMemoryGraphStatus.run(%{revision: "abc123"}, context)

      assert status_result.ready? == false
      assert status_result.stale? == false
      assert status_result.latest_validation_status.state == :not_validated
      assert status_result.state == :not_ready
      assert status_result.recovery_action == :refresh
      assert status_result.feedback.recovery.action == :refresh
    end
  end

  describe "QueryMemoryGraph" do
    test "returns typed not-ready error before validation", %{context: context} do
      assert {:error, :memory_graph_not_ready, diagnostics} =
               QueryMemoryGraph.run(%{sparql: "SELECT * WHERE { ?s ?p ?o }"}, context)

      assert diagnostics.graph.state == :not_ready
      assert diagnostics.feedback.state == :not_ready
      assert diagnostics.feedback.recovery.action == :refresh
    end

    test "returns structured SPARQL results for the memory graph after refresh", %{context: context} do
      assert {:ok, refresh_result} = RefreshMemoryGraph.run(%{revision: "abc123"}, context)

      assert {:ok, result} =
               QueryMemoryGraph.run(
                 %{
                   sparql: """
                   SELECT ?class
                   WHERE {
                     ?class a owl:Class .
                     FILTER(?class = jido:Fact)
                   }
                   """
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status,
                   graph: %{revision: "abc123"}
                 }
               )

      assert result.status == :query_succeeded
      assert result.engine == :sparql
      assert result.graph_name == "memory"
      assert result.named_graph_iri == MemoryGraph.memory_named_graph_iri()
      assert result.row_count == 1

      assert Enum.any?(result.bindings, fn row ->
               get_in(row, ["class", :value]) == "https://jido.run/ontology/memory#Fact"
             end)

      assert result.degraded? == false
      assert result.stale_graph? == false
      assert result.feedback.state == :ready
    end

    test "allows bounded degraded queries when the workspace revision moved", %{context: context} do
      assert {:ok, refresh_result} = RefreshMemoryGraph.run(%{}, context)
      rewrite_workspace_module!(context.workspace_path, "ExampleMemoryGraphRenamed")

      assert {:ok, result} =
               QueryMemoryGraph.run(
                 %{sparql: "SELECT * WHERE { ?s ?p ?o } LIMIT 5", allow_stale?: true},
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status
                 }
               )

      assert result.degraded? == true
      assert result.stale_graph? == true
      assert result.stale_reason == :workspace_revision_changed
      assert result.current_revision != result.validated_revision
      assert result.feedback.recovery.action == :validate
    end
  end

  describe "record and invalidate actions" do
    test "records typed workflow provenance envelopes into the workflow_provenance graph", %{context: context} do
      assert {:ok, refresh_result} = RefreshMemoryGraph.run(%{}, context)

      assert {:ok, record_result} =
               RecordMemoryGraph.run(
                 %{
                   graph_name: "workflow_provenance",
                   capture:
                     JidoCode.MemoryGraph.CaptureEnvelope.work_session(
                       session_id: "session-1",
                       actor_id: "system:test",
                       workflow: :plan,
                       work_item_id: "work-1",
                       goal: "Plan work item",
                       anchors: %{module_name: "ExampleMemoryGraph"}
                     )
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status
                 }
               )

      assert record_result.status == :workflow_provenance_recorded
      assert record_result.graph_name == "workflow_provenance"
      assert record_result.capture.kind == :work_session
      assert record_result.latest_record_status.state == :recorded

      assert {:ok, query_result} =
               QueryMemoryGraph.run(
                 %{
                   graph_name: "workflow_provenance",
                   sparql: """
                   SELECT ?session
                   WHERE {
                     ?session a jido:WorkSession ;
                       jido:sessionId "session-1" .
                   }
                   """
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status
                 }
               )

      assert query_result.row_count == 1
    end

    test "fails safely when workflow provenance capture is missing actor context", %{context: context} do
      assert {:ok, refresh_result} = RefreshMemoryGraph.run(%{}, context)

      assert {:error, :invalid_memory_capture, diagnostics} =
               RecordMemoryGraph.run(
                 %{
                   graph_name: "workflow_provenance",
                   capture: %{kind: :work_session, session_id: "session-missing-actor"}
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status
                 }
               )

      assert diagnostics.field == :actor_id
      assert diagnostics.reason == :missing
    end

    test "requires explicit classification metadata before durable memory is recorded", %{context: context} do
      assert {:ok, refresh_result} = RefreshMemoryGraph.run(%{}, context)

      assert {:error, :invalid_memory_capture, diagnostics} =
               RecordMemoryGraph.run(
                 %{
                   capture: %{
                     kind: :fact,
                     actor_id: "system:test",
                     session_id: "missing-classification",
                     content: "example",
                     confidence: 0.8
                   }
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status
                 }
               )

      assert diagnostics.field == :classification
      assert diagnostics.reason == :missing
    end

    test "records typed durable memory instances into the memory graph", %{context: context} do
      assert {:ok, refresh_result} = RefreshMemoryGraph.run(%{}, context)
      revision = refresh_result.latest_validation_status.current_revision

      record_work_session!(context, refresh_result.latest_validation_status, revision, "memory-session-1")

      record_result =
        record_fact_memory!(
          context,
          refresh_result.latest_validation_status,
          revision,
          "memory-session-1",
          "memory-fact-1",
          "ExampleMemoryGraph.greet/1 should keep accepting binaries."
        )

      assert record_result.status == :durable_memory_recorded
      assert record_result.graph_name == "memory"
      assert record_result.capture.kind == :fact

      assert {:ok, query_result} =
               QueryMemoryGraph.run(
                 %{
                   sparql: """
                   SELECT ?memory ?module ?session
                   WHERE {
                     ?memory a jido:Fact ;
                       jido:content "ExampleMemoryGraph.greet/1 should keep accepting binaries." ;
                       jido:sourceSession ?session ;
                       jido:aboutModule ?module .
                   }
                   """
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status,
                   graph: %{revision: revision}
                 }
               )

      assert query_result.row_count == 1
    end

    test "writes typed governed references for provenance, durable memory, and memory updates", %{context: context} do
      assert {:ok, refresh_result} = RefreshMemoryGraph.run(%{}, context)
      revision = refresh_result.latest_validation_status.current_revision

      record_work_session!(
        context,
        refresh_result.latest_validation_status,
        revision,
        "memory-governed-session"
      )

      assert {:ok, provenance_result} =
               RecordMemoryGraph.run(
                 %{
                   graph_name: "workflow_provenance",
                   capture:
                     JidoCode.MemoryGraph.CaptureEnvelope.plan(
                       id: "plan-governed-1",
                       session_id: "memory-governed-session",
                       actor_id: "system:test",
                       workflow: :memory_capture,
                       work_item_id: "work-36",
                       revision: revision,
                       content: "Plan artifact with governed context.",
                       governed_references: [
                         %{kind: :run, id: "run-36"},
                         %{kind: :work_item, id: "work-36"}
                       ]
                     )
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status,
                   graph: %{revision: revision}
                 }
               )

      assert {:ok, memory_result} =
               RecordMemoryGraph.run(
                 %{
                   capture:
                     JidoCode.MemoryGraph.DurableMemoryEnvelope.fact(
                       id: "memory-governed-1",
                       session_id: "memory-governed-session",
                       actor_id: "system:test",
                       revision: revision,
                       content: "Durable memory with governed context.",
                       confidence: 0.9,
                       classification: %{
                         source: "memory_graph_actions_test",
                         reason: "The operator adopted durable memory with typed governed context."
                       },
                       governed_references: [
                         %{kind: :run, id: "run-36"},
                         %{kind: :evidence, id: "evidence-36"}
                       ]
                     )
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status,
                   graph: %{revision: revision}
                 }
               )

      assert {:ok, update_result} =
               RecordMemoryGraph.run(
                 %{
                   capture:
                     JidoCode.MemoryGraph.DurableMemoryUpdateEnvelope.memory_validation(
                       memory_iri: memory_result.capture.resource_iri,
                       actor_id: "system:test",
                       session_id: "memory-governed-session",
                       revision: revision,
                       freshness_score: 0.96,
                       governed_references: [
                         %{kind: :run, id: "run-36"},
                         %{kind: :decision, id: "decision-36"}
                       ]
                     )
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status,
                   graph: %{revision: revision}
                 }
               )

      assert {:ok, provenance_query} =
               QueryMemoryGraph.run(
                 %{
                   graph_name: "workflow_provenance",
                   sparql: """
                   SELECT ?run ?workItem
                   WHERE {
                     <#{provenance_result.capture.resource_iri}> jido:aboutRun ?run ;
                       jido:aboutWorkItem ?workItem .
                     ?run a <https://jido.run/ontology/control-plane#Run> .
                     ?workItem a <https://jido.run/ontology/control-plane#WorkItem> .
                   }
                   """
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status,
                   graph: %{revision: revision}
                 }
               )

      assert provenance_query.row_count == 1

      assert {:ok, provenance_not_artifact_query} =
               QueryMemoryGraph.run(
                 %{
                   graph_name: "workflow_provenance",
                   sparql: """
                   SELECT ?run
                   WHERE {
                     <#{provenance_result.capture.resource_iri}> jido:aboutRun ?run .
                     ?run a jido:EvidenceArtifact .
                   }
                   """
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status,
                   graph: %{revision: revision}
                 }
               )

      assert provenance_not_artifact_query.row_count == 0

      assert {:ok, memory_query} =
               QueryMemoryGraph.run(
                 %{
                   sparql: """
                   SELECT ?run ?evidence
                   WHERE {
                     <#{memory_result.capture.resource_iri}> jido:aboutRun ?run ;
                       jido:aboutEvidence ?evidence .
                     ?run a <https://jido.run/ontology/control-plane#Run> .
                     ?evidence a <https://jido.run/ontology/control-plane#Evidence> .
                   }
                   """
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status,
                   graph: %{revision: revision}
                 }
               )

      assert memory_query.row_count == 1

      assert {:ok, memory_not_artifact_query} =
               QueryMemoryGraph.run(
                 %{
                   sparql: """
                   SELECT ?evidence
                   WHERE {
                     <#{memory_result.capture.resource_iri}> jido:aboutEvidence ?evidence .
                     ?evidence a jido:EvidenceArtifact .
                   }
                   """
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status,
                   graph: %{revision: revision}
                 }
               )

      assert memory_not_artifact_query.row_count == 0

      assert {:ok, update_query} =
               QueryMemoryGraph.run(
                 %{
                   sparql: """
                   SELECT ?run ?decision
                   WHERE {
                     <#{update_result.capture.update_iri}> jido:aboutRun ?run ;
                       jido:aboutDecision ?decision .
                     ?decision a <https://jido.run/ontology/control-plane#Decision> .
                   }
                   """
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status,
                   graph: %{revision: revision}
                 }
               )

      assert update_query.row_count == 1

      assert {:ok, update_not_artifact_query} =
               QueryMemoryGraph.run(
                 %{
                   sparql: """
                   SELECT ?decision
                   WHERE {
                     <#{update_result.capture.update_iri}> jido:aboutDecision ?decision .
                     ?decision a jido:EvidenceArtifact .
                   }
                   """
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status,
                   graph: %{revision: revision}
                 }
               )

      assert update_not_artifact_query.row_count == 0
    end

    test "returns typed durable validation errors when evidence cannot be applied safely", %{context: context} do
      assert {:ok, refresh_result} = RefreshMemoryGraph.run(%{}, context)
      revision = refresh_result.latest_validation_status.current_revision

      assert {:error, :invalid_memory_capture, diagnostics} =
               RecordMemoryGraph.run(
                 %{
                   capture:
                     JidoCode.MemoryGraph.DurableMemoryUpdateEnvelope.memory_validation(
                       actor_id: "system:test",
                       session_id: "validation-missing-target",
                       revision: revision,
                       freshness_score: 0.9
                     )
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status,
                   graph: %{revision: revision}
                 }
               )

      assert diagnostics.field == :memory_iri
      assert diagnostics.reason == :missing
    end

    test "records durable validation metadata with explicit test evidence", %{context: context} do
      assert {:ok, refresh_result} = RefreshMemoryGraph.run(%{}, context)
      revision = refresh_result.latest_validation_status.current_revision

      record_work_session!(
        context,
        refresh_result.latest_validation_status,
        revision,
        "memory-validation-session"
      )

      record_result =
        record_fact_memory!(
          context,
          refresh_result.latest_validation_status,
          revision,
          "memory-validation-session",
          "memory-fact-validation",
          "Validated memory should remain explainable."
        )

      assert {:ok, validation_result} =
               RecordMemoryGraph.run(
                 %{
                   capture:
                     JidoCode.MemoryGraph.DurableMemoryUpdateEnvelope.memory_validation(
                       memory_iri: record_result.capture.resource_iri,
                       actor_id: "system:test",
                       session_id: "memory-validation-session",
                       revision: revision,
                       freshness_score: 0.95,
                       test_run: %{id: "mix-test-validation", label: "mix test"},
                       supported_by: [%{id: "review-validation", label: "review validation"}],
                       evidence_artifacts: [%{id: "artifact-validation", label: "artifact validation"}]
                     )
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status,
                   graph: %{revision: revision}
                 }
               )

      assert validation_result.status == :durable_memory_validated

      assert {:ok, query_result} =
               QueryMemoryGraph.run(
                 %{
                   sparql: """
                   SELECT ?score ?validatedAt ?revision ?testRun
                   WHERE {
                     <#{record_result.capture.resource_iri}> jido:freshnessScore ?score ;
                       jido:lastValidatedAt ?validatedAt ;
                       jido:validForRevision ?revision ;
                       jido:validatedByTestRun ?testRun .
                   }
                   """
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status,
                   graph: %{revision: revision}
                 }
               )

      assert query_result.row_count == 1
      assert get_in(List.first(query_result.bindings), ["score", :lexical]) == "0.95"

      assert {:ok, supported_by_query} =
               QueryMemoryGraph.run(
                 %{
                   sparql: """
                   SELECT ?artifact
                   WHERE {
                     <#{record_result.capture.resource_iri}> jido:supportedBy ?artifact .
                     ?artifact <http://www.w3.org/2000/01/rdf-schema#label> "review validation" .
                   }
                   """
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status,
                   graph: %{revision: revision}
                 }
               )

      assert supported_by_query.row_count == 1
    end

    test "records invalidation and supersession without deleting prior durable memory", %{context: context} do
      assert {:ok, refresh_result} = RefreshMemoryGraph.run(%{}, context)
      initial_revision = refresh_result.latest_validation_status.current_revision

      record_work_session!(
        context,
        refresh_result.latest_validation_status,
        initial_revision,
        "memory-update-session"
      )

      invalidated_memory =
        record_fact_memory!(
          context,
          refresh_result.latest_validation_status,
          initial_revision,
          "memory-update-session",
          "memory-fact-invalidated",
          "This fact will be invalidated after a later revision."
        )

      still_valid_memory =
        record_fact_memory!(
          context,
          refresh_result.latest_validation_status,
          initial_revision,
          "memory-update-session",
          "memory-fact-still-valid",
          "This fact remains valid after revalidation."
        )

      prior_decision =
        record_decision_memory!(
          context,
          refresh_result.latest_validation_status,
          initial_revision,
          "memory-update-session",
          "decision-prior",
          "Keep the original greet contract.",
          "It matches the current public API."
        )

      newer_decision =
        record_decision_memory!(
          context,
          refresh_result.latest_validation_status,
          initial_revision,
          "memory-update-session",
          "decision-new",
          "Document the stronger greet contract.",
          "The revised API decision supersedes the older wording."
        )

      rewrite_workspace_module!(context.workspace_path, "ExampleMemoryGraphUpdated")
      {:ok, revision_metadata} = MemoryGraph.current_revision_metadata(context.workspace_path)
      updated_revision = revision_metadata.current_revision

      assert {:ok, invalidation_result} =
               RecordMemoryGraph.run(
                 %{
                   capture:
                     JidoCode.MemoryGraph.DurableMemoryUpdateEnvelope.memory_invalidation(
                       memory_iri: invalidated_memory.capture.resource_iri,
                       actor_id: "system:test",
                       session_id: "memory-update-session",
                       revision: updated_revision,
                       stale_reason: :workspace_revision_changed
                     )
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status,
                   graph: %{revision: updated_revision}
                 }
               )

      assert invalidation_result.status == :durable_memory_invalidated

      assert {:ok, validation_result} =
               RecordMemoryGraph.run(
                 %{
                   capture:
                     JidoCode.MemoryGraph.DurableMemoryUpdateEnvelope.memory_validation(
                       memory_iri: still_valid_memory.capture.resource_iri,
                       actor_id: "system:test",
                       session_id: "memory-update-session",
                       revision: updated_revision,
                       freshness_score: 1.0,
                       test_run: %{id: "mix-test-still-valid", label: "mix test"}
                     )
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status,
                   graph: %{revision: updated_revision}
                 }
               )

      assert validation_result.status == :durable_memory_validated

      assert {:ok, supersession_result} =
               RecordMemoryGraph.run(
                 %{
                   capture:
                     JidoCode.MemoryGraph.DurableMemoryUpdateEnvelope.decision_supersession(
                       memory_iri: newer_decision.capture.resource_iri,
                       superseded_memory_iri: prior_decision.capture.resource_iri,
                       actor_id: "system:test",
                       session_id: "memory-update-session",
                       revision: updated_revision
                     )
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status,
                   graph: %{revision: updated_revision}
                 }
               )

      assert supersession_result.status == :durable_memory_superseded

      assert {:ok, invalidated_query} =
               QueryMemoryGraph.run(
                 %{
                   revision: updated_revision,
                   allow_stale?: true,
                   sparql: """
                   SELECT ?memory
                   WHERE {
                     ?memory a jido:Fact ;
                       jido:invalidatedByRevision ?revision .
                   }
                   """
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status
                 }
               )

      assert invalidated_query.row_count == 1

      assert get_in(List.first(invalidated_query.bindings), ["memory", :value]) ==
               invalidated_memory.capture.resource_iri

      assert {:ok, current_query} =
               QueryMemoryGraph.run(
                 %{
                   revision: updated_revision,
                   allow_stale?: true,
                   sparql: """
                   SELECT ?memory
                   WHERE {
                     VALUES ?memory { <#{still_valid_memory.capture.resource_iri}> }
                     ?memory a jido:Fact ;
                       jido:validForRevision <https://jido.run/managed_repos/#{context.managed_repo_id}/workflow_provenance#revision/#{updated_revision}> .
                   }
                   """
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status
                 }
               )

      assert current_query.row_count == 1

      assert {:ok, still_valid_invalidation_query} =
               QueryMemoryGraph.run(
                 %{
                   revision: updated_revision,
                   allow_stale?: true,
                   sparql: """
                   SELECT ?invalidated
                   WHERE {
                     <#{still_valid_memory.capture.resource_iri}> jido:invalidatedByRevision ?invalidated .
                   }
                   """
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status
                 }
               )

      assert still_valid_invalidation_query.row_count == 0

      assert {:ok, decision_query} =
               QueryMemoryGraph.run(
                 %{
                   revision: updated_revision,
                   allow_stale?: true,
                   sparql: """
                   SELECT ?status
                   WHERE {
                     <#{prior_decision.capture.resource_iri}> jido:decisionStatus ?status .
                   }
                   """
                 },
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status
                 }
               )

      assert decision_query.row_count >= 1

      assert Enum.any?(decision_query.bindings, fn row ->
               get_in(row, ["status", :value]) == "https://jido.run/ontology/memory#superseded"
             end)
    end

    test "returns a bounded invalidation outcome", %{context: context} do
      assert {:ok, refresh_result} = RefreshMemoryGraph.run(%{revision: "abc123"}, context)

      assert {:ok, result} =
               InvalidateMemoryGraph.run(
                 %{reason: :manual_invalidation, revision: "abc123"},
                 %{
                   managed_repo_id: context.managed_repo_id,
                   workspace_path: context.workspace_path,
                   latest_validation_status: refresh_result.latest_validation_status
                 }
               )

      assert result.status == :memory_graph_invalidated
      assert result.stale? == true
      assert result.stale_reason == :manual_invalidation
      assert result.latest_validation_status.state == :invalidated
      assert result.latest_validation_status.ready? == false
      assert result.feedback.state == :invalidated
      assert result.feedback.recovery.action == :validate
    end
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_memory_graph_actions_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule MemoryGraphActionsExample.MixProject do
        use Mix.Project

        def project do
          [app: :memory_graph_actions_example, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example.ex"),
      """
      defmodule ExampleMemoryGraph do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
  end

  defp rewrite_workspace_module!(workspace_path, module_name) do
    File.write!(
      Path.join(workspace_path, "lib/example.ex"),
      """
      defmodule #{module_name} do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )
  end

  defp record_work_session!(context, latest_validation_status, revision, session_id) do
    assert {:ok, provenance_result} =
             RecordMemoryGraph.run(
               %{
                 graph_name: "workflow_provenance",
                 capture:
                   JidoCode.MemoryGraph.CaptureEnvelope.work_session(
                     session_id: session_id,
                     actor_id: "system:test",
                     workflow: :memory_capture,
                     work_item_id: "work-1",
                     goal: "Record durable memory",
                     revision: revision,
                     anchors: %{module_name: "ExampleMemoryGraph"}
                   )
               },
               %{
                 managed_repo_id: context.managed_repo_id,
                 workspace_path: context.workspace_path,
                 latest_validation_status: latest_validation_status
               }
             )

    provenance_result
  end

  defp record_fact_memory!(
         context,
         latest_validation_status,
         revision,
         session_id,
         id,
         content
       ) do
    assert {:ok, record_result} =
             RecordMemoryGraph.run(
               %{
                 capture:
                   JidoCode.MemoryGraph.DurableMemoryEnvelope.fact(
                     id: id,
                     session_id: session_id,
                     actor_id: "system:test",
                     revision: revision,
                     content: content,
                     confidence: 0.9,
                     classification: %{
                       source: "memory_graph_actions_test",
                       reason: "The operator explicitly adopted a durable fact."
                     },
                     anchors: %{module_name: "ExampleMemoryGraph"}
                   )
               },
               %{
                 managed_repo_id: context.managed_repo_id,
                 workspace_path: context.workspace_path,
                 latest_validation_status: latest_validation_status,
                 graph: %{revision: revision}
               }
             )

    record_result
  end

  defp record_decision_memory!(
         context,
         latest_validation_status,
         revision,
         session_id,
         id,
         content,
         rationale
       ) do
    assert {:ok, record_result} =
             RecordMemoryGraph.run(
               %{
                 capture:
                   JidoCode.MemoryGraph.DurableMemoryEnvelope.decision(
                     id: id,
                     session_id: session_id,
                     actor_id: "system:test",
                     revision: revision,
                     content: content,
                     rationale: rationale,
                     classification: %{
                       source: "memory_graph_actions_test",
                       reason: "The operator explicitly adopted a durable decision."
                     },
                     anchors: %{module_name: "ExampleMemoryGraph"}
                   )
               },
               %{
                 managed_repo_id: context.managed_repo_id,
                 workspace_path: context.workspace_path,
                 latest_validation_status: latest_validation_status,
                 graph: %{revision: revision}
               }
             )

    record_result
  end
end
