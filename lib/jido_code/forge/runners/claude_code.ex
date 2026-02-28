defmodule JidoCode.Forge.Runners.ClaudeCode do
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

  ## Environment Layout

  The runner sets up the following structure in the environment:

      /var/local/forge/
      +-- session/           # Session state files
      +-- templates/         # Prompt templates
      +-- .claude/           # Claude CLI config
  """

  @behaviour JidoCode.Forge.Runner

  require Logger

  alias JidoCode.Forge.PromptRedaction
  alias JidoCode.Forge.InfraClient

  @forge_home "/var/local/forge"

  @impl true
  def init(client, config) do
    with :ok <- setup_directories(client),
         :ok <- setup_claude_settings(client, config),
         :ok <- setup_templates(client, config) do
      :ok
    end
  end

  @impl true
  def run_iteration(client, state, opts) do
    model = opts[:model] || state[:model] || "claude-sonnet-4-20250514"
    max_turns = opts[:max_turns] || state[:max_turns] || 200
    max_budget = opts[:max_budget] || state[:max_budget] || 10.0
    prompt = opts[:prompt] || state[:prompt]

    with {:ok, redacted_prompt} <- redact_prompt(prompt, :run_iteration_prompt) do
      cmd = build_claude_command(model, max_turns, max_budget, redacted_prompt)

      case InfraClient.exec(client, cmd, timeout: :infinity) do
        {output, 0} ->
          result = parse_claude_output(output)
          {:ok, result}

        {output, code} ->
          {:ok,
           %{
             status: :error,
             output: output,
             error: "Claude exited with code #{code}",
             metadata: %{exit_code: code}
           }}
      end
    else
      {:error, typed_error} = error ->
        emit_redaction_failure(:run_iteration_prompt, typed_error)
        error
    end
  end

  @impl true
  def apply_input(client, input, _state) do
    response = Jason.encode!(%{answer: input})
    InfraClient.write_file(client, "#{@forge_home}/session/response.json", response)
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
      case InfraClient.exec(client, "mkdir -p #{dir}", []) do
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
        InfraClient.write_file(
          client,
          "#{@forge_home}/.claude/settings.json",
          Jason.encode!(settings)
        )
    end
  end

  defp setup_templates(client, config) do
    with :ok <- maybe_write_template(client, config, :prompt_template, "iterate.md"),
         :ok <- maybe_write_template(client, config, :context_template, "context.md") do
      :ok
    end
  end

  defp maybe_write_template(client, config, key, filename) do
    case Map.get(config, key) do
      nil ->
        :ok

      content ->
        with {:ok, redacted_content} <- redact_prompt(content, template_operation(key)) do
          InfraClient.write_file(client, "#{@forge_home}/templates/#{filename}", redacted_content)
        else
          {:error, typed_error} = error ->
            emit_redaction_failure(template_operation(key), typed_error)
            error
        end
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

  defp redact_prompt(prompt, operation) do
    PromptRedaction.redact_prompt_payload(prompt, operation: operation)
  end

  defp template_operation(:prompt_template), do: :write_prompt_template
  defp template_operation(:context_template), do: :write_context_template
  defp template_operation(_key), do: :write_template

  defp emit_redaction_failure(operation, typed_error) do
    Logger.error(
      "security_audit=forge_prompt_redaction_failed severity=high action=llm_prompt_blocked operation=#{operation} error_type=#{typed_error.error_type} reason_type=#{typed_error.reason_type}"
    )
  end
end
