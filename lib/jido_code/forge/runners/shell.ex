defmodule JidoCode.Forge.Runners.Shell do
  @moduledoc """
  Simple shell command runner.

  Executes a shell command and returns the result. The command can be
  provided via opts or state.
  """

  @behaviour JidoCode.Forge.Runner

  alias JidoCode.Forge.InfraClient

  @impl true
  def init(_client, _config) do
    :ok
  end

  @impl true
  def run_iteration(client, state, opts) do
    command = opts[:command] || Map.get(state, :command) || Map.get(state, "command")

    case InfraClient.exec(client, command, opts) do
      {output, 0} ->
        {:ok,
         %{
           status: :done,
           output: output,
           summary: nil,
           question: nil,
           error: nil,
           metadata: %{exit_code: 0}
         }}

      {output, code} ->
        {:ok,
         %{
           status: :error,
           output: output,
           summary: nil,
           question: nil,
           error: "Exit code: #{code}",
           metadata: %{exit_code: code}
         }}
    end
  end

  @impl true
  def apply_input(_client, _input, _state) do
    {:error, :not_supported}
  end
end
