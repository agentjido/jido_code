defmodule JidoCode.Forge.Bootstrap do
  @moduledoc """
  Execute bootstrap steps to set up an infrastructure environment.

  Bootstrap steps prepare the environment for running iterations by executing
  commands, writing files, and configuring the environment.
  """

  require Logger

  @type step :: exec_step() | file_step()
  @type exec_step :: %{type: String.t(), command: String.t()}
  @type file_step :: %{type: String.t(), path: String.t(), content: String.t()}
  @type client :: term()
  @type opts :: keyword()

  @doc """
  Execute a list of bootstrap steps in order.

  Stops on the first failure and returns the failing step with the reason.

  ## Options

    * `:infra_client` - The infra client module to use (defaults to JidoCode.Forge.InfraClient)
    * `:infra_id` - The infrastructure identifier for command execution
    * `:on_step` - Optional callback `fn step, index -> :ok end` called before each step

  ## Examples

      steps = [
        %{type: "exec", command: "npm install"},
        %{type: "file", path: "config.json", content: "{}"}
      ]

      Bootstrap.execute(client, steps, infra_id: "abc123")
      #=> :ok

  """
  @spec execute(client(), [step()], opts()) :: :ok | {:error, step(), term()}
  def execute(client, steps, opts \\ []) do
    on_step = Keyword.get(opts, :on_step, fn _, _ -> :ok end)

    steps
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {step, index}, :ok ->
      on_step.(step, index)

      case execute_step(client, step, opts) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          Logger.error("Bootstrap step #{index} failed: #{inspect(reason)}")
          {:halt, {:error, step, reason}}
      end
    end)
  end

  @doc """
  Execute a single bootstrap step.
  """
  @spec execute_step(client(), step(), opts()) :: :ok | {:error, term()}
  def execute_step(client, %{type: "exec", command: command} = step, opts) do
    Logger.debug("Executing bootstrap command: #{command}")

    infra_client = Keyword.get(opts, :infra_client, JidoCode.Forge.InfraClient)

    case infra_client.exec(client, command, opts) do
      {_output, 0} ->
        :ok

      {output, exit_code} ->
        {:error, {:command_failed, exit_code, output, step}}
    end
  end

  def execute_step(client, %{type: "file", path: path, content: content}, opts) do
    Logger.debug("Writing bootstrap file: #{path}")

    infra_client = Keyword.get(opts, :infra_client, JidoCode.Forge.InfraClient)

    case infra_client.write_file(client, path, content) do
      :ok -> :ok
      {:error, reason} -> {:error, {:write_failed, path, reason}}
    end
  end

  def execute_step(_client, step, _opts) do
    {:error, {:unknown_step_type, step}}
  end
end
