defmodule JidoCode.Tools.Definitions.ElixirTest do
  use ExUnit.Case, async: false

  alias JidoCode.Tools.{Executor, Registry, Result}
  alias JidoCode.Tools.Definitions.Elixir, as: Definitions
  alias JidoCode.Tools.Handlers.Elixir, as: ElixirHandler

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    # Ensure application is started (Manager and registries)
    Application.ensure_all_started(:jido_code)

    # Clear registry for each test (persistent_term requires explicit clear)
    Registry.clear()

    # Register all Elixir tools
    for tool <- Definitions.all() do
      :ok = Registry.register(tool)
    end

    {:ok, project_root: tmp_dir}
  end

  describe "all/0" do
    test "returns Elixir tools" do
      tools = Definitions.all()
      assert length(tools) == 2

      names = Enum.map(tools, & &1.name)
      assert "mix_task" in names
      assert "run_exunit" in names
    end
  end

  describe "mix_task/0 tool definition" do
    test "has correct name and description" do
      tool = Definitions.mix_task()
      assert tool.name == "mix_task"
      assert tool.description =~ "Mix task"
      assert tool.description =~ "allowlisted"
    end

    test "has correct parameters" do
      tool = Definitions.mix_task()
      assert length(tool.parameters) == 4

      task_param = Enum.find(tool.parameters, &(&1.name == "task"))
      args_param = Enum.find(tool.parameters, &(&1.name == "args"))
      env_param = Enum.find(tool.parameters, &(&1.name == "env"))
      timeout_param = Enum.find(tool.parameters, &(&1.name == "timeout"))

      assert task_param.required == true
      assert task_param.type == :string
      assert task_param.description =~ "compile"

      assert args_param.required == false
      assert args_param.type == :array
      assert args_param.description =~ "arguments"

      assert env_param.required == false
      assert env_param.type == :string
      assert env_param.description =~ "prod"
      assert env_param.enum == ["dev", "test"]

      assert timeout_param.required == false
      assert timeout_param.type == :integer
      assert timeout_param.description =~ "60000"
    end

    test "has correct handler" do
      tool = Definitions.mix_task()
      assert tool.handler == JidoCode.Tools.Handlers.Elixir.MixTask
    end
  end

  describe "run_exunit/0 tool definition" do
    test "has correct name and description" do
      tool = Definitions.run_exunit()
      assert tool.name == "run_exunit"
      assert tool.description =~ "ExUnit"
      assert tool.description =~ "filtering"
    end

    test "has correct parameters" do
      tool = Definitions.run_exunit()
      assert length(tool.parameters) == 8

      path_param = Enum.find(tool.parameters, &(&1.name == "path"))
      line_param = Enum.find(tool.parameters, &(&1.name == "line"))
      tag_param = Enum.find(tool.parameters, &(&1.name == "tag"))
      exclude_tag_param = Enum.find(tool.parameters, &(&1.name == "exclude_tag"))
      max_failures_param = Enum.find(tool.parameters, &(&1.name == "max_failures"))
      seed_param = Enum.find(tool.parameters, &(&1.name == "seed"))
      trace_param = Enum.find(tool.parameters, &(&1.name == "trace"))
      timeout_param = Enum.find(tool.parameters, &(&1.name == "timeout"))

      # All parameters are optional
      assert path_param.required == false
      assert path_param.type == :string
      assert path_param.description =~ "test"

      assert line_param.required == false
      assert line_param.type == :integer
      assert line_param.description =~ "line"

      assert tag_param.required == false
      assert tag_param.type == :string
      assert tag_param.description =~ "tag"

      assert exclude_tag_param.required == false
      assert exclude_tag_param.type == :string
      assert exclude_tag_param.description =~ "Exclude"

      assert max_failures_param.required == false
      assert max_failures_param.type == :integer
      assert max_failures_param.description =~ "failures"

      assert seed_param.required == false
      assert seed_param.type == :integer
      assert seed_param.description =~ "seed"

      assert trace_param.required == false
      assert trace_param.type == :boolean
      assert trace_param.description =~ "trace"

      assert timeout_param.required == false
      assert timeout_param.type == :integer
      assert timeout_param.description =~ "120000"
    end

    test "has correct handler" do
      tool = Definitions.run_exunit()
      assert tool.handler == JidoCode.Tools.Handlers.Elixir.RunExunit
    end
  end

  describe "ElixirHandler.allowed_tasks/0" do
    test "returns list of allowed tasks" do
      tasks = ElixirHandler.allowed_tasks()
      assert is_list(tasks)
      assert "compile" in tasks
      assert "test" in tasks
      assert "format" in tasks
      assert "deps.get" in tasks
    end
  end

  describe "ElixirHandler.blocked_tasks/0" do
    test "returns list of blocked tasks" do
      tasks = ElixirHandler.blocked_tasks()
      assert is_list(tasks)
      assert "release" in tasks
      assert "hex.publish" in tasks
      assert "ecto.drop" in tasks
    end
  end

  describe "ElixirHandler.validate_task/1" do
    test "allows valid tasks" do
      assert {:ok, "compile"} = ElixirHandler.validate_task("compile")
      assert {:ok, "test"} = ElixirHandler.validate_task("test")
      assert {:ok, "format"} = ElixirHandler.validate_task("format")
      assert {:ok, "deps.get"} = ElixirHandler.validate_task("deps.get")
    end

    test "blocks explicitly blocked tasks" do
      assert {:error, :task_blocked} = ElixirHandler.validate_task("release")
      assert {:error, :task_blocked} = ElixirHandler.validate_task("hex.publish")
      assert {:error, :task_blocked} = ElixirHandler.validate_task("ecto.drop")
    end

    test "rejects unknown tasks" do
      assert {:error, :task_not_allowed} = ElixirHandler.validate_task("unknown_task")
      assert {:error, :task_not_allowed} = ElixirHandler.validate_task("phx.server")
    end
  end

  describe "ElixirHandler.validate_env/1" do
    test "allows dev and test environments" do
      assert {:ok, "dev"} = ElixirHandler.validate_env("dev")
      assert {:ok, "test"} = ElixirHandler.validate_env("test")
    end

    test "defaults to dev when nil" do
      assert {:ok, "dev"} = ElixirHandler.validate_env(nil)
    end

    test "blocks prod environment" do
      assert {:error, :env_blocked} = ElixirHandler.validate_env("prod")
    end

    test "blocks unknown environments" do
      assert {:error, :env_blocked} = ElixirHandler.validate_env("staging")
      assert {:error, :env_blocked} = ElixirHandler.validate_env("production")
    end
  end

  describe "executor integration" do
    test "mix_task tool is registered and executable", %{project_root: project_root} do
      # Create a minimal mix project structure
      File.write!(Path.join(project_root, "mix.exs"), """
      defmodule TestProject.MixProject do
        use Mix.Project
        def project do
          [app: :test_project, version: "0.1.0"]
        end
      end
      """)

      tool_call = %{
        id: "call_123",
        name: "mix_task",
        arguments: %{"task" => "help"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      output = Jason.decode!(result.content)
      assert is_integer(output["exit_code"])
      assert is_binary(output["output"])
    end

    test "validates required task parameter", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "mix_task",
        arguments: %{}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "missing required parameter"
    end

    test "blocks unknown tasks", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "mix_task",
        arguments: %{"task" => "unknown_task"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "not allowed"
    end

    test "blocks explicitly blocked tasks", %{project_root: project_root} do
      tool_call = %{
        id: "call_123",
        name: "mix_task",
        arguments: %{"task" => "hex.publish"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "blocked"
    end

    test "blocks prod environment", %{project_root: project_root} do
      # Create a minimal mix project structure
      File.write!(Path.join(project_root, "mix.exs"), """
      defmodule TestProject.MixProject do
        use Mix.Project
        def project do
          [app: :test_project, version: "0.1.0"]
        end
      end
      """)

      tool_call = %{
        id: "call_123",
        name: "mix_task",
        arguments: %{"task" => "compile", "env" => "prod"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      # Should be rejected at executor level due to enum validation
      assert result.content =~ "prod" or result.content =~ "unknown parameter"
    end

    test "passes arguments to mix task", %{project_root: project_root} do
      # Create a minimal mix project structure
      File.write!(Path.join(project_root, "mix.exs"), """
      defmodule TestProject.MixProject do
        use Mix.Project
        def project do
          [app: :test_project, version: "0.1.0"]
        end
      end
      """)

      tool_call = %{
        id: "call_123",
        name: "mix_task",
        arguments: %{"task" => "help", "args" => ["compile"]}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      output = Jason.decode!(result.content)
      assert output["output"] =~ "compile" or output["exit_code"] == 0
    end

    test "results can be converted to LLM messages", %{project_root: project_root} do
      # Create a minimal mix project structure
      File.write!(Path.join(project_root, "mix.exs"), """
      defmodule TestProject.MixProject do
        use Mix.Project
        def project do
          [app: :test_project, version: "0.1.0"]
        end
      end
      """)

      tool_call = %{
        id: "call_abc",
        name: "mix_task",
        arguments: %{"task" => "help"}
      }

      context = %{project_root: project_root}
      {:ok, result} = Executor.execute(tool_call, context: context)

      message = Result.to_llm_message(result)
      assert message.role == "tool"
      assert message.tool_call_id == "call_abc"
      assert is_binary(message.content)
    end

    test "run_exunit tool is registered and executable", %{project_root: project_root} do
      # Create a minimal mix project with a simple test
      File.write!(Path.join(project_root, "mix.exs"), """
      defmodule TestProject.MixProject do
        use Mix.Project
        def project do
          [app: :test_project, version: "0.1.0", elixir: "~> 1.14"]
        end
      end
      """)

      File.mkdir_p!(Path.join(project_root, "test"))

      File.write!(Path.join(project_root, "test/test_helper.exs"), """
      ExUnit.start()
      """)

      File.write!(Path.join(project_root, "test/simple_test.exs"), """
      defmodule SimpleTest do
        use ExUnit.Case
        test "passes" do
          assert 1 + 1 == 2
        end
      end
      """)

      tool_call = %{
        id: "call_exunit",
        name: "run_exunit",
        arguments: %{}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      output = Jason.decode!(result.content)
      assert is_integer(output["exit_code"])
      assert is_binary(output["output"])
    end

    test "run_exunit blocks path traversal", %{project_root: project_root} do
      tool_call = %{
        id: "call_exunit",
        name: "run_exunit",
        arguments: %{"path" => "../../../etc/passwd"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "Path traversal"
    end

    test "run_exunit accepts filtering parameters", %{project_root: project_root} do
      # Create a minimal mix project with a tagged test
      File.write!(Path.join(project_root, "mix.exs"), """
      defmodule TestProject.MixProject do
        use Mix.Project
        def project do
          [app: :test_project, version: "0.1.0", elixir: "~> 1.14"]
        end
      end
      """)

      File.mkdir_p!(Path.join(project_root, "test"))

      File.write!(Path.join(project_root, "test/test_helper.exs"), """
      ExUnit.start()
      """)

      File.write!(Path.join(project_root, "test/tagged_test.exs"), """
      defmodule TaggedTest do
        use ExUnit.Case

        @tag :integration
        test "integration test" do
          assert true
        end

        test "unit test" do
          assert true
        end
      end
      """)

      # Test with tag filter
      tool_call = %{
        id: "call_exunit_tag",
        name: "run_exunit",
        arguments: %{"tag" => "integration"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      output = Jason.decode!(result.content)
      assert output["exit_code"] == 0
    end

    test "run_exunit with max_failures", %{project_root: project_root} do
      File.write!(Path.join(project_root, "mix.exs"), """
      defmodule TestProject.MixProject do
        use Mix.Project
        def project do
          [app: :test_project, version: "0.1.0", elixir: "~> 1.14"]
        end
      end
      """)

      File.mkdir_p!(Path.join(project_root, "test"))

      File.write!(Path.join(project_root, "test/test_helper.exs"), """
      ExUnit.start()
      """)

      File.write!(Path.join(project_root, "test/pass_test.exs"), """
      defmodule PassTest do
        use ExUnit.Case
        test "passes" do
          assert true
        end
      end
      """)

      tool_call = %{
        id: "call_exunit_max",
        name: "run_exunit",
        arguments: %{"max_failures" => 1}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok
    end
  end
end
