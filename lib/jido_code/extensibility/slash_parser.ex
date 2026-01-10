defmodule JidoCode.Extensibility.SlashParser do
  @moduledoc """
  Parse slash command strings into structured command data.

  This module parses slash commands like `/commit --amend -m "fix bug"` into
  a structured format that can be executed by the CommandDispatcher.

  ## Supported Syntax

  - `/command` - Command only
  - `/command arg1 arg2` - With positional arguments
  - `/command --flag value` - With long flag
  - `/command -f value` - With short flag
  - `/command "quoted string"` - With quoted string
  - `/commit --amend -m "fix bug" src/` - Combined syntax

  ## Examples

      iex> SlashParser.parse("/commit")
      {:ok, %ParsedCommand{command: "commit", args: [], flags: %{}}}

      iex> SlashParser.parse("/review --mode strict file.ex")
      {:ok, %ParsedCommand{command: "review", args: ["file.ex"], flags: %{"mode" => "strict"}}}

      iex> SlashParser.parse(~s(/commit -m "fix bug"))
      {:ok, %ParsedCommand{command: "commit", args: [], flags: %{"m" => "fix bug"}}}

  """

  defmodule ParsedCommand do
    @moduledoc """
    Struct representing a parsed slash command.

    ## Fields

    - `:command` - The command name (without the slash)
    - `:args` - List of positional arguments (strings)
    - `:flags` - Map of flag names to their values
    - `:raw` - The original input string
    """

    @type t :: %__MODULE__{
      command: String.t(),
      args: [String.t()],
      flags: %{String.t() => String.t() | boolean()},
      raw: String.t()
    }

    defstruct [:command, args: [], flags: %{}, raw: nil]
  end

  @type parse_result :: {:ok, ParsedCommand.t()} | {:error, term()}

  @doc """
  Parse a slash command string into a ParsedCommand struct.

  ## Parameters

  - `input` - The slash command string to parse

  ## Returns

  - `{:ok, %ParsedCommand{}}` - Successfully parsed
  - `{:error, reason}` - Parse failed

  ## Examples

      iex> {:ok, cmd} = SlashParser.parse("/commit")
      iex> cmd.command
      "commit"

      iex> {:ok, cmd} = SlashParser.parse("/review --mode strict")
      iex> cmd.flags
      %{"mode" => "strict"}

  """
  @spec parse(String.t()) :: parse_result()
  def parse(input) when is_binary(input) do
    trimmed = String.trim(input)

    cond do
      not String.starts_with?(trimmed, "/") ->
        {:error, :not_a_slash_command}

      trimmed == "/" ->
        {:error, :empty_command}

      true ->
        do_parse(trimmed)
    end
  end

  @doc """
  Quick check if a string appears to be a slash command.

  ## Examples

      iex> SlashParser.slash_command?("/commit")
      true

      iex> SlashParser.slash_command?("commit")
      false

  """
  @spec slash_command?(String.t()) :: boolean()
  def slash_command?(input) when is_binary(input) do
    String.starts_with?(String.trim(input), "/")
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp do_parse(input) do
    # Remove leading slash
    rest = String.slice(input, 1..-1//1)

    # Tokenize the input (handles quoted strings)
    case tokenize(rest) do
      {:ok, tokens} ->
        # Separate command name from arguments/flags
        {command_name, remaining} = extract_command_name(tokens)

        # Parse flags and arguments
        {flags, args} = parse_flags_and_args(remaining)

        {:ok,
         %ParsedCommand{
           command: command_name,
           args: args,
           flags: flags,
           raw: input
         }}

      {:error, _} = error ->
        error
    end
  end

  # Extract command name (first token, can't start with -)
  defp extract_command_name([]), do: {"", []}

  defp extract_command_name([first | rest]) do
    if String.starts_with?(first, "-") do
      {"", [first | rest]}
    else
      {first, rest}
    end
  end

  # Parse flags and arguments from remaining tokens
  # Flags start with -- (long) or - (short)
  defp parse_flags_and_args(tokens) do
    parse_flags_and_args(tokens, %{}, [])
  end

  defp parse_flags_and_args([], flags, args), do: {flags, Enum.reverse(args)}

  defp parse_flags_and_args([token | rest], flags, args) do
    cond do
      # Long flag: --flag value
      String.starts_with?(token, "--") ->
        flag_name = String.slice(token, 2..-1//1)

        case rest do
          [value | remaining] ->
            if String.starts_with?(value, "-") do
              # Next token is a flag, treat this as boolean
              parse_flags_and_args(rest, Map.put(flags, flag_name, true), args)
            else
              parse_flags_and_args(remaining, Map.put(flags, flag_name, value), args)
            end

          [] ->
            # No value, treat as boolean true
            parse_flags_and_args([], Map.put(flags, flag_name, true), args)
        end

      # Short flag: -f value (or -f as boolean)
      String.starts_with?(token, "-") and byte_size(token) > 1 ->
        flag_name = String.slice(token, 1..1//1)

        case rest do
          [value | remaining] ->
            if String.starts_with?(value, "-") do
              # Next token is a flag, treat this as boolean
              parse_flags_and_args(rest, Map.put(flags, flag_name, true), args)
            else
              # For short flags, value can be directly attached: -fvalue
              parse_flags_and_args(remaining, Map.put(flags, flag_name, value), args)
            end

          [] ->
            # No value, treat as boolean true
            parse_flags_and_args([], Map.put(flags, flag_name, true), args)
        end

      # Positional argument
      true ->
        parse_flags_and_args(rest, flags, [token | args])
    end
  end

  # Tokenize input string, handling quoted strings
  defp tokenize(input) do
    do_tokenize(input, [], false)
  rescue
    _ -> {:error, :tokenization_failed}
  end

  defp do_tokenize("", acc, _in_quotes), do: {:ok, Enum.reverse(acc)}

  defp do_tokenize("\"" <> rest, acc, false) do
    # Start of quoted string
    case String.split(rest, "\"", parts: 2) do
      [quoted, remaining] ->
        do_tokenize(remaining, [quoted | acc], false)

      _ ->
        {:error, :unclosed_quote}
    end
  end

  defp do_tokenize("'" <> rest, acc, false) do
    # Start of single-quoted string
    case String.split(rest, "'", parts: 2) do
      [quoted, remaining] ->
        do_tokenize(remaining, [quoted | acc], false)

      _ ->
        {:error, :unclosed_quote}
    end
  end

  defp do_tokenize(<<c::utf8, rest::binary>>, acc, false) when c in [?\s, ?\t, ?\n] do
    # Whitespace - skip and continue
    do_tokenize(rest, acc, false)
  end

  defp do_tokenize(<<c::utf8, rest::binary>>, acc, false) do
    # Regular character - accumulate until we hit whitespace or quote
    {token, remaining} = accumulate_token(<<c::utf8>> <> rest, "")
    do_tokenize(remaining, [token | acc], false)
  end

  # Accumulate a token until whitespace or quote
  defp accumulate_token(<<>>, acc), do: {acc, ""}

  defp accumulate_token(<<c::utf8, rest::binary>>, acc) when c in [?\s, ?\t, ?\n, ?", ?'] do
    {acc, <<c::utf8>> <> rest}
  end

  defp accumulate_token(<<c::utf8, rest::binary>>, acc) do
    accumulate_token(rest, acc <> <<c::utf8>>)
  end
end
