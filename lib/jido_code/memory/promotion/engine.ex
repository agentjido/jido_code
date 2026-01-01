defmodule JidoCode.Memory.Promotion.Engine do
  @moduledoc """
  Core promotion engine that evaluates short-term memories for promotion to long-term storage.

  The Engine is responsible for:
  1. Evaluating context items and pending memories to find promotion candidates
  2. Scoring candidates using the ImportanceScorer
  3. Persisting worthy candidates to long-term storage via the Memory facade
  4. Cleaning up promoted items from short-term storage

  ## Promotion Flow

  ```
  Session.State
       │
       ▼
  ┌─────────────────────────────────────────────┐
  │              Promotion.Engine               │
  │  ┌─────────────────────────────────────┐    │
  │  │          evaluate/1                 │    │
  │  │  • Score context items              │    │
  │  │  • Get ready pending memories       │    │
  │  │  • Filter by threshold              │    │
  │  │  • Sort by importance               │    │
  │  └─────────────────────────────────────┘    │
  │                    │                         │
  │                    ▼                         │
  │  ┌─────────────────────────────────────┐    │
  │  │          promote/3                  │    │
  │  │  • Convert candidates to memory     │    │
  │  │  • Persist to long-term store       │    │
  │  └─────────────────────────────────────┘    │
  └─────────────────────────────────────────────┘
       │
       ▼
  Long-Term Memory (Triple Store)
  ```

  ## Configuration

  - `@promotion_threshold` - Minimum importance score for promotion (default: 0.6)
  - `@max_promotions_per_run` - Maximum candidates promoted per run (default: 20)

  ## Example Usage

      # Evaluate a session state for promotion candidates
      candidates = Engine.evaluate(state)

      # Promote candidates to long-term storage
      {:ok, count} = Engine.promote(candidates, "session-123", agent_id: "agent-1")

      # Convenience function combining evaluation, promotion, and cleanup
      {:ok, count} = Engine.run("session-123", agent_id: "agent-1")

  """

  alias JidoCode.Memory
  alias JidoCode.Memory.Promotion.ImportanceScorer
  alias JidoCode.Memory.Promotion.Utils, as: PromotionUtils
  alias JidoCode.Memory.ShortTerm.{AccessLog, PendingMemories, WorkingContext}
  alias JidoCode.Memory.Types

  # =============================================================================
  # Configuration
  # =============================================================================

  # Use centralized defaults from Types
  @default_promotion_threshold Types.default_promotion_threshold()
  @default_max_promotions_per_run Types.default_max_promotions_per_run()

  # Application environment key for runtime configuration
  @config_key :promotion_engine

  # =============================================================================
  # Types
  # =============================================================================

  @typedoc """
  A candidate for promotion to long-term storage.

  ## Fields

  - `id` - Optional identifier (nil for context-derived candidates)
  - `content` - The memory content (string or term)
  - `suggested_type` - The memory type classification
  - `confidence` - Confidence score (0.0 to 1.0)
  - `source_type` - Origin of the memory
  - `evidence` - Supporting evidence references
  - `rationale` - Optional explanation
  - `suggested_by` - Whether implicit or agent-driven
  - `importance_score` - Calculated importance for ranking
  - `created_at` - When the candidate was created
  - `access_count` - Number of times accessed
  """
  @type promotion_candidate :: %{
          id: String.t() | nil,
          content: term(),
          suggested_type: Types.memory_type(),
          confidence: float(),
          source_type: Types.source_type(),
          evidence: [String.t()],
          rationale: String.t() | nil,
          suggested_by: :implicit | :agent,
          importance_score: float(),
          created_at: DateTime.t(),
          access_count: non_neg_integer()
        }

  @typedoc """
  Session state structure expected by evaluate/1.

  This type defines the minimum required fields from the session state.
  """
  @type session_state :: %{
          working_context: WorkingContext.t(),
          pending_memories: PendingMemories.t(),
          access_log: AccessLog.t()
        }

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Evaluates a session state to find promotion candidates.

  Combines candidates from two sources:
  1. Working context items that have promotable types
  2. Pending memories that meet the threshold or are agent decisions

  Candidates are:
  - Filtered to ensure they have valid suggested_type
  - Filtered by importance threshold (except agent decisions with score 1.0)
  - Sorted by importance_score descending
  - Limited to @max_promotions_per_run

  ## Parameters

  - `state` - Session state containing working_context, pending_memories, and access_log

  ## Returns

  List of promotion candidates, sorted by importance descending.

  ## Examples

      state = %{
        working_context: WorkingContext.new(),
        pending_memories: PendingMemories.new(),
        access_log: AccessLog.new()
      }

      candidates = Engine.evaluate(state)

  """
  @spec evaluate(session_state()) :: [promotion_candidate()]
  def evaluate(state) do
    threshold = promotion_threshold()
    max_promotions = max_promotions_per_run()

    # Score context items and build candidates
    context_candidates = build_context_candidates(state.working_context, state.access_log)

    # Get pending items ready for promotion
    pending_ready = PendingMemories.ready_for_promotion(
      state.pending_memories,
      threshold
    )

    # Convert pending items to promotion candidates
    pending_candidates = Enum.map(pending_ready, &pending_to_candidate/1)

    # Combine, filter, sort, and limit
    (context_candidates ++ pending_candidates)
    |> Enum.filter(&promotable?/1)
    |> Enum.filter(&(&1.importance_score >= threshold))
    |> Enum.sort_by(& &1.importance_score, :desc)
    |> Enum.take(max_promotions)
  end

  @doc """
  Promotes candidates to long-term storage.

  Converts each candidate to a memory input format and persists it via the
  Memory facade. Returns the count of successfully persisted items.

  ## Parameters

  - `candidates` - List of promotion candidates
  - `session_id` - Session identifier for the store
  - `opts` - Optional parameters:
    - `:agent_id` - Agent identifier to associate with memories
    - `:project_id` - Project identifier to associate with memories

  ## Returns

  - `{:ok, count}` - Number of successfully persisted candidates

  ## Examples

      candidates = Engine.evaluate(state)
      {:ok, 5} = Engine.promote(candidates, "session-123", agent_id: "agent-1")

  """
  @spec promote([promotion_candidate()], String.t(), keyword()) ::
          {:ok, non_neg_integer()}
  def promote(candidates, session_id, opts \\ []) when is_binary(session_id) do
    agent_id = Keyword.get(opts, :agent_id)
    project_id = Keyword.get(opts, :project_id)

    results =
      Enum.map(candidates, fn candidate ->
        memory_input = build_memory_input(candidate, session_id, agent_id, project_id)
        Memory.persist(memory_input, session_id)
      end)

    success_count = Enum.count(results, &match?({:ok, _}, &1))
    {:ok, success_count}
  end

  @doc """
  Convenience function that evaluates, promotes, and cleans up in one call.

  This function:
  1. Retrieves session state (when available via Session.State)
  2. Evaluates candidates using evaluate/1
  3. Promotes candidates using promote/3
  4. Clears promoted items from pending memories
  5. Emits telemetry events

  ## Parameters

  - `session_id` - Session identifier
  - `opts` - Optional parameters passed to promote/3
    - `:agent_id` - Agent identifier
    - `:project_id` - Project identifier
    - `:state` - Provide state directly instead of fetching

  ## Returns

  - `{:ok, count}` - Number of promoted items
  - `{:error, reason}` - If session state cannot be retrieved

  ## Examples

      {:ok, 5} = Engine.run("session-123", agent_id: "agent-1")
      {:ok, 0} = Engine.run("session-123")  # No candidates

  """
  @spec run(String.t(), keyword()) ::
          {:ok, non_neg_integer(), [String.t()]} | {:error, term()}
  def run(session_id, opts \\ []) when is_binary(session_id) do
    # For now, require state to be passed in opts
    # Future: integrate with Session.State.get_state/1
    case Keyword.fetch(opts, :state) do
      {:ok, state} ->
        run_with_state(state, session_id, opts)

      :error ->
        {:error, :state_required}
    end
  end

  @doc """
  Runs promotion with a provided state.

  This is the implementation that performs the actual promotion logic.
  It's separated to allow direct invocation with a state map.

  ## Parameters

  - `state` - Session state map
  - `session_id` - Session identifier
  - `opts` - Options passed to promote/3

  ## Returns

  - `{:ok, count, promoted_ids}` - Number of promoted items and list of promoted IDs

  """
  @spec run_with_state(session_state(), String.t(), keyword()) ::
          {:ok, non_neg_integer(), [String.t()]}
  def run_with_state(state, session_id, opts) do
    candidates = evaluate(state)

    if candidates != [] do
      {:ok, count} = promote(candidates, session_id, opts)

      # Collect promoted IDs for cleanup
      promoted_ids =
        candidates
        |> Enum.map(& &1.id)
        |> Enum.reject(&is_nil/1)

      # Emit telemetry
      emit_promotion_telemetry(session_id, count, length(candidates))

      {:ok, count, promoted_ids}
    else
      {:ok, 0, []}
    end
  end

  @doc """
  Returns the current promotion threshold.

  The threshold can be configured at runtime using `configure/1`.
  Defaults to #{Types.default_promotion_threshold()}.

  ## Examples

      iex> Engine.promotion_threshold()
      0.6

  """
  @spec promotion_threshold() :: float()
  def promotion_threshold do
    get_config(:promotion_threshold, @default_promotion_threshold)
  end

  @doc """
  Returns the maximum promotions per run.

  The limit can be configured at runtime using `configure/1`.
  Defaults to #{Types.default_max_promotions_per_run()}.

  ## Examples

      iex> Engine.max_promotions_per_run()
      20

  """
  @spec max_promotions_per_run() :: pos_integer()
  def max_promotions_per_run do
    get_config(:max_promotions_per_run, @default_max_promotions_per_run)
  end

  @doc """
  Configures engine parameters at runtime.

  ## Options

  - `:promotion_threshold` - Minimum importance score for promotion (default: 0.6)
  - `:max_promotions_per_run` - Maximum candidates per run (default: 20)

  ## Examples

      iex> Engine.configure(promotion_threshold: 0.7, max_promotions_per_run: 30)
      :ok

  """
  @spec configure(keyword()) :: :ok | {:error, String.t()}
  def configure(opts) when is_list(opts) do
    config = get_all_config()

    new_config =
      config
      |> Keyword.merge(Keyword.take(opts, [:promotion_threshold, :max_promotions_per_run]))

    case validate_config(new_config) do
      :ok ->
        Application.put_env(:jido_code, @config_key, new_config)
        :ok

      error ->
        error
    end
  end

  @doc """
  Resets engine configuration to defaults.

  ## Examples

      iex> Engine.reset_config()
      :ok

  """
  @spec reset_config() :: :ok
  def reset_config do
    Application.delete_env(:jido_code, @config_key)
    :ok
  end

  @doc """
  Returns current engine configuration.

  ## Examples

      iex> Engine.get_config()
      %{promotion_threshold: 0.6, max_promotions_per_run: 20}

  """
  @spec get_config() :: map()
  def get_config do
    %{
      promotion_threshold: promotion_threshold(),
      max_promotions_per_run: max_promotions_per_run()
    }
  end

  # Private helpers for configuration
  defp get_config(key, default) do
    :jido_code
    |> Application.get_env(@config_key, [])
    |> Keyword.get(key, default)
  end

  defp get_all_config do
    Application.get_env(:jido_code, @config_key, [])
  end

  defp validate_config(config) do
    threshold = Keyword.get(config, :promotion_threshold, @default_promotion_threshold)
    max_promo = Keyword.get(config, :max_promotions_per_run, @default_max_promotions_per_run)

    cond do
      not is_number(threshold) or threshold < 0.0 or threshold > 1.0 ->
        {:error, "promotion_threshold must be a number between 0.0 and 1.0"}

      not is_integer(max_promo) or max_promo < 1 ->
        {:error, "max_promotions_per_run must be a positive integer"}

      true ->
        :ok
    end
  end

  # =============================================================================
  # Private Functions - Candidate Building
  # =============================================================================

  @doc false
  @spec build_context_candidates(WorkingContext.t(), AccessLog.t()) :: [promotion_candidate()]
  def build_context_candidates(working_context, access_log) do
    working_context
    |> WorkingContext.to_list()
    |> Enum.map(fn item ->
      access_stats = AccessLog.get_stats(access_log, item.key)
      build_candidate_from_context(item, access_stats)
    end)
    |> Enum.filter(&(&1.suggested_type != nil))
  end

  defp build_candidate_from_context(item, access_stats) do
    # Build scorable item for ImportanceScorer
    last_accessed = access_stats.recency || item.last_accessed
    access_count = max(access_stats.frequency, item.access_count)

    scorable = %{
      last_accessed: last_accessed,
      access_count: access_count,
      confidence: item.confidence,
      suggested_type: item.suggested_type
    }

    importance_score = ImportanceScorer.score(scorable)

    %{
      id: nil,
      content: item.value,
      suggested_type: item.suggested_type,
      confidence: item.confidence,
      source_type: source_from_context(item.source),
      evidence: [],
      rationale: nil,
      suggested_by: :implicit,
      importance_score: importance_score,
      created_at: item.first_seen,
      access_count: access_count
    }
  end

  defp pending_to_candidate(pending_item) do
    %{
      id: pending_item.id,
      content: pending_item.content,
      suggested_type: pending_item.memory_type,
      confidence: pending_item.confidence,
      source_type: pending_item.source_type,
      evidence: pending_item.evidence,
      rationale: pending_item.rationale,
      suggested_by: pending_item.suggested_by,
      importance_score: pending_item.importance_score,
      created_at: pending_item.created_at,
      access_count: pending_item.access_count
    }
  end

  # Convert context source to source_type
  defp source_from_context(:tool), do: :tool
  defp source_from_context(:explicit), do: :user
  defp source_from_context(:inferred), do: :agent
  defp source_from_context(_), do: :agent

  # =============================================================================
  # Private Functions - Memory Input Building
  # =============================================================================

  defp build_memory_input(candidate, session_id, agent_id, project_id) do
    PromotionUtils.build_memory_input(candidate, session_id,
      agent_id: agent_id,
      project_id: project_id
    )
  end

  @doc false
  @spec format_content(term()) :: String.t()
  defdelegate format_content(value), to: PromotionUtils

  @doc false
  @spec generate_id() :: String.t()
  defdelegate generate_id(), to: PromotionUtils

  # =============================================================================
  # Private Functions - Validation
  # =============================================================================

  defp promotable?(%{suggested_type: nil}), do: false
  defp promotable?(%{content: nil}), do: false
  defp promotable?(%{content: ""}), do: false
  defp promotable?(_), do: true

  # =============================================================================
  # Private Functions - Telemetry
  # =============================================================================

  defp emit_promotion_telemetry(session_id, success_count, total_candidates) do
    :telemetry.execute(
      [:jido_code, :memory, :promotion, :completed],
      %{
        success_count: success_count,
        total_candidates: total_candidates
      },
      %{
        session_id: session_id
      }
    )
  end
end
