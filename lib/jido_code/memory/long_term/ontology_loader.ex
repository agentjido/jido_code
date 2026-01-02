defmodule JidoCode.Memory.LongTerm.OntologyLoader do
  @moduledoc """
  Loads the Jido ontology TTL files into a TripleStore.

  The ontology provides the class hierarchy, properties, and individuals
  that define the structure of long-term memory.

  ## Ontology Files

  The following TTL files are loaded from `lib/ontology/long-term-context/`:

  - `jido-core.ttl` - Core classes (MemoryItem, Entity, Confidence, Source)
  - `jido-knowledge.ttl` - Knowledge types (Fact, Assumption, Hypothesis)
  - `jido-decision.ttl` - Decision types (Decision, Alternative, TradeOff)
  - `jido-convention.ttl` - Convention types (CodingStandard, AgentRule)
  - `jido-error.ttl` - Error types (Bug, Failure, LessonLearned)
  - `jido-session.ttl` - Session modeling
  - `jido-agent.ttl` - Agent modeling
  - `jido-project.ttl` - Project modeling
  - `jido-task.ttl` - Task modeling
  - `jido-code.ttl` - Code-related classes

  ## Usage

      {:ok, store} = TripleStore.open(path, create_if_missing: true)
      {:ok, count} = OntologyLoader.load_ontology(store)

      # Check if ontology is loaded
      true = OntologyLoader.ontology_loaded?(store)

      # Force reload
      {:ok, count} = OntologyLoader.reload_ontology(store)
  """

  require Logger

  @jido_namespace "https://jido.ai/ontology#"

  # Core ontology files in load order
  # jido-core must be first as it defines base classes
  @ontology_files [
    "jido-core.ttl",
    "jido-knowledge.ttl",
    "jido-decision.ttl",
    "jido-convention.ttl",
    "jido-error.ttl",
    "jido-session.ttl",
    "jido-agent.ttl",
    "jido-project.ttl",
    "jido-task.ttl",
    "jido-code.ttl"
  ]

  # Relative path from project root
  @ontology_path "lib/ontology/long-term-context"

  @doc """
  Returns the Jido ontology namespace IRI.
  """
  @spec namespace() :: String.t()
  def namespace, do: @jido_namespace

  @doc """
  Returns the list of ontology files that will be loaded.
  """
  @spec ontology_files() :: [String.t()]
  def ontology_files, do: @ontology_files

  @doc """
  Returns the resolved ontology directory path.

  Caches the resolved path for efficiency.
  """
  @spec ontology_path() :: String.t()
  def ontology_path do
    case :persistent_term.get({__MODULE__, :ontology_path}, nil) do
      nil ->
        path = resolve_ontology_path()
        :persistent_term.put({__MODULE__, :ontology_path}, path)
        path

      path ->
        path
    end
  end

  @doc """
  Loads all ontology TTL files into the given TripleStore.

  Returns `{:ok, total_triple_count}` on success, or `{:error, reason}` on failure.

  ## Example

      {:ok, store} = TripleStore.open(path, create_if_missing: true)
      {:ok, 450} = OntologyLoader.load_ontology(store)
  """
  @spec load_ontology(TripleStore.store()) :: {:ok, non_neg_integer()} | {:error, term()}
  def load_ontology(store) do
    base_path = ontology_path()

    Logger.debug("Loading ontology from #{base_path}")

    results =
      @ontology_files
      |> Enum.map(fn file ->
        path = Path.join(base_path, file)
        load_ttl_file(store, path, file)
      end)

    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {successes, []} ->
        total = successes |> Enum.map(fn {:ok, count} -> count end) |> Enum.sum()
        Logger.info("Loaded ontology: #{total} triples from #{length(successes)} files")
        {:ok, total}

      {_successes, failures} ->
        errors = Enum.map(failures, fn {:error, reason} -> reason end)
        Logger.error("Failed to load ontology: #{inspect(errors)}")
        {:error, {:load_failed, errors}}
    end
  end

  @doc """
  Checks if the ontology has been loaded into the store.

  Returns `true` if the jido:MemoryItem class exists in the store.
  """
  @spec ontology_loaded?(TripleStore.store()) :: boolean()
  def ontology_loaded?(store) do
    query = """
    PREFIX jido: <#{@jido_namespace}>
    PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
    PREFIX owl: <http://www.w3.org/2002/07/owl#>

    ASK {
      jido:MemoryItem rdf:type owl:Class .
    }
    """

    case TripleStore.query(store, query) do
      {:ok, true} -> true
      {:ok, false} -> false
      {:error, _} -> false
    end
  end

  @doc """
  Reloads the ontology by clearing existing ontology triples and loading fresh.

  This is useful for development when ontology files are modified.

  Returns `{:ok, total_triple_count}` on success.
  """
  @spec reload_ontology(TripleStore.store()) :: {:ok, non_neg_integer()} | {:error, term()}
  def reload_ontology(store) do
    Logger.info("Reloading ontology...")

    # Clear existing ontology triples (those with jido: namespace subjects)
    clear_query = """
    PREFIX jido: <#{@jido_namespace}>

    DELETE WHERE {
      ?s ?p ?o .
      FILTER(STRSTARTS(STR(?s), "#{@jido_namespace}"))
    }
    """

    case TripleStore.update(store, clear_query) do
      {:ok, _} ->
        load_ontology(store)

      {:error, reason} ->
        Logger.warning("Could not clear ontology: #{inspect(reason)}, loading anyway")
        load_ontology(store)
    end
  end

  @doc """
  Lists all classes defined in the ontology.
  """
  @spec list_classes(TripleStore.store()) :: {:ok, [String.t()]} | {:error, term()}
  def list_classes(store) do
    query = """
    PREFIX jido: <#{@jido_namespace}>
    PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
    PREFIX owl: <http://www.w3.org/2002/07/owl#>

    SELECT DISTINCT ?class WHERE {
      ?class rdf:type owl:Class .
      FILTER(STRSTARTS(STR(?class), "#{@jido_namespace}"))
    }
    ORDER BY ?class
    """

    case TripleStore.query(store, query) do
      {:ok, results} ->
        classes = Enum.map(results, fn %{"class" => class} -> extract_iri(class) end)
        {:ok, classes}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all individuals defined in the ontology.
  """
  @spec list_individuals(TripleStore.store()) :: {:ok, [String.t()]} | {:error, term()}
  def list_individuals(store) do
    query = """
    PREFIX jido: <#{@jido_namespace}>
    PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
    PREFIX owl: <http://www.w3.org/2002/07/owl#>

    SELECT DISTINCT ?individual WHERE {
      ?individual rdf:type owl:NamedIndividual .
      FILTER(STRSTARTS(STR(?individual), "#{@jido_namespace}"))
    }
    ORDER BY ?individual
    """

    case TripleStore.query(store, query) do
      {:ok, results} ->
        individuals = Enum.map(results, fn %{"individual" => ind} -> extract_iri(ind) end)
        {:ok, individuals}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all properties defined in the ontology.
  """
  @spec list_properties(TripleStore.store()) :: {:ok, [String.t()]} | {:error, term()}
  def list_properties(store) do
    query = """
    PREFIX jido: <#{@jido_namespace}>
    PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
    PREFIX owl: <http://www.w3.org/2002/07/owl#>

    SELECT DISTINCT ?prop WHERE {
      { ?prop rdf:type owl:ObjectProperty }
      UNION
      { ?prop rdf:type owl:DatatypeProperty }
      FILTER(STRSTARTS(STR(?prop), "#{@jido_namespace}"))
    }
    ORDER BY ?prop
    """

    case TripleStore.query(store, query) do
      {:ok, results} ->
        properties = Enum.map(results, fn %{"prop" => prop} -> extract_iri(prop) end)
        {:ok, properties}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helpers

  defp load_ttl_file(store, path, file) do
    if File.exists?(path) do
      case TripleStore.load(store, path) do
        {:ok, count} ->
          Logger.debug("Loaded #{file}: #{count} triples")
          {:ok, count}

        {:error, reason} ->
          Logger.error("Failed to load #{file}: #{inspect(reason)}")
          {:error, {file, reason}}
      end
    else
      Logger.error("Ontology file not found: #{path}")
      {:error, {file, :not_found}}
    end
  end

  defp resolve_ontology_path do
    # Try various methods to find the ontology path
    cwd_path = Path.join(File.cwd!(), @ontology_path)
    compile_path = Path.join([__DIR__, "..", "..", "..", "..", @ontology_path]) |> Path.expand()

    cond do
      # From current working directory (most common in development/test)
      File.dir?(cwd_path) ->
        cwd_path

      # From __DIR__ relative (works when running from different directory)
      File.dir?(compile_path) ->
        compile_path

      true ->
        # Fallback to relative path, will fail at load time if wrong
        @ontology_path
    end
  end

  defp extract_iri({:named_node, iri}), do: iri
  defp extract_iri(%RDF.IRI{} = iri), do: to_string(iri)
  defp extract_iri(iri) when is_binary(iri), do: iri
end
