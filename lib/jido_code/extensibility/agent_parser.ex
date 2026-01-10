defmodule JidoCode.Extensibility.AgentParser do
  @moduledoc """
  Parse markdown agent definitions with YAML frontmatter into SubAgent structs.

  This module handles parsing markdown files that define sub-agents. The markdown
  files use YAML frontmatter for metadata and the markdown body becomes the
  system prompt.

  ## Frontmatter Schema

  ### Required Fields

  - `name` (string): Agent identifier (kebab-case, unique)
  - `description` (string): Human-readable description

  ### Optional Fields

  - `model` (string): LLM model identifier (default: from config)
  - `temperature` (float): LLM temperature 0.0-1.0 (default: 0.7)
  - `max_tokens` (integer): Maximum tokens per response (default: 4096)
  - `tools` (list of string): Allowed tool names (default: [])

  ### Nested `jido` Section

  - `jido.schema` (map): NimbleOptions schema definition for agent state
  - `jido.channels` (map): Channel broadcasting configuration
  - `jido.signals` (map): Signal emit/subscribe configuration

  ## Example

  ```markdown
  ---
  name: code_reviewer
  description: Reviews code for security and performance issues
  model: anthropic:claude-sonnet-4-20250514
  temperature: 0.3
  tools:
    - read_file
    - grep

  jido:
    schema:
      review_depth:
        type: atom
        default: standard
      focus_areas:
        type: list
        item_type: string
        default: [security]
    channels:
      broadcast_to: ["ui_state"]
    signals:
      events:
        on_start: ["agent.started"]
        on_complete: ["review.completed"]
  ---

  # Code Reviewer Agent

  You are a specialized code reviewer focused on:
  - Security vulnerabilities
  - Performance issues
  - Code quality concerns
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

  alias JidoCode.Extensibility.{SubAgent, Parser.Frontmatter}

  @required_fields [:name, :description]

  @doc """
  Parse a markdown file into a SubAgent struct.

  ## Parameters

  - `path` - Path to the markdown agent definition file

  ## Returns

  - `{:ok, %SubAgent{}}` - Successfully parsed
  - `{:error, reason}` - Parse failed

  ## Examples

      iex> {:ok, sub_agent} = AgentParser.parse_file("/path/to/agent.md")
      iex> sub_agent.name
      "code_reviewer"

      iex> {:error, :no_frontmatter} = AgentParser.parse_file("/path/to/bad.md")

  """
  @spec parse_file(String.t()) :: {:ok, SubAgent.t()} | {:error, term()}
  def parse_file(path) when is_binary(path) do
    with {:ok, content} <- File.read(path),
         {:ok, frontmatter, body} <- parse_frontmatter(content),
         {:ok, sub_agent_attrs} <- build_sub_agent_attrs(frontmatter, body, path) do
      SubAgent.new(sub_agent_attrs)
    end
  end

  @doc """
  Parse markdown content with frontmatter.

  Validates that required fields are present after parsing.

  ## Parameters

  - `content` - Markdown file content

  ## Returns

  - `{:ok, frontmatter_map, body}` - Successfully parsed
  - `{:error, :no_frontmatter}` - No frontmatter found
  - `{:error, {:yaml_parse_error, reason}}` - YAML parsing failed
  - `{:error, {:missing_required, fields}}` - Required fields missing

  """
  @spec parse_frontmatter(String.t()) :: {:ok, map(), String.t()} | {:error, term()}
  def parse_frontmatter(content) do
    with {:ok, frontmatter, body} <- Frontmatter.parse_frontmatter(content),
         :ok <- Frontmatter.validate_required(frontmatter, @required_fields) do
      {:ok, frontmatter, body}
    end
  end

  @doc """
  Convert YAML schema definition to NimbleOptions schema (delegates to Frontmatter module).

  ## Parameters

  - `schema_yaml` - Map from parsed YAML frontmatter

  ## Returns

  - `{:ok, schema_list}` - Converted to NimbleOptions-style schema list
  - `{:error, reason}` - Invalid schema definition

  """
  @spec parse_zoi_schema(map() | nil) :: {:ok, keyword()} | {:error, term()}
  def parse_zoi_schema(schema_yaml), do: Frontmatter.parse_schema(schema_yaml)

  @doc """
  Check if a string has valid frontmatter structure (delegates to Frontmatter module).

  ## Examples

      iex> AgentParser.has_frontmatter?(~s(---\nname: test\n---\nbody))
      true

      iex> AgentParser.has_frontmatter?("no frontmatter")
      false

  """
  @spec has_frontmatter?(String.t()) :: boolean()
  def has_frontmatter?(content), do: Frontmatter.has_frontmatter?(content)

  # ============================================================================
  # Module Generation
  # ============================================================================

  @doc """
  Generates a Jido.Agent module from a SubAgent struct.

  Uses `Module.create/3` to dynamically create a module that uses the
  SubAgent macro with the configuration from the parsed agent definition.

  ## Parameters

  - `sub_agent` - A %SubAgent{} struct from parse_file/1

  ## Returns

  - `{:ok, module}` - Successfully created module
  - `{:error, reason}` - Module creation failed

  ## Examples

      {:ok, sub_agent} = AgentParser.parse_file("/path/to/agent.md")
      {:ok, module} = AgentParser.generate_module(sub_agent)
      # => {:ok, JidoCode.Extensibility.Agents.CodeReviewer}

      # Create an agent instance
      {:ok, agent} = module.new()

  """
  @spec generate_module(SubAgent.t()) :: {:ok, module()} | {:error, term()}
  def generate_module(%SubAgent{name: name} = sub_agent) do
    module_name = SubAgent.module_name(name)

    # Build the macro options from the SubAgent struct
    opts = build_macro_opts(sub_agent)

    # Generate the module code using a quoted expression
    module_contents = quote do
      use JidoCode.Extensibility.SubAgent, unquote(opts)
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

  - `path` - Path to the markdown agent definition file

  ## Returns

  - `{:ok, module}` - Successfully created module
  - `{:error, reason}` - Parse or module creation failed

  ## Examples

      {:ok, module} = AgentParser.load_and_generate("/path/to/agent.md")
      {:ok, agent} = module.new()

  """
  @spec load_and_generate(String.t()) :: {:ok, module()} | {:error, term()}
  def load_and_generate(path) when is_binary(path) do
    with {:ok, %SubAgent{} = sub_agent} <- parse_file(path),
         {:ok, module} <- generate_module(sub_agent) do
      {:ok, module}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp build_sub_agent_attrs(frontmatter, body, source_path) do
    jido_config = Map.get(frontmatter, "jido", %{})

    {:ok, schema} =
      jido_config
      |> Map.get("schema")
      |> parse_zoi_schema()

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
      |> maybe_put_attr(:temperature, Map.get(frontmatter, "temperature"))
      |> maybe_put_attr(:max_tokens, Map.get(frontmatter, "max_tokens"))

    {:ok, base_attrs}
  end

  defp maybe_put_attr(attrs, _key, nil), do: attrs
  defp maybe_put_attr(attrs, key, value), do: Map.put(attrs, key, value)

  # Build the keyword list options for the SubAgent macro
  defp build_macro_opts(%SubAgent{
    name: name,
    description: description,
    prompt: prompt,
    schema: schema,
    tools: tools,
    channels: channels,
    signals: signals
  }) do
    # Sanitize name for Jido.Agent (replace hyphens with underscores)
    # Jido.Agent requires names with only letters, numbers, and underscores
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
