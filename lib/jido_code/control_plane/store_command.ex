defmodule JidoCode.ControlPlane.StoreCommand do
  @moduledoc """
  Typed write command boundary for the embedded control-plane store.

  Commands carry actor, correlation, graph, identity, and validation context
  metadata beside the graph changes. This keeps product callers away from raw
  SPARQL update strings while later phases build richer codecs and validators.
  """

  alias JidoCode.ControlPlane.{GraphTopology, StoreServer}

  defstruct [
    :type,
    :graph_name,
    :subject_iri,
    :actor,
    :correlation_id,
    :identity,
    :expected_updated_at,
    triples: [],
    validation_context: %{}
  ]

  @type t :: %__MODULE__{
          type: :insert | :replace_subject | :delete_subject | :append_event | :upsert_by_identity,
          graph_name: GraphTopology.graph_name(),
          subject_iri: String.t(),
          actor: map() | nil,
          correlation_id: String.t() | nil,
          identity: map() | nil,
          expected_updated_at: term(),
          triples: [{term(), term(), term()}],
          validation_context: map()
        }

  @spec insert(keyword() | map()) :: t()
  def insert(attrs), do: command(:insert, attrs)

  @spec replace_subject(keyword() | map()) :: t()
  def replace_subject(attrs), do: command(:replace_subject, attrs)

  @spec delete_subject(keyword() | map()) :: t()
  def delete_subject(attrs), do: command(:delete_subject, attrs)

  @spec append_event(keyword() | map()) :: t()
  def append_event(attrs), do: command(:append_event, attrs)

  @spec upsert_by_identity(keyword() | map()) :: t()
  def upsert_by_identity(attrs), do: command(:upsert_by_identity, attrs)

  @spec execute(t(), GenServer.server()) :: {:ok, map()} | {:error, term()}
  def execute(%__MODULE__{} = command, server \\ StoreServer) do
    case StoreServer.with_store(server, &do_execute(&1, command)) do
      {:ok, {:ok, outcome}} -> {:ok, outcome}
      {:ok, {:error, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp command(type, attrs) do
    attrs = attrs_map(attrs)

    %__MODULE__{
      type: type,
      graph_name: get_attr(attrs, :graph_name, :control_plane),
      subject_iri: get_attr(attrs, :subject_iri),
      triples: get_attr(attrs, :triples, []),
      actor: get_attr(attrs, :actor),
      correlation_id: get_attr(attrs, :correlation_id),
      identity: get_attr(attrs, :identity),
      expected_updated_at: get_attr(attrs, :expected_updated_at),
      validation_context: get_attr(attrs, :validation_context, %{})
    }
  end

  defp do_execute(store, command) do
    with {:ok, graph_resource} <- GraphTopology.graph_resource(command.graph_name),
         {:ok, subject} <- subject_resource(command),
         {:ok, triples} <- normalize_triples(command.triples) do
      execute_type(store, graph_resource, subject, triples, command)
    end
  end

  defp execute_type(store, graph_resource, subject, triples, %{type: :insert} = command) do
    with {:ok, count} <- load_triples(store, graph_resource, triples) do
      {:ok, write_outcome(command, subject, count)}
    end
  end

  defp execute_type(store, graph_resource, subject, triples, %{type: :append_event} = command) do
    if GraphTopology.append_only_graph?(command.graph_name) do
      with {:ok, count} <- load_triples(store, graph_resource, triples) do
        {:ok, write_outcome(command, subject, count) |> Map.put(:event_iri, to_string(subject))}
      end
    else
      {:error, {:invalid_append_graph, command.graph_name}}
    end
  end

  defp execute_type(store, graph_resource, subject, _triples, %{type: :delete_subject} = command) do
    with {:ok, deleted_count} <- delete_subject(store, graph_resource, subject) do
      {:ok,
       %{
         command: command.type,
         graph_name: command.graph_name,
         subject_iri: to_string(subject),
         deleted_triple_count: deleted_count,
         actor: command.actor,
         correlation_id: command.correlation_id
       }}
    end
  end

  defp execute_type(store, graph_resource, subject, triples, %{type: :replace_subject} = command) do
    with :ok <- assert_expected_updated_at(store, graph_resource, subject, command.expected_updated_at),
         {:ok, deleted_count} <- delete_subject(store, graph_resource, subject),
         {:ok, written_count} <- load_triples(store, graph_resource, triples) do
      {:ok,
       command
       |> write_outcome(subject, written_count)
       |> Map.put(:deleted_triple_count, deleted_count)}
    end
  end

  defp execute_type(store, graph_resource, subject, triples, %{type: :upsert_by_identity} = command) do
    with :ok <- assert_identity_available(store, graph_resource, subject, command.identity),
         :ok <- assert_expected_updated_at(store, graph_resource, subject, command.expected_updated_at),
         {:ok, deleted_count} <- delete_subject(store, graph_resource, subject),
         {:ok, written_count} <- load_triples(store, graph_resource, triples) do
      {:ok,
       command
       |> write_outcome(subject, written_count)
       |> Map.put(:deleted_triple_count, deleted_count)
       |> Map.put(:identity, command.identity)}
    end
  end

  defp execute_type(_store, _graph_resource, _subject, _triples, command),
    do: {:error, {:invalid_command_type, command.type}}

  defp write_outcome(command, subject, count) do
    %{
      command: command.type,
      graph_name: command.graph_name,
      subject_iri: to_string(subject),
      written_subject_iris: [to_string(subject)],
      written_triple_count: count,
      actor: command.actor,
      correlation_id: command.correlation_id,
      validation_context: command.validation_context
    }
  end

  defp load_triples(_store, _graph_resource, []), do: {:ok, 0}

  defp load_triples(store, graph_resource, triples) do
    triples
    |> RDF.Graph.new()
    |> then(&TripleStore.load_graph(store, &1, graph: graph_resource))
  end

  defp delete_subject(store, graph_resource, subject) do
    with {:ok, graph_id} <- lookup_id(store, graph_resource),
         {:ok, subject_id} <- lookup_id(store, subject) do
      quads =
        TripleStore.QuadOperations.lookup_quads(
          store.db,
          {:bound, :var, :var, :bound},
          %{s: subject_id, g: graph_id}
        )

      case TripleStore.QuadOperations.delete_quads(store.db, quads, sync: true) do
        :ok -> {:ok, length(quads)}
        {:error, reason} -> {:error, {:delete_subject_failed, reason}}
      end
    else
      :not_found -> {:ok, 0}
      {:error, reason} -> {:error, reason}
    end
  end

  defp assert_expected_updated_at(_store, _graph_resource, _subject, nil), do: :ok

  defp assert_expected_updated_at(store, graph_resource, subject, expected_updated_at) do
    updated_at_predicate = RDF.iri("https://jido.run/ontology/control-plane#updatedAt")

    case objects_for(store, graph_resource, subject, updated_at_predicate) do
      {:ok, [current | _rest]} ->
        if comparable_term(current) == comparable_term(expected_updated_at) do
          :ok
        else
          {:error, {:stale_write, to_string(subject)}}
        end

      {:ok, []} ->
        {:error, {:stale_write, to_string(subject)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp assert_identity_available(_store, _graph_resource, _subject, nil), do: {:error, :missing_identity}

  defp assert_identity_available(store, graph_resource, subject, identity) when is_map(identity) do
    with {:ok, predicate} <- identity_predicate(identity),
         {:ok, value} <- identity_value(identity),
         {:ok, subjects} <- subjects_for_identity(store, graph_resource, predicate, value),
         {:ok, identity_subjects} <- filter_identity_subjects(store, graph_resource, identity, subjects) do
      conflicting_subjects = Enum.reject(identity_subjects, &(to_string(&1) == to_string(subject)))

      case conflicting_subjects do
        [] -> :ok
        [conflict | _rest] -> {:error, {:conflict, identity_name(identity), to_string(conflict)}}
      end
    end
  end

  defp assert_identity_available(_store, _graph_resource, _subject, _identity), do: {:error, :invalid_identity}

  defp filter_identity_subjects(store, graph_resource, identity, subjects) do
    case identity_class_iri(identity) do
      nil ->
        {:ok, subjects}

      class_iri ->
        {:ok, Enum.filter(subjects, &subject_has_class?(store, graph_resource, &1, class_iri))}
    end
  end

  defp subject_has_class?(store, graph_resource, subject, class_iri) do
    case objects_for(store, graph_resource, subject, RDF.type()) do
      {:ok, class_terms} -> Enum.any?(class_terms, &(to_string(&1) == to_string(class_iri)))
      {:error, _reason} -> false
    end
  end

  defp subjects_for_identity(store, graph_resource, predicate, object) do
    with {:ok, graph_id} <- lookup_id(store, graph_resource),
         {:ok, predicate_id} <- lookup_id(store, predicate),
         {:ok, object_id} <- lookup_id(store, object) do
      subjects =
        store.db
        |> TripleStore.QuadOperations.lookup_quads(
          {:var, :bound, :bound, :bound},
          %{p: predicate_id, o: object_id, g: graph_id}
        )
        |> Enum.map(fn {subject_id, _predicate_id, _object_id, _graph_id} ->
          TripleStore.Adapter.id_to_term(store.db, subject_id)
        end)
        |> Enum.flat_map(fn
          {:ok, subject} -> [subject]
          _other -> []
        end)

      {:ok, Enum.uniq(subjects)}
    else
      :not_found -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  defp objects_for(store, graph_resource, subject, predicate) do
    with {:ok, graph_id} <- lookup_id(store, graph_resource),
         {:ok, subject_id} <- lookup_id(store, subject),
         {:ok, predicate_id} <- lookup_id(store, predicate) do
      objects =
        store.db
        |> TripleStore.QuadOperations.lookup_quads(
          {:bound, :bound, :var, :bound},
          %{s: subject_id, p: predicate_id, g: graph_id}
        )
        |> Enum.map(fn {_subject_id, _predicate_id, object_id, _graph_id} ->
          TripleStore.Adapter.id_to_term(store.db, object_id)
        end)
        |> Enum.flat_map(fn
          {:ok, object} -> [object]
          _other -> []
        end)

      {:ok, objects}
    else
      :not_found -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lookup_id(store, term) do
    case TripleStore.Adapter.lookup_term_id(store.db, term) do
      {:ok, id} -> {:ok, id}
      {:error, :requires_manager} -> TripleStore.Adapter.term_to_id(store.dict_manager, term)
      :not_found -> :not_found
      {:error, reason} -> {:error, reason}
    end
  end

  defp subject_resource(%{subject_iri: subject_iri}) when is_binary(subject_iri) and subject_iri != "" do
    {:ok, RDF.iri(subject_iri)}
  end

  defp subject_resource(_command), do: {:error, :missing_subject_iri}

  defp normalize_triples(triples) when is_list(triples) do
    if Enum.all?(triples, &triple?/1) do
      {:ok, triples}
    else
      {:error, :invalid_triples}
    end
  end

  defp normalize_triples(_triples), do: {:error, :invalid_triples}

  defp triple?({_subject, _predicate, _object}), do: true
  defp triple?(_other), do: false

  defp identity_predicate(identity) do
    case get_attr(identity, :predicate_iri) || get_attr(identity, :predicate) do
      %RDF.IRI{} = iri -> {:ok, iri}
      value when is_binary(value) and value != "" -> {:ok, RDF.iri(value)}
      _other -> {:error, :invalid_identity}
    end
  end

  defp identity_value(identity) do
    case get_attr(identity, :value) do
      %RDF.IRI{} = iri -> {:ok, iri}
      %RDF.Literal{} = literal -> {:ok, literal}
      value when is_binary(value) -> {:ok, RDF.literal(value)}
      value when is_atom(value) -> {:ok, RDF.literal(Atom.to_string(value))}
      value when is_integer(value) -> {:ok, RDF.literal(value)}
      _other -> {:error, :invalid_identity}
    end
  end

  defp identity_name(identity), do: get_attr(identity, :identity, :identity)

  defp identity_class_iri(identity) do
    case get_attr(identity, :class_iri) do
      %RDF.IRI{} = iri -> iri
      value when is_binary(value) and value != "" -> RDF.iri(value)
      _other -> nil
    end
  end

  defp comparable_term(%RDF.Literal{} = term) do
    case RDF.Literal.value(term) do
      %DateTime{} = datetime -> DateTime.to_unix(datetime, :millisecond)
      value -> value
    end
  end

  defp comparable_term(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :millisecond)

  defp comparable_term(term), do: to_string(term)

  defp attrs_map(attrs) when is_list(attrs), do: Map.new(attrs)
  defp attrs_map(attrs) when is_map(attrs), do: attrs

  defp get_attr(attrs, key, default \\ nil) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key), default)
  end
end
