defmodule JidoCode.Memory.Promotion.Triggers do
  @moduledoc """
  Event-based promotion triggers for the memory promotion system.

  This module provides callbacks that trigger memory promotion in response to
  various session lifecycle events. Unlike the periodic timer (which runs at
  fixed intervals), these triggers respond to specific events that indicate
  a good time to evaluate and promote memories.

  ## Trigger Types

  | Trigger | Event | Behavior |
  |---------|-------|----------|
  | `on_session_pause/1` | Session paused | Synchronous promotion before pause completes |
  | `on_session_close/1` | Session closing | Final promotion ensuring all worthy memories saved |
  | `on_memory_limit_reached/2` | Pending memories at capacity | Promotion to clear space |
  | `on_agent_decision/2` | Agent explicitly requests remember | Immediate high-priority promotion |

  ## Usage

  These triggers are called from Session.State callbacks:

      # In Session.State handle_call(:pause, ...)
      def handle_call(:pause, _from, state) do
        Triggers.on_session_pause(state.session_id)
        # ... existing pause logic ...
      end

  ## Telemetry

  All triggers emit telemetry events:

      [:jido_code, :memory, :promotion, :triggered]

  With measurements `%{promoted_count: integer()}` and metadata
  `%{session_id: string, trigger: atom}`.

  """

  alias JidoCode.Memory.Promotion.Engine, as: PromotionEngine

  require Logger

  # =============================================================================
  # Types
  # =============================================================================

  @typedoc """
  Options for trigger functions.

  - `:agent_id` - Agent identifier to associate with promoted memories
  - `:project_id` - Project identifier to associate with promoted memories
  - `:force` - Force promotion even if threshold not met (for agent decisions)
  """
  @type trigger_opts :: [
          agent_id: String.t() | nil,
          project_id: String.t() | nil,
          force: boolean()
        ]

  # =============================================================================
  # Session Lifecycle Triggers
  # =============================================================================

  @doc """
  Triggers promotion when a session is paused.

  This is a synchronous trigger - the pause operation will wait for promotion
  to complete before returning. This ensures that memories accumulated during
  an active session are promoted before the session becomes inactive.

  ## Parameters

  - `session_id` - The session identifier
  - `opts` - Optional parameters (see `t:trigger_opts/0`)

  ## Returns

  - `{:ok, count}` - Number of memories promoted
  - `{:error, reason}` - If promotion fails

  ## Examples

      {:ok, 5} = Triggers.on_session_pause("session-123")

  """
  @spec on_session_pause(String.t(), trigger_opts()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def on_session_pause(session_id, opts \\ []) when is_binary(session_id) do
    Logger.debug("Promotion trigger: session_pause for #{session_id}")

    result = run_promotion(session_id, :session_pause, opts)
    emit_trigger_telemetry(session_id, :session_pause, result)
    result
  end

  @doc """
  Triggers final promotion when a session is closing.

  This trigger performs a more aggressive promotion run to ensure all worthy
  memories have a chance to be promoted before the session ends. It may use
  a lower threshold than normal periodic promotion.

  ## Parameters

  - `session_id` - The session identifier
  - `opts` - Optional parameters (see `t:trigger_opts/0`)

  ## Returns

  - `{:ok, count}` - Number of memories promoted
  - `{:error, reason}` - If promotion fails

  ## Examples

      {:ok, 12} = Triggers.on_session_close("session-123")

  """
  @spec on_session_close(String.t(), trigger_opts()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def on_session_close(session_id, opts \\ []) when is_binary(session_id) do
    Logger.debug("Promotion trigger: session_close for #{session_id}")

    # For session close, we want to be more aggressive about promoting
    # Pass a lower threshold option if not already specified
    opts = Keyword.put_new(opts, :threshold, 0.4)

    result = run_promotion(session_id, :session_close, opts)
    emit_trigger_telemetry(session_id, :session_close, result)
    result
  end

  # =============================================================================
  # Capacity Triggers
  # =============================================================================

  @doc """
  Triggers promotion when pending memories reach capacity.

  This trigger is called when the pending memories store reaches its maximum
  capacity. It runs promotion to clear space for new memories. The trigger
  promotes the highest-importance items first.

  ## Parameters

  - `session_id` - The session identifier
  - `current_count` - Current number of pending memories
  - `opts` - Optional parameters (see `t:trigger_opts/0`)

  ## Returns

  - `{:ok, count}` - Number of memories promoted (space cleared)
  - `{:error, reason}` - If promotion fails

  ## Examples

      {:ok, 10} = Triggers.on_memory_limit_reached("session-123", 100)

  """
  @spec on_memory_limit_reached(String.t(), non_neg_integer(), trigger_opts()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def on_memory_limit_reached(session_id, current_count, opts \\ [])
      when is_binary(session_id) and is_integer(current_count) and current_count >= 0 do
    Logger.debug(
      "Promotion trigger: memory_limit_reached for #{session_id} (count: #{current_count})"
    )

    result = run_promotion(session_id, :memory_limit_reached, opts)
    emit_trigger_telemetry(session_id, :memory_limit_reached, result, %{current_count: current_count})
    result
  end

  # =============================================================================
  # Agent Decision Triggers
  # =============================================================================

  @doc """
  Triggers immediate promotion for an agent decision.

  When an agent explicitly decides to remember something, this trigger
  promotes that specific memory immediately without waiting for the next
  periodic run. Agent decisions bypass the normal importance threshold
  and are always promoted.

  ## Parameters

  - `session_id` - The session identifier
  - `memory_item` - The memory item to promote (from pending_memories)
  - `opts` - Optional parameters (see `t:trigger_opts/0`)

  ## Returns

  - `{:ok, 1}` - Memory successfully promoted
  - `{:error, reason}` - If promotion fails

  ## Examples

      memory_item = %{
        id: "mem-123",
        content: "User prefers explicit type specs",
        memory_type: :convention,
        confidence: 1.0,
        source_type: :user
      }

      {:ok, 1} = Triggers.on_agent_decision("session-123", memory_item)

  """
  @spec on_agent_decision(String.t(), map(), trigger_opts()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def on_agent_decision(session_id, memory_item, opts \\ [])
      when is_binary(session_id) and is_map(memory_item) do
    Logger.debug("Promotion trigger: agent_decision for #{session_id}")

    # Agent decisions are promoted directly, bypassing threshold
    result = promote_single_item(session_id, memory_item, opts)
    emit_trigger_telemetry(session_id, :agent_decision, result)
    result
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  @spec run_promotion(String.t(), atom(), trigger_opts()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp run_promotion(session_id, _trigger_type, opts) do
    # Build options for the promotion engine
    engine_opts =
      opts
      |> Keyword.take([:agent_id, :project_id])

    # Use Session.State.run_promotion_now/1 which handles state access
    case JidoCode.Session.State.run_promotion_now(session_id) do
      {:ok, count} ->
        {:ok, count}

      {:error, :not_found} ->
        Logger.warning("Trigger failed: session #{session_id} not found")
        {:error, :session_not_found}

      {:error, reason} ->
        Logger.warning("Trigger failed for #{session_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec promote_single_item(String.t(), map(), trigger_opts()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp promote_single_item(session_id, memory_item, opts) do
    # Build a candidate from the memory item
    candidate = build_candidate_from_item(memory_item)

    # Promote directly via the engine
    case JidoCode.Memory.LongTerm.StoreManager.get_or_create(session_id) do
      {:ok, _store} ->
        # Use the Memory facade to persist
        memory_input = build_memory_input(candidate, session_id, opts)

        case JidoCode.Memory.persist(memory_input, session_id) do
          {:ok, _id} ->
            # Clear from pending memories if it has an ID
            if memory_item[:id] do
              JidoCode.Session.State.clear_promoted_memories(session_id, [memory_item[:id]])
            end

            {:ok, 1}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_candidate_from_item(item) do
    %{
      id: item[:id],
      content: item[:content],
      suggested_type: item[:memory_type],
      confidence: item[:confidence] || 1.0,
      source_type: item[:source_type] || :agent,
      evidence: item[:evidence] || [],
      rationale: item[:rationale],
      suggested_by: :agent,
      importance_score: 1.0,
      created_at: item[:created_at] || DateTime.utc_now(),
      access_count: item[:access_count] || 0
    }
  end

  defp build_memory_input(candidate, session_id, opts) do
    %{
      id: candidate.id || generate_id(),
      content: format_content(candidate.content),
      memory_type: candidate.suggested_type,
      confidence: candidate.confidence,
      source_type: candidate.source_type,
      session_id: session_id,
      agent_id: Keyword.get(opts, :agent_id),
      project_id: Keyword.get(opts, :project_id),
      evidence: candidate.evidence,
      rationale: candidate.rationale,
      created_at: candidate.created_at || DateTime.utc_now()
    }
  end

  defp format_content(value) when is_binary(value), do: value
  defp format_content(value), do: inspect(value)

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  # =============================================================================
  # Telemetry
  # =============================================================================

  @spec emit_trigger_telemetry(String.t(), atom(), {:ok, non_neg_integer()} | {:error, term()}, map()) :: :ok
  defp emit_trigger_telemetry(session_id, trigger, result, extra_metadata \\ %{}) do
    {measurements, status} =
      case result do
        {:ok, count} -> {%{promoted_count: count}, :success}
        {:error, _} -> {%{promoted_count: 0}, :error}
      end

    metadata =
      Map.merge(
        %{
          session_id: session_id,
          trigger: trigger,
          status: status
        },
        extra_metadata
      )

    :telemetry.execute(
      [:jido_code, :memory, :promotion, :triggered],
      measurements,
      metadata
    )

    :ok
  end
end
