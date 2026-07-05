defmodule JidoCode.ControlPlane.Integrity do
  @moduledoc """
  Integrity checks for the embedded control-plane store.

  The checks are intentionally bounded to the product-owned store contract:
  graph topology, ontology bootstrap version, codec identity uniqueness, and
  control-plane object links.
  """

  alias JidoCode.ControlPlane.{GraphTopology, SemanticIdentity, StoreServer}
  alias JidoCode.ControlPlane.Codecs.Registry
  alias JidoCode.MemoryGraph

  @owl_version_info RDF.iri("http://www.w3.org/2002/07/owl#versionInfo")
  @control_plane_ontology RDF.iri(SemanticIdentity.ontology_namespace())

  @type issue :: %{
          severity: :error | :warning,
          code: atom(),
          message: String.t(),
          metadata: map()
        }

  @type report :: %{
          status: :ok | :degraded | :failed,
          checked_at: DateTime.t(),
          topology: map(),
          ontology: map(),
          identities: map(),
          links: map(),
          issues: [issue()]
        }

  @spec check(GenServer.server(), keyword()) :: {:ok, report()} | {:error, term()}
  def check(server \\ StoreServer, opts \\ []) do
    case StoreServer.with_store(server, &check_store(&1, opts)) do
      {:ok, {:ok, report}} -> {:ok, report}
      {:ok, {:error, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec check_store(map(), keyword()) :: {:ok, report()} | {:error, term()}
  def check_store(store, _opts \\ []) do
    with {:ok, quads} <- all_quads(store),
         {:ok, graph_counts} <- graph_counts(store),
         {:ok, expected_version} <- expected_control_plane_ontology_version() do
      topology = topology_report(graph_counts)
      ontology = ontology_report(quads, expected_version)
      identities = identity_report(quads)
      links = link_report(quads)

      issues =
        topology.issues ++
          ontology.issues ++
          identities.issues ++
          links.issues

      {:ok,
       %{
         status: status_for(issues),
         checked_at: DateTime.utc_now(),
         topology: Map.delete(topology, :issues),
         ontology: Map.delete(ontology, :issues),
         identities: Map.delete(identities, :issues),
         links: Map.delete(links, :issues),
         issues: issues
       }}
    end
  end

  @spec expected_control_plane_ontology_version() :: {:ok, String.t()} | {:error, term()}
  def expected_control_plane_ontology_version do
    with {:ok, graph} <- RDF.Turtle.read_file(MemoryGraph.control_plane_ontology_path()),
         {:ok, version} <- version_from_triples(RDF.Graph.triples(graph)) do
      {:ok, version}
    end
  end

  @spec all_quads(map()) :: {:ok, [tuple()]} | {:error, term()}
  def all_quads(store) do
    internal_quads = TripleStore.QuadOperations.lookup_quads(store.db, {:var, :var, :var, :var}, %{})

    case TripleStore.Adapter.to_rdf_quads(store.db, internal_quads) do
      {:ok, quads} -> {:ok, Enum.reject(quads, &(&1 == :not_found))}
      {:error, reason} -> {:error, reason}
    end
  end

  defp graph_counts(store) do
    case TripleStore.QuadOperations.graphs_summary(store.db, include_default: false) do
      {:ok, summary} -> {:ok, Map.new(summary, fn {graph, count} -> {to_string(graph), count} end)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp topology_report(graph_counts) do
    graph_iris = GraphTopology.graph_iris()
    duplicate_iris = duplicate_values(graph_iris)

    graphs =
      graph_iris
      |> Enum.sort_by(fn {graph_name, _iri} -> graph_name end)
      |> Enum.map(fn {graph_name, iri} ->
        %{
          graph_name: graph_name,
          graph_iri: iri,
          present?: Map.has_key?(graph_counts, iri),
          quad_count: Map.get(graph_counts, iri, 0),
          required?: graph_name == :control_plane
        }
      end)

    issues =
      []
      |> maybe_issue(
        map_size(duplicate_iris) > 0,
        :error,
        :duplicate_graph_iri,
        "Graph topology contains duplicate graph IRIs.",
        %{graph_iris: duplicate_iris}
      )
      |> maybe_issue(
        not Enum.any?(graphs, &(&1.graph_name == :control_plane and &1.present?)),
        :error,
        :missing_control_plane_graph,
        "The control-plane ontology graph is missing.",
        %{}
      )

    %{graphs: graphs, graph_count: length(graphs), issues: issues}
  end

  defp ontology_report(quads, expected_version) do
    {:ok, control_plane_graph_iri} = GraphTopology.graph_iri(:control_plane)

    stored_versions =
      quads
      |> Enum.filter(fn {subject, predicate, _object, graph} ->
        to_string(graph) == control_plane_graph_iri and subject == @control_plane_ontology and
          predicate == @owl_version_info
      end)
      |> Enum.map(fn {_subject, _predicate, object, _graph} -> literal_value(object) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    issues =
      []
      |> maybe_issue(
        stored_versions == [],
        :error,
        :missing_control_plane_ontology_version,
        "The control-plane ontology version triple is missing from the control-plane graph.",
        %{expected_version: expected_version}
      )
      |> maybe_issue(
        stored_versions != [] and expected_version not in stored_versions,
        :error,
        :stale_control_plane_ontology_version,
        "The control-plane ontology version in the store does not match the checked-in ontology.",
        %{expected_version: expected_version, stored_versions: stored_versions}
      )

    %{
      ontology_iri: to_string(@control_plane_ontology),
      graph_iri: control_plane_graph_iri,
      expected_version: expected_version,
      stored_versions: stored_versions,
      issues: issues
    }
  end

  defp identity_report(quads) do
    reports =
      Registry.codecs()
      |> Enum.sort_by(fn {record_type, _codec} -> record_type end)
      |> Enum.map(fn {record_type, _codec} -> identity_report_for_record(quads, record_type) end)

    issues = Enum.flat_map(reports, & &1.issues)

    %{
      checked_record_types: Enum.map(reports, & &1.record_type),
      record_reports: Enum.map(reports, &Map.delete(&1, :issues)),
      duplicate_identity_count: Enum.count(issues, &(&1.code == :duplicate_record_identity)),
      missing_identity_count: Enum.count(issues, &(&1.code == :missing_record_identity)),
      issues: issues
    }
  end

  defp identity_report_for_record(quads, record_type) do
    with {:ok, graph_iri} <- GraphTopology.graph_iri_for_record(record_type),
         {:ok, class_iri} <- SemanticIdentity.class_iri(record_type),
         {:ok, id_predicate} <- SemanticIdentity.id_predicate_iri(record_type) do
      subjects = typed_subjects(quads, graph_iri, class_iri)
      identities = identities_by_subject(quads, graph_iri, id_predicate, subjects)

      missing_identity_issues =
        identities
        |> Enum.filter(fn {_subject, values} -> values == [] end)
        |> Enum.map(fn {subject, _values} ->
          issue(:error, :missing_record_identity, "A typed record is missing its canonical identity value.", %{
            record_type: record_type,
            subject_iri: to_string(subject),
            graph_iri: graph_iri,
            identity_predicate_iri: to_string(id_predicate)
          })
        end)

      duplicate_identity_issues =
        identities
        |> Enum.flat_map(fn {subject, values} -> Enum.map(values, &{identity_key(&1), &1, subject}) end)
        |> Enum.group_by(fn {key, _value, _subject} -> key end)
        |> Enum.filter(fn {_key, entries} ->
          entries |> Enum.map(fn {_key, _value, subject} -> to_string(subject) end) |> Enum.uniq() |> length() > 1
        end)
        |> Enum.map(fn {_key, entries} ->
          {_key, value, _subject} = hd(entries)

          issue(:error, :duplicate_record_identity, "Multiple typed records share a canonical identity value.", %{
            record_type: record_type,
            identity_value: display_value(value),
            graph_iri: graph_iri,
            identity_predicate_iri: to_string(id_predicate),
            subject_iris:
              entries
              |> Enum.map(fn {_key, _value, subject} -> to_string(subject) end)
              |> Enum.uniq()
              |> Enum.sort()
          })
        end)

      %{
        record_type: record_type,
        graph_iri: graph_iri,
        class_iri: to_string(class_iri),
        identity_predicate_iri: to_string(id_predicate),
        subject_count: length(subjects),
        issues: missing_identity_issues ++ duplicate_identity_issues
      }
    else
      {:error, reason} ->
        %{
          record_type: record_type,
          graph_iri: nil,
          class_iri: nil,
          identity_predicate_iri: nil,
          subject_count: 0,
          issues: [
            issue(:error, :codec_identity_contract_unavailable, "A codec record type has no identity contract.", %{
              record_type: record_type,
              reason: reason
            })
          ]
        }
    end
  end

  defp typed_subjects(quads, graph_iri, class_iri) do
    class_iri_string = to_string(class_iri)

    quads
    |> Enum.filter(fn {subject, predicate, object, graph} ->
      to_string(graph) == graph_iri and predicate == RDF.type() and to_string(object) == class_iri_string and
        match?(%RDF.IRI{}, subject)
    end)
    |> Enum.map(fn {subject, _predicate, _object, _graph} -> subject end)
    |> Enum.uniq_by(&to_string/1)
    |> Enum.sort_by(&to_string/1)
  end

  defp identities_by_subject(quads, graph_iri, id_predicate, subjects) do
    subject_set = MapSet.new(subjects, &to_string/1)

    values_by_subject =
      quads
      |> Enum.filter(fn {subject, predicate, _object, graph} ->
        to_string(graph) == graph_iri and predicate == id_predicate and MapSet.member?(subject_set, to_string(subject))
      end)
      |> Enum.group_by(fn {subject, _predicate, _object, _graph} -> subject end, fn {_subject, _predicate, object,
                                                                                     _graph} ->
        object
      end)

    Map.new(subjects, fn subject -> {subject, Map.get(values_by_subject, subject, [])} end)
  end

  defp link_report(quads) do
    control_base = SemanticIdentity.base_iri()

    known_subjects =
      quads
      |> Enum.flat_map(fn {subject, _predicate, _object, _graph} ->
        if control_iri?(subject, control_base), do: [to_string(subject)], else: []
      end)
      |> MapSet.new()

    dangling =
      quads
      |> Enum.filter(fn {_subject, predicate, object, _graph} ->
        predicate != RDF.type() and control_iri?(object, control_base) and
          not MapSet.member?(known_subjects, to_string(object))
      end)
      |> Enum.map(fn {subject, predicate, object, graph} ->
        %{
          source_subject_iri: to_string(subject),
          predicate_iri: to_string(predicate),
          target_subject_iri: to_string(object),
          graph_iri: to_string(graph)
        }
      end)
      |> Enum.uniq()
      |> Enum.sort_by(fn link ->
        {link.graph_iri, link.source_subject_iri, link.predicate_iri, link.target_subject_iri}
      end)

    issues =
      Enum.map(dangling, fn link ->
        issue(:error, :dangling_control_plane_link, "A control-plane object link points to a missing subject.", link)
      end)

    %{
      checked_link_count:
        Enum.count(quads, fn {_subject, predicate, object, _graph} ->
          predicate != RDF.type() and control_iri?(object, control_base)
        end),
      dangling_link_count: length(dangling),
      dangling_links: dangling,
      issues: issues
    }
  end

  defp version_from_triples(triples) do
    triples
    |> Enum.find_value(fn
      {@control_plane_ontology, @owl_version_info, object} -> literal_value(object)
      _other -> nil
    end)
    |> case do
      nil -> {:error, :missing_control_plane_ontology_version}
      version -> {:ok, version}
    end
  end

  defp duplicate_values(map) do
    map
    |> Enum.group_by(fn {_key, value} -> value end, fn {key, _value} -> key end)
    |> Enum.filter(fn {_value, keys} -> length(keys) > 1 end)
    |> Map.new(fn {value, keys} -> {value, Enum.sort(keys)} end)
  end

  defp control_iri?(%RDF.IRI{} = iri, control_base), do: String.starts_with?(to_string(iri), control_base <> "/")
  defp control_iri?(_term, _control_base), do: false

  defp literal_value(%RDF.Literal{} = literal), do: RDF.Literal.value(literal) |> to_string()
  defp literal_value(_term), do: nil

  defp identity_key(%RDF.Literal{} = literal) do
    {:literal, RDF.Literal.value(literal), RDF.Literal.datatype_id(literal), RDF.Literal.language(literal)}
  end

  defp identity_key(%RDF.IRI{} = iri), do: {:iri, to_string(iri)}
  defp identity_key(term), do: {:term, inspect(term)}

  defp display_value(%RDF.Literal{} = literal), do: RDF.Literal.value(literal)
  defp display_value(term), do: to_string(term)

  defp maybe_issue(issues, true, severity, code, message, metadata),
    do: [issue(severity, code, message, metadata) | issues]

  defp maybe_issue(issues, false, _severity, _code, _message, _metadata), do: issues

  defp issue(severity, code, message, metadata) do
    %{severity: severity, code: code, message: message, metadata: metadata}
  end

  defp status_for(issues) do
    cond do
      Enum.any?(issues, &(&1.severity == :error)) -> :failed
      issues != [] -> :degraded
      true -> :ok
    end
  end
end
