defmodule AgentJido.Forge.Runners.ClaudeCode do
  @moduledoc """
  Runner adapter for Claude Code CLI.
  Executes Claude in iteration loops with state sync.

  ## Configuration

  The runner accepts the following config:

    * `:model` - Claude model to use (default: "claude-sonnet-4-20250514")
    * `:max_turns` - Maximum turns per iteration (default: 200)
    * `:max_budget` - Maximum budget in USD (default: 10.0)
    * `:prompt_template` - Initial prompt template
    * `:context_template` - Additional context to append
    * `:claude_settings` - Claude CLI settings JSON

  ## Sprite Layout

  The runner sets up the following structure in the sprite:

      /var/local/forge/
      +-- session/           # Session state files
      +-- templates/         # Prompt templates
      +-- .claude/           # Claude CLI config
  """

  @behaviour AgentJido.Forge.Runner

  alias AgentJido.Forge.SpriteClient

  @forge_home "/var/local/forge"

  @impl true
  def init(client, config) do
    with :ok <- setup_directories(client),
         :ok <- setup_claude_settings(client, config) do
      setup_templates(client, config)
    end
  end

  @impl true
  def run_iteration(client, state, opts) do
    {model, max_turns, max_budget, prompt} = resolve_run_options(state, opts)
    cmd = build_claude_command(model, max_turns, max_budget, prompt)

    client
    |> SpriteClient.exec(cmd, timeout: :infinity)
    |> handle_exec_result()
  end

  defp resolve_run_options(state, opts) do
    model = opts[:model] || state[:model] || "claude-sonnet-4-20250514"
    max_turns = opts[:max_turns] || state[:max_turns] || 200
    max_budget = opts[:max_budget] || state[:max_budget] || 10.0
    prompt = opts[:prompt] || state[:prompt]
    {model, max_turns, max_budget, prompt}
  end

  defp handle_exec_result({output, 0}), do: {:ok, parse_claude_output(output)}

  defp handle_exec_result({output, code}) do
    {:ok,
     %{
       status: :error,
       output: output,
       error: "Claude exited with code #{code}",
       metadata: %{exit_code: code}
     }}
  end

  @impl true
  def apply_input(client, input, _state) do
    response = Jason.encode!(%{answer: input})
    SpriteClient.write_file(client, "#{@forge_home}/session/response.json", response)
  end

  @impl true
  def handle_output(chunk, :stdout, state) do
    events = parse_stream_json(chunk)
    {:ok, events, state}
  end

  def handle_output(_chunk, :stderr, state) do
    {:ok, [], state}
  end

  @impl true
  def terminate(_client, _reason), do: :ok

  # Private helpers

  defp setup_directories(client) do
    dirs = [
      "#{@forge_home}/session",
      "#{@forge_home}/templates",
      "#{@forge_home}/.claude"
    ]

    Enum.reduce_while(dirs, :ok, fn dir, :ok ->
      case SpriteClient.exec(client, "mkdir -p #{dir}", []) do
        {_, 0} -> {:cont, :ok}
        {output, code} -> {:halt, {:error, {:mkdir_failed, dir, output, code}}}
      end
    end)
  end

  defp setup_claude_settings(client, config) do
    case Map.get(config, :claude_settings) do
      nil ->
        :ok

      settings ->
        SpriteClient.write_file(
          client,
          "#{@forge_home}/.claude/settings.json",
          Jason.encode!(settings)
        )
    end
  end

  defp setup_templates(client, config) do
    with :ok <- maybe_write_template(client, config, :prompt_template, "iterate.md") do
      maybe_write_template(client, config, :context_template, "context.md")
    end
  end

  defp maybe_write_template(client, config, key, filename) do
    case Map.get(config, key) do
      nil ->
        :ok

      content ->
        SpriteClient.write_file(client, "#{@forge_home}/templates/#{filename}", content)
    end
  end

  defp build_claude_command(model, max_turns, _max_budget, prompt) do
    prompt_arg = build_prompt_arg(prompt)

    [
      "export HOME=#{@forge_home} &&",
      "claude #{prompt_arg}",
      "--append-system-prompt-file #{@forge_home}/templates/context.md",
      "--model #{model}",
      "--dangerously-skip-permissions",
      "--output-format stream-json",
      "--max-turns #{max_turns}"
    ]
    |> Enum.join(" ")
  end

  defp build_prompt_arg(nil) do
    "-p \"$(cat #{@forge_home}/templates/iterate.md)\""
  end

  defp build_prompt_arg(prompt) do
    escaped = escape_for_shell(prompt)
    "-p \"#{escaped}\""
  end

  defp escape_for_shell(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("$", "\\$")
    |> String.replace("`", "\\`")
  end

  defp parse_claude_output(output) do
    lines = String.split(output, "\n", trim: true)

    events =
      Enum.flat_map(lines, fn line ->
        case Jason.decode(line) do
          {:ok, event} -> [event]
          _ -> []
        end
      end)

    last_event = List.last(events)

    cond do
      is_nil(last_event) ->
        %{status: :done, output: output, metadata: %{}}

      last_event["type"] == "result" && last_event["subtype"] == "success" ->
        %{
          status: :done,
          output: output,
          summary: last_event["result"],
          metadata: %{
            cost_usd: last_event["cost_usd"],
            duration_ms: last_event["duration_ms"],
            session_id: last_event["session_id"]
          }
        }

      last_event["type"] == "result" && last_event["subtype"] == "error_max_turns" ->
        %{
          status: :continue,
          output: output,
          summary: "Max turns reached",
          metadata: %{cost_usd: last_event["cost_usd"]}
        }

      true ->
        %{status: :done, output: output, metadata: %{}}
    end
  end

  defp parse_stream_json(chunk) do
    chunk
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case Jason.decode(line) do
        {:ok, event} -> [event]
        _ -> []
      end
    end)
  end
end
