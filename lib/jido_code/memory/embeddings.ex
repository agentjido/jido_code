defmodule JidoCode.Memory.Embeddings do
  @moduledoc """
  TF-IDF based text embeddings for semantic similarity.

  Provides lightweight semantic search without external model dependencies.
  Suitable for finding related memories based on content similarity.

  ## How It Works

  1. **Tokenization**: Text is lowercased, punctuation removed, and split into words.
     Common stopwords (the, a, is, etc.) are filtered out.

  2. **TF-IDF Scoring**: Each term gets a score based on:
     - Term Frequency (TF): How often the term appears in the document
     - Inverse Document Frequency (IDF): How rare the term is across documents

  3. **Cosine Similarity**: Embeddings are compared using cosine similarity,
     which measures the angle between vectors regardless of magnitude.

  ## Usage

      # Generate an embedding
      {:ok, embedding} = Embeddings.generate("Phoenix is a web framework")

      # Compare two embeddings
      similarity = Embeddings.cosine_similarity(embed_a, embed_b)

      # Find similar memories
      ranked = Embeddings.rank_by_similarity(query_embedding, memories)

  ## Corpus Statistics

  The module uses pre-computed IDF values based on common English text.
  This provides reasonable defaults without requiring a corpus to be built.
  """

  # =============================================================================
  # Constants
  # =============================================================================

  # Common English stopwords to filter out
  @stopwords MapSet.new(~w(
    the a an is are was were be been being
    have has had do does did will would could should
    may might must shall can
    i you he she it we they me him her us them
    my your his her its our their
    this that these those
    what which who whom whose
    and or but if then else when where why how
    all any both each few more most other some such
    no nor not only own same so than too very
    just now also
    to of in for on with at by from up about into
    over after before under between through during
    out off above below again
  ))

  # Default IDF values for common programming/tech terms
  # Higher IDF = more informative (rarer across documents)
  @default_idf_values %{
    # Common programming terms (lower IDF - appear often)
    "function" => 1.5,
    "class" => 1.5,
    "module" => 1.5,
    "file" => 1.2,
    "code" => 1.2,
    "error" => 1.8,
    "test" => 1.5,
    "data" => 1.3,
    "type" => 1.4,
    "value" => 1.3,
    "return" => 1.4,
    "call" => 1.5,
    "method" => 1.5,
    "variable" => 1.6,
    "string" => 1.5,
    "integer" => 1.7,
    "list" => 1.5,
    "map" => 1.6,
    "struct" => 1.8,
    "pattern" => 1.8,
    "tree" => 1.8,
    "processes" => 2.0,
    "application" => 1.6,

    # Elixir-specific terms (higher IDF - more specific)
    "elixir" => 2.5,
    "phoenix" => 2.8,
    "ecto" => 2.8,
    "genserver" => 3.0,
    "supervision" => 2.8,
    "supervisor" => 2.8,
    "process" => 2.0,
    "agent" => 2.5,
    "otp" => 3.0,
    "beam" => 3.0,
    "erlang" => 2.8,
    "defmodule" => 3.0,
    "def" => 1.5,
    "defp" => 2.5,
    "pipe" => 2.5,

    # Other language/framework terms
    "java" => 2.5,
    "spring" => 2.8,
    "boot" => 2.0,
    "rails" => 2.8,
    "django" => 2.8,
    "ruby" => 2.5,
    "python" => 2.5,

    # Architecture/design terms
    "architecture" => 2.5,
    "design" => 2.0,
    "convention" => 2.5,
    "decision" => 2.3,
    "configuration" => 2.0,
    "dependency" => 2.2,
    "api" => 2.0,
    "interface" => 2.0,
    "implementation" => 1.8,

    # Common action words
    "create" => 1.5,
    "update" => 1.5,
    "delete" => 1.5,
    "read" => 1.4,
    "write" => 1.5,
    "query" => 1.8,
    "filter" => 1.7,
    "sort" => 1.7,
    "validate" => 1.8,
    "handle" => 1.6
  }

  # Default IDF for unknown terms (slightly penalized for being generic)
  @default_unknown_idf 2.0

  # Minimum similarity threshold for considering a match
  @default_similarity_threshold 0.1

  # =============================================================================
  # Types
  # =============================================================================

  @typedoc """
  An embedding is a map of terms to their TF-IDF scores.
  """
  @type embedding :: %{String.t() => float()}

  @typedoc """
  Corpus statistics for TF-IDF calculation.
  """
  @type corpus_stats :: %{
          idf: %{String.t() => float()},
          default_idf: float()
        }

  # =============================================================================
  # Public API - Tokenization
  # =============================================================================

  @doc """
  Tokenizes text into a list of normalized terms.

  Performs the following transformations:
  - Converts to lowercase
  - Removes punctuation (preserving word boundaries)
  - Splits on whitespace
  - Removes stopwords
  - Filters empty tokens

  ## Examples

      iex> Embeddings.tokenize("Hello, World!")
      ["hello", "world"]

      iex> Embeddings.tokenize("The quick brown fox")
      ["quick", "brown", "fox"]

      iex> Embeddings.tokenize("Phoenix is a web framework")
      ["phoenix", "web", "framework"]

  """
  @spec tokenize(String.t()) :: [String.t()]
  def tokenize(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&stopword?/1)
    |> Enum.reject(&(&1 == ""))
  end

  def tokenize(_), do: []

  @doc """
  Checks if a word is a stopword.
  """
  @spec stopword?(String.t()) :: boolean()
  def stopword?(word) when is_binary(word) do
    MapSet.member?(@stopwords, word)
  end

  def stopword?(_), do: false

  @doc """
  Returns the set of stopwords used for filtering.
  """
  @spec stopwords() :: MapSet.t(String.t())
  def stopwords, do: @stopwords

  # =============================================================================
  # Public API - TF-IDF
  # =============================================================================

  @doc """
  Computes TF-IDF scores for a list of tokens.

  ## Parameters

  - `tokens` - List of terms from tokenization
  - `corpus_stats` - Corpus statistics with IDF values (optional)

  ## Returns

  A map of terms to their TF-IDF scores.

  ## Examples

      iex> tokens = ["phoenix", "web", "framework"]
      iex> Embeddings.compute_tfidf(tokens)
      %{"phoenix" => 0.933, "web" => 0.666, "framework" => 0.666}

  """
  @spec compute_tfidf([String.t()], corpus_stats()) :: embedding()
  def compute_tfidf(tokens, corpus_stats \\ default_corpus_stats())

  def compute_tfidf([], _corpus_stats), do: %{}

  def compute_tfidf(tokens, corpus_stats) when is_list(tokens) do
    # Term frequency in document
    tf = Enum.frequencies(tokens)
    doc_length = length(tokens)

    # TF-IDF for each term
    Enum.reduce(tf, %{}, fn {term, count}, acc ->
      tf_score = count / doc_length
      idf_score = Map.get(corpus_stats.idf, term, corpus_stats.default_idf)
      Map.put(acc, term, tf_score * idf_score)
    end)
  end

  @doc """
  Returns the default corpus statistics.

  Uses pre-computed IDF values for common programming and Elixir terms.
  """
  @spec default_corpus_stats() :: corpus_stats()
  def default_corpus_stats do
    %{
      idf: @default_idf_values,
      default_idf: @default_unknown_idf
    }
  end

  # =============================================================================
  # Public API - Embedding Generation
  # =============================================================================

  @doc """
  Generates a TF-IDF embedding for the given text.

  ## Parameters

  - `text` - The text to embed
  - `corpus_stats` - Optional corpus statistics (defaults to programming corpus)

  ## Returns

  - `{:ok, embedding}` - The TF-IDF embedding map
  - `{:error, :empty_text}` - If the text produces no tokens

  ## Examples

      iex> {:ok, embedding} = Embeddings.generate("Phoenix web framework")
      iex> Map.has_key?(embedding, "phoenix")
      true

      iex> Embeddings.generate("")
      {:error, :empty_text}

  """
  @spec generate(String.t(), corpus_stats()) :: {:ok, embedding()} | {:error, :empty_text}
  def generate(text, corpus_stats \\ default_corpus_stats())

  def generate(text, corpus_stats) when is_binary(text) do
    tokens = tokenize(text)

    if tokens == [] do
      {:error, :empty_text}
    else
      {:ok, compute_tfidf(tokens, corpus_stats)}
    end
  end

  def generate(_, _), do: {:error, :empty_text}

  @doc """
  Generates an embedding, returning an empty map on error.

  Useful for pipeline-style code where errors should be ignored.
  """
  @spec generate!(String.t(), corpus_stats()) :: embedding()
  def generate!(text, corpus_stats \\ default_corpus_stats()) do
    case generate(text, corpus_stats) do
      {:ok, embedding} -> embedding
      {:error, _} -> %{}
    end
  end

  # =============================================================================
  # Public API - Similarity
  # =============================================================================

  @doc """
  Computes cosine similarity between two embeddings.

  Returns a value between 0.0 (completely different) and 1.0 (identical).

  ## Algorithm

  Cosine similarity measures the angle between two vectors:
  - 1.0 means vectors point in the same direction (identical content)
  - 0.0 means vectors are perpendicular (no overlap)
  - Negative values are theoretically possible but rare with TF-IDF

  ## Examples

      iex> vec_a = %{"phoenix" => 1.0, "web" => 0.5}
      iex> vec_b = %{"phoenix" => 1.0, "web" => 0.5}
      iex> Embeddings.cosine_similarity(vec_a, vec_b)
      1.0

      iex> vec_a = %{"phoenix" => 1.0}
      iex> vec_b = %{"rails" => 1.0}
      iex> Embeddings.cosine_similarity(vec_a, vec_b)
      0.0

  """
  @spec cosine_similarity(embedding(), embedding()) :: float()
  def cosine_similarity(vec_a, vec_b) when is_map(vec_a) and is_map(vec_b) do
    # Get all terms from both vectors
    all_terms =
      MapSet.union(
        MapSet.new(Map.keys(vec_a)),
        MapSet.new(Map.keys(vec_b))
      )

    # Calculate dot product and magnitudes
    {dot, mag_a, mag_b} =
      Enum.reduce(all_terms, {0.0, 0.0, 0.0}, fn term, {dot, ma, mb} ->
        a = Map.get(vec_a, term, 0.0)
        b = Map.get(vec_b, term, 0.0)
        {dot + a * b, ma + a * a, mb + b * b}
      end)

    if mag_a == 0.0 or mag_b == 0.0 do
      0.0
    else
      dot / (:math.sqrt(mag_a) * :math.sqrt(mag_b))
    end
  end

  def cosine_similarity(_, _), do: 0.0

  @doc """
  Returns the default similarity threshold.
  """
  @spec default_similarity_threshold() :: float()
  def default_similarity_threshold, do: @default_similarity_threshold

  # =============================================================================
  # Public API - Ranking
  # =============================================================================

  @doc """
  Ranks items by semantic similarity to a query embedding.

  ## Parameters

  - `query_embedding` - The embedding to compare against
  - `items` - List of items to rank
  - `opts` - Options:
    - `:get_content` - Function to extract text content from item (default: `& &1.content`)
    - `:threshold` - Minimum similarity to include (default: 0.1)
    - `:limit` - Maximum items to return (default: nil = all)

  ## Returns

  List of `{item, similarity_score}` tuples, sorted by score descending.

  ## Examples

      memories = [
        %{id: 1, content: "Phoenix framework patterns"},
        %{id: 2, content: "Rails convention over configuration"},
        %{id: 3, content: "Phoenix LiveView components"}
      ]

      {:ok, query_embed} = Embeddings.generate("Phoenix patterns")
      ranked = Embeddings.rank_by_similarity(query_embed, memories)
      # Returns memories related to Phoenix, ranked by similarity

  """
  @spec rank_by_similarity(embedding(), [map()], keyword()) :: [{map(), float()}]
  def rank_by_similarity(query_embedding, items, opts \\ []) do
    get_content = Keyword.get(opts, :get_content, & &1.content)
    threshold = Keyword.get(opts, :threshold, @default_similarity_threshold)
    limit = Keyword.get(opts, :limit)

    items
    |> Enum.map(fn item ->
      content = get_content.(item)
      item_embedding = generate!(content)
      score = cosine_similarity(query_embedding, item_embedding)
      {item, score}
    end)
    |> Enum.filter(fn {_, score} -> score >= threshold end)
    |> Enum.sort_by(fn {_, score} -> score end, :desc)
    |> maybe_limit(limit)
  end

  defp maybe_limit(items, nil), do: items
  defp maybe_limit(items, limit) when is_integer(limit), do: Enum.take(items, limit)

  @doc """
  Finds items semantically similar to a query string.

  Convenience function that generates the query embedding internally.

  ## Parameters

  - `query` - The query string
  - `items` - List of items to search
  - `opts` - Same options as `rank_by_similarity/3`

  ## Returns

  List of `{item, similarity_score}` tuples, or empty list if query produces no tokens.
  """
  @spec find_similar(String.t(), [map()], keyword()) :: [{map(), float()}]
  def find_similar(query, items, opts \\ []) do
    case generate(query) do
      {:ok, query_embedding} ->
        rank_by_similarity(query_embedding, items, opts)

      {:error, _} ->
        []
    end
  end

  # =============================================================================
  # Public API - Utilities
  # =============================================================================

  @doc """
  Returns the default IDF values used for common terms.
  """
  @spec default_idf_values() :: %{String.t() => float()}
  def default_idf_values, do: @default_idf_values

  @doc """
  Returns the default IDF value for unknown terms.
  """
  @spec default_unknown_idf() :: float()
  def default_unknown_idf, do: @default_unknown_idf
end
