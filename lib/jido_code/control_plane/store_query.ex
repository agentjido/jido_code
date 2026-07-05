defmodule JidoCode.ControlPlane.StoreQuery do
  @moduledoc """
  Bounded read boundary for product control-plane records in the embedded store.

  Product callers use shaped helpers for ordinary reads. Raw SPARQL stays behind
  `diagnostics_query/2`, where graph allow-lists, timeouts, row limits, and
  security redaction are explicit.
  """

  alias JidoCode.ControlPlane.{GraphTopology, SemanticIdentity, StoreServer, Telemetry}
  alias TripleStore.Dictionary.{Manager, ShardedManager}

  @control_plane_ns "https://jido.run/ontology/control-plane#"
  @default_limit 50
  @max_limit 500
  @default_timeout_ms 5_000
  @diagnostics_default_graphs [:control_plane]
  @sensitive_graphs [:auth, :security]

  @type query_options :: [
          server: GenServer.server(),
          limit: pos_integer(),
          offset: non_neg_integer(),
          timeout: pos_integer(),
          allowed_graphs: [GraphTopology.graph_name()]
        ]

  @spec get_by_id(SemanticIdentity.record_type(), String.t() | map() | keyword(), query_options()) ::
          {:ok, map() | nil} | {:error, atom(), map()}
  def get_by_id(record_type, identity, opts \\ []) do
    with {:ok, context} <- record_context(record_type),
         {:ok, subject_iri} <- SemanticIdentity.canonical_iri(record_type, identity) do
      run_query(opts, :get_by_id, fn store ->
        projection_for_subject(store, context, RDF.iri(subject_iri))
      end)
    else
      {:error, reason} -> invalid_query(:get_by_id, reason, %{record_type: record_type})
    end
  end

  @spec list_by_class(SemanticIdentity.record_type(), query_options()) ::
          {:ok, map()} | {:error, atom(), map()}
  def list_by_class(record_type, opts \\ []) do
    with {:ok, context} <- record_context(record_type) do
      run_query(opts, :list_by_class, fn store ->
        with {:ok, subjects} <- subjects_for_class(store, context) do
          {:ok, paged_projection_result(store, context, subjects, opts, :list_by_class)}
        end
      end)
    else
      {:error, reason} -> invalid_query(:list_by_class, reason, %{record_type: record_type})
    end
  end

  @spec list_by_repo(SemanticIdentity.record_type(), String.t(), query_options()) ::
          {:ok, map()} | {:error, atom(), map()}
  def list_by_repo(record_type, managed_repo_id, opts \\ [])

  def list_by_repo(record_type, managed_repo_id, opts) when is_binary(managed_repo_id) do
    with {:ok, context} <- record_context(record_type) do
      run_query(opts, :list_by_repo, fn store ->
        with {:ok, subjects} <-
               subjects_for_predicate_value(store, context, control_iri("managedRepoId"), managed_repo_id),
             {:ok, typed_subjects} <- filter_subjects_by_class(store, context, subjects) do
          {:ok,
           paged_projection_result(
             store,
             context,
             typed_subjects,
             opts,
             :list_by_repo,
             %{managed_repo_id: managed_repo_id}
           )}
        end
      end)
    else
      {:error, reason} -> invalid_query(:list_by_repo, reason, %{record_type: record_type})
    end
  end

  def list_by_repo(record_type, _managed_repo_id, _opts),
    do: invalid_query(:list_by_repo, :invalid_managed_repo_id, %{record_type: record_type})

  @spec lookup_by_identity(SemanticIdentity.record_type(), map() | keyword(), query_options()) ::
          {:ok, map() | nil} | {:error, atom(), map()}
  def lookup_by_identity(record_type, identity, opts \\ []) do
    with {:ok, context} <- record_context(record_type),
         {:ok, predicate} <- identity_predicate(identity),
         {:ok, value} <- identity_value(identity) do
      run_query(opts, :lookup_by_identity, fn store ->
        with {:ok, subjects} <- subjects_for_predicate_value(store, context, predicate, value),
             {:ok, typed_subjects} <- filter_subjects_by_class(store, context, subjects) do
          case typed_subjects do
            [] ->
              {:ok, nil}

            [subject] ->
              projection_for_subject(store, context, subject)

            subjects ->
              {:error, :control_plane_query_failed,
               diagnostics(:lookup_by_identity, :ambiguous_identity, %{
                 record_type: record_type,
                 identity: identity_name(identity),
                 subject_count: length(subjects)
               })}
          end
        end
      end)
    else
      {:error, reason} -> invalid_query(:lookup_by_identity, reason, %{record_type: record_type})
    end
  end

  @spec diagnostics_query(String.t(), query_options()) :: {:ok, map()} | {:error, atom(), map()}
  def diagnostics_query(sparql, opts \\ [])

  def diagnostics_query(sparql, opts) when is_binary(sparql) do
    with {:ok, allowed_graphs} <- allowed_diagnostic_graphs(opts),
         :ok <- validate_diagnostic_sparql(sparql, allowed_graphs) do
      limit = limit(opts)
      timeout = timeout_ms(opts)
      bounded_sparql = bounded_select_sparql(sparql, limit + 1)

      run_query(opts, :diagnostics_query, fn store ->
        query_context = %{db: store.db, dict_manager: store.dict_manager, permit_all: true}

        case TripleStore.SPARQL.Query.query(query_context, bounded_sparql, timeout: timeout) do
          {:ok, raw_result} ->
            {:ok, diagnostic_result(raw_result, sparql, allowed_graphs, limit, timeout)}

          {:error, {:parse_error, reason}} ->
            {:error, :control_plane_invalid_query,
             diagnostics(:parse_query, reason, %{library: :sparql, allowed_graphs: allowed_graphs})}

          {:error, :timeout} ->
            {:error, :control_plane_query_timeout,
             diagnostics(:diagnostics_query, :timeout, %{timeout_ms: timeout, allowed_graphs: allowed_graphs})}

          {:error, reason} ->
            {:error, :control_plane_query_failed,
             diagnostics(:diagnostics_query, reason, %{library: :sparql, allowed_graphs: allowed_graphs})}
        end
      end)
    else
      {:error, reason} -> invalid_query(:diagnostics_query, reason)
      {:error, reason, diagnostics} -> {:error, reason, diagnostics}
    end
  end

  def diagnostics_query(_sparql, _opts), do: invalid_query(:diagnostics_query, :invalid_sparql)

  defp record_context(record_type) do
    with {:ok, graph_name} <- GraphTopology.graph_for_record(record_type),
         {:ok, graph_resource} <- GraphTopology.graph_resource(graph_name),
         {:ok, graph_iri} <- GraphTopology.graph_iri(graph_name),
         {:ok, class_iri} <- SemanticIdentity.class_iri(record_type) do
      {:ok,
       %{
         record_type: record_type,
         graph_name: graph_name,
         graph_resource: graph_resource,
         graph_iri: graph_iri,
         class_iri: class_iri
       }}
    end
  end

  defp run_query(opts, stage, fun) when is_function(fun, 1) do
    Telemetry.span(:query, %{stage: stage, limit: limit(opts), timeout_ms: timeout_ms(opts)}, fn ->
      do_run_query(opts, stage, fun)
    end)
  end

  defp do_run_query(opts, stage, fun) do
    server = Keyword.get(opts, :server, StoreServer)
    timeout = timeout_ms(opts)

    with_store_result =
      try do
        StoreServer.with_store(server, fn store -> run_with_timeout(store, timeout, stage, fun) end)
      catch
        :exit, reason -> {:error, reason}
      end

    case with_store_result do
      {:ok, {:ok, result}} ->
        {:ok, result}

      {:ok, {:error, reason, diagnostics}} ->
        {:error, reason, diagnostics}

      {:ok, {:error, reason}} ->
        {:error, :control_plane_query_failed, diagnostics(stage, reason)}

      {:error, reason} ->
        {:error, :control_plane_store_unavailable, diagnostics(stage, reason)}
    end
  end

  defp run_with_timeout(store, timeout, stage, fun) do
    task = Task.async(fn -> fun.(store) end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} ->
        result

      {:exit, reason} ->
        {:error, :control_plane_query_failed, diagnostics(stage, reason)}

      nil ->
        {:error, :control_plane_query_timeout, diagnostics(stage, :timeout, %{timeout_ms: timeout})}
    end
  end

  defp projection_for_subject(store, context, subject) do
    with {:ok, graph_id} <- lookup_id(store, context.graph_resource),
         {:ok, subject_id} <- lookup_id(store, subject) do
      quads =
        TripleStore.QuadOperations.lookup_quads(
          store.db,
          {:bound, :var, :var, :bound},
          %{s: subject_id, g: graph_id}
        )

      case quads do
        [] ->
          {:ok, nil}

        quads ->
          {:ok, projection_from_quads(store, context, subject, quads)}
      end
    else
      :not_found -> {:ok, nil}
      {:error, reason} -> {:error, :control_plane_query_failed, diagnostics(:projection, reason)}
    end
  end

  defp projection_from_quads(store, context, subject, quads) do
    facts =
      quads
      |> Enum.flat_map(&decode_predicate_object(store, &1))
      |> Enum.sort_by(fn %{predicate_iri: predicate_iri, object: object} -> {predicate_iri, inspect(object)} end)

    attributes =
      facts
      |> Enum.reject(&(&1.predicate_iri == to_string(RDF.type())))
      |> Enum.group_by(&local_name(&1.predicate_iri), & &1.object)

    %{
      subject_iri: to_string(subject),
      record_type: context.record_type,
      class_iri: to_string(context.class_iri),
      graph_name: context.graph_name,
      graph_iri: context.graph_iri,
      attributes: attributes,
      facts: facts
    }
  end

  defp subjects_for_class(store, context) do
    with {:ok, graph_id} <- lookup_id(store, context.graph_resource),
         {:ok, type_id} <- lookup_id(store, RDF.type()),
         {:ok, class_id} <- lookup_id(store, context.class_iri) do
      subjects =
        store.db
        |> TripleStore.QuadOperations.lookup_quads(
          {:var, :bound, :bound, :bound},
          %{p: type_id, o: class_id, g: graph_id}
        )
        |> decode_subjects(store)

      {:ok, subjects}
    else
      :not_found -> {:ok, []}
      {:error, reason} -> {:error, :control_plane_query_failed, diagnostics(:subjects_for_class, reason)}
    end
  end

  defp subjects_for_predicate_value(store, context, predicate, value) do
    with {:ok, graph_id} <- lookup_id(store, context.graph_resource),
         {:ok, predicate_id} <- lookup_id(store, predicate),
         {:ok, object_id} <- lookup_id(store, literal_or_term(value)) do
      subjects =
        store.db
        |> TripleStore.QuadOperations.lookup_quads(
          {:var, :bound, :bound, :bound},
          %{p: predicate_id, o: object_id, g: graph_id}
        )
        |> decode_subjects(store)

      {:ok, subjects}
    else
      :not_found -> {:ok, []}
      {:error, reason} -> {:error, :control_plane_query_failed, diagnostics(:subjects_for_predicate_value, reason)}
    end
  end

  defp filter_subjects_by_class(store, context, subjects) do
    with {:ok, graph_id} <- lookup_id(store, context.graph_resource),
         {:ok, type_id} <- lookup_id(store, RDF.type()),
         {:ok, class_id} <- lookup_id(store, context.class_iri) do
      {:ok,
       Enum.filter(subjects, fn subject ->
         with {:ok, subject_id} <- lookup_id(store, subject) do
           TripleStore.QuadOperations.quad_exists?(store.db, {subject_id, type_id, class_id, graph_id}) == true
         else
           _other -> false
         end
       end)}
    else
      :not_found -> {:ok, []}
      {:error, reason} -> {:error, :control_plane_query_failed, diagnostics(:filter_subjects_by_class, reason)}
    end
  end

  defp paged_projection_result(store, context, subjects, opts, query_name, extra \\ %{}) do
    {paged_subjects, page} =
      subjects
      |> Enum.uniq_by(&to_string/1)
      |> Enum.sort_by(&to_string/1)
      |> paginate(opts)

    results =
      paged_subjects
      |> Enum.map(fn subject -> projection_for_subject(store, context, subject) end)
      |> Enum.flat_map(fn
        {:ok, nil} -> []
        {:ok, projection} -> [projection]
        _error -> []
      end)

    %{
      status: :query_succeeded,
      query: query_name,
      graph_name: context.graph_name,
      graph_iri: context.graph_iri,
      record_type: context.record_type,
      class_iri: to_string(context.class_iri),
      results: results,
      row_count: length(results),
      total_count: page.total_count,
      limit: page.limit,
      offset: page.offset,
      next_offset: page.next_offset
    }
    |> Map.merge(extra)
  end

  defp paginate(subjects, opts) do
    limit = limit(opts)
    offset = offset(opts)
    total_count = length(subjects)
    page = subjects |> Enum.drop(offset) |> Enum.take(limit)
    next_offset = if offset + length(page) < total_count, do: offset + length(page), else: nil

    {page, %{limit: limit, offset: offset, total_count: total_count, next_offset: next_offset}}
  end

  defp decode_subjects(quads, store) do
    quads
    |> Enum.flat_map(fn {subject_id, _predicate_id, _object_id, _graph_id} ->
      case TripleStore.Adapter.id_to_term(store.db, subject_id) do
        {:ok, subject} -> [subject]
        _other -> []
      end
    end)
    |> Enum.uniq_by(&to_string/1)
  end

  defp decode_predicate_object(store, {_subject_id, predicate_id, object_id, _graph_id}) do
    with {:ok, predicate} <- TripleStore.Adapter.id_to_term(store.db, predicate_id),
         {:ok, object} <- TripleStore.Adapter.id_to_term(store.db, object_id) do
      [
        %{
          predicate_iri: to_string(predicate),
          predicate: local_name(to_string(predicate)),
          object: format_term(object)
        }
      ]
    else
      _other -> []
    end
  end

  defp lookup_id(store, %RDF.Literal{} = literal) do
    case TripleStore.Adapter.lookup_term_id(store.db, literal) do
      {:error, :requires_manager} -> manager_lookup_id(store.dict_manager, literal)
      other -> other
    end
  end

  defp lookup_id(store, term), do: TripleStore.Adapter.lookup_term_id(store.db, term)

  defp manager_lookup_id(manager, term) do
    case manager_kind(manager) do
      :sharded -> ShardedManager.lookup_id(manager, term)
      :manager -> Manager.lookup_id(manager, term)
      :unknown -> {:error, :unsupported_dictionary_manager}
    end
  end

  defp manager_kind(manager) when is_pid(manager) do
    case Process.info(manager, :dictionary) do
      {:dictionary, dictionary} ->
        case Keyword.get(dictionary, :"$initial_call") do
          {:supervisor, Supervisor.Default, 1} -> :sharded
          _other -> :manager
        end

      nil ->
        :unknown
    end
  end

  defp manager_kind(_manager), do: :unknown

  defp identity_predicate(identity) do
    attrs = attrs_map(identity)

    case get_attr(attrs, :predicate_iri) || get_attr(attrs, :predicate) do
      %RDF.IRI{} = iri -> {:ok, iri}
      value when is_binary(value) and value != "" -> {:ok, RDF.iri(value)}
      _other -> {:error, :invalid_identity}
    end
  end

  defp identity_value(identity) do
    attrs = attrs_map(identity)

    case get_attr(attrs, :value) do
      %RDF.IRI{} = iri -> {:ok, iri}
      %RDF.Literal{} = literal -> {:ok, literal}
      value when is_binary(value) -> {:ok, RDF.literal(value)}
      value when is_atom(value) -> {:ok, RDF.literal(Atom.to_string(value))}
      value when is_integer(value) -> {:ok, RDF.literal(value)}
      _other -> {:error, :invalid_identity}
    end
  end

  defp identity_name(identity), do: identity |> attrs_map() |> get_attr(:identity, :identity)

  defp literal_or_term(%RDF.IRI{} = iri), do: iri
  defp literal_or_term(%RDF.BlankNode{} = blank_node), do: blank_node
  defp literal_or_term(%RDF.Literal{} = literal), do: literal
  defp literal_or_term(value) when is_binary(value), do: RDF.literal(value)
  defp literal_or_term(value) when is_atom(value), do: RDF.literal(Atom.to_string(value))
  defp literal_or_term(value), do: RDF.literal(value)

  defp allowed_diagnostic_graphs(opts) do
    graph_names = Keyword.get(opts, :allowed_graphs, @diagnostics_default_graphs)

    graph_names
    |> List.wrap()
    |> Enum.map(&normalize_graph_name/1)
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, graph_name}, {:ok, acc} ->
        {:cont, {:ok, [graph_name | acc]}}

      {:error, reason}, _acc ->
        {:halt, {:error, reason}}
    end)
    |> case do
      {:ok, []} -> {:error, :missing_allowed_graphs}
      {:ok, names} -> {:ok, names |> Enum.uniq() |> Enum.reverse()}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_graph_name(graph_name) when is_atom(graph_name) do
    with {:ok, _iri} <- GraphTopology.graph_iri(graph_name), do: {:ok, graph_name}
  end

  defp normalize_graph_name(graph_name) when is_binary(graph_name) do
    graph_name
    |> String.to_existing_atom()
    |> normalize_graph_name()
  rescue
    ArgumentError -> {:error, :unknown_graph}
  end

  defp normalize_graph_name(_graph_name), do: {:error, :unknown_graph}

  defp validate_diagnostic_sparql(sparql, allowed_graphs) do
    cond do
      String.trim(sparql) == "" ->
        {:error, :empty_sparql}

      not Regex.match?(~r/^\s*(SELECT|ASK)\b/i, sparql) ->
        {:error, :unsupported_diagnostic_query_form}

      Regex.match?(~r/\bGRAPH\s+(?!<)/i, sparql) ->
        {:error, :diagnostic_graph_must_be_explicit_iri}

      true ->
        validate_diagnostic_graph_refs(sparql, allowed_graphs)
    end
  end

  defp validate_diagnostic_graph_refs(sparql, allowed_graphs) do
    allowed_iris =
      allowed_graphs
      |> Map.new(fn graph_name ->
        {:ok, iri} = GraphTopology.graph_iri(graph_name)
        {iri, graph_name}
      end)

    sparql
    |> graph_iris_in_sparql()
    |> Enum.find(&(not Map.has_key?(allowed_iris, &1)))
    |> case do
      nil -> :ok
      blocked_iri -> {:error, {:graph_not_allowed, blocked_iri}}
    end
  end

  defp graph_iris_in_sparql(sparql) do
    ~r/\bGRAPH\s+<([^>]+)>/i
    |> Regex.scan(sparql, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp bounded_select_sparql(sparql, row_limit) do
    cond do
      Regex.match?(~r/^\s*ASK\b/i, sparql) ->
        sparql

      Regex.match?(~r/\bLIMIT\s+\d+\b/i, sparql) ->
        Regex.replace(~r/\bLIMIT\s+(\d+)\b/i, sparql, fn _match, limit ->
          "LIMIT #{min(String.to_integer(limit), row_limit)}"
        end)

      true ->
        sparql <> "\nLIMIT #{row_limit}"
    end
  end

  defp diagnostic_result(raw_result, sparql, allowed_graphs, limit, timeout) when is_list(raw_result) do
    sensitive? = Enum.any?(allowed_graphs, &(&1 in @sensitive_graphs))
    bindings = raw_result |> Enum.take(limit) |> Enum.map(&format_solution(&1, sensitive?))

    %{
      status: :query_succeeded,
      query: :diagnostics_query,
      engine: :sparql,
      library: :sparql,
      sparql: sparql,
      allowed_graphs: allowed_graphs,
      bindings: bindings,
      row_count: length(bindings),
      limit: limit,
      timeout_ms: timeout,
      truncated?: length(raw_result) > limit,
      redacted?: sensitive?
    }
  end

  defp diagnostic_result(raw_result, sparql, allowed_graphs, limit, timeout) when is_boolean(raw_result) do
    %{
      status: :query_succeeded,
      query: :diagnostics_query,
      engine: :sparql,
      library: :sparql,
      sparql: sparql,
      allowed_graphs: allowed_graphs,
      boolean: raw_result,
      bindings: [],
      row_count: 0,
      limit: limit,
      timeout_ms: timeout,
      truncated?: false,
      redacted?: false
    }
  end

  defp diagnostic_result(raw_result, sparql, allowed_graphs, limit, timeout) do
    %{
      status: :query_succeeded,
      query: :diagnostics_query,
      engine: :sparql,
      library: :sparql,
      sparql: sparql,
      allowed_graphs: allowed_graphs,
      result: inspect(raw_result),
      bindings: [],
      row_count: 0,
      limit: limit,
      timeout_ms: timeout,
      truncated?: false,
      redacted?: Enum.any?(allowed_graphs, &(&1 in @sensitive_graphs))
    }
  end

  defp format_solution(solution, sensitive?) when is_map(solution) do
    solution
    |> Map.drop([:__id__])
    |> Map.new(fn {variable, value} -> {to_string(variable), format_diagnostic_value(value, sensitive?)} end)
  end

  defp format_diagnostic_value(value, true) do
    case format_term(value) do
      %{type: :literal} = literal -> Map.merge(literal, %{value: "[REDACTED]", lexical: "[REDACTED]", redacted?: true})
      formatted -> formatted
    end
  end

  defp format_diagnostic_value(value, false), do: format_term(value)

  defp format_term(%RDF.IRI{} = iri), do: %{type: :iri, value: to_string(iri)}
  defp format_term(%RDF.BlankNode{} = blank_node), do: %{type: :blank_node, value: RDF.BlankNode.value(blank_node)}

  defp format_term(%RDF.Literal{} = literal) do
    %{
      type: :literal,
      value: RDF.Literal.value(literal),
      lexical: RDF.Literal.lexical(literal),
      datatype: RDF.Literal.datatype_id(literal) && to_string(RDF.Literal.datatype_id(literal)),
      language: RDF.Literal.language(literal)
    }
  end

  defp format_term({:named_node, iri}), do: %{type: :iri, value: iri}
  defp format_term({:literal, :simple, value}), do: literal_value(value, nil, nil)
  defp format_term({:literal, :typed, value, datatype}), do: literal_value(value, datatype, nil)
  defp format_term({:literal, :lang, value, language}), do: literal_value(value, nil, language)
  defp format_term(value), do: %{type: :value, value: value}

  defp literal_value(value, datatype, language) do
    %{
      type: :literal,
      value: value,
      lexical: to_string(value),
      datatype: datatype && to_string(datatype),
      language: language
    }
  end

  defp local_name(iri) do
    iri
    |> to_string()
    |> String.split(["#", "/"])
    |> List.last()
  end

  defp control_iri(local), do: RDF.iri(@control_plane_ns <> local)

  defp limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> clamp_integer(@default_limit, 1, @max_limit)
  end

  defp offset(opts) do
    opts
    |> Keyword.get(:offset, 0)
    |> clamp_integer(0, 0, 1_000_000)
  end

  defp timeout_ms(opts) do
    opts
    |> Keyword.get(:timeout, @default_timeout_ms)
    |> clamp_integer(@default_timeout_ms, 1, 60_000)
  end

  defp clamp_integer(value, _default, min, max) when is_integer(value), do: value |> max(min) |> min(max)
  defp clamp_integer(_value, default, _min, _max), do: default

  defp invalid_query(stage, reason, extra \\ %{}),
    do: {:error, :control_plane_invalid_query, diagnostics(stage, reason, extra)}

  defp diagnostics(stage, reason, extra \\ %{}) do
    Map.merge(
      %{
        status: :degraded,
        stage: stage,
        reason: reason,
        backend: :triple_store,
        schema: :quad
      },
      extra
    )
  end

  defp attrs_map(attrs) when is_list(attrs), do: Map.new(attrs)
  defp attrs_map(attrs) when is_map(attrs), do: attrs
  defp attrs_map(_attrs), do: %{}

  defp get_attr(attrs, key, default \\ nil) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key), default)
  end
end
