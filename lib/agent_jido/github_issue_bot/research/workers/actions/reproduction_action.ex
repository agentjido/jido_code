defmodule AgentJido.GithubIssueBot.Research.Workers.Actions.ReproductionAction do
  @moduledoc """
  Analyzes reproduction steps from an issue.

  Parses the issue body to extract structured reproduction information.

  ## Input

  - run_id: The parent run identifier
  - issue: Map with :title, :body, :repo, etc.
  - triage: Triage results with :classification, :needs_info

  ## Output

  Emits reproduction.result to parent with:
  - has_repro_steps: Boolean indicating if repro steps were found
  - steps: List of reproduction steps (if found)
  - environment: Extracted environment info (versions, OS, etc.)
  - expected_behavior: What should happen
  - actual_behavior: What actually happens
  - summary: Human-readable summary

  ## Current Behavior (Stub)

  Uses simple regex/string matching to extract info.
  TODO: Use LLM for more sophisticated extraction.
  """
  use Jido.Action,
    name: "reproduction",
    schema: [
      run_id: [type: :string, required: true],
      issue: [type: :map, required: true],
      triage: [type: :map, required: true]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  require Logger

  def run(%{run_id: run_id, issue: issue, triage: _triage}, context) do
    Logger.debug("Reproduction analysis for run: #{run_id}")

    body = Map.get(issue, :body, "") |> String.downcase()

    # Extract reproduction information (stub implementation)
    result = %{
      has_repro_steps: has_repro_steps?(body),
      steps: extract_steps(body),
      environment: extract_environment(body),
      expected_behavior: extract_section(body, "expected"),
      actual_behavior: extract_section(body, "actual"),
      summary: summarize_repro(body)
    }

    result_signal =
      Signal.new!(
        "reproduction.result",
        %{
          run_id: run_id,
          worker_type: :reproduction,
          result: result
        },
        source: "/reproduction"
      )

    emit_directive = Directive.emit_to_parent(context.agent, result_signal)

    {:ok,
     %{
       status: :completed,
       run_id: run_id,
       issue_number: Map.get(issue, :number)
     }, List.wrap(emit_directive)}
  end

  # Check if issue has reproduction steps
  defp has_repro_steps?(body) do
    String.contains?(body, "steps to reproduce") or
      String.contains?(body, "reproduction") or
      String.contains?(body, "to reproduce") or
      String.contains?(body, "1.")
  end

  # Extract numbered steps from body
  defp extract_steps(body) do
    # Look for numbered lists like "1. Do this\n2. Do that"
    Regex.scan(~r/\d+\.\s+(.+?)(?=\n|$)/i, body)
    |> Enum.map(fn [_, step] -> String.trim(step) end)
    |> Enum.take(10)
  end

  # Extract environment/version info
  defp extract_environment(body) do
    %{
      elixir_version: extract_version(body, "elixir"),
      otp_version: extract_version(body, "otp"),
      package_version: extract_version(body, "jido")
    }
  end

  # Extract version for a specific component
  defp extract_version(body, component) do
    # Match patterns like "Elixir: 1.18" or "OTP: 27" or "Jido: 2.0.0-rc.2"
    case Regex.run(~r/#{component}[:\s]+(\d+[\.\d\-\w]*)/i, body) do
      [_, version] -> version
      _ -> nil
    end
  end

  # Extract a section by header keyword
  defp extract_section(body, keyword) do
    # Look for "Expected Behavior" or "Expected:" etc.
    pattern = ~r/#{keyword}[^:]*:?\s*\n(.+?)(?=\n\n|##|$)/is

    case Regex.run(pattern, body) do
      [_, content] -> String.trim(content) |> String.slice(0, 500)
      _ -> nil
    end
  end

  # Generate summary of reproduction info
  defp summarize_repro(body) do
    has_steps = has_repro_steps?(body)
    steps = extract_steps(body)

    cond do
      length(steps) >= 3 ->
        "Complete reproduction steps provided (#{length(steps)} steps)"

      has_steps ->
        "Partial reproduction info found"

      true ->
        "No clear reproduction steps found"
    end
  end
end
