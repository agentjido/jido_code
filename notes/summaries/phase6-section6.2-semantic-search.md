# Phase 6 Section 6.2: Semantic Memory Search

**Date:** 2026-01-02
**Branch:** `feature/phase6-section6.2-semantic-search`

## Overview

This section implements TF-IDF based semantic similarity search for the memory system. The implementation provides lightweight semantic search without external model dependencies, enabling more intelligent memory retrieval based on content similarity rather than just exact text matching.

## Implementation Summary

### New Module: `lib/jido_code/memory/embeddings.ex`

Created a comprehensive TF-IDF embeddings module with:

**Tokenization:**
- Lowercases text
- Removes punctuation (preserving word boundaries)
- Splits on whitespace
- Removes common English stopwords (~60 words)
- Handles underscores and numbers in programming terms

**TF-IDF Calculation:**
- Term Frequency (TF): count / document_length
- Inverse Document Frequency (IDF): Pre-computed values for common programming/Elixir terms
- Unknown terms get a default IDF value of 2.0

**Default Corpus Statistics:**
Pre-computed IDF values for:
- Common programming terms (function, class, module, etc.) - lower IDF (1.2-1.8)
- Elixir-specific terms (phoenix, ecto, genserver, etc.) - higher IDF (2.5-3.0)
- Other language/framework terms (rails, django, python, etc.)
- Architecture/design terms (architecture, convention, api, etc.)
- Common action words (create, update, delete, etc.)

**Cosine Similarity:**
- Computes similarity between two TF-IDF vectors
- Returns 1.0 for identical vectors, 0.0 for orthogonal vectors
- Handles empty vectors and nil inputs gracefully

**Ranking Functions:**
- `rank_by_similarity/3`: Ranks items by semantic similarity with options for threshold, limit, and custom content extractor
- `find_similar/3`: Convenience function that generates query embedding internally

### Modified: `lib/jido_code/memory/actions/recall.ex`

Added semantic search capabilities to the Recall action:

**New `search_mode` Parameter:**
```elixir
search_mode: [
  type: {:in, [:text, :semantic, :hybrid]},
  default: :hybrid,
  doc: "Search mode: :text (substring), :semantic (TF-IDF similarity), :hybrid (both)"
]
```

**Three Search Modes:**

1. **`:text`** - Simple substring matching (fast, exact matches)
   - Case-insensitive
   - Returns memories containing the query string

2. **`:semantic`** - TF-IDF based semantic similarity
   - Generates embeddings for query and memories
   - Ranks by cosine similarity
   - Filters by similarity threshold (0.2)
   - Falls back to text search if query produces no tokens

3. **`:hybrid`** (default) - Combines text matches with semantic ranking
   - Gets text matches as a boost set
   - Ranks all memories by semantic similarity
   - Text matches get a 0.5 boost to their similarity score
   - Falls back to text search if embeddings unavailable

**Implementation Notes:**
- Embeddings computed on-the-fly rather than stored (TF-IDF is fast, avoids storage overhead)
- Fetches 3x the limit for semantic/hybrid modes to ensure good candidates after ranking
- Telemetry updated to include `search_mode` metadata

## Test Coverage

### New Test File: `test/jido_code/memory/embeddings_test.exs`

47 comprehensive tests covering:

- `tokenize/1`: Lowercase, punctuation, whitespace, stopwords, empty strings, nil, programming terms
- `stopword?/1`: Common stopwords, content words, nil
- `compute_tfidf/2`: Empty tokens, valid scores, IDF weights, term frequency effects, unknown terms
- `generate/2`: Valid text, empty string, nil, stopwords-only, special characters
- `generate!/2`: Valid text, empty text (returns empty map)
- `cosine_similarity/2`: Identical vectors, orthogonal vectors, partial overlap, empty vectors, nil inputs, symmetry, magnitude independence
- `rank_by_similarity/3`: Ranking by similarity, threshold filtering, limit option, custom content extractor, empty items
- `find_similar/3`: Query string search, empty query, stopwords-only query
- Integration tests: Similar content has higher similarity, shared terms increase similarity, end-to-end memory search simulation
- Utility functions: stopwords/0, default_corpus_stats/0, default_idf_values/0, default_similarity_threshold/0

### Modified: `test/jido_code/memory/actions/recall_test.exs`

10 new tests for search_mode functionality:

- `:text` mode returns exact matches only
- `:semantic` mode finds related content
- `:semantic` mode ranks by relevance
- `:hybrid` mode combines text and semantic
- `:hybrid` mode boosts text matches
- Invalid search mode returns error
- Default search mode is `:hybrid`
- Semantic search gracefully handles stopwords-only query
- Semantic search falls back to text when needed
- Telemetry includes search_mode metadata

## Test Results

```
867 memory tests, 0 failures
- 47 embeddings tests
- 66 recall tests (10 new for search_mode)
```

## Files Changed

| File | Change |
|------|--------|
| `lib/jido_code/memory/embeddings.ex` | New - TF-IDF embeddings module |
| `lib/jido_code/memory/actions/recall.ex` | Modified - Added search_mode parameter and semantic search |
| `test/jido_code/memory/embeddings_test.exs` | New - 47 tests for embeddings |
| `test/jido_code/memory/actions/recall_test.exs` | Modified - Added 10 search_mode tests |

## Design Decisions

1. **No External Dependencies**: Used TF-IDF rather than external embedding models to keep the system lightweight and fast.

2. **On-the-fly Computation**: Embeddings are computed when needed rather than stored, since TF-IDF computation is fast and this avoids storage overhead and synchronization complexity.

3. **Pre-computed IDF Values**: Used a curated set of IDF values for programming/Elixir terms rather than building a corpus dynamically, providing consistent behavior without warm-up period.

4. **Hybrid as Default**: The hybrid mode provides the best of both worlds - exact matches are boosted while still returning semantically related results.

5. **Graceful Fallback**: When semantic search fails (e.g., query produces no tokens), the system falls back to text search rather than returning an error.

## API Examples

```elixir
# Text search (exact substring matching)
Recall.run(%{query: "Phoenix", search_mode: :text}, context)

# Semantic search (similarity-based)
Recall.run(%{query: "web framework patterns", search_mode: :semantic}, context)

# Hybrid search (default - combines both)
Recall.run(%{query: "authentication flow", search_mode: :hybrid}, context)

# Direct embeddings usage
{:ok, embedding} = Embeddings.generate("Phoenix web framework")
similarity = Embeddings.cosine_similarity(embed_a, embed_b)
ranked = Embeddings.find_similar("Phoenix patterns", memories)
```

## Planning Document Updates

Marked all Section 6.2 tasks as complete in `notes/planning/two-tier-memory/phase-06-advanced-features.md`:
- 6.2.1.1 through 6.2.1.6 (Embeddings Module)
- 6.2.2.1 through 6.2.2.4 (Semantic Search Integration)
- 6.2.3 Unit Tests (all 12 test categories)
