defmodule JidoCode.Tools.Definitions.ShellTest do
  use ExUnit.Case, async: false

  alias JidoCode.Tools.{Executor, Registry, Result}

  alias JidoCode.Tools.Definitions.Shell, as: Definitions

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    # Clear and set up registry for each test
    Registry.clear()

    # Register all shell tools
    for tool <- Definitions.all() do
      :ok = Registry.register(tool)
    end

    {:ok, project_root: tmp_dir}
  end

  describe "all/0" do
    test "returns shell tools" do
      tools = Definitions.all()
      assert length(tools) == 1

      names = Enum.map(tools, & &1.name)
      assert "run_command" in names
    end
  end

  describe "tool definitions" do
    test "run_command has correct schema" do
      tool = Definitions.run_command()
      assert tool.name == "run_command"
      assert tool.description =~ "Execute"
      assert length(tool.parameters) == 3

      command_param = Enum.find(tool.parameters, &(&1.name == "command"))
      args_param = Enum.find(tool.parameters, &(&1.name == "args"))
      timeout_param = Enum.find(tool.parameters, &(&1.name == "timeout"))

      assert command_param.required == true
      assert args_param.required == false
      assert timeout_param.required == false
    end
  end

  describe "executor integration" do
    test "run_command tool works via executor", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "run_command",
        arguments: %{"command" => "echo", "args" => ["hello"]}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      output = Jason.decode!(result.content)
      assert output["exit_code"] == 0
      assert String.trim(output["stdout"]) == "hello"
    end

    test "handles command failure", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "run_command",
        arguments: %{"command" => "false"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      output = Jason.decode!(result.content)
      assert output["exit_code"] != 0
    end

    test "executor validates arguments", %{project_root: project_root} do
      # Missing required argument
      tool_call = %{
        id: "call_123",
        name: "run_command",
        arguments: %{}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "missing required parameter"
    end

    test "results can be converted to LLM messages", %{project_root: project_root} do
      tool_call = %{
        id: "call_abc",
        name: "run_command",
        arguments: %{"command" => "true"}
      }

      context = %{project_root: project_root}
      {:ok, result} = Executor.execute(tool_call, context: context)

      message = Result.to_llm_message(result)
      assert message.role == "tool"
      assert message.tool_call_id == "call_abc"
      assert is_binary(message.content)
    end

    test "runs commands in project directory", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "run_command",
        arguments: %{"command" => "pwd"}
      }

      context = %{project_root: project_root}
      {:ok, result} = Executor.execute(tool_call, context: context)

      output = Jason.decode!(result.content)
      assert String.trim(output["stdout"]) == project_root
    end
  end
end
