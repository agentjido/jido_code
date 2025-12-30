defmodule JidoCode.Memory.Promotion.ImportanceScorer do
  @moduledoc """
  Multi-factor importance scoring algorithm for memory promotion decisions.

  This module evaluates short-term memories to determine which should be promoted
  to long-term storage. The scoring algorithm combines four factors:

  ## Scoring Factors

  | Factor     | Weight | Description                                        |
  |------------|--------|----------------------------------------------------|
  | Recency    | 0.2    | How recently the memory was accessed               |
  | Frequency  | 0.3    | How often the memory has been accessed             |
  | Confidence | 0.25   | The confidence level assigned to the memory        |
  | Salience   | 0.25   | The inherent importance of the memory type         |

  ## Recency Scoring

  Uses a decay function to score recency:

      recency_score = 1 / (1 + minutes_ago / 30)

  - Full score (1.0) at 0 minutes
  - ~0.5 score at 30 minutes ago
  - ~0.33 score at 60 minutes ago

  ## Frequency Scoring

  Normalizes access count against a cap (default 10):

      frequency_score = min(access_count / frequency_cap, 1.0)

  Accesses beyond the cap don't increase the score further.

  ## Salience Scoring

  Different memory types have different inherent importance:

  | Type                | Score |
  |---------------------|-------|
  | Decision types      | 1.0   |
  | Lesson learned      | 1.0   |
  | Risk, Convention    | 1.0   |
  | Discovery           | 0.8   |
  | Fact                | 0.7   |
  | Hypothesis          | 0.5   |
  | Assumption          | 0.4   |
  | Unknown/nil         | 0.3   |

  ## Configuration

  Weights can be customized via application environment:

      config :jido_code, JidoCode.Memory.Promotion.ImportanceScorer,
        recency_weight: 0.2,
        frequency_weight: 0.3,
        confidence_weight: 0.25,
        salience_weight: 0.25,
        frequency_cap: 10

  Or at runtime using `configure/1`:

      ImportanceScorer.configure(recency_weight: 0.3, frequency_weight: 0.2)

  ## Usage

      item = %{
        last_accessed: ~U[2025-01-01 10:00:00Z],
        access_count: 5,
        confidence: 0.9,
        suggested_type: :decision
      }

      ImportanceScorer.score(item)
      # => 0.82 (example value)

      ImportanceScorer.score_with_breakdown(item)
      # => %{total: 0.82, recency: 0.95, frequency: 0.5, confidence: 0.9, salience: 1.0}

  """

  alias JidoCode.Memory.Types

  # =============================================================================
  # Configuration Constants
  # =============================================================================

  @default_recency_weight 0.2
  @default_frequency_weight 0.3
  @default_confidence_weight 0.25
  @default_salience_weight 0.25
  @default_frequency_cap 10

  @high_salience_types [
    :decision,
    :architectural_decision,
    :convention,
    :coding_standard,
    :lesson_learned,
    :risk
  ]

  # =============================================================================
  # Type Definitions
  # =============================================================================

  @typedoc """
  An item that can be scored for promotion importance.

  ## Fields

  - `last_accessed` - When the item was last accessed (DateTime)
  - `access_count` - How many times the item has been accessed
  - `confidence` - Confidence score (0.0 to 1.0)
  - `suggested_type` - The suggested memory type for promotion (may be nil)
  """
  @type scorable_item :: %{
          last_accessed: DateTime.t(),
          access_count: non_neg_integer(),
          confidence: float(),
          suggested_type: Types.memory_type() | nil
        }

  @typedoc """
  Breakdown of individual score components.
  """
  @type score_breakdown :: %{
          total: float(),
          recency: float(),
          frequency: float(),
          confidence: float(),
          salience: float()
        }

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Calculates the importance score for a scorable item.

  Returns a float between 0.0 and 1.0, where higher values indicate
  more important memories that should be prioritized for promotion.

  ## Parameters

  - `item` - A map containing `last_accessed`, `access_count`, `confidence`, and `suggested_type`

  ## Examples

      iex> item = %{
      ...>   last_accessed: DateTime.utc_now(),
      ...>   access_count: 10,
      ...>   confidence: 0.9,
      ...>   suggested_type: :decision
      ...> }
      iex> score = ImportanceScorer.score(item)
      iex> score >= 0.0 and score <= 1.0
      true

  """
  @spec score(scorable_item()) :: float()
  def score(item) do
    config = get_config()

    recency = recency_score(item.last_accessed)
    frequency = frequency_score(item.access_count, config.frequency_cap)
    confidence = Types.clamp_to_unit(item.confidence)
    salience = salience_score(item.suggested_type)

    weighted_score =
      config.recency_weight * recency +
        config.frequency_weight * frequency +
        config.confidence_weight * confidence +
        config.salience_weight * salience

    Types.clamp_to_unit(weighted_score)
  end

  @doc """
  Calculates the importance score with a breakdown of each component.

  Useful for debugging and understanding why certain items scored as they did.

  ## Parameters

  - `item` - A map containing `last_accessed`, `access_count`, `confidence`, and `suggested_type`

  ## Returns

  A map with:
  - `total` - The final weighted score
  - `recency` - The raw recency component (0.0 to 1.0)
  - `frequency` - The raw frequency component (0.0 to 1.0)
  - `confidence` - The raw confidence component (0.0 to 1.0)
  - `salience` - The raw salience component (0.0 to 1.0)

  ## Examples

      iex> item = %{
      ...>   last_accessed: DateTime.utc_now(),
      ...>   access_count: 5,
      ...>   confidence: 0.8,
      ...>   suggested_type: :fact
      ...> }
      iex> breakdown = ImportanceScorer.score_with_breakdown(item)
      iex> Map.keys(breakdown) |> Enum.sort()
      [:confidence, :frequency, :recency, :salience, :total]

  """
  @spec score_with_breakdown(scorable_item()) :: score_breakdown()
  def score_with_breakdown(item) do
    config = get_config()

    recency = recency_score(item.last_accessed)
    frequency = frequency_score(item.access_count, config.frequency_cap)
    confidence = Types.clamp_to_unit(item.confidence)
    salience = salience_score(item.suggested_type)

    total =
      config.recency_weight * recency +
        config.frequency_weight * frequency +
        config.confidence_weight * confidence +
        config.salience_weight * salience

    %{
      total: Types.clamp_to_unit(total),
      recency: recency,
      frequency: frequency,
      confidence: confidence,
      salience: salience
    }
  end

  @doc """
  Configures the scorer weights at runtime.

  Changes are stored in application environment and persist for the lifetime
  of the application. To reset to defaults, call `reset_config/0`.

  ## Options

  - `:recency_weight` - Weight for recency factor (default: 0.2)
  - `:frequency_weight` - Weight for frequency factor (default: 0.3)
  - `:confidence_weight` - Weight for confidence factor (default: 0.25)
  - `:salience_weight` - Weight for salience factor (default: 0.25)
  - `:frequency_cap` - Access count cap for frequency scoring (default: 10)

  ## Examples

      iex> ImportanceScorer.configure(recency_weight: 0.3, frequency_weight: 0.2)
      :ok

  """
  @spec configure(keyword()) :: :ok
  def configure(opts) when is_list(opts) do
    current = get_config()

    new_config = %{
      recency_weight: Keyword.get(opts, :recency_weight, current.recency_weight),
      frequency_weight: Keyword.get(opts, :frequency_weight, current.frequency_weight),
      confidence_weight: Keyword.get(opts, :confidence_weight, current.confidence_weight),
      salience_weight: Keyword.get(opts, :salience_weight, current.salience_weight),
      frequency_cap: Keyword.get(opts, :frequency_cap, current.frequency_cap)
    }

    Application.put_env(:jido_code, __MODULE__, Map.to_list(new_config))
    :ok
  end

  @doc """
  Resets configuration to default values.

  ## Examples

      iex> ImportanceScorer.reset_config()
      :ok

  """
  @spec reset_config() :: :ok
  def reset_config do
    Application.delete_env(:jido_code, __MODULE__)
    :ok
  end

  @doc """
  Returns the current configuration.

  ## Examples

      iex> config = ImportanceScorer.get_config()
      iex> config.recency_weight
      0.2

  """
  @spec get_config() :: %{
          recency_weight: float(),
          frequency_weight: float(),
          confidence_weight: float(),
          salience_weight: float(),
          frequency_cap: pos_integer()
        }
  def get_config do
    env = Application.get_env(:jido_code, __MODULE__, [])

    %{
      recency_weight: Keyword.get(env, :recency_weight, @default_recency_weight),
      frequency_weight: Keyword.get(env, :frequency_weight, @default_frequency_weight),
      confidence_weight: Keyword.get(env, :confidence_weight, @default_confidence_weight),
      salience_weight: Keyword.get(env, :salience_weight, @default_salience_weight),
      frequency_cap: Keyword.get(env, :frequency_cap, @default_frequency_cap)
    }
  end

  @doc """
  Returns the list of memory types considered high salience.

  High salience types receive a salience score of 1.0.
  """
  @spec high_salience_types() :: [atom()]
  def high_salience_types, do: @high_salience_types

  # =============================================================================
  # Scoring Functions (Public for testing)
  # =============================================================================

  @doc """
  Calculates the recency score based on when the item was last accessed.

  Uses decay function: `1 / (1 + minutes_ago / 30)`

  - Returns 1.0 for items accessed just now
  - Returns ~0.5 for items accessed 30 minutes ago
  - Returns ~0.33 for items accessed 60 minutes ago

  ## Examples

      iex> recency_score(DateTime.utc_now())
      1.0

  """
  @spec recency_score(DateTime.t()) :: float()
  def recency_score(last_accessed) do
    minutes_ago = max(DateTime.diff(DateTime.utc_now(), last_accessed, :minute), 0)

    # Decay function: 1 / (1 + minutes_ago / 30)
    1 / (1 + minutes_ago / 30)
  end

  @doc """
  Calculates the frequency score based on access count.

  Normalizes against the frequency cap (default 10).
  Accesses beyond the cap don't increase the score.

  ## Examples

      iex> frequency_score(0, 10)
      0.0

      iex> frequency_score(5, 10)
      0.5

      iex> frequency_score(15, 10)
      1.0

  """
  @spec frequency_score(non_neg_integer(), pos_integer()) :: float()
  def frequency_score(access_count, frequency_cap \\ @default_frequency_cap) do
    min(access_count / frequency_cap, 1.0)
  end

  @doc """
  Calculates the salience score based on memory type.

  Different memory types have different inherent importance:

  - Decision types (decision, architectural_decision): 1.0
  - Conventions and standards: 1.0
  - Lessons learned and risks: 1.0
  - Discoveries: 0.8
  - Facts: 0.7
  - Hypotheses: 0.5
  - Assumptions: 0.4
  - Unknown/nil: 0.3

  ## Examples

      iex> salience_score(:decision)
      1.0

      iex> salience_score(:fact)
      0.7

      iex> salience_score(nil)
      0.3

  """
  @spec salience_score(Types.memory_type() | nil) :: float()
  def salience_score(nil), do: 0.3
  def salience_score(type) when type in @high_salience_types, do: 1.0
  def salience_score(:fact), do: 0.7
  def salience_score(:discovery), do: 0.8
  def salience_score(:hypothesis), do: 0.5
  def salience_score(:assumption), do: 0.4
  def salience_score(:unknown), do: 0.3
  def salience_score(_), do: 0.3
end
