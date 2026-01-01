defmodule JidoCode.Memory.ShortTerm.AccessLogTest do
  use ExUnit.Case, async: true

  alias JidoCode.Memory.ShortTerm.AccessLog

  describe "new/0" do
    test "creates empty log with default max_entries (1000)" do
      log = AccessLog.new()

      assert log.max_entries == 1000
      assert log.entries == []
    end
  end

  describe "new/1" do
    test "accepts custom max_entries value" do
      log = AccessLog.new(500)

      assert log.max_entries == 500
      assert log.entries == []
    end

    test "creates log with various max_entries values" do
      assert AccessLog.new(100).max_entries == 100
      assert AccessLog.new(5000).max_entries == 5000
    end
  end

  describe "record/3" do
    test "adds entry to front of list (newest first)" do
      log = AccessLog.new()

      log =
        log
        |> AccessLog.record(:framework, :read)
        |> AccessLog.record(:primary_language, :write)

      assert length(log.entries) == 2
      # Most recent should be first
      assert hd(log.entries).key == :primary_language
    end

    test "sets timestamp to current time" do
      before = DateTime.utc_now()
      log = AccessLog.new()
      log = AccessLog.record(log, :framework, :read)
      after_record = DateTime.utc_now()

      [entry] = log.entries
      assert DateTime.compare(entry.timestamp, before) in [:gt, :eq]
      assert DateTime.compare(entry.timestamp, after_record) in [:lt, :eq]
    end

    test "enforces max_entries limit by dropping oldest" do
      log = AccessLog.new(3)

      log =
        log
        |> AccessLog.record(:first, :read)
        |> AccessLog.record(:second, :read)
        |> AccessLog.record(:third, :read)

      assert AccessLog.size(log) == 3

      # Add a 4th entry - should drop the oldest (first)
      log = AccessLog.record(log, :fourth, :read)

      assert AccessLog.size(log) == 3
      keys = Enum.map(log.entries, & &1.key)
      assert :fourth in keys
      assert :third in keys
      assert :second in keys
      refute :first in keys
    end

    test "accepts context_key as key" do
      log = AccessLog.new()

      log =
        log
        |> AccessLog.record(:framework, :read)
        |> AccessLog.record(:primary_language, :write)
        |> AccessLog.record(:project_root, :read)
        |> AccessLog.record(:active_file, :query)

      assert AccessLog.size(log) == 4
    end

    test "accepts {:memory, id} tuple as key" do
      log = AccessLog.new()

      log =
        log
        |> AccessLog.record({:memory, "mem-123"}, :read)
        |> AccessLog.record({:memory, "mem-456"}, :query)

      assert AccessLog.size(log) == 2
      assert AccessLog.get_frequency(log, {:memory, "mem-123"}) == 1
    end

    test "accepts all access_type values (:read, :write, :query)" do
      log = AccessLog.new()

      log =
        log
        |> AccessLog.record(:framework, :read)
        |> AccessLog.record(:framework, :write)
        |> AccessLog.record(:framework, :query)

      types = Enum.map(log.entries, & &1.access_type)
      assert :read in types
      assert :write in types
      assert :query in types
    end

    test "preserves entry structure" do
      log = AccessLog.new()
      log = AccessLog.record(log, :framework, :read)

      [entry] = log.entries
      assert entry.key == :framework
      assert entry.access_type == :read
      assert %DateTime{} = entry.timestamp
    end
  end

  describe "get_frequency/2" do
    test "counts all accesses for key" do
      log = AccessLog.new()

      log =
        log
        |> AccessLog.record(:framework, :read)
        |> AccessLog.record(:other, :write)
        |> AccessLog.record(:framework, :write)
        |> AccessLog.record(:framework, :query)

      assert AccessLog.get_frequency(log, :framework) == 3
      assert AccessLog.get_frequency(log, :other) == 1
    end

    test "returns 0 for unknown keys" do
      log = AccessLog.new()
      log = AccessLog.record(log, :framework, :read)

      assert AccessLog.get_frequency(log, :unknown) == 0
    end

    test "works with memory tuple keys" do
      log = AccessLog.new()

      log =
        log
        |> AccessLog.record({:memory, "mem-1"}, :read)
        |> AccessLog.record({:memory, "mem-1"}, :query)
        |> AccessLog.record({:memory, "mem-2"}, :read)

      assert AccessLog.get_frequency(log, {:memory, "mem-1"}) == 2
      assert AccessLog.get_frequency(log, {:memory, "mem-2"}) == 1
    end
  end

  describe "get_recency/2" do
    test "returns most recent timestamp for key" do
      log = AccessLog.new()

      log = AccessLog.record(log, :framework, :read)
      first_time = hd(log.entries).timestamp

      Process.sleep(10)

      log = AccessLog.record(log, :framework, :write)
      second_time = hd(log.entries).timestamp

      recency = AccessLog.get_recency(log, :framework)
      assert recency == second_time
      assert DateTime.compare(recency, first_time) == :gt
    end

    test "returns nil for unknown keys" do
      log = AccessLog.new()
      log = AccessLog.record(log, :framework, :read)

      assert AccessLog.get_recency(log, :unknown) == nil
    end

    test "works with memory tuple keys" do
      log = AccessLog.new()
      log = AccessLog.record(log, {:memory, "mem-123"}, :query)

      recency = AccessLog.get_recency(log, {:memory, "mem-123"})
      assert %DateTime{} = recency
    end
  end

  describe "get_stats/2" do
    test "returns both frequency and recency" do
      log = AccessLog.new()

      log =
        log
        |> AccessLog.record(:framework, :read)
        |> AccessLog.record(:framework, :write)

      stats = AccessLog.get_stats(log, :framework)

      assert stats.frequency == 2
      assert %DateTime{} = stats.recency
    end

    test "returns 0 frequency and nil recency for unknown keys" do
      log = AccessLog.new()

      stats = AccessLog.get_stats(log, :unknown)

      assert stats.frequency == 0
      assert stats.recency == nil
    end
  end

  describe "recent_accesses/2" do
    test "returns last N entries" do
      log = AccessLog.new()

      log =
        log
        |> AccessLog.record(:first, :read)
        |> AccessLog.record(:second, :read)
        |> AccessLog.record(:third, :read)

      recent = AccessLog.recent_accesses(log, 2)

      assert length(recent) == 2
      # Most recent first
      assert hd(recent).key == :third
      assert List.last(recent).key == :second
    end

    test "returns all entries if N > size" do
      log = AccessLog.new()

      log =
        log
        |> AccessLog.record(:first, :read)
        |> AccessLog.record(:second, :read)

      recent = AccessLog.recent_accesses(log, 10)

      assert length(recent) == 2
    end

    test "returns empty list for empty log" do
      log = AccessLog.new()

      assert AccessLog.recent_accesses(log, 5) == []
    end
  end

  describe "clear/1" do
    test "resets entries to empty list" do
      log = AccessLog.new()

      log =
        log
        |> AccessLog.record(:framework, :read)
        |> AccessLog.record(:primary_language, :write)

      assert AccessLog.size(log) == 2

      log = AccessLog.clear(log)

      assert AccessLog.size(log) == 0
      assert log.entries == []
    end

    test "preserves max_entries setting" do
      log = AccessLog.new(500)
      log = AccessLog.record(log, :framework, :read)

      log = AccessLog.clear(log)

      assert log.max_entries == 500
    end
  end

  describe "size/1" do
    test "returns correct entry count" do
      log = AccessLog.new()

      assert AccessLog.size(log) == 0

      log = AccessLog.record(log, :framework, :read)
      assert AccessLog.size(log) == 1

      log = AccessLog.record(log, :primary_language, :write)
      assert AccessLog.size(log) == 2
    end
  end

  describe "entries_for/2" do
    test "returns all entries for a specific key" do
      log = AccessLog.new()

      log =
        log
        |> AccessLog.record(:framework, :read)
        |> AccessLog.record(:other, :write)
        |> AccessLog.record(:framework, :write)

      entries = AccessLog.entries_for(log, :framework)

      assert length(entries) == 2
      assert Enum.all?(entries, fn e -> e.key == :framework end)
    end

    test "returns empty list for unknown keys" do
      log = AccessLog.new()
      log = AccessLog.record(log, :framework, :read)

      assert AccessLog.entries_for(log, :unknown) == []
    end

    test "returns entries in newest-first order" do
      log = AccessLog.new()

      log =
        log
        |> AccessLog.record(:framework, :read)
        |> AccessLog.record(:framework, :write)

      entries = AccessLog.entries_for(log, :framework)

      # Most recent (write) should be first
      assert hd(entries).access_type == :write
    end
  end

  describe "unique_keys/1" do
    test "returns unique keys that have been accessed" do
      log = AccessLog.new()

      log =
        log
        |> AccessLog.record(:framework, :read)
        |> AccessLog.record(:framework, :write)
        |> AccessLog.record(:primary_language, :read)
        |> AccessLog.record({:memory, "mem-1"}, :query)

      keys = AccessLog.unique_keys(log)

      assert length(keys) == 3
      assert :framework in keys
      assert :primary_language in keys
      assert {:memory, "mem-1"} in keys
    end

    test "returns empty list for empty log" do
      log = AccessLog.new()

      assert AccessLog.unique_keys(log) == []
    end
  end

  describe "access_type_counts/2" do
    test "returns counts grouped by access type" do
      log = AccessLog.new()

      log =
        log
        |> AccessLog.record(:framework, :read)
        |> AccessLog.record(:framework, :read)
        |> AccessLog.record(:framework, :write)
        |> AccessLog.record(:framework, :query)
        |> AccessLog.record(:framework, :query)
        |> AccessLog.record(:framework, :query)

      counts = AccessLog.access_type_counts(log, :framework)

      assert counts == %{read: 2, write: 1, query: 3}
    end

    test "returns zero counts for unknown keys" do
      log = AccessLog.new()

      counts = AccessLog.access_type_counts(log, :unknown)

      assert counts == %{read: 0, write: 0, query: 0}
    end
  end

  describe "max_entries enforcement" do
    test "drops entries when limit exceeded" do
      log = AccessLog.new(5)

      # Add 7 entries
      log =
        Enum.reduce(1..7, log, fn i, acc ->
          AccessLog.record(acc, :"key_#{i}", :read)
        end)

      assert AccessLog.size(log) == 5

      # Should have kept the 5 most recent (key_3 through key_7)
      keys = Enum.map(log.entries, & &1.key)
      refute :key_1 in keys
      refute :key_2 in keys
      assert :key_7 in keys
    end
  end
end
