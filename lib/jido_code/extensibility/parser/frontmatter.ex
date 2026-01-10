defmodule JidoCode.Extensibility.Parser.Frontmatter do
  @moduledoc """
  Shared YAML frontmatter parser for markdown-based definitions.

  This module provides common parsing functionality for extracting and parsing
  YAML frontmatter from markdown files. It is used by both `AgentParser` and
  `CommandParser` to avoid code duplication.

  ## Frontmatter Format

  ```markdown
  ---
  name: my_command
  description: A command description
  optional_field: value
  nested:
    key: value
  ---

  Markdown body content here.
  ```

  ## Features

  - YAML frontmatter extraction
  - Type-aware value parsing (strings, integers, floats, booleans, null, lists)
  - Nested map support
  - List value support
  - Schema conversion to NimbleOptions format
  """

  @frontmatter_regex ~r/\A---\r?\n(.+?)\r?\n---\r?\n(.*)\z/s

  @type frontmatter_map :: %{optional(String.t()) => term()}
  @type parse_result :: {:ok, frontmatter_map(), String.t()} | {:error, term()}

  @doc """
  Parse markdown content with YAML frontmatter.

  ## Parameters

  - `content` - Markdown file content

  ## Returns

  - `{:ok, frontmatter_map, body}` - Successfully parsed
  - `{:error, :no_frontmatter}` - No frontmatter found
  - `{:error, {:yaml_parse_error, reason}}` - YAML parsing failed

  ## Examples

      iex> {:ok, fm, body} = Frontmatter.parse_frontmatter(markdown)
      iex> fm["name"]
      "my_command"

      iex> {:error, :no_frontmatter} = Frontmatter.parse_frontmatter("no frontmatter here")

  """
  @spec parse_frontmatter(String.t()) :: parse_result()
  def parse_frontmatter(content) when is_binary(content) do
    case Regex.run(@frontmatter_regex, content) do
      [_, yaml, body] ->
        case parse_yaml(yaml) do
          {:ok, frontmatter} ->
            {:ok, frontmatter, String.trim(body)}

          {:error, _reason} = error ->
            error
        end

      nil ->
        {:error, :no_frontmatter}
    end
  end

  @doc """
  Check if a string has valid frontmatter structure.

  ## Examples

      iex> Frontmatter.has_frontmatter?(~s(---\nname: test\n---\nbody))
      true

      iex> Frontmatter.has_frontmatter?("no frontmatter")
      false

  """
  @spec has_frontmatter?(String.t()) :: boolean()
  def has_frontmatter?(content) when is_binary(content) do
    Regex.match?(@frontmatter_regex, content)
  end

  @doc """
  Validate that required fields are present in frontmatter.

  ## Parameters

  - `frontmatter` - The frontmatter map
  - `required` - List of required field names (strings or atoms)

  ## Returns

  - `:ok` - All required fields present
  - `{:error, {:missing_required, [field_names]}}` - Missing fields

  """
  @spec validate_required(frontmatter_map(), [atom() | String.t()]) :: :ok | {:error, term()}
  def validate_required(frontmatter, required) when is_map(frontmatter) and is_list(required) do
    string_keys = Enum.map(required, &to_string/1)

    missing =
      string_keys
      |> Enum.reject(fn key -> Map.has_key?(frontmatter, key) and frontmatter[key] != "" end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_required, missing}}
    end
  end

  @doc """
  Convert YAML schema definition to NimbleOptions-style schema list.

  Supports basic types: string, integer, float, boolean, atom, list

  ## Schema Format

  ```yaml
  schema:
    field_name:
      type: string
      default: "value"
    another_field:
      type: atom
      default: standard
    list_field:
      type: list
      item_type: string
      default: [a, b]
  ```

  ## Returns

  - `{:ok, schema_list}` - Converted to NimbleOptions-style schema list
  - `{:error, reason}` - Invalid schema definition

  """
  @spec parse_schema(map() | nil) :: {:ok, keyword()} | {:error, term()}
  def parse_schema(nil), do: {:ok, []}

  def parse_schema(schema_yaml) when is_map(schema_yaml) do
    try do
      schema =
        Enum.map(schema_yaml, fn {field_name, field_config} ->
          parse_field_config(field_name, field_config)
        end)

      {:ok, schema}
    rescue
      e -> {:error, {:schema_parse_error, Exception.message(e)}}
    end
  end

  @doc """
  Parse jido.channels configuration from frontmatter.

  Converts string keys to atoms for keyword list compatibility.

  ## Examples

      iex> {:ok, channels} = Frontmatter.parse_channels(%{"broadcast_to" => ["ui_state"]})
      iex> channels
      [broadcast_to: ["ui_state"]]

  """
  @spec parse_channels(map()) :: keyword()
  def parse_channels(channels) when is_map(channels) do
    for {key, value} <- channels, into: [] do
      key_atom = String.to_existing_atom(key)
      {key_atom, normalize_value(value)}
    end
  rescue
    _ -> []
  end

  def parse_channels(_), do: []

  @doc """
  Parse jido.signals configuration from frontmatter.

  Converts string keys to atoms and normalizes nested structures.

  ## Examples

      iex> {:ok, signals} = Frontmatter.parse_signals(%{"emit" => ["cmd.done"], "events" => %{"on_start" => ["cmd.started"]}})
      iex> signals
      [emit: ["cmd.done"], events: [on_start: ["cmd.started"]]]

  """
  @spec parse_signals(map()) :: keyword()
  def parse_signals(signals) when is_map(signals) do
    for {key, value} <- signals, into: [] do
      key_atom = String.to_existing_atom(key)
      normalized_value = normalize_signal_value(value)
      {key_atom, normalized_value}
    end
  rescue
    _ -> []
  end

  def parse_signals(_), do: []

  # ============================================================================
  # YAML Parsing
  # ============================================================================

  defp parse_yaml(yaml_string) do
    try do
      result = parse_yaml_lines(yaml_string)
      {:ok, result}
    rescue
      e -> {:error, {:yaml_parse_error, Exception.message(e)}}
    end
  end

  # Simple YAML parser for frontmatter
  defp parse_yaml_lines(yaml_string) do
    lines = String.split(yaml_string, "\n")
    do_parse_yaml(lines, %{}, 0)
  end

  defp do_parse_yaml([], acc, _indent), do: acc

  defp do_parse_yaml([line | rest], acc, base_indent) do
    trimmed = String.trim(line)
    indent = count_indent(line)

    cond do
      # Skip empty lines and comments
      trimmed == "" or String.starts_with?(trimmed, "#") ->
        do_parse_yaml(rest, acc, base_indent)

      # Key-value pair
      String.contains?(trimmed, ":") and not String.starts_with?(trimmed, "-") ->
        [key | value_parts] = String.split(trimmed, ":", parts: 2)
        key = String.trim(key)
        raw_value = Enum.join(value_parts, ":") |> String.trim()

        handle_yaml_key_value(rest, acc, base_indent, indent, key, raw_value)

      true ->
        do_parse_yaml(rest, acc, base_indent)
    end
  end

  defp handle_yaml_key_value(rest, acc, base_indent, indent, key, raw_value) do
    if raw_value == "" do
      # Check if the next line is a list item
      next_line = Enum.find(rest, fn line -> String.trim(line) != "" end)
      is_list = next_line && String.starts_with?(String.trim(next_line), "- ")

      if is_list do
        # Collect list items for this key
        {list_values, remaining} = collect_yaml_list(rest, indent)
        do_parse_yaml(remaining, Map.put(acc, key, list_values), base_indent)
      else
        # Nested map - collect and parse recursively
        {nested_lines, remaining} = collect_yaml_nested(rest, indent)
        nested_value = do_parse_yaml(nested_lines, %{}, indent)
        do_parse_yaml(remaining, Map.put(acc, key, nested_value), base_indent)
      end
    else
      parsed_value = parse_yaml_value(raw_value)
      do_parse_yaml(rest, Map.put(acc, key, parsed_value), base_indent)
    end
  end

  defp collect_yaml_list(lines, base_indent) do
    # Collect all list items at this indent level
    {list_lines, remaining} =
      Enum.split_while(lines, fn line ->
        trimmed = String.trim(line)
        indent = count_indent(line)
        trimmed == "" or (String.starts_with?(trimmed, "- ") and indent > base_indent)
      end)

    # Parse the list items
    list_values =
      list_lines
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.map(fn line ->
        value = String.trim_leading(String.trim(line), "- ")
        parse_yaml_value(value)
      end)

    {list_values, remaining}
  end

  defp collect_yaml_nested(lines, parent_indent) do
    Enum.split_while(lines, fn line ->
      trimmed = String.trim(line)
      indent = count_indent(line)
      trimmed == "" or indent > parent_indent
    end)
  end

  defp count_indent(line) do
    line
    |> String.graphemes()
    |> Enum.take_while(&(&1 == " "))
    |> length()
  end

  defp parse_yaml_value(str) do
    cond do
      str == "" -> ""
      str == "true" -> true
      str == "false" -> false
      str == "null" or str == "~" -> nil
      String.starts_with?(str, "[") and String.ends_with?(str, "]") -> parse_inline_list(str)
      String.starts_with?(str, "\"") and String.ends_with?(str, "\"") ->
        String.slice(str, 1..-2//1)
      String.starts_with?(str, "'") and String.ends_with?(str, "'") ->
        String.slice(str, 1..-2//1)
      match?({_, ""}, Integer.parse(str)) -> String.to_integer(str)
      match?({_, ""}, Float.parse(str)) -> String.to_float(str)
      true -> str
    end
  end

  defp parse_inline_list(str) do
    str
    |> String.slice(1..-2//1)
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse_yaml_value/1)
  end

  # ============================================================================
  # Schema Field Parsing
  # ============================================================================

  defp parse_field_config(field_name, field_config) when is_map(field_config) do
    type = Map.get(field_config, "type", "string")
    default = Map.get(field_config, "default")

    field_opts = build_field_opts(type, field_config)

    field_opts =
      if default != nil do
        [{:default, default} | field_opts]
      else
        field_opts
      end

    {String.to_atom(field_name), field_opts}
  end

  defp build_field_opts("string", _config), do: [type: :string]
  defp build_field_opts("integer", _config), do: [type: :integer]
  defp build_field_opts("float", _config), do: [type: :float]
  defp build_field_opts("boolean", _config), do: [type: :boolean]

  defp build_field_opts("atom", config) do
    case Map.get(config, "values") do
      values when is_list(values) -> [type: {:in, values}]
      _ -> [type: :atom]
    end
  end

  defp build_field_opts("list", config) do
    item_type = Map.get(config, "item_type", "string")

    inner_type =
      case item_type do
        "string" -> :string
        "integer" -> :integer
        "atom" -> :atom
        _ -> :any
      end

    [type: {:list, inner_type}]
  end

  defp build_field_opts(_type, _config), do: [type: :string]

  # ============================================================================
  # Value Normalization
  # ============================================================================

  defp normalize_signal_value(value) when is_map(value) do
    for {k, v} <- value, into: [] do
      key = String.to_existing_atom(k)
      {key, normalize_value(v)}
    end
  rescue
    _ -> normalize_value(value)
  end

  defp normalize_signal_value(value), do: normalize_value(value)

  defp normalize_value(value) when is_list(value) do
    Enum.map(value, fn
      v when is_map(v) -> normalize_value(v)
      v when is_list(v) -> Enum.map(v, &normalize_value/1)
      v -> v
    end)
  end

  defp normalize_value(value) when is_map(value) do
    for {k, v} <- value, into: %{} do
      key = if is_atom(k), do: k, else: String.to_atom(k)
      {key, normalize_value(v)}
    end
  end

  defp normalize_value(value), do: value
end
