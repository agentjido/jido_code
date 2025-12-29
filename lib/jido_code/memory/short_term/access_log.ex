defmodule JidoCode.Memory.ShortTerm.AccessLog do
  @moduledoc """
  Tracks memory and context access patterns to inform importance scoring.

  The AccessLog maintains a time-ordered list of access entries, recording
  when context keys or memory items are read, written, or queried. This data
  is used by the promotion engine to calculate importance scores based on
  access frequency and recency.

  ## Purpose

  Access patterns are key signals for determining which context items should
  be promoted to long-term memory:

  - **Frequency** - Items accessed more often are likely more important
  - **Recency** - Recently accessed items are likely still relevant
  - **Access Type** - Writes may indicate more significant updates than reads

  ## Memory Limits

  The log enforces a maximum entry limit (default 1000) to prevent unbounded
  memory growth. When the limit is reached, the oldest entries are dropped.

  ## Data Structure

  Entries are stored newest-first for O(1) prepend operations. This makes
  recording new accesses fast, which is important since access logging happens
  frequently during agent sessions.

  ## Example Usage

      iex> log = AccessLog.new()
      iex> log = AccessLog.record(log, :framework, :read)
      iex> log = AccessLog.record(log, :framework, :read)
      iex> AccessLog.get_frequency(log, :framework)
      2

      iex> log = AccessLog.record(log, {:memory, "mem-123"}, :query)
      iex> AccessLog.get_recency(log, {:memory, "mem-123"})
      ~U[2025-12-29 12:00:00Z]  # Example timestamp

  """

  alias JidoCode.Memory.Types

  # =============================================================================
  # Types
  # =============================================================================

  @typedoc """
  An access log entry recording a single access event.

  ## Fields

  - `key` - The context key or memory reference that was accessed
  - `timestamp` - When the access occurred
  - `access_type` - Type of access (:read, :write, or :query)
  """
  @type access_entry :: %{
          key: Types.context_key() | {:memory, String.t()},
          timestamp: DateTime.t(),
          access_type: :read | :write | :query
        }

  @typedoc """
  The AccessLog struct.

  ## Fields

  - `entries` - List of access entries, newest first
  - `max_entries` - Maximum number of entries to retain
  """
  @type t :: %__MODULE__{
          entries: [access_entry()],
          max_entries: pos_integer()
        }

  @default_max_entries 1000

  defstruct entries: [],
            max_entries: @default_max_entries

  # =============================================================================
  # Constructors
  # =============================================================================

  @doc """
  Creates a new empty AccessLog with default max_entries (1000).

  ## Examples

      iex> log = AccessLog.new()
      iex> log.max_entries
      1000
      iex> log.entries
      []

  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Creates a new empty AccessLog with custom max_entries.

  ## Examples

      iex> log = AccessLog.new(500)
      iex> log.max_entries
      500

  """
  @spec new(pos_integer()) :: t()
  def new(max_entries) when is_integer(max_entries) and max_entries > 0 do
    %__MODULE__{max_entries: max_entries}
  end

  # =============================================================================
  # Core API
  # =============================================================================

  @doc """
  Records an access event.

  Creates a new entry with the current timestamp and prepends it to the log.
  If the log exceeds max_entries, the oldest entries are dropped.

  ## Parameters

  - `log` - The AccessLog struct
  - `key` - Either a context_key atom or a `{:memory, id}` tuple
  - `access_type` - One of `:read`, `:write`, or `:query`

  ## Examples

      iex> log = AccessLog.new()
      iex> log = AccessLog.record(log, :framework, :read)
      iex> AccessLog.size(log)
      1

      iex> log = AccessLog.record(log, {:memory, "mem-123"}, :query)
      iex> AccessLog.size(log)
      2

  """
  @spec record(t(), Types.context_key() | {:memory, String.t()}, :read | :write | :query) :: t()
  def record(%__MODULE__{} = log, key, access_type)
      when access_type in [:read, :write, :query] do
    entry = %{
      key: key,
      timestamp: DateTime.utc_now(),
      access_type: access_type
    }

    entries = [entry | log.entries]

    # Enforce max_entries limit
    entries =
      if length(entries) > log.max_entries do
        Enum.take(entries, log.max_entries)
      else
        entries
      end

    %{log | entries: entries}
  end

  @doc """
  Returns the number of times a key has been accessed.

  Counts all entries for the given key, regardless of access type.

  ## Examples

      iex> log = AccessLog.new()
      iex> log = log |> AccessLog.record(:framework, :read) |> AccessLog.record(:framework, :write)
      iex> AccessLog.get_frequency(log, :framework)
      2

      iex> AccessLog.get_frequency(log, :unknown_key)
      0

  """
  @spec get_frequency(t(), Types.context_key() | {:memory, String.t()}) :: non_neg_integer()
  def get_frequency(%__MODULE__{} = log, key) do
    Enum.count(log.entries, fn entry -> entry.key == key end)
  end

  @doc """
  Returns the timestamp of the most recent access for a key.

  Since entries are stored newest-first, this returns the timestamp of the
  first matching entry found.

  ## Examples

      iex> log = AccessLog.new()
      iex> log = AccessLog.record(log, :framework, :read)
      iex> recency = AccessLog.get_recency(log, :framework)
      iex> %DateTime{} = recency
      true

      iex> AccessLog.get_recency(log, :unknown_key)
      nil

  """
  @spec get_recency(t(), Types.context_key() | {:memory, String.t()}) :: DateTime.t() | nil
  def get_recency(%__MODULE__{} = log, key) do
    case Enum.find(log.entries, fn entry -> entry.key == key end) do
      nil -> nil
      entry -> entry.timestamp
    end
  end

  @doc """
  Returns combined frequency and recency statistics for a key.

  ## Examples

      iex> log = AccessLog.new()
      iex> log = log |> AccessLog.record(:framework, :read) |> AccessLog.record(:framework, :read)
      iex> stats = AccessLog.get_stats(log, :framework)
      iex> stats.frequency
      2
      iex> %DateTime{} = stats.recency
      true

      iex> stats = AccessLog.get_stats(log, :unknown_key)
      iex> stats.frequency
      0
      iex> stats.recency
      nil

  """
  @spec get_stats(t(), Types.context_key() | {:memory, String.t()}) :: %{
          frequency: non_neg_integer(),
          recency: DateTime.t() | nil
        }
  def get_stats(%__MODULE__{} = log, key) do
    %{
      frequency: get_frequency(log, key),
      recency: get_recency(log, key)
    }
  end

  @doc """
  Returns the N most recent access entries.

  If N is greater than the number of entries, returns all entries.

  ## Examples

      iex> log = AccessLog.new()
      iex> log = log
      ...>   |> AccessLog.record(:framework, :read)
      ...>   |> AccessLog.record(:primary_language, :write)
      ...>   |> AccessLog.record(:project_root, :read)
      iex> recent = AccessLog.recent_accesses(log, 2)
      iex> length(recent)
      2
      iex> hd(recent).key
      :project_root  # Most recent first

  """
  @spec recent_accesses(t(), pos_integer()) :: [access_entry()]
  def recent_accesses(%__MODULE__{} = log, n) when is_integer(n) and n > 0 do
    Enum.take(log.entries, n)
  end

  @doc """
  Clears all entries from the log.

  Preserves the max_entries setting.

  ## Examples

      iex> log = AccessLog.new(500)
      iex> log = AccessLog.record(log, :framework, :read)
      iex> log = AccessLog.clear(log)
      iex> AccessLog.size(log)
      0
      iex> log.max_entries
      500

  """
  @spec clear(t()) :: t()
  def clear(%__MODULE__{} = log) do
    %{log | entries: []}
  end

  @doc """
  Returns the number of entries in the log.

  ## Examples

      iex> log = AccessLog.new()
      iex> AccessLog.size(log)
      0

      iex> log = AccessLog.record(log, :framework, :read)
      iex> AccessLog.size(log)
      1

  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{} = log) do
    length(log.entries)
  end

  @doc """
  Returns all entries for a specific key.

  Entries are returned in chronological order (newest first).

  ## Examples

      iex> log = AccessLog.new()
      iex> log = log
      ...>   |> AccessLog.record(:framework, :read)
      ...>   |> AccessLog.record(:other, :write)
      ...>   |> AccessLog.record(:framework, :write)
      iex> entries = AccessLog.entries_for(log, :framework)
      iex> length(entries)
      2

  """
  @spec entries_for(t(), Types.context_key() | {:memory, String.t()}) :: [access_entry()]
  def entries_for(%__MODULE__{} = log, key) do
    Enum.filter(log.entries, fn entry -> entry.key == key end)
  end

  @doc """
  Returns unique keys that have been accessed.

  ## Examples

      iex> log = AccessLog.new()
      iex> log = log
      ...>   |> AccessLog.record(:framework, :read)
      ...>   |> AccessLog.record(:framework, :write)
      ...>   |> AccessLog.record(:primary_language, :read)
      iex> keys = AccessLog.unique_keys(log)
      iex> length(keys)
      2

  """
  @spec unique_keys(t()) :: [Types.context_key() | {:memory, String.t()}]
  def unique_keys(%__MODULE__{} = log) do
    log.entries
    |> Enum.map(& &1.key)
    |> Enum.uniq()
  end

  @doc """
  Returns access counts grouped by access type for a key.

  ## Examples

      iex> log = AccessLog.new()
      iex> log = log
      ...>   |> AccessLog.record(:framework, :read)
      ...>   |> AccessLog.record(:framework, :read)
      ...>   |> AccessLog.record(:framework, :write)
      iex> counts = AccessLog.access_type_counts(log, :framework)
      iex> counts
      %{read: 2, write: 1, query: 0}

  """
  @spec access_type_counts(t(), Types.context_key() | {:memory, String.t()}) :: %{
          read: non_neg_integer(),
          write: non_neg_integer(),
          query: non_neg_integer()
        }
  def access_type_counts(%__MODULE__{} = log, key) do
    entries = entries_for(log, key)

    %{
      read: Enum.count(entries, fn e -> e.access_type == :read end),
      write: Enum.count(entries, fn e -> e.access_type == :write end),
      query: Enum.count(entries, fn e -> e.access_type == :query end)
    }
  end
end
