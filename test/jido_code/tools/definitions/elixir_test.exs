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
      assert length(tools) == 6

      names = Enum.map(tools, & &1.name)
      assert "mix_task" in names
      assert "run_exunit" in names
      assert "get_process_state" in names
      assert "inspect_supervisor" in names
      assert "ets_inspect" in names
      assert "fetch_elixir_docs" in names
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

  describe "get_process_state/0 tool definition" do
    test "has correct name and description" do
      tool = Definitions.get_process_state()
      assert tool.name == "get_process_state"
      assert tool.description =~ "GenServer"
      assert tool.description =~ "process"
    end

    test "has correct parameters" do
      tool = Definitions.get_process_state()
      assert length(tool.parameters) == 2

      process_param = Enum.find(tool.parameters, &(&1.name == "process"))
      timeout_param = Enum.find(tool.parameters, &(&1.name == "timeout"))

      assert process_param.required == true
      assert process_param.type == :string
      assert process_param.description =~ "Registered name"

      assert timeout_param.required == false
      assert timeout_param.type == :integer
      assert timeout_param.description =~ "5000"
    end

    test "has correct handler" do
      tool = Definitions.get_process_state()
      assert tool.handler == JidoCode.Tools.Handlers.Elixir.ProcessState
    end
  end

  describe "inspect_supervisor/0 tool definition" do
    test "has correct name and description" do
      tool = Definitions.inspect_supervisor()
      assert tool.name == "inspect_supervisor"
      assert tool.description =~ "supervisor"
      assert tool.description =~ "tree"
    end

    test "has correct parameters" do
      tool = Definitions.inspect_supervisor()
      assert length(tool.parameters) == 2

      supervisor_param = Enum.find(tool.parameters, &(&1.name == "supervisor"))
      depth_param = Enum.find(tool.parameters, &(&1.name == "depth"))

      assert supervisor_param.required == true
      assert supervisor_param.type == :string
      assert supervisor_param.description =~ "Registered name"

      assert depth_param.required == false
      assert depth_param.type == :integer
      assert depth_param.description =~ "depth"
    end

    test "has correct handler" do
      tool = Definitions.inspect_supervisor()
      assert tool.handler == JidoCode.Tools.Handlers.Elixir.SupervisorTree
    end
  end

  describe "ets_inspect/0 tool definition" do
    test "has correct name and description" do
      tool = Definitions.ets_inspect()
      assert tool.name == "ets_inspect"
      assert tool.description =~ "ETS"
      assert tool.description =~ "tables"
    end

    test "has correct parameters" do
      tool = Definitions.ets_inspect()
      assert length(tool.parameters) == 4

      operation_param = Enum.find(tool.parameters, &(&1.name == "operation"))
      table_param = Enum.find(tool.parameters, &(&1.name == "table"))
      key_param = Enum.find(tool.parameters, &(&1.name == "key"))
      limit_param = Enum.find(tool.parameters, &(&1.name == "limit"))

      assert operation_param.required == true
      assert operation_param.type == :string
      assert operation_param.enum == ["list", "info", "lookup", "sample"]
      assert operation_param.description =~ "Operation"

      assert table_param.required == false
      assert table_param.type == :string
      assert table_param.description =~ "Table name"

      assert key_param.required == false
      assert key_param.type == :string
      assert key_param.description =~ "Key"

      assert limit_param.required == false
      assert limit_param.type == :integer
      assert limit_param.description =~ "100"
    end

    test "has correct handler" do
      tool = Definitions.ets_inspect()
      assert tool.handler == JidoCode.Tools.Handlers.Elixir.EtsInspect
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

    test "get_process_state tool is registered and executable", %{project_root: project_root} do
      # Start a test agent
      {:ok, agent_pid} = Agent.start_link(fn -> %{test_key: "test_value"} end)
      Process.register(agent_pid, :test_definitions_agent_for_state)

      on_exit(fn ->
        if Process.alive?(agent_pid), do: Agent.stop(agent_pid)
      end)

      tool_call = %{
        id: "call_process_state",
        name: "get_process_state",
        arguments: %{"process" => "test_definitions_agent_for_state"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      output = Jason.decode!(result.content)
      assert is_binary(output["state"])
      assert output["state"] =~ "test_key"
    end

    test "get_process_state validates required process parameter", %{project_root: project_root} do
      tool_call = %{
        id: "call_process_state",
        name: "get_process_state",
        arguments: %{}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "missing required parameter"
    end

    test "get_process_state blocks raw PIDs", %{project_root: project_root} do
      tool_call = %{
        id: "call_process_state",
        name: "get_process_state",
        arguments: %{"process" => "#PID<0.123.0>"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "Raw PIDs"
    end

    test "get_process_state blocks system processes", %{project_root: project_root} do
      tool_call = %{
        id: "call_process_state",
        name: "get_process_state",
        arguments: %{"process" => ":kernel"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "blocked"
    end

    test "inspect_supervisor tool is registered and executable", %{project_root: project_root} do
      # Start a test supervisor
      children = [{Agent, fn -> :test end}]
      {:ok, sup_pid} = Supervisor.start_link(children, strategy: :one_for_one)
      Process.register(sup_pid, :test_definitions_supervisor)

      on_exit(fn ->
        try do
          if Process.alive?(sup_pid), do: Supervisor.stop(sup_pid)
        catch
          :exit, _ -> :ok
        end
      end)

      tool_call = %{
        id: "call_inspect_supervisor",
        name: "inspect_supervisor",
        arguments: %{"supervisor" => "test_definitions_supervisor"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      output = Jason.decode!(result.content)
      assert is_binary(output["tree"])
      assert is_list(output["children"])
    end

    test "inspect_supervisor validates required supervisor parameter", %{project_root: project_root} do
      tool_call = %{
        id: "call_inspect_supervisor",
        name: "inspect_supervisor",
        arguments: %{}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "missing required parameter"
    end

    test "inspect_supervisor blocks raw PIDs", %{project_root: project_root} do
      tool_call = %{
        id: "call_inspect_supervisor",
        name: "inspect_supervisor",
        arguments: %{"supervisor" => "#PID<0.123.0>"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "Raw PIDs"
    end

    test "inspect_supervisor blocks system supervisors", %{project_root: project_root} do
      tool_call = %{
        id: "call_inspect_supervisor",
        name: "inspect_supervisor",
        arguments: %{"supervisor" => ":kernel_sup"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "blocked"
    end

    test "ets_inspect tool is registered and executable - list operation", %{project_root: project_root} do
      # Create a test ETS table
      table = :ets.new(:test_definitions_ets_list, [:named_table, :public])

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      tool_call = %{
        id: "call_ets_inspect_list",
        name: "ets_inspect",
        arguments: %{"operation" => "list"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      output = Jason.decode!(result.content)
      assert output["operation"] == "list"
      assert is_list(output["tables"])
    end

    test "ets_inspect tool is registered and executable - info operation", %{project_root: project_root} do
      table = :ets.new(:test_definitions_ets_info, [:named_table, :public])
      :ets.insert(table, {:test, "value"})

      on_exit(fn ->
        try do
          :ets.delete(table)
        catch
          :error, _ -> :ok
        end
      end)

      tool_call = %{
        id: "call_ets_inspect_info",
        name: "ets_inspect",
        arguments: %{"operation" => "info", "table" => "test_definitions_ets_info"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      output = Jason.decode!(result.content)
      assert output["operation"] == "info"
      assert is_map(output["info"])
    end

    test "ets_inspect validates required operation parameter", %{project_root: project_root} do
      tool_call = %{
        id: "call_ets_inspect",
        name: "ets_inspect",
        arguments: %{}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "missing required parameter"
    end

    test "ets_inspect blocks system tables", %{project_root: project_root} do
      tool_call = %{
        id: "call_ets_inspect",
        name: "ets_inspect",
        arguments: %{"operation" => "info", "table" => "code"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "blocked"
    end
  end

  describe "fetch_elixir_docs/0 tool definition" do
    test "has correct name and description" do
      tool = Definitions.fetch_elixir_docs()
      assert tool.name == "fetch_elixir_docs"
      assert tool.description =~ "documentation"
      assert tool.description =~ "module"
    end

    test "has correct parameters" do
      tool = Definitions.fetch_elixir_docs()
      assert length(tool.parameters) == 3

      module_param = Enum.find(tool.parameters, &(&1.name == "module"))
      function_param = Enum.find(tool.parameters, &(&1.name == "function"))
      arity_param = Enum.find(tool.parameters, &(&1.name == "arity"))

      assert module_param.required == true
      assert module_param.type == :string
      assert module_param.description =~ "Enum"

      assert function_param.required == false
      assert function_param.type == :string
      assert function_param.description =~ "Function name"

      assert arity_param.required == false
      assert arity_param.type == :integer
      assert arity_param.description =~ "arity"
    end

    test "has correct handler" do
      tool = Definitions.fetch_elixir_docs()
      assert tool.handler == JidoCode.Tools.Handlers.Elixir.FetchDocs
    end
  end

  describe "fetch_elixir_docs executor integration" do
    test "fetch_elixir_docs tool is registered and executable", %{project_root: project_root} do
      tool_call = %{
        id: "call_fetch_docs",
        name: "fetch_elixir_docs",
        arguments: %{"module" => "Enum"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      output = Jason.decode!(result.content)
      assert output["module"] == "Enum"
      assert is_binary(output["moduledoc"])
      assert is_list(output["docs"])
      assert is_list(output["specs"])
    end

    test "fetch_elixir_docs returns error for non-existent module", %{project_root: project_root} do
      tool_call = %{
        id: "call_fetch_docs",
        name: "fetch_elixir_docs",
        arguments: %{"module" => "NonExistentModule"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "Module not found"
    end

    test "fetch_elixir_docs filters by function name", %{project_root: project_root} do
      tool_call = %{
        id: "call_fetch_docs",
        name: "fetch_elixir_docs",
        arguments: %{"module" => "Enum", "function" => "map"}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      output = Jason.decode!(result.content)
      assert is_list(output["docs"])

      # All returned docs should be for "map"
      Enum.each(output["docs"], fn doc ->
        assert doc["name"] == "map"
      end)
    end

    test "fetch_elixir_docs filters by function and arity", %{project_root: project_root} do
      tool_call = %{
        id: "call_fetch_docs",
        name: "fetch_elixir_docs",
        arguments: %{"module" => "Enum", "function" => "map", "arity" => 2}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok

      output = Jason.decode!(result.content)

      # All returned docs should be for "map/2"
      Enum.each(output["docs"], fn doc ->
        assert doc["name"] == "map"
        assert doc["arity"] == 2
      end)
    end

    test "fetch_elixir_docs requires module parameter", %{project_root: project_root} do
      tool_call = %{
        id: "call_fetch_docs",
        name: "fetch_elixir_docs",
        arguments: %{}
      }

      context = %{project_root: project_root}
      assert {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :error
      assert result.content =~ "Missing required parameter" or result.content =~ "missing required"
    end
  end
end
