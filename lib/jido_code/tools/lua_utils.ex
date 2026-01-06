defmodule JidoCode.Tools.LuaUtils do
  @moduledoc """
  Shared utilities for Lua/Luerl integration.

  This module provides common functions for:
  - String escaping for Lua literals
  - Lua table encoding/decoding
  - Result parsing from Luerl calls

  ## String Escaping

  Lua strings require escaping of special characters. Use `escape_string/1`
  to safely embed user input in Lua code:

      iex> LuaUtils.escape_string("hello\\nworld")
      "hello\\\\nworld"

  For complete Lua string literals (with quotes), use `encode_string/1`:

      iex> LuaUtils.encode_string("hello")
      "\"hello\""

  ## Result Parsing

  Luerl returns results in a specific format. Use the parsing helpers
  to convert to standard Elixir `{:ok, _}` / `{:error, _}` tuples:

      iex> LuaUtils.parse_lua_result({:ok, [42], state})
      {:ok, 42}

      iex> LuaUtils.parse_lua_result({:ok, [nil, "error"], state})
      {:error, "error"}
  """

  alias JidoCode.ErrorFormatter

  # ============================================================================
  # String Escaping
  # ============================================================================

  @doc """
  Escapes special characters in a string for use in Lua code.

  Handles the following escape sequences:
  - `\\` → `\\\\`
  - `"` → `\\"`
  - `\\n` → `\\\\n`
  - `\\r` → `\\\\r`
  - `\\t` → `\\\\t`

  ## Parameters

  - `str` - The string to escape

  ## Returns

  The escaped string (without surrounding quotes).

  ## Examples

      iex> LuaUtils.escape_string("hello")
      "hello"

      iex> LuaUtils.escape_string("line1\\nline2")
      "line1\\\\nline2"

      iex> LuaUtils.escape_string("say \\"hello\\"")
      "say \\\\\\"hello\\\\\\""
  """
  @spec escape_string(String.t()) :: String.t()
  def escape_string(str) when is_binary(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  @doc """
  Encodes a string as a Lua string literal with surrounding quotes.

  ## Parameters

  - `str` - The string to encode

  ## Returns

  The string as a Lua literal: `"escaped_content"`.

  ## Examples

      iex> LuaUtils.encode_string("hello")
      "\\"hello\\""

      iex> LuaUtils.encode_string("line1\\nline2")
      "\\"line1\\\\nline2\\""
  """
  @spec encode_string(String.t()) :: String.t()
  def encode_string(str) when is_binary(str) do
    "\"#{escape_string(str)}\""
  end

  # ============================================================================
  # Result Parsing
  # ============================================================================

  @doc """
  Parses a Luerl execution result into a standard Elixir result tuple.

  Handles the common patterns:
  - `{:ok, [nil, error_msg], state}` → `{:error, error_msg}`
  - `{:ok, [result], state}` → `{:ok, result}`
  - `{:ok, [], state}` → `{:ok, nil}`
  - `{:error, reason, state}` → `{:error, formatted_reason}`

  ## Parameters

  - `result` - The result tuple from `:luerl.do/2` or `:luerl.call/3`

  ## Returns

  - `{:ok, value}` - On successful execution
  - `{:error, reason}` - On failure

  ## Examples

      iex> LuaUtils.parse_lua_result({:ok, [42], state})
      {:ok, 42}

      iex> LuaUtils.parse_lua_result({:ok, [nil, "not found"], state})
      {:error, "not found"}
  """
  @spec parse_lua_result({:ok, list(), term()} | {:error, term(), term()}) ::
          {:ok, term()} | {:error, term()}
  def parse_lua_result({:ok, [nil, error_msg], _state}) when is_binary(error_msg) do
    {:error, error_msg}
  end

  def parse_lua_result({:ok, [result], _state}) do
    {:ok, result}
  end

  def parse_lua_result({:ok, [], _state}) do
    {:ok, nil}
  end

  def parse_lua_result({:ok, results, _state}) when is_list(results) do
    {:ok, results}
  end

  def parse_lua_result({:error, reason, _state}) do
    {:error, ErrorFormatter.format(reason)}
  end

  @doc """
  Parses a Luerl execution result with exception handling.

  Same as `parse_lua_result/1` but handles exceptions and catch clauses.
  Returns the new Lua state on success for state updates.

  ## Returns

  - `{:ok, value, new_state}` - On success with updated state
  - `{:error, reason}` - On failure

  ## Examples

      result = safe_lua_execute(fn ->
        :luerl.do("return 42", state)
      end)
  """
  @spec safe_lua_execute((-> {:ok, list(), term()} | {:error, term(), term()})) ::
          {:ok, term(), term()} | {:error, term()}
  def safe_lua_execute(fun) when is_function(fun, 0) do
    case fun.() do
      {:ok, [nil, error_msg], _state} when is_binary(error_msg) ->
        {:error, error_msg}

      {:ok, [result], new_state} ->
        {:ok, result, new_state}

      {:ok, [], new_state} ->
        {:ok, nil, new_state}

      {:ok, results, new_state} when is_list(results) ->
        {:ok, results, new_state}

      {:error, reason, _state} ->
        {:error, ErrorFormatter.format(reason)}
    end
  rescue
    e ->
      {:error, Exception.message(e)}
  catch
    kind, reason ->
      {:error, "#{kind}: #{inspect(reason)}"}
  end

  # ============================================================================
  # Table Encoding
  # ============================================================================

  @doc """
  Encodes an Elixir value as a Lua literal.

  Handles:
  - Strings → quoted and escaped
  - Numbers → as-is
  - Booleans → `true` or `false`
  - nil → `nil`
  - Lists → Lua arrays `{1, 2, 3}`
  - Keyword lists → Lua tables `{key = value, ...}`

  ## Examples

      iex> LuaUtils.encode_value("hello")
      "\\"hello\\""

      iex> LuaUtils.encode_value(42)
      "42"

      iex> LuaUtils.encode_value([offset: 10, limit: 50])
      "{offset = 10, limit = 50}"
  """
  @spec encode_value(term()) :: String.t()
  def encode_value(nil), do: "nil"
  def encode_value(true), do: "true"
  def encode_value(false), do: "false"
  def encode_value(num) when is_number(num), do: to_string(num)
  def encode_value(str) when is_binary(str), do: encode_string(str)

  def encode_value(list) when is_list(list) do
    if Keyword.keyword?(list) do
      # Keyword list → Lua table with keys
      items =
        list
        |> Enum.map(fn {k, v} -> "#{k} = #{encode_value(v)}" end)
        |> Enum.join(", ")

      "{#{items}}"
    else
      # Plain list → Lua array
      items =
        list
        |> Enum.map(&encode_value/1)
        |> Enum.join(", ")

      "{#{items}}"
    end
  end

  def encode_value(map) when is_map(map) do
    items =
      map
      |> Enum.map(fn {k, v} -> "[#{encode_value(to_string(k))}] = #{encode_value(v)}" end)
      |> Enum.join(", ")

    "{#{items}}"
  end

  def encode_value(other), do: inspect(other)

  # ============================================================================
  # Git Result Decoding
  # ============================================================================

  @doc """
  Decodes a git command result from Lua table format to Elixir map.

  Git results contain:
  - `"output"` - Command output string
  - `"parsed"` - Parsed structured data (optional)
  - `"exit_code"` - Exit code as float (converted to integer)

  ## Parameters

  - `result` - The Lua table result (list of tuples or table reference)
  - `lua_state` - The Luerl state for decoding table references

  ## Returns

  A map with atom keys: `%{output: string, parsed: map, exit_code: integer}`

  ## Examples

      iex> LuaUtils.decode_git_result([{"output", "..."}, {"exit_code", 0.0}], state)
      %{output: "...", exit_code: 0}
  """
  @spec decode_git_result(list() | {:tref, term()}, term()) :: map()
  def decode_git_result(result, lua_state) when is_list(result) do
    result
    |> Enum.reduce(%{}, fn
      {"output", output}, acc -> Map.put(acc, :output, output)
      {"parsed", parsed}, acc -> Map.put(acc, :parsed, decode_lua_table(parsed, lua_state))
      {"exit_code", code}, acc -> Map.put(acc, :exit_code, trunc(code))
      _, acc -> acc
    end)
  end

  def decode_git_result({:tref, _} = tref, lua_state) do
    decoded = :luerl.decode(tref, lua_state)
    decode_git_result(decoded, lua_state)
  end

  def decode_git_result(other, _lua_state), do: other

  @doc """
  Decodes a Lua table to an Elixir map or list.

  Handles:
  - Tables with string keys → Elixir map with atom keys
  - Tables with integer keys → Elixir list (sorted by key)
  - Table references → Decoded and processed recursively

  ## Parameters

  - `table` - The Lua table (list of tuples or table reference)
  - `lua_state` - The Luerl state for decoding table references

  ## Returns

  A map, list, or the original value if not a table.
  """
  @spec decode_lua_table(term(), term()) :: term()
  def decode_lua_table({:tref, _} = tref, lua_state) do
    decoded = :luerl.decode(tref, lua_state)
    decode_lua_table(decoded, lua_state)
  end

  def decode_lua_table(table, lua_state) when is_list(table) do
    cond do
      # Empty table
      table == [] ->
        %{}

      # Table with string keys → map
      Enum.all?(table, fn {k, _v} -> is_binary(k) end) ->
        table
        |> Enum.reduce(%{}, fn {k, v}, acc ->
          Map.put(acc, String.to_atom(k), decode_lua_table(v, lua_state))
        end)

      # Table with integer keys → list (array)
      Enum.all?(table, fn {k, _v} -> is_integer(k) end) ->
        table
        |> Enum.sort_by(fn {k, _} -> k end)
        |> Enum.map(fn {_, v} -> decode_lua_table(v, lua_state) end)

      # Mixed or other → keep as-is
      true ->
        table
    end
  end

  def decode_lua_table(value, _lua_state), do: value

  @doc """
  Builds a Lua array literal from an Elixir list.

  ## Examples

      iex> LuaUtils.build_lua_array(["--force", "origin", "main"])
      "{\\"--force\\", \\"origin\\", \\"main\\"}"

      iex> LuaUtils.build_lua_array([])
      "{}"
  """
  @spec build_lua_array(list()) :: String.t()
  def build_lua_array([]), do: "{}"

  def build_lua_array(args) when is_list(args) do
    items =
      args
      |> Enum.map(&encode_string/1)
      |> Enum.join(", ")

    "{#{items}}"
  end
end
