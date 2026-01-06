defmodule JidoCode.Memory.ResponseProcessor do
  @moduledoc """
  Automatic extraction and storage of working context from LLM responses.

  This module analyzes LLM response text to extract contextual information
  that can be stored in the session's working context. It uses regex patterns
  to identify mentions of:

  - **Active files** - Files being worked on or discussed
  - **Frameworks** - Technologies and frameworks mentioned
  - **Current tasks** - What the user is working on
  - **Primary language** - The main programming language of the project

  Extracted context is stored with lower confidence (0.6) and marked as
  `:inferred` source since it's derived from LLM output rather than explicit
  user input or tool execution.

  ## Usage

      # Process an LLM response and extract context
      {:ok, extractions} = ResponseProcessor.process_response(response, session_id)

      # Check what was extracted
      %{active_file: "lib/app.ex", framework: "Phoenix 1.7"} = extractions

  ## Integration

  This module is called asynchronously after stream completion in the LLMAgent
  to avoid blocking the response flow. Extraction failures are logged but don't
  affect the user experience.
  """

  require Logger

  alias JidoCode.Session.State

  # =============================================================================
  # Constants
  # =============================================================================

  # Confidence level for inferred context (lower than explicit context)
  @inferred_confidence 0.6

  # Context extraction patterns
  # Each key maps to a list of regex patterns that capture the relevant value
  @context_patterns %{
    active_file: [
      # "working on lib/app.ex" or "editing `config.exs`"
      ~r/(?:working on|editing|reading|looking at|opened?|viewing)\s+[`"]?([^`"\s]+\.\w+)[`"]?/i,
      # "file: lib/app.ex" or "file `config.exs`"
      ~r/file[:\s]+[`"]?([^`"\s]+\.\w+)[`"]?/i,
      # "in the file lib/app.ex"
      ~r/in\s+(?:the\s+)?file\s+[`"]?([^`"\s]+\.\w+)[`"]?/i
    ],
    framework: [
      # "using Phoenix 1.7" or "project uses React"
      ~r/(?:using|project uses|built with|based on|powered by)\s+([A-Z][a-zA-Z]+(?:\s+\d+(?:\.\d+)*)?)/i,
      # "This is a Phoenix application"
      ~r/(?:this is a|it's a|we're using)\s+([A-Z][a-zA-Z]+)\s+(?:application|project|app)/i
    ],
    current_task: [
      # "implementing user authentication"
      ~r/(?:implementing|fixing|creating|adding|updating|refactoring|debugging|testing)\s+(.+?)(?:\.|,|$)/i,
      # "working to add feature X"
      ~r/(?:working to|trying to|need to)\s+(.+?)(?:\.|,|$)/i
    ],
    primary_language: [
      # "this is an Elixir project"
      ~r/(?:this is an?|coded in)\s+(\w+)\s+(?:project|codebase|application|app)/i,
      # "written in Python" (standalone, no need for project/codebase after)
      ~r/(?:written in|coded in)\s+(\w+)\b/i,
      # "Elixir application" or "Python project"
      ~r/(\w+)\s+(?:project|application|codebase)\b/i
    ]
  }

  # Known programming languages for validation
  @known_languages MapSet.new([
    "elixir", "erlang", "python", "javascript", "typescript", "ruby", "go",
    "rust", "java", "kotlin", "swift", "c", "cpp", "csharp", "php", "scala",
    "haskell", "clojure", "lua", "perl", "r", "julia", "dart", "zig"
  ])

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Process an LLM response and extract working context.

  Analyzes the response text for contextual information and updates the
  session's working context with any extracted values. Context is stored
  with `:inferred` source and lower confidence (#{@inferred_confidence}).

  Returns `{:ok, extractions}` with a map of extracted key-value pairs,
  even if the map is empty (no matches found).

  ## Parameters

  - `response` - The LLM response text to analyze
  - `session_id` - The session ID to update context for

  ## Returns

  - `{:ok, map()}` - Map of extracted context (may be empty)

  ## Examples

      iex> ResponseProcessor.process_response("I'm looking at lib/app.ex", "session-123")
      {:ok, %{active_file: "lib/app.ex"}}

      iex> ResponseProcessor.process_response("Hello!", "session-123")
      {:ok, %{}}
  """
  @spec process_response(String.t(), String.t()) :: {:ok, map()}
  def process_response(response, session_id) when is_binary(response) and is_binary(session_id) do
    start_time = System.monotonic_time(:millisecond)
    extractions = extract_context(response)

    if map_size(extractions) > 0 do
      Logger.debug("ResponseProcessor: Extracted #{map_size(extractions)} context items from response")
      update_working_context(extractions, session_id)
    end

    emit_telemetry(session_id, map_size(extractions), start_time)
    {:ok, extractions}
  end

  def process_response(nil, _session_id), do: {:ok, %{}}
  def process_response("", _session_id), do: {:ok, %{}}

  @doc """
  Extract context from response text without updating session state.

  Useful for testing or when you only need to analyze text without
  side effects.

  ## Parameters

  - `response` - The text to analyze

  ## Returns

  - Map of extracted context key-value pairs

  ## Examples

      iex> ResponseProcessor.extract_context("Working on lib/app.ex using Phoenix")
      %{active_file: "lib/app.ex", framework: "Phoenix"}
  """
  @spec extract_context(String.t()) :: map()
  def extract_context(response) when is_binary(response) do
    @context_patterns
    |> Enum.reduce(%{}, fn {key, patterns}, acc ->
      case extract_first_match(response, patterns, key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  def extract_context(_), do: %{}

  @doc """
  Returns the confidence level used for inferred context.
  """
  @spec inferred_confidence() :: float()
  def inferred_confidence, do: @inferred_confidence

  @doc """
  Returns the context patterns used for extraction.

  Useful for testing or extending the patterns.
  """
  @spec context_patterns() :: map()
  def context_patterns, do: @context_patterns

  # =============================================================================
  # Private Functions
  # =============================================================================

  # Extract the first matching value from a list of patterns
  @spec extract_first_match(String.t(), [Regex.t()], atom()) :: String.t() | nil
  defp extract_first_match(text, patterns, key) do
    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, text) do
        [_, match | _] ->
          value = String.trim(match)
          validate_and_normalize(key, value)

        _ ->
          nil
      end
    end)
  end

  # Validate and normalize extracted values based on their type
  @spec validate_and_normalize(atom(), String.t()) :: String.t() | nil
  defp validate_and_normalize(:active_file, value) do
    # File paths should contain at least one path separator or be a simple filename
    if valid_file_path?(value) do
      value
    else
      nil
    end
  end

  defp validate_and_normalize(:primary_language, value) do
    # Normalize language names and validate against known languages
    normalized = String.downcase(value)

    if MapSet.member?(@known_languages, normalized) do
      # Return capitalized version
      String.capitalize(normalized)
    else
      nil
    end
  end

  defp validate_and_normalize(:current_task, value) do
    # Tasks should be reasonably short (not entire paragraphs)
    if String.length(value) <= 100 do
      value
    else
      # Truncate long tasks
      String.slice(value, 0, 97) <> "..."
    end
  end

  defp validate_and_normalize(:framework, value) do
    # Frameworks should start with uppercase
    if String.match?(value, ~r/^[A-Z]/) do
      value
    else
      nil
    end
  end

  defp validate_and_normalize(_key, value), do: value

  # Check if a string looks like a valid file path
  @spec valid_file_path?(String.t()) :: boolean()
  defp valid_file_path?(path) do
    # Must have an extension and reasonable length
    String.length(path) >= 3 and
      String.length(path) <= 256 and
      String.contains?(path, ".") and
      not String.contains?(path, " ") and
      # Must not start with common non-file patterns
      not String.starts_with?(path, "http") and
      not String.starts_with?(path, "www.")
  end

  # Update session working context with extracted values
  @spec update_working_context(map(), String.t()) :: :ok
  defp update_working_context(extractions, session_id) do
    Enum.each(extractions, fn {key, value} ->
      case State.update_context(session_id, key, value,
             source: :inferred,
             confidence: @inferred_confidence
           ) do
        :ok ->
          Logger.debug("ResponseProcessor: Updated #{key} = #{inspect(value)} for session #{session_id}")

        {:error, reason} ->
          Logger.warning("ResponseProcessor: Failed to update #{key}: #{inspect(reason)}")
      end
    end)

    :ok
  end

  # =============================================================================
  # Private Functions - Telemetry
  # =============================================================================

  defp emit_telemetry(session_id, extractions_count, start_time) do
    duration_ms = System.monotonic_time(:millisecond) - start_time

    :telemetry.execute(
      [:jido_code, :memory, :response_process],
      %{duration_ms: duration_ms, extractions: extractions_count},
      %{session_id: session_id}
    )
  end
end
