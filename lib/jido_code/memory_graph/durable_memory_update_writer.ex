defmodule JidoCode.MemoryGraph.DurableMemoryUpdateWriter do
  # covers: architecture.memory_capture_plane.validation_and_invalidation_follow_revision_and_test_evidence
  # covers: architecture.memory_capture_plane.workflow_provenance_and_memory_are_written_to_distinct_named_graphs
  # covers: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  # covers: architecture.memory_graph.memory_graph_supports_cross_graph_provenance
  # covers: architecture.memory_ontology.change_and_revision_provenance_is_explicit
  # covers: architecture.memory_ontology.decision_structure_supports_supersession_and_consequence
  # covers: architecture.memory_ontology.freshness_evidence_and_validation_metadata_are_explicit
  # covers: architecture.memory_ontology.memory_updates_preserve_mutation_lineage
  @moduledoc false

  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.DurableMemoryUpdateEnvelope

  @jido_ns "https://jido.run/ontology/memory#"
  @prov_ns "http://www.w3.org/ns/prov#"
  @rdfs_ns "http://www.w3.org/2000/01/rdf-schema#"

  @type graph_context :: map()

  @spec write(graph_context(), map()) :: {:ok, map()} | {:error, atom(), map()}
  def write(graph_context, capture) when is_map(graph_context) and is_map(capture) do
    with {:ok, envelope} <- DurableMemoryUpdateEnvelope.normalize(capture, graph_context),
         true <-
           graph_context.selected_graph_name == MemoryGraph.memory_graph_name() or
             {:error, :invalid_memory_capture, wrong_graph_diagnostics(graph_context, capture)},
         {:ok, store} <- open_store(graph_context.graph_store_path) do
      try do
        graph = RDF.Graph.new(triples(envelope))

        case TripleStore.load_graph(store, graph, graph: MemoryGraph.memory_named_graph_resource()) do
          {:ok, triple_count} ->
            {:ok,
             %{
               status: status(envelope.kind),
               graph_name: envelope.graph_name,
               named_graph_iri: envelope.named_graph_iri,
               capture: %{
                 kind: envelope.kind,
                 memory_iri: to_string(envelope.memory_iri),
                 superseded_memory_iri: envelope.superseded_memory_iri && to_string(envelope.superseded_memory_iri),
                 session_id: envelope.session_id,
                 actor_id: envelope.actor_id,
                 revision: envelope.revision,
                 update_iri: to_string(envelope.update_iri)
               },
               triple_count: triple_count,
               latest_record_status: %{
                 state: :recorded,
                 ready?: true,
                 graph_name: envelope.graph_name,
                 capture_kind: envelope.kind,
                 resource_iri: to_string(envelope.memory_iri),
                 session_id: envelope.session_id,
                 recorded_revision: envelope.revision,
                 recorded_at: envelope.timestamp,
                 failure: nil
               }
             }}

          {:error, reason} ->
            {:error, :memory_graph_record_failed, %{stage: :load_memory_graph, reason: inspect(reason)}}
        end
      after
        :ok = TripleStore.close(store)
      end
    end
  end

  defp triples(%{kind: :memory_validation} = envelope) do
    [
      revision_triples(envelope),
      update_artifact_triples(envelope, "Memory validation update"),
      test_run_triples(envelope),
      artifact_links(envelope.memory_iri, envelope),
      [
        {envelope.memory_iri, jido("freshnessScore"), RDF.XSD.decimal(envelope.freshness_score)},
        {envelope.memory_iri, jido("lastValidatedAt"), RDF.XSD.dateTime(envelope.timestamp)},
        {envelope.memory_iri, jido("validForRevision"), envelope.valid_for_revision_iri},
        {envelope.memory_iri, jido("supportedBy"), envelope.update_iri},
        {envelope.memory_iri, jido("evidenceArtifact"), envelope.update_iri},
        maybe_triple(
          envelope.memory_iri,
          jido("validatedByTestRun"),
          envelope.test_run && envelope.test_run.iri
        )
      ]
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  defp triples(%{kind: :memory_invalidation} = envelope) do
    [
      revision_triples(envelope),
      update_artifact_triples(envelope, "Memory invalidation update"),
      artifact_links(envelope.memory_iri, envelope),
      [
        {envelope.memory_iri, jido("invalidatedByRevision"), envelope.invalidated_by_revision_iri},
        {envelope.memory_iri, jido("staleReason"), RDF.literal(envelope.stale_reason)},
        {envelope.memory_iri, jido("freshnessScore"), RDF.XSD.decimal(envelope.freshness_score)},
        {envelope.memory_iri, jido("supportedBy"), envelope.update_iri},
        {envelope.memory_iri, jido("evidenceArtifact"), envelope.update_iri}
      ]
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  defp triples(%{kind: :decision_supersession} = envelope) do
    [
      revision_triples(envelope),
      update_artifact_triples(envelope, "Decision supersession update"),
      artifact_links(envelope.memory_iri, envelope),
      [
        {envelope.memory_iri, jido("supersedes"), envelope.superseded_memory_iri},
        maybe_triple(envelope.memory_iri, jido("decisionStatus"), envelope.decision_status_iri),
        maybe_triple(
          envelope.superseded_memory_iri,
          jido("decisionStatus"),
          envelope.superseded_status_iri
        ),
        {envelope.memory_iri, jido("freshnessScore"), RDF.XSD.decimal(envelope.freshness_score)},
        {envelope.memory_iri, jido("lastValidatedAt"), RDF.XSD.dateTime(envelope.timestamp)},
        {envelope.memory_iri, jido("validForRevision"), envelope.valid_for_revision_iri},
        {envelope.memory_iri, jido("supportedBy"), envelope.update_iri},
        {envelope.memory_iri, jido("evidenceArtifact"), envelope.update_iri},
        {envelope.superseded_memory_iri, jido("invalidatedByRevision"), envelope.invalidated_by_revision_iri},
        {envelope.superseded_memory_iri, jido("staleReason"), RDF.literal(envelope.stale_reason)},
        {envelope.superseded_memory_iri, jido("freshnessScore"), RDF.XSD.decimal(0)},
        {envelope.superseded_memory_iri, jido("supportedBy"), envelope.update_iri},
        {envelope.superseded_memory_iri, jido("evidenceArtifact"), envelope.update_iri}
      ]
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  defp revision_triples(envelope) do
    [
      {envelope.revision_iri, RDF.type(), jido("RepositoryRevision")},
      {envelope.revision_iri, RDF.type(), prov("Entity")},
      maybe_triple(envelope.revision_iri, rdfs("label"), RDF.literal(envelope.revision))
    ]
  end

  defp update_artifact_triples(envelope, label) do
    [
      {envelope.update_iri, RDF.type(), jido("EvidenceArtifact")},
      {envelope.update_iri, RDF.type(), prov("Entity")},
      maybe_triple(envelope.update_iri, rdfs("label"), RDF.literal(label)),
      {envelope.update_iri, prov("wasDerivedFrom"), envelope.session_iri},
      {envelope.update_iri, prov("wasAttributedTo"), envelope.actor_iri},
      {envelope.update_iri, jido("observedAtRevision"), envelope.revision_iri}
    ]
  end

  defp test_run_triples(%{test_run: nil}), do: []

  defp test_run_triples(%{test_run: test_run, actor_iri: actor_iri}) do
    [
      {test_run.iri, RDF.type(), jido("TestRun")},
      {test_run.iri, RDF.type(), prov("Activity")},
      maybe_triple(test_run.iri, rdfs("label"), literal_or_nil(test_run.label)),
      {test_run.iri, prov("wasAttributedTo"), actor_iri}
    ]
  end

  defp artifact_links(subject, envelope) do
    []
    |> add_artifacts(subject, envelope.governed_artifacts, jido("supportedBy"))
    |> add_artifacts(subject, envelope.supported_by_artifacts, jido("supportedBy"))
    |> add_artifacts(subject, envelope.evidence_artifacts, jido("evidenceArtifact"))
    |> maybe_add_confidence_source(subject, envelope.confidence_source)
  end

  defp add_artifacts(triples, _subject, [], _predicate), do: triples

  defp add_artifacts(triples, subject, artifacts, predicate) do
    triples ++
      Enum.flat_map(artifacts, fn artifact ->
        [
          {artifact.iri, RDF.type(), jido("EvidenceArtifact")},
          {artifact.iri, RDF.type(), prov("Entity")},
          maybe_triple(artifact.iri, rdfs("label"), literal_or_nil(artifact.label)),
          {subject, predicate, artifact.iri},
          {subject, jido("supportedBy"), artifact.iri}
        ]
      end)
  end

  defp maybe_add_confidence_source(triples, _subject, nil), do: triples

  defp maybe_add_confidence_source(triples, subject, artifact) do
    triples ++
      [
        {artifact.iri, RDF.type(), jido("EvidenceArtifact")},
        {artifact.iri, RDF.type(), prov("Entity")},
        maybe_triple(artifact.iri, rdfs("label"), literal_or_nil(artifact.label)),
        {subject, jido("confidenceSource"), artifact.iri},
        {subject, jido("supportedBy"), artifact.iri}
      ]
  end

  defp status(:memory_validation), do: :durable_memory_validated
  defp status(:memory_invalidation), do: :durable_memory_invalidated
  defp status(:decision_supersession), do: :durable_memory_superseded

  defp open_store(store_path) do
    case TripleStore.open(store_path, create_if_missing: false, schema: :quad) do
      {:ok, store} -> {:ok, store}
      {:error, reason} -> {:error, :memory_graph_record_failed, %{stage: :open_store, reason: inspect(reason)}}
    end
  end

  defp wrong_graph_diagnostics(graph_context, capture) do
    %{
      state: :capture_plane_not_ready,
      graph_name: graph_context.selected_graph_name,
      named_graph_iri: graph_context.selected_named_graph_iri,
      capture_ready?: false,
      current_revision: graph_context.revision_metadata.current_revision,
      requested_revision: graph_context.revision_metadata.requested_revision,
      supported_graph_name: MemoryGraph.memory_graph_name(),
      capture: capture
    }
  end

  defp maybe_triple(_subject, _predicate, nil), do: nil
  defp maybe_triple(subject, predicate, object), do: {subject, predicate, object}

  defp literal_or_nil(nil), do: nil
  defp literal_or_nil(value), do: RDF.literal(value)

  defp jido(local), do: RDF.iri(@jido_ns <> local)
  defp prov(local), do: RDF.iri(@prov_ns <> local)
  defp rdfs(local), do: RDF.iri(@rdfs_ns <> local)
end
