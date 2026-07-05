defmodule JidoCode.MemoryGraph.ConversationMemoryAdoption do
  # covers: architecture.memory_graph_product_adoption.conversation_derived_context_uses_bounded_projections
  # covers: architecture.memory_capture_plane.durable_memories_are_inserted_through_explicit_classification_and_adoption
  @moduledoc """
  Explicit durable-memory adoption for bounded conversation-derived origin summaries.

  This boundary lets product callers promote one selected conversation-origin
  summary into durable memory without exposing transcript replay or raw graph
  writes to route code.
  """

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.Actor
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.DurableMemoryEnvelope

  @adoption_actor Actor.factory_system_actor(%{
                    "id" => "system:conversation-memory-adoption",
                    "email" => "conversation-memory-adoption@system.local"
                  })

  @spec adopt(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def adopt(projection_or_item, opts \\ [])

  def adopt(projection_or_item, opts) when is_map(projection_or_item) and is_list(opts) do
    with {:ok, item} <- selected_item(projection_or_item, opts),
         {:ok, managed_repo_id} <- required_string(Map.get(item, :managed_repo_id), :managed_repo_id),
         {:ok, workspace_path} <- MemoryGraph.normalize_workspace_path(Keyword.get(opts, :workspace_path)),
         {:ok, revision} <- revision(projection_or_item, workspace_path, opts),
         {:ok, kind} <- memory_kind(opts),
         actor = actor(opts),
         {:ok, actor_id} <- required_string(actor["id"] || actor[:id], :actor_id),
         {:ok, classification} <- classification(opts),
         {:ok, capture} <-
           durable_memory_capture(kind, managed_repo_id, revision, actor_id, item, classification, opts),
         {:ok, record} <-
           AgentWorkspace.record_memory_graph(
             managed_repo_id,
             workspace_path,
             capture,
             revision: revision
           ) do
      {:ok,
       %{
         status: :conversation_memory_adopted,
         managed_repo_id: managed_repo_id,
         revision: revision,
         memory_kind: kind,
         origin: item,
         record: record
       }}
    end
  end

  def adopt(_projection_or_item, _opts), do: {:error, :invalid_conversation_recall_projection}

  defp selected_item(%{kind: :conversation_recall, items: items}, opts) when is_list(items) do
    turn_id = normalize_optional_string(Keyword.get(opts, :turn_id))
    conversation_id = normalize_optional_string(Keyword.get(opts, :conversation_id))
    resource_iri = normalize_optional_string(Keyword.get(opts, :resource_iri))

    item =
      cond do
        is_binary(turn_id) ->
          Enum.find(items, &(Map.get(&1, :turn_id) == turn_id))

        is_binary(resource_iri) ->
          Enum.find(items, &(resource_iri in Map.get(&1, :resource_iris, [])))

        is_binary(conversation_id) ->
          Enum.find(items, &(Map.get(&1, :conversation_id) == conversation_id))

        items != [] ->
          List.first(items)

        true ->
          nil
      end

    case item do
      %{} = selected -> {:ok, selected}
      nil -> {:error, :conversation_recall_item_not_found}
    end
  end

  defp selected_item(%{conversation_id: conversation_id} = item, _opts) when is_binary(conversation_id),
    do: {:ok, item}

  defp selected_item(_projection_or_item, _opts), do: {:error, :invalid_conversation_recall_projection}

  defp durable_memory_capture(kind, _managed_repo_id, revision, actor_id, item, classification, opts) do
    content = content(kind, item, opts)

    builder =
      [
        session_id: session_id(item, opts),
        actor_id: actor_id,
        workflow: "conversation_memory_adoption",
        work_item_id: Keyword.get(opts, :work_item_id) || governed_reference_id(item, :work_item),
        revision: revision,
        content: content,
        rationale: rationale(kind, item, opts),
        context: lesson_context(kind, item, opts),
        confidence: confidence(kind, opts),
        decision_status: Keyword.get(opts, :decision_status, :accepted),
        anchors: anchors(item),
        governed_references: governed_references(item),
        supported_by: supporting_artifacts(item),
        conversation_id: Map.get(item, :conversation_id),
        turn_id: Map.get(item, :turn_id),
        command_id: Map.get(item, :command_id),
        conversation_event: Map.get(item, :latest_event),
        clarification_state: get_in(item, [:conversation_context, :clarification_state]),
        scope: get_in(item, [:conversation_context, :scope]),
        attachment_mode: get_in(item, [:conversation_context, :attachment_mode]),
        status: get_in(item, [:conversation_context, :status]),
        source: get_in(item, [:conversation_context, :source]),
        classification: classification
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    {:ok, apply(DurableMemoryEnvelope, kind, [builder])}
  rescue
    UndefinedFunctionError -> {:error, :unsupported_conversation_memory_kind}
  end

  defp memory_kind(opts) do
    case normalize_optional_string(Keyword.get(opts, :memory_kind) || Keyword.get(opts, :kind)) do
      nil ->
        {:error, :missing_conversation_memory_kind}

      kind ->
        case normalize_memory_kind(kind) do
          nil -> {:error, :unsupported_conversation_memory_kind}
          normalized -> {:ok, normalized}
        end
    end
  end

  defp classification(opts) do
    classification =
      case Keyword.get(opts, :classification, %{}) do
        %{} = classification -> classification
        classification when is_list(classification) -> Enum.into(classification, %{})
        _other -> %{}
      end

    source =
      normalize_optional_string(
        Map.get(classification, :source) || Map.get(classification, "source") ||
          Keyword.get(opts, :classification_source)
      )

    reason =
      normalize_optional_string(
        Map.get(classification, :reason) || Map.get(classification, "reason") ||
          Keyword.get(opts, :classification_reason)
      )

    label =
      normalize_optional_string(
        Map.get(classification, :label) || Map.get(classification, "label") || Keyword.get(opts, :classification_label)
      )

    case {source, reason} do
      {source, reason} when is_binary(source) and is_binary(reason) ->
        {:ok,
         %{
           source: source,
           reason: reason,
           label: label || "Conversation-derived durable memory adoption"
         }}

      _other ->
        {:error, :missing_conversation_memory_classification}
    end
  end

  defp revision(%{graph: graph}, _workspace_path, opts) when is_map(graph) do
    case normalize_optional_string(
           Keyword.get(opts, :revision) || graph[:validated_revision] || graph[:current_revision]
         ) do
      nil -> {:error, :missing_conversation_memory_revision}
      revision -> {:ok, revision}
    end
  end

  defp revision(_projection_or_item, workspace_path, opts) do
    case normalize_optional_string(Keyword.get(opts, :revision)) do
      nil ->
        with {:ok, revision_metadata} <- MemoryGraph.current_revision_metadata(workspace_path),
             {:ok, revision} <- required_string(revision_metadata.current_revision, :revision) do
          {:ok, revision}
        end

      revision ->
        {:ok, revision}
    end
  end

  defp content(:fact, item, opts),
    do: Keyword.get(opts, :content) || Map.get(item, :content_preview) || Map.get(item, :origin_summary)

  defp content(_kind, item, opts),
    do: Keyword.get(opts, :content) || Map.get(item, :origin_summary) || Map.get(item, :content_preview)

  defp rationale(:decision, item, opts) do
    Keyword.get(opts, :rationale) ||
      "Conversation-derived origin context was explicitly adopted as a durable decision."
      |> append_context(item)
  end

  defp rationale(_kind, _item, opts), do: Keyword.get(opts, :rationale)

  defp lesson_context(:lesson_learned, item, opts) do
    Keyword.get(opts, :context) ||
      Map.get(item, :content_preview) ||
      "Conversation-derived origin context was explicitly adopted as a reusable lesson."
  end

  defp lesson_context(_kind, _item, opts), do: Keyword.get(opts, :context)

  defp confidence(:fact, opts), do: Keyword.get(opts, :confidence, 0.8)
  defp confidence(_kind, opts), do: Keyword.get(opts, :confidence)

  defp anchors(item) do
    %{}
    |> maybe_put(:module_name, Map.get(item, :module_name))
    |> maybe_put(:function_name, Map.get(item, :function_name))
    |> maybe_put(:subject_iri, Map.get(item, :subject_iri))
  end

  defp governed_references(item) do
    item
    |> Map.get(:governed_context, [])
    |> List.wrap()
    |> Enum.flat_map(fn link ->
      case {Map.get(link, :kind), normalize_optional_string(Map.get(link, :id))} do
        {kind, id}
        when kind in [:managed_repo, :observation, :assessment, :work_item, :run, :evidence, :change_request, :decision] and
               is_binary(id) ->
          [%{kind: kind, id: id}]

        _other ->
          []
      end
    end)
    |> Enum.uniq_by(fn reference -> {reference.kind, reference.id} end)
  end

  defp supporting_artifacts(item) do
    resource_artifacts =
      item
      |> Map.get(:resource_iris, [])
      |> List.wrap()
      |> Enum.map(fn resource_iri ->
        %{
          id: resource_iri,
          label: "Conversation provenance #{resource_iri}"
        }
      end)

    turn_artifact =
      case {Map.get(item, :conversation_id), Map.get(item, :turn_id)} do
        {conversation_id, turn_id} when is_binary(conversation_id) and is_binary(turn_id) ->
          [
            %{
              id: "conversation/#{conversation_id}/turn/#{turn_id}",
              label: "Conversation #{conversation_id} turn #{turn_id}"
            }
          ]

        _other ->
          []
      end

    resource_artifacts ++ turn_artifact
  end

  defp session_id(item, opts) do
    Keyword.get(opts, :session_id) ||
      [
        "conversation-memory",
        Map.get(item, :conversation_id),
        Map.get(item, :turn_id),
        System.unique_integer([:positive])
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("-")
  end

  defp governed_reference_id(item, kind) do
    item
    |> Map.get(:governed_context, [])
    |> List.wrap()
    |> Enum.find_value(fn link ->
      if Map.get(link, :kind) == kind, do: Map.get(link, :id)
    end)
  end

  defp append_context(text, item) do
    case Map.get(item, :origin_summary) do
      summary when is_binary(summary) -> "#{text} #{summary}"
      _other -> text
    end
  end

  defp normalize_memory_kind(kind) do
    case kind |> String.replace("-", "_") |> String.downcase() do
      "fact" -> :fact
      "decision" -> :decision
      "lesson_learned" -> :lesson_learned
      "invariant" -> :invariant
      "convention" -> :convention
      "known_issue" -> :known_issue
      "open_question" -> :open_question
      "pattern" -> :pattern
      "anti_pattern" -> :anti_pattern
      _other -> nil
    end
  end

  defp actor(opts) do
    opts
    |> Keyword.get(:actor)
    |> Actor.effective_actor()
    |> case do
      nil -> @adoption_actor
      actor -> actor
    end
  end

  defp required_string(value, field) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, {:missing_field, field}}
      normalized -> {:ok, normalized}
    end
  end

  defp required_string(_value, field), do: {:error, {:missing_field, field}}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(_value), do: nil
end
