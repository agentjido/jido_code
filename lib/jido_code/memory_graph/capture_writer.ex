defmodule JidoCode.MemoryGraph.CaptureWriter do
  # covers: architecture.memory_capture_plane.memory_capture_plane_is_canonical_write_boundary
  # covers: architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
  # covers: architecture.memory_capture_plane.workflow_provenance_and_memory_are_written_to_distinct_named_graphs
  # covers: architecture.memory_graph.memory_graph_supports_cross_graph_provenance
  @moduledoc false

  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.CaptureEnvelope
  alias JidoCode.MemoryGraph.GovernedReference

  @jido_ns "https://jido.run/ontology/memory#"
  @prov_ns "http://www.w3.org/ns/prov#"
  @rdfs_ns "http://www.w3.org/2000/01/rdf-schema#"

  @type graph_context :: map()

  @spec write(graph_context(), map()) :: {:ok, map()} | {:error, atom(), map()}
  def write(graph_context, capture) when is_map(graph_context) and is_map(capture) do
    with {:ok, envelope} <- CaptureEnvelope.normalize(capture, graph_context),
         true <-
           graph_context.selected_graph_name == MemoryGraph.workflow_provenance_graph_name() or
             {:error, :memory_capture_plane_not_ready, wrong_graph_diagnostics(graph_context, capture)},
         {:ok, store} <- open_store(graph_context.graph_store_path) do
      try do
        graph = RDF.Graph.new(triples(envelope))

        with {:ok, triple_count} <- load_graph(store, graph) do
          recorded_at = DateTime.utc_now() |> DateTime.truncate(:second)

          {:ok,
           %{
             status: :workflow_provenance_recorded,
             graph_name: envelope.graph_name,
             named_graph_iri: envelope.named_graph_iri,
             capture: %{
               kind: envelope.kind,
               resource_id: envelope.resource_id,
               resource_iri: to_string(envelope.resource_iri),
               session_id: envelope.session_id,
               session_iri: to_string(envelope.session_iri),
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
        end
      after
        :ok = TripleStore.close(store)
      end
    end
  end

  defp triples(envelope) do
    resource = envelope.resource_iri
    session = envelope.session_iri
    actor = envelope.actor_iri
    revision = envelope.revision_iri
    resource_class = envelope.resource_class_iri

    common_actor_and_revision =
      [
        {actor, RDF.type(), jido("Actor")},
        {actor, RDF.type(), prov("Agent")},
        maybe_triple(actor, rdfs("label"), RDF.literal(envelope.actor_id)),
        {revision, RDF.type(), jido("RepositoryRevision")},
        {revision, RDF.type(), prov("Entity")},
        maybe_triple(revision, rdfs("label"), RDF.literal(envelope.revision))
      ]

    session_stub =
      [
        {session, RDF.type(), jido("WorkSession")},
        maybe_triple(session, jido("sessionId"), RDF.literal(envelope.session_id)),
        maybe_triple(session, prov("startedAtTime"), RDF.XSD.dateTime(envelope.started_at)),
        {session, jido("performedByActor"), actor},
        {session, jido("validForRevision"), revision},
        maybe_triple(session, jido("sessionGoal"), literal_or_nil(envelope.goal)),
        maybe_triple(session, jido("sessionOutcome"), literal_or_nil(envelope.outcome)),
        maybe_triple(session, jido("branchName"), literal_or_nil(envelope.branch_name)),
        maybe_triple(session, rdfs("label"), literal_or_nil(envelope.label))
      ]
      |> maybe_add_model(envelope)
      |> maybe_add_toolchain(envelope)
      |> add_anchors(session, envelope.source_code_anchors)
      |> add_related_resources(session, related_session_resources(envelope))

    resource_triples =
      case envelope.kind do
        :work_session ->
          []

        :agent_run ->
          [
            {session, jido("hasAgentRun"), resource},
            {resource, RDF.type(), resource_class},
            {resource, RDF.type(), prov("Activity")},
            maybe_triple(resource, prov("startedAtTime"), RDF.XSD.dateTime(envelope.started_at)),
            maybe_triple(resource, prov("endedAtTime"), datetime_or_nil(envelope.ended_at)),
            maybe_triple(resource, rdfs("label"), literal_or_nil(envelope.label)),
            maybe_triple(resource, rdfs("comment"), literal_or_nil(envelope.content)),
            {resource, prov("wasAssociatedWith"), actor},
            {resource, prov("wasInformedBy"), session},
            {resource, jido("validForRevision"), revision}
          ]

        :tool_invocation ->
          [
            {session, jido("hasToolInvocation"), resource},
            {resource, RDF.type(), resource_class},
            {resource, RDF.type(), prov("Activity")},
            maybe_triple(resource, prov("startedAtTime"), RDF.XSD.dateTime(envelope.started_at)),
            maybe_triple(resource, prov("endedAtTime"), datetime_or_nil(envelope.ended_at)),
            maybe_triple(resource, rdfs("label"), literal_or_nil(envelope.label)),
            maybe_triple(resource, rdfs("comment"), literal_or_nil(envelope.content)),
            {resource, prov("wasAssociatedWith"), actor},
            maybe_triple(resource, prov("wasInformedBy"), envelope.parent_agent_run_iri || session),
            {resource, jido("validForRevision"), revision}
          ]

        :prompt_turn ->
          [
            {session, jido("hasPromptTurn"), resource},
            {resource, RDF.type(), resource_class},
            {resource, RDF.type(), prov("Activity")},
            maybe_triple(resource, prov("startedAtTime"), RDF.XSD.dateTime(envelope.started_at)),
            maybe_triple(resource, prov("endedAtTime"), datetime_or_nil(envelope.ended_at)),
            maybe_triple(resource, rdfs("label"), literal_or_nil(envelope.label)),
            maybe_triple(resource, rdfs("comment"), literal_or_nil(envelope.content)),
            {resource, prov("wasAssociatedWith"), actor},
            {resource, prov("wasInformedBy"), session},
            {resource, jido("validForRevision"), revision}
          ]

        :plan ->
          [
            {session, jido("hasPlan"), resource},
            {resource, RDF.type(), resource_class},
            {resource, RDF.type(), prov("Entity")},
            maybe_triple(resource, rdfs("label"), literal_or_nil(envelope.label)),
            maybe_triple(resource, rdfs("comment"), literal_or_nil(envelope.content)),
            maybe_triple(resource, prov("wasGeneratedBy"), envelope.parent_agent_run_iri || session),
            {resource, jido("validForRevision"), revision}
          ]

        :patch ->
          [
            {session, jido("hasPatch"), resource},
            {resource, RDF.type(), resource_class},
            {resource, RDF.type(), prov("Entity")},
            maybe_triple(resource, rdfs("label"), literal_or_nil(envelope.label)),
            maybe_triple(resource, rdfs("comment"), literal_or_nil(envelope.content)),
            maybe_triple(resource, prov("wasGeneratedBy"), envelope.parent_agent_run_iri || session),
            {resource, jido("validForRevision"), revision}
          ]

        :review ->
          [
            {session, jido("hasReview"), resource},
            {resource, RDF.type(), resource_class},
            {resource, RDF.type(), prov("Activity")},
            maybe_triple(resource, prov("startedAtTime"), RDF.XSD.dateTime(envelope.started_at)),
            maybe_triple(resource, prov("endedAtTime"), datetime_or_nil(envelope.ended_at)),
            maybe_triple(resource, rdfs("label"), literal_or_nil(envelope.label)),
            maybe_triple(resource, rdfs("comment"), literal_or_nil(envelope.content)),
            {resource, prov("wasAssociatedWith"), actor},
            maybe_triple(resource, prov("wasInformedBy"), envelope.parent_agent_run_iri || session),
            maybe_triple(resource, prov("used"), envelope.patch_iri),
            {resource, jido("validForRevision"), revision}
          ]
      end
      |> add_anchors(resource, envelope.source_code_anchors)
      |> add_governed_references(resource, envelope.managed_repo_id, envelope.governed_references)
      |> add_related_resources(resource, related_resource_targets(envelope))
      |> add_conversation_context(resource, envelope.conversation_context)

    (common_actor_and_revision ++ session_stub ++ resource_triples)
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  defp maybe_add_model(triples, %{model_name: nil}), do: triples

  defp maybe_add_model(triples, %{model_name: model_name, managed_repo_id: managed_repo_id}) do
    model = RDF.iri("#{MemoryGraph.workflow_provenance_base_iri(managed_repo_id)}model/#{URI.encode(model_name)}")

    triples ++
      [
        {model, RDF.type(), jido("Model")},
        {model, RDF.type(), prov("Agent")},
        maybe_triple(model, rdfs("label"), RDF.literal(model_name)),
        {List.first(triples) |> elem(0), jido("usedModel"), model}
      ]
  end

  defp maybe_add_toolchain(triples, %{toolchain_name: nil}), do: triples

  defp maybe_add_toolchain(triples, %{toolchain_name: toolchain_name, managed_repo_id: managed_repo_id}) do
    toolchain =
      RDF.iri("#{MemoryGraph.workflow_provenance_base_iri(managed_repo_id)}toolchain/#{URI.encode(toolchain_name)}")

    triples ++
      [
        {toolchain, RDF.type(), jido("Toolchain")},
        {toolchain, RDF.type(), prov("Entity")},
        maybe_triple(toolchain, rdfs("label"), RDF.literal(toolchain_name)),
        {List.first(triples) |> elem(0), jido("usedToolchain"), toolchain}
      ]
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

    managed_repo_triples =
      [
        {managed_repo_resource, RDF.type(), GovernedReference.class_iri(:managed_repo)},
        {managed_repo_resource, RDF.type(), GovernedReference.governed_record_class_iri()},
        {managed_repo_resource, RDF.type(), prov("Entity")},
        {managed_repo_resource, GovernedReference.id_predicate_iri(:managed_repo), RDF.literal(managed_repo_id)},
        maybe_triple(
          managed_repo_resource,
          rdfs("label"),
          RDF.literal(GovernedReference.label(:managed_repo, managed_repo_id))
        ),
        maybe_triple(
          managed_repo_resource,
          GovernedReference.record_label_predicate_iri(),
          RDF.literal(GovernedReference.label(:managed_repo, managed_repo_id))
        )
      ]

    reference_triples =
      [
        {governed_resource, RDF.type(), GovernedReference.class_iri(kind)},
        {governed_resource, RDF.type(), GovernedReference.governed_record_class_iri()},
        {governed_resource, RDF.type(), prov("Entity")},
        {governed_resource, GovernedReference.id_predicate_iri(kind), RDF.literal(id)},
        maybe_triple(governed_resource, rdfs("label"), literal_or_nil(label)),
        maybe_triple(
          governed_resource,
          GovernedReference.record_label_predicate_iri(),
          literal_or_nil(label)
        ),
        {subject, GovernedReference.predicate_iri(kind), governed_resource}
      ] ++
        case kind do
          :managed_repo -> []
          _other -> [{governed_resource, GovernedReference.for_managed_repo_predicate_iri(), managed_repo_resource}]
        end

    managed_repo_triples ++ reference_triples
  end

  defp maybe_triple(_subject, _predicate, nil), do: nil
  defp maybe_triple(subject, predicate, object), do: {subject, predicate, object}

  defp add_related_resources(triples, _subject, []), do: triples

  defp add_related_resources(triples, subject, related_resources) do
    triples ++ Enum.map(related_resources, &{subject, jido("relatedTo"), &1})
  end

  defp add_conversation_context(triples, _subject, nil), do: triples

  defp add_conversation_context(triples, subject, conversation_context) when is_map(conversation_context) do
    triples ++
      [
        maybe_triple(
          subject,
          jido("conversationId"),
          literal_or_nil(Map.get(conversation_context, :conversation_id))
        ),
        maybe_triple(
          subject,
          jido("conversationTurnId"),
          literal_or_nil(Map.get(conversation_context, :turn_id))
        ),
        maybe_triple(
          subject,
          jido("conversationCommandId"),
          literal_or_nil(Map.get(conversation_context, :command_id))
        ),
        maybe_triple(
          subject,
          jido("conversationEvent"),
          literal_or_nil(Map.get(conversation_context, :conversation_event))
        ),
        maybe_triple(
          subject,
          jido("clarificationState"),
          literal_or_nil(Map.get(conversation_context, :clarification_state))
        ),
        maybe_triple(
          subject,
          jido("conversationScope"),
          literal_or_nil(Map.get(conversation_context, :scope))
        ),
        maybe_triple(
          subject,
          jido("conversationAttachmentMode"),
          literal_or_nil(Map.get(conversation_context, :attachment_mode))
        ),
        maybe_triple(
          subject,
          jido("conversationStatus"),
          literal_or_nil(Map.get(conversation_context, :status))
        ),
        maybe_triple(
          subject,
          jido("conversationSource"),
          literal_or_nil(Map.get(conversation_context, :source))
        )
      ]
  end

  defp related_session_resources(%{kind: :work_session, related_resources: resources}), do: resources
  defp related_session_resources(_envelope), do: []

  defp related_resource_targets(%{kind: :work_session}), do: []
  defp related_resource_targets(%{related_resources: resources}), do: resources

  defp literal_or_nil(nil), do: nil
  defp literal_or_nil(value), do: RDF.literal(value)

  defp datetime_or_nil(nil), do: nil
  defp datetime_or_nil(value), do: RDF.XSD.dateTime(value)

  defp load_graph(store, %RDF.Graph{} = graph) do
    case TripleStore.load_graph(store, graph, graph: MemoryGraph.workflow_provenance_named_graph_resource()) do
      {:ok, triple_count} ->
        {:ok, triple_count}

      {:error, reason} ->
        {:error, :memory_graph_record_failed, %{stage: :load_provenance_graph, reason: inspect(reason)}}
    end
  end

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
      supported_graph_name: MemoryGraph.workflow_provenance_graph_name(),
      capture: capture
    }
  end

  defp jido(local), do: RDF.iri(@jido_ns <> local)
  defp prov(local), do: RDF.iri(@prov_ns <> local)
  defp rdfs(local), do: RDF.iri(@rdfs_ns <> local)
end
