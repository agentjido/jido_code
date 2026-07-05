defmodule JidoCode.MemoryGraph.DurableMemoryWriter do
  # covers: architecture.memory_capture_plane.durable_memories_are_inserted_through_explicit_classification_and_adoption
  # covers: architecture.memory_capture_plane.workflow_provenance_and_memory_are_written_to_distinct_named_graphs
  # covers: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  # covers: architecture.memory_graph.memory_graph_supports_cross_graph_provenance
  # covers: architecture.memory_graph.memory_graph_links_to_source_code_entities_by_stable_iri
  # covers: architecture.memory_ontology.change_and_revision_provenance_is_explicit
  @moduledoc false

  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.Config
  alias JidoCode.MemoryGraph.DurableMemoryEnvelope
  alias JidoCode.MemoryGraph.GovernedReference
  alias JidoCode.MemoryGraph.ResourceLimits
  alias JidoCode.MemoryGraph.Retry

  @jido_ns "https://jido.run/ontology/memory#"
  @prov_ns "http://www.w3.org/ns/prov#"
  @rdfs_ns "http://www.w3.org/2000/01/rdf-schema#"

  @type graph_context :: map()

  @spec write(graph_context(), map()) :: {:ok, map()} | {:error, atom(), map()}
  def write(graph_context, capture) when is_map(graph_context) and is_map(capture) do
    with {:ok, envelope} <- DurableMemoryEnvelope.normalize(capture, graph_context),
         true <-
           graph_context.selected_graph_name == MemoryGraph.memory_graph_name() or
             {:error, :invalid_memory_capture, wrong_graph_diagnostics(graph_context, capture)},
         :ok <- validate_resource_limits(graph_context.graph_store_path, envelope),
         {:ok, store} <- open_store(graph_context.graph_store_path) do
      try do
        graph = RDF.Graph.new(triples(envelope))

        case load_graph_with_timeout(store, graph, envelope) do
          {:ok, triple_count} ->
            recorded_at = DateTime.utc_now() |> DateTime.truncate(:second)

            {:ok,
             %{
               status: :durable_memory_recorded,
               graph_name: envelope.graph_name,
               named_graph_iri: envelope.named_graph_iri,
               capture: %{
                 kind: envelope.kind,
                 resource_id: envelope.resource_id,
                 resource_iri: to_string(envelope.resource_iri),
                 session_id: envelope.session_id,
                 actor_id: envelope.actor_id,
                 workflow: envelope.workflow,
                 work_item_id: envelope.work_item_id
               },
               triple_count: triple_count,
               latest_record_status: %{
                 state: :recorded,
                 ready?: true,
                 graph_name: envelope.graph_name,
                 capture_kind: envelope.kind,
                 resource_iri: to_string(envelope.resource_iri),
                 session_id: envelope.session_id,
                 recorded_revision: envelope.revision,
                 recorded_at: recorded_at,
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

  defp triples(envelope) do
    memory = envelope.resource_iri
    session = envelope.session_iri
    actor = envelope.actor_iri
    revision = envelope.revision_iri

    memory_triples =
      [
        {memory, RDF.type(), envelope.resource_class_iri},
        {memory, RDF.type(), jido("Memory")},
        {memory, RDF.type(), prov("Entity")},
        {memory, jido("content"), RDF.literal(envelope.content)},
        {memory, jido("timestamp"), RDF.XSD.dateTime(envelope.timestamp)},
        {memory, jido("sourceSession"), session},
        {session, jido("hasMemory"), memory},
        {memory, jido("observedAtRevision"), envelope.observed_at_revision_iri},
        {memory, jido("validForRevision"), envelope.valid_for_revision_iri},
        {memory, prov("wasAttributedTo"), actor},
        {memory, prov("wasDerivedFrom"), revision},
        maybe_triple(memory, jido("confidence"), decimal_or_nil(envelope.confidence)),
        maybe_triple(memory, jido("rationale"), literal_or_nil(envelope.rationale)),
        maybe_triple(memory, jido("context"), literal_or_nil(envelope.lesson_context)),
        maybe_triple(memory, jido("decisionStatus"), envelope.decision_status_iri),
        maybe_triple(memory, jido("supersedes"), envelope.supersedes_iri)
      ]
      |> add_memory_links(memory, jido("relatedTo"), envelope.related_memory_iris)
      |> add_memory_links(memory, jido("alternativeConsidered"), envelope.alternative_considered_iris)
      |> add_memory_links(memory, jido("hasConsequence"), envelope.consequence_memory_iris)
      |> add_anchors(memory, envelope.source_code_anchors)
      |> add_governed_references(memory, envelope.managed_repo_id, envelope.governed_references)
      |> add_tags(memory, envelope)
      |> add_artifact_links(memory, envelope)
      |> add_conversation_context(memory, envelope.conversation_context)

    (classification_triples(envelope) ++ memory_triples)
    |> Enum.reject(&is_nil/1)
  end

  defp classification_triples(envelope) do
    classification_iri =
      RDF.iri("#{MemoryGraph.base_iri(envelope.managed_repo_id)}classification/#{URI.encode(envelope.resource_id)}")

    [
      {classification_iri, RDF.type(), jido("EvidenceArtifact")},
      {classification_iri, RDF.type(), prov("Entity")},
      maybe_triple(classification_iri, rdfs("label"), literal_or_nil(envelope.classification.label)),
      maybe_triple(classification_iri, rdfs("comment"), literal_or_nil(envelope.classification.reason)),
      {classification_iri, prov("wasDerivedFrom"), envelope.session_iri},
      {envelope.resource_iri, jido("supportedBy"), classification_iri},
      {envelope.resource_iri, jido("evidenceArtifact"), classification_iri}
    ]
  end

  defp add_artifact_links(triples, subject, envelope) do
    triples
    |> add_artifacts(subject, envelope.supported_by_artifacts, jido("supportedBy"))
    |> add_artifacts(subject, envelope.evidence_artifacts, jido("evidenceArtifact"))
    |> maybe_add_confidence_source(subject, envelope.confidence_source)
  end

  defp add_conversation_context(triples, _subject, nil), do: triples

  defp add_conversation_context(triples, subject, context) when is_map(context) do
    triples ++
      [
        maybe_triple(subject, jido("conversationId"), literal_or_nil(Map.get(context, :conversation_id))),
        maybe_triple(subject, jido("conversationTurnId"), literal_or_nil(Map.get(context, :turn_id))),
        maybe_triple(subject, jido("conversationCommandId"), literal_or_nil(Map.get(context, :command_id))),
        maybe_triple(subject, jido("conversationEvent"), literal_or_nil(Map.get(context, :conversation_event))),
        maybe_triple(subject, jido("clarificationState"), literal_or_nil(Map.get(context, :clarification_state))),
        maybe_triple(subject, jido("conversationScope"), literal_or_nil(Map.get(context, :scope))),
        maybe_triple(subject, jido("conversationAttachmentMode"), literal_or_nil(Map.get(context, :attachment_mode))),
        maybe_triple(subject, jido("conversationStatus"), literal_or_nil(Map.get(context, :status))),
        maybe_triple(subject, jido("conversationSource"), literal_or_nil(Map.get(context, :source)))
      ]
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

  defp add_governed_references(triples, _subject, _managed_repo_id, []), do: triples

  defp add_governed_references(triples, subject, managed_repo_id, references) when is_list(references) do
    triples ++
      Enum.flat_map(references, fn
        %{kind: kind, id: id, iri: iri} = reference when not is_nil(iri) ->
          governed_reference_triples(subject, managed_repo_id, kind, id, iri, Map.get(reference, :label))

        _other ->
          []
      end)
  end

  defp governed_reference_triples(subject, managed_repo_id, kind, id, iri, label) do
    governed_resource = RDF.iri(iri)
    managed_repo_resource = GovernedReference.resource(managed_repo_id, :managed_repo, managed_repo_id)
    managed_repo_label = GovernedReference.label(:managed_repo, managed_repo_id)

    managed_repo_triples =
      [
        {managed_repo_resource, RDF.type(), GovernedReference.class_iri(:managed_repo)},
        {managed_repo_resource, RDF.type(), GovernedReference.governed_record_class_iri()},
        {managed_repo_resource, RDF.type(), prov("Entity")},
        {managed_repo_resource, GovernedReference.id_predicate_iri(:managed_repo), RDF.literal(managed_repo_id)},
        maybe_triple(managed_repo_resource, rdfs("label"), RDF.literal(managed_repo_label)),
        maybe_triple(
          managed_repo_resource,
          GovernedReference.record_label_predicate_iri(),
          RDF.literal(managed_repo_label)
        )
      ]

    reference_triples =
      [
        {governed_resource, RDF.type(), GovernedReference.class_iri(kind)},
        {governed_resource, RDF.type(), GovernedReference.governed_record_class_iri()},
        {governed_resource, RDF.type(), prov("Entity")},
        {governed_resource, GovernedReference.id_predicate_iri(kind), RDF.literal(id)},
        maybe_triple(governed_resource, rdfs("label"), literal_or_nil(label)),
        maybe_triple(governed_resource, GovernedReference.record_label_predicate_iri(), literal_or_nil(label)),
        {subject, GovernedReference.predicate_iri(kind), governed_resource}
      ] ++
        case kind do
          :managed_repo -> []
          _other -> [{governed_resource, GovernedReference.for_managed_repo_predicate_iri(), managed_repo_resource}]
        end

    managed_repo_triples ++ reference_triples
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

  defp add_memory_links(triples, _subject, _predicate, []), do: triples

  defp add_memory_links(triples, subject, predicate, iris) do
    triples ++ Enum.map(iris, &{subject, predicate, &1})
  end

  defp add_anchors(triples, subject, anchors) do
    triples ++
      Enum.map(anchors, fn
        {:about_repository, iri} -> {subject, jido("aboutRepository"), iri}
        {:about_file, iri} -> {subject, jido("aboutFile"), iri}
        {:about_module, iri} -> {subject, jido("aboutModule"), iri}
        {:about_function, iri} -> {subject, jido("aboutFunction"), iri}
        {:about_test, iri} -> {subject, jido("aboutTest"), iri}
        {:about_config, iri} -> {subject, jido("aboutConfig"), iri}
        {:affects_symbol, iri} -> {subject, jido("affectsSymbol"), iri}
      end)
  end

  defp add_tags(triples, _subject, %{tags: []}), do: triples

  defp add_tags(triples, subject, %{tags: tags, managed_repo_id: managed_repo_id}) do
    triples ++
      Enum.flat_map(tags, fn tag ->
        tag_iri = RDF.iri("#{MemoryGraph.base_iri(managed_repo_id)}tag/#{URI.encode(tag)}")

        [
          {tag_iri, RDF.type(), jido("Tag")},
          maybe_triple(tag_iri, rdfs("label"), RDF.literal(tag)),
          {subject, jido("hasTag"), tag_iri}
        ]
      end)
  end

  defp open_store(store_path) do
    case TripleStore.open(store_path, create_if_missing: false, schema: :quad) do
      {:ok, store} -> {:ok, store}
      {:error, reason} -> {:error, :memory_graph_record_failed, %{stage: :open_store, reason: inspect(reason)}}
    end
  end

  defp load_graph_with_timeout(store, graph, envelope) do
    timeout = Config.store_timeout([])

    load_task =
      Task.async(fn ->
        Retry.with_write_retry(
          fn -> TripleStore.load_graph(store, graph, graph: MemoryGraph.memory_named_graph_resource()) end,
          attempt_context: %{resource_id: envelope.resource_id, kind: envelope.kind}
        )
      end)

    case Task.yield(load_task, timeout) || Task.shutdown(load_task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, %{stage: :load_memory_graph, reason: :timeout, timeout_ms: timeout}}
    end
  end

  defp validate_resource_limits(store_path, envelope) do
    # Estimate the size of this write
    estimated_triples = estimate_triple_count(envelope)
    estimated_bytes = ResourceLimits.estimate_graph_size(estimated_triples, [])

    with :ok <- ResourceLimits.validate_graph_size(store_path, estimated_bytes, []),
         :ok <- ResourceLimits.validate_disk_space(store_path, estimated_bytes, []),
         :ok <- ResourceLimits.validate_concurrent_operations([]) do
      :ok
    else
      {:error, :graph_size_limit_exceeded, _detail} ->
        # Allow write with degraded warning
        log_resource_limit_warning(:graph_size, envelope)
        :ok

      {:error, :disk_space_insufficient, detail} ->
        {:error, :memory_graph_write_failed, Map.put(detail, :stage, :validate_disk_space)}

      {:error, :concurrent_operation_limit_exceeded, detail} ->
        {:error, :memory_graph_write_failed, Map.put(detail, :stage, :validate_concurrent_operations)}
    end
  end

  defp estimate_triple_count(envelope) do
    # Base triples for a memory
    base_count = 20
    tags_count = length(envelope.tags) * 3
    governed_count = length(envelope.governed_references) * 7
    anchor_count = length(envelope.source_code_anchors) * 2
    artifact_count = length(envelope.supported_by_artifacts) * 5
    evidence_count = length(envelope.evidence_artifacts) * 5

    base_count + tags_count + governed_count + anchor_count + artifact_count + evidence_count
  end

  defp log_resource_limit_warning(limit_type, envelope) do
    require Logger

    Logger.warning("""
    Memory graph resource limit exceeded: #{limit_type}
    Resource ID: #{envelope.resource_id}
    Kind: #{envelope.kind}
    Operation proceeding with degraded capacity.
    """)
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

  defp decimal_or_nil(nil), do: nil
  defp decimal_or_nil(value), do: RDF.XSD.decimal(value)

  defp jido(local), do: RDF.iri(@jido_ns <> local)
  defp prov(local), do: RDF.iri(@prov_ns <> local)
  defp rdfs(local), do: RDF.iri(@rdfs_ns <> local)
end
