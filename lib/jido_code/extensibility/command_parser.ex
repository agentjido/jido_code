defmodule JidoCode.Extensibility.CommandParser do
  @moduledoc """
  Parse markdown command definitions with YAML frontmatter into Command structs.

  This module handles parsing markdown files that define commands. The markdown
  files use YAML frontmatter for metadata and the markdown body becomes the
  system prompt for the command.

  ## Frontmatter Schema

  ### Required Fields

  - `name` (string): Command identifier (kebab-case, unique)
  - `description` (string): Human-readable description

  ### Optional Fields

  - `model` (string): LLM model identifier (default: from config)
  - `tools` (list of string): Allowed tool names (default: [])

  ### Nested `jido` Section

  - `jido.schema` (map): NimbleOptions schema definition for command parameters
  - `jido.channels` (map): Channel broadcasting configuration
  - `jido.signals` (map): Signal emit/subscribe configuration

  ## Example

  ```markdown
  ---
  name: commit
  description: Create a git commit with a generated message
  model: anthropic:claude-sonnet-4-20250514
  tools:
    - read_file
    - grep

  jido:
    schema:
      message:
        type: string
        default: ""
      amend:
        type: boolean
        default: false
    channels:
      broadcast_to: ["ui_state"]
    signals:
      events:
        on_start: ["commit.started"]
        on_complete: ["commit.completed"]
  ---

  # Git Commit Command

  You are a git commit message generator. Analyze the changes
  and create a concise, descriptive commit message.
  ```

  ## Schema Conversion

  YAML schema definitions are converted to NimbleOptions format:

  | Type | NimbleOptions Type |
  |------|-------------------|
  | `string` | `type: :string` |
  | `integer` | `type: :integer` |
  | `float` | `type: :float` |
  | `boolean` | `type: :boolean` |
  | `atom` | `type: :atom` |
  | `list` | `type: {:list, inner_type}` |

  """

  alias JidoCode.Extensibility.{Command, Parser.Frontmatter}

  @required_fields [:name, :description]

  @doc """
  Parse a markdown file into a Command struct.

  ## Parameters

  - `path` - Path to the markdown command definition file

  ## Returns

  - `{:ok, %Command{}}` - Successfully parsed
  - `{:error, reason}` - Parse failed

  ## Examples

      iex> {:ok, command} = CommandParser.parse_file("/path/to/command.md")
      iex> command.name
      "commit"

      iex> {:error, :no_frontmatter} = CommandParser.parse_file("/path/to/bad.md")

  """
  @spec parse_file(String.t()) :: {:ok, Command.t()} | {:error, term()}
  def parse_file(path) when is_binary(path) do
    with {:ok, content} <- File.read(path),
         {:ok, frontmatter, body} <- Frontmatter.parse_frontmatter(content),
         :ok <- Frontmatter.validate_required(frontmatter, @required_fields),
         {:ok, command_attrs} <- build_command_attrs(frontmatter, body, path) do
      Command.new(command_attrs)
    end
  end

  @doc """
  Parse markdown content with frontmatter (delegates to Frontmatter module).

  ## Parameters

  - `content` - Markdown file content

  ## Returns

  - `{:ok, frontmatter_map, body}` - Successfully parsed
  - `{:error, :no_frontmatter}` - No frontmatter found
  - `{:error, {:yaml_parse_error, reason}}` - YAML parsing failed
  - `{:error, {:missing_required, fields}}` - Required fields missing

  """
  @spec parse_frontmatter(String.t()) :: {:ok, map(), String.t()} | {:error, term()}
  def parse_frontmatter(content), do: Frontmatter.parse_frontmatter(content)

  @doc """
  Convert YAML schema definition to NimbleOptions schema.

  ## Parameters

  - `schema_yaml` - Map from parsed YAML frontmatter

  ## Returns

  - `{:ok, schema_list}` - Converted to NimbleOptions-style schema list
  - `{:error, reason}` - Invalid schema definition

  """
  @spec parse_schema(map() | nil) :: {:ok, keyword()} | {:error, term()}
  def parse_schema(schema_yaml), do: Frontmatter.parse_schema(schema_yaml)

  @doc """
  Check if a string has valid frontmatter structure.

  ## Examples

      iex> CommandParser.has_frontmatter?(~s(---\nname: test\n---\nbody))
      true

      iex> CommandParser.has_frontmatter?("no frontmatter")
      false

  """
  @spec has_frontmatter?(String.t()) :: boolean()
  def has_frontmatter?(content), do: Frontmatter.has_frontmatter?(content)

  # ============================================================================
  # Module Generation
  # ============================================================================

  @doc """
  Generates a Jido.Action module from a Command struct.

  Uses `Module.create/3` to dynamically create a module that uses the
  Command macro with the configuration from the parsed command definition.

  ## Parameters

  - `command` - A %Command{} struct from parse_file/1

  ## Returns

  - `{:ok, module}` - Successfully created module
  - `{:error, reason}` - Module creation failed

  ## Examples

      {:ok, command} = CommandParser.parse_file("/path/to/command.md")
      {:ok, module} = CommandParser.generate_module(command)
      # => {:ok, JidoCode.Extensibility.Commands.Commit}

      # Execute the command action
      {:ok, result, directives} = module.run(%{}, %{})

  """
  @spec generate_module(Command.t()) :: {:ok, module()} | {:error, term()}
  def generate_module(%Command{name: name} = command) do
    module_name = Command.module_name(name)

    # Build the macro options from the Command struct
    opts = build_macro_opts(command)

    # Generate the module code using a quoted expression
    module_contents = quote do
      use JidoCode.Extensibility.Command, unquote(opts)
    end

    # Create the module - Module.create returns a tuple starting with :module
    try do
      file = __ENV__.file
      line = __ENV__.line

      result = Module.create(module_name, module_contents, file: file, line: line)

      case result do
        {:module, actual_module, _binary, _extra} when is_atom(actual_module) ->
          {:ok, actual_module}

        {:module, actual_module, _binary} when is_atom(actual_module) ->
          {:ok, actual_module}

        {:error, reason} ->
          {:error, {:module_creation_failed, reason}}

        other ->
          {:error, {:unexpected_result, other}}
      end
    rescue
      e -> {:error, {:module_creation_error, Exception.message(e)}}
    end
  end

  @doc """
  Parses a markdown file and generates a module in one step.

  ## Parameters

  - `path` - Path to the markdown command definition file

  ## Returns

  - `{:ok, module}` - Successfully created module
  - `{:error, reason}` - Parse or module creation failed

  ## Examples

      {:ok, module} = CommandParser.load_and_generate("/path/to/command.md")
      {:ok, result, directives} = module.run(%{}, %{})

  """
  @spec load_and_generate(String.t()) :: {:ok, module()} | {:error, term()}
  def load_and_generate(path) when is_binary(path) do
    with {:ok, %Command{} = command} <- parse_file(path),
         {:ok, module} <- generate_module(command) do
      {:ok, module}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp build_command_attrs(frontmatter, body, source_path) do
    jido_config = Map.get(frontmatter, "jido", %{})

    {:ok, schema} =
      jido_config
      |> Map.get("schema")
      |> parse_schema()

    # Build attrs map
    base_attrs = %{
      name: Map.get(frontmatter, "name"),
      description: Map.get(frontmatter, "description"),
      tools: Map.get(frontmatter, "tools", []),
      prompt: body,
      schema: schema,
      channels: Frontmatter.parse_channels(Map.get(jido_config, "channels", %{})),
      signals: Frontmatter.parse_signals(Map.get(jido_config, "signals", %{})),
      source_path: source_path
    }

    # Add optional fields only if present
    base_attrs =
      base_attrs
      |> maybe_put_attr(:model, Map.get(frontmatter, "model"))

    {:ok, base_attrs}
  end

  defp maybe_put_attr(attrs, _key, nil), do: attrs
  defp maybe_put_attr(attrs, key, value), do: Map.put(attrs, key, value)

  # Build the keyword list options for the Command macro
  defp build_macro_opts(%Command{
    name: name,
    description: description,
    prompt: prompt,
    schema: schema,
    tools: tools,
    channels: channels,
    signals: signals
  }) do
    # Sanitize name for Jido.Action (replace hyphens with underscores)
    # Jido.Action requires names with only letters, numbers, and underscores
    sanitized_name = name |> String.replace("-", "_") |> String.replace(" ", "_")

    base_opts = [
      {:name, sanitized_name},
      {:description, description},
      {:system_prompt, prompt},
      {:schema, schema},
      {:tools, tools},
      {:channels, channels},
      {:signals, signals}
    ]

    # Remove nil values from opts
    Enum.reject(base_opts, fn {_key, value} -> is_nil(value) end)
  end
end
