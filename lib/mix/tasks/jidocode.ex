defmodule Mix.Tasks.Jidocode do
  use Mix.Task

  @shortdoc "Delegates jidocode CLI commands to skill/command/workflow runtimes"

  @moduledoc """
  Unified wrapper for jidocode CLI entrypoints exposed by:

  - `jido_skill` (`--skill` / `--skills`)
  - `jido_command` (`--command` / `--commands`)
  - `jido_workflow` (`--workflow` / `--workflows`)

  Examples:

      mix jidocode --skills
      mix jidocode --skill list
      mix jidocode --skill run pdf-processor --route pdf/extract/text --data '{"file":"report.pdf"}'
      mix jidocode --command code-review --params '{"target_file":"lib/foo.ex"}'
      mix jidocode --workflow code_review -file_path lib/example.ex -mode full
  """

  @usage """
  Usage:
    mix jidocode --skills [skill.list options]
    mix jidocode --skill <name> [skill.run options]
    mix jidocode --skill run <name> [skill.run options]
    mix jidocode --skill list [skill.list options]

    mix jidocode --commands
    mix jidocode --command <name> [command.invoke options]
    mix jidocode --command=<name> [command.invoke options]

    mix jidocode --workflows [workflow.control definitions options]
    mix jidocode --workflow <workflow-id> [-option-name option-value]...

  Notes:
    - `--skills` is an alias for `--skill list`.
    - `--commands` is an alias for `--command list`.
    - `--workflows` is an alias for `workflow.control definitions`.
  """

  @impl Mix.Task
  def run(args) when is_list(args) do
    case route(args) do
      {:help} ->
        Mix.shell().info(@usage)

      {:skill, skill_args} ->
        delegate_skill(skill_args)

      {:command, command_args} ->
        delegate_command(command_args)

      {:workflow, workflow_args} ->
        delegate_workflow(workflow_args)

      {:workflow_control, workflow_control_args} ->
        delegate_workflow_control(workflow_control_args)

      :invalid ->
        Mix.raise(@usage)
    end
  end

  @doc false
  @spec route([String.t()]) ::
          {:help}
          | {:skill, [String.t()]}
          | {:command, [String.t()]}
          | {:workflow, [String.t()]}
          | {:workflow_control, [String.t()]}
          | :invalid
  def route([]), do: {:help}
  def route([arg]) when arg in ["help", "--help", "-h"], do: {:help}

  def route(["--skills" | rest]), do: {:skill, ["--skill", "list" | rest]}
  def route(["--skill" | _rest] = args), do: {:skill, args}

  def route(["--commands" | rest]), do: {:command, ["list" | rest]}
  def route(["--command" | _rest] = args), do: {:command, args}

  def route([first | _rest] = args) when is_binary(first) do
    if String.starts_with?(first, "--command=") do
      {:command, args}
    else
      route_non_command(first, args)
    end
  end

  def route(_args), do: :invalid

  defp route_non_command("--workflows", [_ | rest]), do: {:workflow_control, ["definitions" | rest]}
  defp route_non_command("--workflow", args), do: {:workflow, args}
  defp route_non_command(_first, _args), do: :invalid

  defp delegate_skill(args) do
    case Jido.Code.Skill.CLI.resolve(args) do
      {:ok, task, task_args} ->
        ensure_app_started!(:jido_skill)
        Mix.Task.run(task, ensure_no_start_app(task_args))

      {:error, _reason} ->
        Mix.raise(@usage)
    end
  end

  defp delegate_command(args) do
    Jido.Code.Command.Escript.main(args)
  end

  defp delegate_workflow(args) do
    case Jido.Code.Workflow.CLI.resolve(args) do
      {:ok, task, task_args} ->
        ensure_app_started!(:jido_workflow)
        Mix.Task.run(task, ensure_no_start_app(task_args))

      {:error, _reason} ->
        Mix.raise(@usage)
    end
  end

  defp delegate_workflow_control(args) do
    ensure_app_started!(:jido_workflow)
    Mix.Task.run("workflow.control", ensure_no_start_app(args))
  end

  defp ensure_app_started!(app) when is_atom(app) do
    case Application.ensure_all_started(app) do
      {:ok, _started} -> :ok
      {:error, reason} -> Mix.raise("failed to start #{app}: #{inspect(reason)}")
    end
  end

  defp ensure_no_start_app(args) when is_list(args) do
    if Enum.any?(args, &(&1 in ["--start-app", "--no-start-app"])) do
      args
    else
      args ++ ["--no-start-app"]
    end
  end
end
