defmodule JidoCode.Memory.ActionsTest do
  use ExUnit.Case, async: true

  alias JidoCode.Memory.Actions
  alias JidoCode.Memory.Actions.{Remember, Recall, Forget}

  # =============================================================================
  # all/0 Tests
  # =============================================================================

  describe "all/0" do
    test "returns all three action modules" do
      modules = Actions.all()

      assert length(modules) == 3
      assert Remember in modules
      assert Recall in modules
      assert Forget in modules
    end

    test "returns modules in expected order" do
      assert Actions.all() == [Remember, Recall, Forget]
    end
  end

  # =============================================================================
  # get/1 Tests
  # =============================================================================

  describe "get/1" do
    test "returns Remember module for 'remember'" do
      assert {:ok, Remember} = Actions.get("remember")
    end

    test "returns Recall module for 'recall'" do
      assert {:ok, Recall} = Actions.get("recall")
    end

    test "returns Forget module for 'forget'" do
      assert {:ok, Forget} = Actions.get("forget")
    end

    test "returns error for unknown name" do
      assert {:error, :not_found} = Actions.get("unknown")
    end

    test "returns error for empty string" do
      assert {:error, :not_found} = Actions.get("")
    end

    test "returns error for nil" do
      assert {:error, :not_found} = Actions.get(nil)
    end

    test "returns error for non-string input" do
      assert {:error, :not_found} = Actions.get(:remember)
      assert {:error, :not_found} = Actions.get(123)
    end
  end

  # =============================================================================
  # names/0 Tests
  # =============================================================================

  describe "names/0" do
    test "returns all action names" do
      names = Actions.names()

      assert length(names) == 3
      assert "remember" in names
      assert "recall" in names
      assert "forget" in names
    end

    test "returns names in expected order" do
      assert Actions.names() == ["remember", "recall", "forget"]
    end
  end

  # =============================================================================
  # memory_action?/1 Tests
  # =============================================================================

  describe "memory_action?/1" do
    test "returns true for 'remember'" do
      assert Actions.memory_action?("remember") == true
    end

    test "returns true for 'recall'" do
      assert Actions.memory_action?("recall") == true
    end

    test "returns true for 'forget'" do
      assert Actions.memory_action?("forget") == true
    end

    test "returns false for unknown action" do
      assert Actions.memory_action?("read_file") == false
      assert Actions.memory_action?("unknown") == false
    end

    test "returns false for empty string" do
      assert Actions.memory_action?("") == false
    end

    test "returns false for non-string input" do
      assert Actions.memory_action?(nil) == false
      assert Actions.memory_action?(:remember) == false
      assert Actions.memory_action?(123) == false
    end
  end

  # =============================================================================
  # to_tool_definitions/0 Tests
  # =============================================================================

  describe "to_tool_definitions/0" do
    test "returns three tool definitions" do
      defs = Actions.to_tool_definitions()
      assert length(defs) == 3
    end

    test "each definition has required keys" do
      for def <- Actions.to_tool_definitions() do
        assert Map.has_key?(def, :name)
        assert Map.has_key?(def, :description)
        assert Map.has_key?(def, :parameters_schema)
        assert Map.has_key?(def, :function)
      end
    end

    test "names match expected action names" do
      names = Actions.to_tool_definitions() |> Enum.map(& &1.name)
      assert names == ["remember", "recall", "forget"]
    end

    test "remember definition has correct schema properties" do
      [remember_def | _] = Actions.to_tool_definitions()

      assert remember_def.name == "remember"
      assert is_binary(remember_def.description)
      assert remember_def.parameters_schema.type == "object"
      assert "content" in remember_def.parameters_schema.required
      assert Map.has_key?(remember_def.parameters_schema.properties, "content")
      assert Map.has_key?(remember_def.parameters_schema.properties, "type")
    end

    test "recall definition has correct schema properties" do
      [_, recall_def | _] = Actions.to_tool_definitions()

      assert recall_def.name == "recall"
      assert is_binary(recall_def.description)
      assert recall_def.parameters_schema.type == "object"
      assert Map.has_key?(recall_def.parameters_schema.properties, "query")
    end

    test "forget definition has correct schema properties" do
      [_, _, forget_def] = Actions.to_tool_definitions()

      assert forget_def.name == "forget"
      assert is_binary(forget_def.description)
      assert forget_def.parameters_schema.type == "object"
      assert "memory_id" in forget_def.parameters_schema.required
      assert Map.has_key?(forget_def.parameters_schema.properties, "memory_id")
    end

    test "function is callable for each definition" do
      for def <- Actions.to_tool_definitions() do
        assert is_function(def.function, 2)
      end
    end
  end

  # =============================================================================
  # Integration Tests
  # =============================================================================

  describe "action module integration" do
    test "all returned modules are valid Jido.Action modules" do
      for module <- Actions.all() do
        # Each module should have these functions from Jido.Action
        assert function_exported?(module, :run, 2)
        assert function_exported?(module, :name, 0)
        assert function_exported?(module, :description, 0)
        assert function_exported?(module, :schema, 0)
        assert function_exported?(module, :to_tool, 0)
      end
    end

    test "get returns modules that can be run" do
      {:ok, remember} = Actions.get("remember")
      {:ok, recall} = Actions.get("recall")
      {:ok, forget} = Actions.get("forget")

      # Each should have a run/2 function
      assert function_exported?(remember, :run, 2)
      assert function_exported?(recall, :run, 2)
      assert function_exported?(forget, :run, 2)
    end

    test "module names match action names" do
      for module <- Actions.all() do
        action_name = module.name()
        {:ok, looked_up} = Actions.get(action_name)
        assert looked_up == module
      end
    end
  end
end
