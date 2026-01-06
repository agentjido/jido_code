defmodule JidoCode.Tools.Security.PermissionsTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Security.Permissions

  # =============================================================================
  # Tests: get_tool_tier/1
  # =============================================================================

  describe "get_tool_tier/1" do
    test "returns :read_only for read-only tools" do
      assert Permissions.get_tool_tier("read_file") == :read_only
      assert Permissions.get_tool_tier("list_directory") == :read_only
      assert Permissions.get_tool_tier("file_info") == :read_only
      assert Permissions.get_tool_tier("grep") == :read_only
      assert Permissions.get_tool_tier("find_files") == :read_only
      assert Permissions.get_tool_tier("fetch_elixir_docs") == :read_only
      assert Permissions.get_tool_tier("web_fetch") == :read_only
      assert Permissions.get_tool_tier("web_search") == :read_only
    end

    test "returns :write for write tools" do
      assert Permissions.get_tool_tier("write_file") == :write
      assert Permissions.get_tool_tier("edit_file") == :write
      assert Permissions.get_tool_tier("create_directory") == :write
      assert Permissions.get_tool_tier("delete_file") == :write
      assert Permissions.get_tool_tier("livebook_edit") == :write
    end

    test "returns :execute for execute tools" do
      assert Permissions.get_tool_tier("run_command") == :execute
      assert Permissions.get_tool_tier("mix_task") == :execute
      assert Permissions.get_tool_tier("run_exunit") == :execute
      assert Permissions.get_tool_tier("git_command") == :execute
      assert Permissions.get_tool_tier("lsp_request") == :execute
    end

    test "returns :privileged for privileged tools" do
      assert Permissions.get_tool_tier("get_process_state") == :privileged
      assert Permissions.get_tool_tier("inspect_supervisor") == :privileged
      assert Permissions.get_tool_tier("ets_inspect") == :privileged
      assert Permissions.get_tool_tier("spawn_task") == :privileged
    end

    test "returns :read_only for unknown tools" do
      assert Permissions.get_tool_tier("unknown_tool") == :read_only
      assert Permissions.get_tool_tier("custom_tool") == :read_only
    end
  end

  # =============================================================================
  # Tests: default_rate_limit/1
  # =============================================================================

  describe "default_rate_limit/1" do
    test "returns correct limits for each tier" do
      assert Permissions.default_rate_limit(:read_only) == {100, 60_000}
      assert Permissions.default_rate_limit(:write) == {30, 60_000}
      assert Permissions.default_rate_limit(:execute) == {10, 60_000}
      assert Permissions.default_rate_limit(:privileged) == {5, 60_000}
    end

    test "returns default for unknown tier" do
      assert Permissions.default_rate_limit(:unknown) == {100, 60_000}
    end
  end

  # =============================================================================
  # Tests: check_permission/4
  # =============================================================================

  describe "check_permission/4" do
    test "allows read_only tool with read_only tier" do
      assert :ok = Permissions.check_permission("read_file", :read_only, [])
    end

    test "allows read_only tool with higher tier" do
      assert :ok = Permissions.check_permission("read_file", :write, [])
      assert :ok = Permissions.check_permission("read_file", :execute, [])
      assert :ok = Permissions.check_permission("read_file", :privileged, [])
    end

    test "denies write tool with read_only tier" do
      assert {:error, {:permission_denied, details}} =
               Permissions.check_permission("write_file", :read_only, [], emit_telemetry: false)

      assert details.tool == "write_file"
      assert details.required_tier == :write
      assert details.granted_tier == :read_only
    end

    test "allows write tool with write tier" do
      assert :ok = Permissions.check_permission("write_file", :write, [])
    end

    test "allows write tool with higher tier" do
      assert :ok = Permissions.check_permission("write_file", :execute, [])
      assert :ok = Permissions.check_permission("write_file", :privileged, [])
    end

    test "denies execute tool with write tier" do
      assert {:error, {:permission_denied, _}} =
               Permissions.check_permission("run_command", :write, [], emit_telemetry: false)
    end

    test "allows execute tool with execute tier" do
      assert :ok = Permissions.check_permission("run_command", :execute, [])
    end

    test "denies privileged tool with execute tier" do
      assert {:error, {:permission_denied, _}} =
               Permissions.check_permission("get_process_state", :execute, [],
                 emit_telemetry: false
               )
    end

    test "allows privileged tool with privileged tier" do
      assert :ok = Permissions.check_permission("get_process_state", :privileged, [])
    end

    test "explicit consent overrides tier requirements" do
      # Should be denied without consent
      assert {:error, _} =
               Permissions.check_permission("run_command", :read_only, [], emit_telemetry: false)

      # Should be allowed with consent
      assert :ok = Permissions.check_permission("run_command", :read_only, ["run_command"])
    end

    test "consent works for multiple tools" do
      consented = ["run_command", "mix_task", "get_process_state"]

      assert :ok = Permissions.check_permission("run_command", :read_only, consented)
      assert :ok = Permissions.check_permission("mix_task", :read_only, consented)
      assert :ok = Permissions.check_permission("get_process_state", :read_only, consented)

      # Non-consented tool should still be denied
      assert {:error, _} =
               Permissions.check_permission("run_exunit", :read_only, consented,
                 emit_telemetry: false
               )
    end
  end

  # =============================================================================
  # Tests: grant_tier/2
  # =============================================================================

  describe "grant_tier/2" do
    test "allows upgrading to higher tier" do
      assert {:ok, :write} = Permissions.grant_tier(:read_only, :write)
      assert {:ok, :execute} = Permissions.grant_tier(:read_only, :execute)
      assert {:ok, :privileged} = Permissions.grant_tier(:read_only, :privileged)
      assert {:ok, :execute} = Permissions.grant_tier(:write, :execute)
      assert {:ok, :privileged} = Permissions.grant_tier(:write, :privileged)
      assert {:ok, :privileged} = Permissions.grant_tier(:execute, :privileged)
    end

    test "allows staying at same tier" do
      assert {:ok, :read_only} = Permissions.grant_tier(:read_only, :read_only)
      assert {:ok, :write} = Permissions.grant_tier(:write, :write)
      assert {:ok, :execute} = Permissions.grant_tier(:execute, :execute)
      assert {:ok, :privileged} = Permissions.grant_tier(:privileged, :privileged)
    end

    test "rejects downgrading to lower tier" do
      assert {:error, :tier_downgrade} = Permissions.grant_tier(:write, :read_only)
      assert {:error, :tier_downgrade} = Permissions.grant_tier(:execute, :write)
      assert {:error, :tier_downgrade} = Permissions.grant_tier(:privileged, :execute)
      assert {:error, :tier_downgrade} = Permissions.grant_tier(:privileged, :read_only)
    end

    test "rejects invalid tier" do
      assert {:error, :invalid_tier} = Permissions.grant_tier(:read_only, :invalid)
      assert {:error, :invalid_tier} = Permissions.grant_tier(:read_only, :admin)
      assert {:error, :invalid_tier} = Permissions.grant_tier(:read_only, nil)
    end
  end

  # =============================================================================
  # Tests: record_consent/2
  # =============================================================================

  describe "record_consent/2" do
    test "adds tool to empty consent list" do
      assert {:ok, ["run_command"]} = Permissions.record_consent([], "run_command")
    end

    test "adds tool to existing consent list" do
      assert {:ok, consented} = Permissions.record_consent(["mix_task"], "run_command")
      assert "run_command" in consented
      assert "mix_task" in consented
    end

    test "rejects duplicate consent" do
      assert {:error, :already_consented} =
               Permissions.record_consent(["run_command"], "run_command")
    end

    test "handles multiple tools" do
      {:ok, consented1} = Permissions.record_consent([], "tool1")
      {:ok, consented2} = Permissions.record_consent(consented1, "tool2")
      {:ok, consented3} = Permissions.record_consent(consented2, "tool3")

      assert length(consented3) == 3
      assert "tool1" in consented3
      assert "tool2" in consented3
      assert "tool3" in consented3
    end
  end

  # =============================================================================
  # Tests: revoke_consent/2
  # =============================================================================

  describe "revoke_consent/2" do
    test "removes tool from consent list" do
      assert {:ok, []} = Permissions.revoke_consent(["run_command"], "run_command")
    end

    test "removes only specified tool" do
      consented = ["tool1", "tool2", "tool3"]
      {:ok, updated} = Permissions.revoke_consent(consented, "tool2")

      assert length(updated) == 2
      assert "tool1" in updated
      assert "tool3" in updated
      refute "tool2" in updated
    end

    test "rejects revoking non-consented tool" do
      assert {:error, :not_consented} = Permissions.revoke_consent([], "run_command")
      assert {:error, :not_consented} = Permissions.revoke_consent(["other_tool"], "run_command")
    end
  end

  # =============================================================================
  # Tests: tier_level/1
  # =============================================================================

  describe "tier_level/1" do
    test "returns correct level for each tier" do
      assert Permissions.tier_level(:read_only) == 0
      assert Permissions.tier_level(:write) == 1
      assert Permissions.tier_level(:execute) == 2
      assert Permissions.tier_level(:privileged) == 3
    end

    test "returns 0 for unknown tier" do
      assert Permissions.tier_level(:unknown) == 0
      assert Permissions.tier_level(:invalid) == 0
    end

    test "levels are in ascending order" do
      levels = [:read_only, :write, :execute, :privileged] |> Enum.map(&Permissions.tier_level/1)
      assert levels == Enum.sort(levels)
    end
  end

  # =============================================================================
  # Tests: valid_tiers/0 and valid_tier?/1
  # =============================================================================

  describe "valid_tiers/0" do
    test "returns all valid tiers in order" do
      assert Permissions.valid_tiers() == [:read_only, :write, :execute, :privileged]
    end
  end

  describe "valid_tier?/1" do
    test "returns true for valid tiers" do
      assert Permissions.valid_tier?(:read_only)
      assert Permissions.valid_tier?(:write)
      assert Permissions.valid_tier?(:execute)
      assert Permissions.valid_tier?(:privileged)
    end

    test "returns false for invalid tiers" do
      refute Permissions.valid_tier?(:invalid)
      refute Permissions.valid_tier?(:admin)
      refute Permissions.valid_tier?(nil)
      refute Permissions.valid_tier?("read_only")
    end
  end

  # =============================================================================
  # Tests: tools_for_tier/1
  # =============================================================================

  describe "tools_for_tier/1" do
    test "returns read_only tools" do
      tools = Permissions.tools_for_tier(:read_only)
      assert "read_file" in tools
      assert "list_directory" in tools
      assert "grep" in tools
      refute "write_file" in tools
    end

    test "returns write tools" do
      tools = Permissions.tools_for_tier(:write)
      assert "write_file" in tools
      assert "edit_file" in tools
      refute "read_file" in tools
    end

    test "returns execute tools" do
      tools = Permissions.tools_for_tier(:execute)
      assert "run_command" in tools
      assert "mix_task" in tools
      refute "write_file" in tools
    end

    test "returns privileged tools" do
      tools = Permissions.tools_for_tier(:privileged)
      assert "get_process_state" in tools
      assert "inspect_supervisor" in tools
      refute "run_command" in tools
    end

    test "returns empty list for unknown tier" do
      assert Permissions.tools_for_tier(:unknown) == []
    end

    test "returns sorted list" do
      for tier <- [:read_only, :write, :execute, :privileged] do
        tools = Permissions.tools_for_tier(tier)
        assert tools == Enum.sort(tools)
      end
    end
  end

  # =============================================================================
  # Tests: all_tool_tiers/0
  # =============================================================================

  describe "all_tool_tiers/0" do
    test "returns map of all tools to tiers" do
      tiers = Permissions.all_tool_tiers()

      assert is_map(tiers)
      assert Map.has_key?(tiers, "read_file")
      assert Map.has_key?(tiers, "write_file")
      assert Map.has_key?(tiers, "run_command")
      assert Map.has_key?(tiers, "get_process_state")
    end

    test "all values are valid tiers" do
      tiers = Permissions.all_tool_tiers()
      valid = Permissions.valid_tiers()

      Enum.each(tiers, fn {_tool, tier} ->
        assert tier in valid
      end)
    end
  end

  # =============================================================================
  # Tests: all_rate_limits/0
  # =============================================================================

  describe "all_rate_limits/0" do
    test "returns map of all tiers to rate limits" do
      limits = Permissions.all_rate_limits()

      assert is_map(limits)
      assert Map.has_key?(limits, :read_only)
      assert Map.has_key?(limits, :write)
      assert Map.has_key?(limits, :execute)
      assert Map.has_key?(limits, :privileged)
    end

    test "all values are valid rate limit tuples" do
      limits = Permissions.all_rate_limits()

      Enum.each(limits, fn {_tier, {count, window}} ->
        assert is_integer(count)
        assert count > 0
        assert is_integer(window)
        assert window > 0
      end)
    end

    test "higher tiers have lower limits" do
      limits = Permissions.all_rate_limits()

      {read_only_count, _} = limits[:read_only]
      {write_count, _} = limits[:write]
      {execute_count, _} = limits[:execute]
      {privileged_count, _} = limits[:privileged]

      assert read_only_count > write_count
      assert write_count > execute_count
      assert execute_count > privileged_count
    end
  end

  # =============================================================================
  # Tests: Telemetry emission
  # =============================================================================

  describe "telemetry emission" do
    test "emits telemetry on permission denied" do
      ref = make_ref()
      test_pid = self()
      handler_id = "test-permissions-telemetry-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :security, :permission_denied],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      try do
        Permissions.check_permission("run_command", :read_only, [])

        assert_receive {:telemetry, ^ref, [:jido_code, :security, :permission_denied], _measurements,
                        metadata}

        assert metadata.tool == "run_command"
        assert metadata.required_tier == :execute
        assert metadata.granted_tier == :read_only
      after
        :telemetry.detach(handler_id)
      end
    end

    test "does not emit telemetry when permission granted" do
      ref = make_ref()
      test_pid = self()
      handler_id = "test-permissions-no-telemetry-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :security, :permission_denied],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      try do
        Permissions.check_permission("read_file", :read_only, [])

        refute_receive {:telemetry, ^ref, _, _, _}, 100
      after
        :telemetry.detach(handler_id)
      end
    end

    test "does not emit telemetry when emit_telemetry: false" do
      ref = make_ref()
      test_pid = self()
      handler_id = "test-permissions-disabled-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :security, :permission_denied],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      try do
        Permissions.check_permission("run_command", :read_only, [], emit_telemetry: false)

        refute_receive {:telemetry, ^ref, _, _, _}, 100
      after
        :telemetry.detach(handler_id)
      end
    end
  end

  # =============================================================================
  # Tests: Edge cases
  # =============================================================================

  describe "edge cases" do
    test "handles empty consented_tools list" do
      assert {:error, _} =
               Permissions.check_permission("run_command", :read_only, [], emit_telemetry: false)
    end

    test "consent is case-sensitive" do
      # Tool name matching is exact
      assert :ok = Permissions.check_permission("run_command", :read_only, ["run_command"])

      assert {:error, _} =
               Permissions.check_permission("run_command", :read_only, ["RUN_COMMAND"],
                 emit_telemetry: false
               )
    end

    test "handles special characters in tool names" do
      tool = "custom:tool/with.special_chars"
      {:ok, consented} = Permissions.record_consent([], tool)
      {:ok, revoked} = Permissions.revoke_consent(consented, tool)
      assert revoked == []
    end
  end
end
