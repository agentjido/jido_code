defmodule JidoCode.Commands do
  @moduledoc """
  Parses and executes slash commands from user input.

  Commands allow users to configure the LLM provider and model at runtime
  without restarting the application.

  ## Available Commands

  | Command | Description |
  |---------|-------------|
  | `/help` | List available commands |
  | `/config` | Display current configuration |
  | `/provider <name>` | Set LLM provider (clears model) |
  | `/model <provider>:<model>` | Set both provider and model |
  | `/model <model>` | Set model for current provider |
  | `/models` | List models for current provider (pending) |
  | `/models <provider>` | List models for provider (pending) |
  | `/providers` | List available providers (pending) |

  ## Usage

      alias JidoCode.Commands

      config = %{provider: "anthropic", model: "claude-3-5-sonnet"}

      Commands.execute("/help", config)
      #=> {:ok, "Available commands:\\n...", %{}}

      Commands.execute("/model openai:gpt-4o", config)
      #=> {:ok, "Model set to openai:gpt-4o", %{provider: "openai", model: "gpt-4o"}}

      Commands.execute("/unknown", config)
      #=> {:error, "Unknown command: /unknown. Type /help for available commands."}
  """

  alias Jido.AI.Keyring
  alias Jido.AI.Model.Registry.Adapter, as: RegistryAdapter
  alias JidoCode.Agents.LLMAgent
  alias JidoCode.AgentSupervisor
  alias JidoCode.PubSubTopics
  alias JidoCode.Settings
  alias JidoCode.Tools.Manager

  @pubsub JidoCode.PubSub

  @type config :: %{provider: String.t() | nil, model: String.t() | nil}
  @type result :: {:ok, String.t(), config()} | {:error, String.t()}

  @help_text """
  Available commands:

    /help                    - Show this help message
    /config                  - Display current configuration
    /provider <name>         - Set LLM provider (clears model)
    /model <provider>:<model> - Set both provider and model
    /model <model>           - Set model for current provider
    /models                  - List models for current provider
    /models <provider>       - List models for a specific provider
    /providers               - List available providers
    /theme                   - List available themes
    /theme <name>            - Switch to a theme (dark, light, high_contrast)
    /session                 - Show session command help
    /session new [path]      - Create new session (--name=NAME for custom name)
    /session list            - List all sessions
    /session switch <target> - Switch to session by index, ID, or name
    /session close [target]  - Close session (default: active)
    /session rename <name>   - Rename current session
    /sandbox-test            - Test the Luerl sandbox security (dev/test only)
    /shell <command> [args]  - Run a shell command (e.g., /shell ls -la)
  """

  @doc """
  Executes a slash command and returns the result.

  ## Parameters

  - `command` - The command string starting with `/`
  - `config` - Current configuration map with :provider and :model keys

  ## Returns

  - `{:ok, message, new_config}` - Command executed successfully
  - `{:error, message}` - Command failed

  ## Examples

      iex> Commands.execute("/help", %{provider: nil, model: nil})
      {:ok, "Available commands:...", %{}}

      iex> Commands.execute("/config", %{provider: "anthropic", model: "claude-3-5-sonnet"})
      {:ok, "Provider: anthropic\\nModel: claude-3-5-sonnet", %{}}
  """
  @spec execute(String.t(), config()) :: result()
  def execute(command, config) when is_binary(command) and is_map(config) do
    command
    |> String.trim()
    |> parse_and_execute(config)
  end

  # ============================================================================
  # Command Parsing
  # ============================================================================

  defp parse_and_execute("/help" <> _, _config) do
    {:ok, String.trim(@help_text), %{}}
  end

  defp parse_and_execute("/config" <> _, config) do
    provider = config[:provider] || config["provider"] || "(not set)"
    model = config[:model] || config["model"] || "(not set)"

    message = "Provider: #{provider}\nModel: #{model}"
    {:ok, message, %{}}
  end

  defp parse_and_execute("/provider " <> rest, _config) do
    provider = String.trim(rest)
    execute_provider_command(provider)
  end

  defp parse_and_execute("/provider", _config) do
    {:error, "Usage: /provider <name>\n\nExample: /provider anthropic"}
  end

  defp parse_and_execute("/model " <> rest, config) do
    model_spec = String.trim(rest)
    execute_model_command(model_spec, config)
  end

  defp parse_and_execute("/model", _config) do
    {:error,
     "Usage: /model <provider>:<model> or /model <model>\n\nExamples:\n  /model anthropic:claude-3-5-sonnet\n  /model gpt-4o"}
  end

  defp parse_and_execute("/models " <> rest, _config) do
    provider = String.trim(rest)
    execute_models_command(provider)
  end

  defp parse_and_execute("/models", config) do
    provider = config[:provider] || config["provider"]

    if provider do
      execute_models_command(provider)
    else
      {:error, "No provider set. Use /provider <name> first, or /models <provider>"}
    end
  end

  defp parse_and_execute("/providers" <> _, _config) do
    execute_providers_command()
  end

  defp parse_and_execute("/theme " <> rest, _config) do
    theme_name = String.trim(rest)
    execute_theme_command(theme_name)
  end

  defp parse_and_execute("/theme", _config) do
    execute_theme_list_command()
  end

  defp parse_and_execute("/sandbox-test" <> _, _config) do
    if Mix.env() in [:dev, :test] do
      execute_sandbox_test()
    else
      {:error, "Command /sandbox-test is only available in dev and test environments"}
    end
  end

  defp parse_and_execute("/session " <> rest, _config) do
    {:session, parse_session_args(String.trim(rest))}
  end

  defp parse_and_execute("/session", _config) do
    {:session, :help}
  end

  defp parse_and_execute("/shell " <> rest, _config) do
    execute_shell_command(String.trim(rest))
  end

  defp parse_and_execute("/shell", _config) do
    {:error,
     "Usage: /shell <command> [args]\n\nExamples:\n  /shell ls -la\n  /shell mix test\n  /shell git status"}
  end

  defp parse_and_execute("/" <> command, _config) do
    # Extract just the command name for error message
    command_name = command |> String.split() |> List.first() || command
    {:error, "Unknown command: /#{command_name}. Type /help for available commands."}
  end

  defp parse_and_execute(text, _config) do
    {:error, "Not a command: #{text}. Commands start with /"}
  end

  # ============================================================================
  # Session Command Parsing
  # ============================================================================

  @doc false
  # Parse session subcommand arguments
  # Returns a tuple that the TUI will handle for execution
  defp parse_session_args("new" <> rest) do
    {:new, parse_new_session_args(String.trim(rest))}
  end

  defp parse_session_args("list"), do: :list

  defp parse_session_args("switch " <> target) do
    {:switch, String.trim(target)}
  end

  defp parse_session_args("switch"), do: {:error, :missing_target}

  defp parse_session_args("close" <> rest) do
    case String.trim(rest) do
      "" -> {:close, nil}
      target -> {:close, target}
    end
  end

  defp parse_session_args("rename " <> name) do
    {:rename, String.trim(name)}
  end

  defp parse_session_args("rename"), do: {:error, :missing_name}

  defp parse_session_args(_), do: :help

  # Parse arguments for /session new [path] [--name=NAME]
  defp parse_new_session_args("") do
    %{path: nil, name: nil}
  end

  defp parse_new_session_args(args_string) do
    parts = String.split(args_string, ~r/\s+/)
    parse_new_session_parts(parts, %{path: nil, name: nil})
  end

  defp parse_new_session_parts([], acc), do: acc

  defp parse_new_session_parts(["--name=" <> name | rest], acc) do
    parse_new_session_parts(rest, %{acc | name: name})
  end

  defp parse_new_session_parts(["-n" <> name | rest], acc) when name != "" do
    # Handle -nNAME (no space)
    parse_new_session_parts(rest, %{acc | name: name})
  end

  defp parse_new_session_parts(["-n", name | rest], acc) do
    # Handle -n NAME (with space)
    parse_new_session_parts(rest, %{acc | name: name})
  end

  defp parse_new_session_parts(["--name", name | rest], acc) do
    # Handle --name NAME (with space)
    parse_new_session_parts(rest, %{acc | name: name})
  end

  defp parse_new_session_parts([part | rest], acc) do
    # First non-flag argument is the path
    if acc.path == nil and not String.starts_with?(part, "-") do
      parse_new_session_parts(rest, %{acc | path: part})
    else
      # Ignore unknown flags
      parse_new_session_parts(rest, acc)
    end
  end

  # ============================================================================
  # Path Resolution
  # ============================================================================

  @doc """
  Resolves a path string to an absolute path.

  Handles:
  - `~` expansion to home directory
  - `.` for current working directory
  - `..` for parent directory
  - Relative paths resolved against CWD
  - Absolute paths passed through unchanged

  Returns `{:ok, absolute_path}` or `{:error, reason}`.

  ## Examples

      iex> Commands.resolve_session_path("~/projects")
      {:ok, "/home/user/projects"}

      iex> Commands.resolve_session_path(".")
      {:ok, "/current/working/dir"}

      iex> Commands.resolve_session_path("/absolute/path")
      {:ok, "/absolute/path"}
  """
  @spec resolve_session_path(String.t() | nil) :: {:ok, String.t()} | {:error, String.t()}
  def resolve_session_path(nil) do
    # Default to current working directory
    {:ok, File.cwd!()}
  end

  def resolve_session_path("") do
    {:ok, File.cwd!()}
  end

  def resolve_session_path("~") do
    {:ok, System.user_home!()}
  end

  def resolve_session_path("~/" <> rest) do
    path = Path.join(System.user_home!(), rest)
    {:ok, Path.expand(path)}
  end

  def resolve_session_path("." <> _ = path) do
    # Handles "." and "./something" and "../something"
    {:ok, Path.expand(path)}
  end

  def resolve_session_path("/" <> _ = path) do
    # Absolute path - just expand to resolve any . or .. within
    {:ok, Path.expand(path)}
  end

  def resolve_session_path(path) do
    # Relative path - resolve against CWD
    {:ok, Path.expand(path)}
  end

  @doc """
  Validates that a resolved path exists and is a directory.

  Returns `{:ok, path}` if valid, `{:error, reason}` otherwise.
  """
  @spec validate_session_path(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_session_path(path) do
    cond do
      not File.exists?(path) ->
        {:error, "Path does not exist: #{path}"}

      not File.dir?(path) ->
        {:error, "Path is not a directory: #{path}"}

      true ->
        {:ok, path}
    end
  end

  # ============================================================================
  # Session Command Execution
  # ============================================================================

  @doc """
  Executes a parsed session command.

  Called by the TUI when a `/session` command is parsed. Returns a result
  tuple that the TUI will handle.

  ## Parameters

  - `subcommand` - The parsed session subcommand from `parse_session_args/1`
  - `model` - The TUI model (used for context like active session)

  ## Returns

  - `{:session_action, action}` - Action for TUI to perform
  - `{:ok, message}` - Success message to display
  - `{:error, message}` - Error message to display

  ## Examples

      iex> Commands.execute_session({:new, %{path: "/tmp/project", name: nil}}, model)
      {:session_action, {:add_session, %Session{...}}}

      iex> Commands.execute_session(:list, model)
      {:ok, "1. project-a\\n2. project-b"}
  """
  @spec execute_session(term(), map()) ::
          {:session_action, term()}
          | {:ok, String.t()}
          | {:error, String.t()}

  def execute_session(:help, _model) do
    help = """
    Session Commands:
      /session new [path] [--name=NAME]  Create new session
      /session list                       List all sessions
      /session switch <index|id|name>     Switch to session
      /session close [index|id]           Close session
      /session rename <name>              Rename current session

    Keyboard Shortcuts:
      Ctrl+1 to Ctrl+0  Switch to session 1-10
      Ctrl+Tab          Next session
      Ctrl+Shift+Tab    Previous session
      Ctrl+W            Close current session
      Ctrl+N            New session
    """

    {:ok, String.trim(help)}
  end

  def execute_session({:new, opts}, _model) do
    path = opts[:path] || opts.path
    name = opts[:name] || opts.name

    with {:ok, resolved_path} <- resolve_session_path(path),
         {:ok, validated_path} <- validate_session_path(resolved_path),
         {:ok, session} <- create_new_session(validated_path, name) do
      {:session_action, {:add_session, session}}
    else
      {:error, message} when is_binary(message) ->
        {:error, message}

      {:error, :session_limit_reached} ->
        {:error, "Maximum 10 sessions reached. Close a session first."}

      {:error, :project_already_open} ->
        {:error, "Project already open in another session."}

      {:error, :path_not_found} ->
        {:error, "Path does not exist: #{path}"}

      {:error, :path_not_directory} ->
        {:error, "Path is not a directory: #{path}"}

      {:error, reason} ->
        {:error, "Failed to create session: #{inspect(reason)}"}
    end
  end

  def execute_session(:list, model) do
    # Get sessions in order from the model
    sessions = get_sessions_in_order(model)

    if sessions == [] do
      {:ok, "No sessions. Use /session new to create one."}
    else
      active_id = Map.get(model, :active_session_id)
      output = format_session_list(sessions, active_id)
      {:ok, output}
    end
  end

  def execute_session({:switch, target}, model) do
    case resolve_session_target(target, model) do
      {:ok, session_id} ->
        {:session_action, {:switch_session, session_id}}

      {:error, :not_found} ->
        {:error, "Session not found: #{target}"}

      {:error, :no_sessions} ->
        {:error, "No sessions available. Use /session new to create one."}

      {:error, {:ambiguous, names}} ->
        options = Enum.join(names, ", ")
        {:error, "Ambiguous session name '#{target}'. Did you mean: #{options}?"}
    end
  end

  def execute_session({:close, _target}, _model) do
    # TODO: Implement in Task 5.5.1
    {:error, "Not yet implemented: /session close"}
  end

  def execute_session({:rename, _name}, _model) do
    # TODO: Implement in Task 5.6.1
    {:error, "Not yet implemented: /session rename"}
  end

  def execute_session({:error, :missing_target}, _model) do
    {:error, "Usage: /session switch <index|id|name>"}
  end

  def execute_session({:error, :missing_name}, _model) do
    {:error, "Usage: /session rename <name>"}
  end

  def execute_session(_, _model) do
    execute_session(:help, nil)
  end

  # Helper to create a new session via SessionSupervisor
  defp create_new_session(path, name) do
    opts = [project_path: path]
    opts = if name, do: Keyword.put(opts, :name, name), else: opts
    JidoCode.SessionSupervisor.create_session(opts)
  end

  # Get sessions in order from the model
  defp get_sessions_in_order(model) do
    session_order = Map.get(model, :session_order, [])
    sessions = Map.get(model, :sessions, %{})

    session_order
    |> Enum.map(&Map.get(sessions, &1))
    |> Enum.reject(&is_nil/1)
  end

  # Format session list for display
  # Shows index (1-10), active marker (*), name, and truncated path
  defp format_session_list(sessions, active_id) do
    sessions
    |> Enum.with_index(1)
    |> Enum.map(fn {session, idx} ->
      format_session_line(session, idx, active_id)
    end)
    |> Enum.join("\n")
  end

  defp format_session_line(session, idx, active_id) do
    marker = if session.id == active_id, do: "*", else: " "
    name = Map.get(session, :name, "unnamed")
    path = Map.get(session, :project_path, "")
    truncated = truncate_path(path)

    "#{marker}#{idx}. #{name} (#{truncated})"
  end

  # Truncate long paths to fit display
  # Replaces home directory with ~ and truncates middle if needed
  @max_path_length 40

  defp truncate_path(nil), do: ""
  defp truncate_path(""), do: ""

  defp truncate_path(path) do
    # Replace home directory with ~
    home = System.user_home!()

    path =
      if String.starts_with?(path, home) do
        "~" <> String.replace_prefix(path, home, "")
      else
        path
      end

    # Truncate if still too long
    if String.length(path) > @max_path_length do
      # Keep the last part of the path (most relevant)
      "..." <> String.slice(path, -(min(@max_path_length - 3, String.length(path) - 1))..-1//1)
    else
      path
    end
  end

  # Resolve a session target (index, ID, or name) to a session ID
  defp resolve_session_target(target, model) do
    session_order = Map.get(model, :session_order, [])
    sessions = Map.get(model, :sessions, %{})

    if session_order == [] do
      {:error, :no_sessions}
    else
      cond do
        # Try as index (1-10, with "0" meaning 10)
        is_numeric_target?(target) ->
          resolve_by_index(target, session_order)

        # Try as session ID
        Map.has_key?(sessions, target) ->
          {:ok, target}

        # Try as session name
        true ->
          find_session_by_name(target, sessions)
      end
    end
  end

  defp is_numeric_target?(target) do
    case Integer.parse(target) do
      {_num, ""} -> true
      _ -> false
    end
  end

  defp resolve_by_index(target, session_order) do
    {index, ""} = Integer.parse(target)

    # Handle "0" as index 10 (for Ctrl+0 keyboard shortcut)
    index = if index == 0, do: 10, else: index

    case Enum.at(session_order, index - 1) do
      nil -> {:error, :not_found}
      session_id -> {:ok, session_id}
    end
  end

  defp find_session_by_name(name, sessions) do
    name_lower = String.downcase(name)

    # First try exact match (case-insensitive)
    exact_match =
      Enum.find(sessions, fn {_id, session} ->
        session_name = Map.get(session, :name, "")
        String.downcase(session_name) == name_lower
      end)

    case exact_match do
      {id, _session} ->
        {:ok, id}

      nil ->
        # Fall back to prefix match (case-insensitive)
        find_session_by_prefix(name_lower, sessions)
    end
  end

  defp find_session_by_prefix(prefix, sessions) do
    matches =
      Enum.filter(sessions, fn {_id, session} ->
        session_name = Map.get(session, :name, "")
        String.starts_with?(String.downcase(session_name), prefix)
      end)

    case matches do
      [] ->
        {:error, :not_found}

      [{id, _session}] ->
        {:ok, id}

      multiple ->
        # Multiple matches - return error with options
        names = Enum.map(multiple, fn {_id, s} -> Map.get(s, :name) end)
        {:error, {:ambiguous, names}}
    end
  end

  # ============================================================================
  # Command Execution
  # ============================================================================

  defp execute_provider_command(provider) do
    with :ok <- validate_provider(provider),
         :ok <- validate_api_key(provider) do
      # Save to settings
      Settings.set(:local, "provider", provider)
      Settings.set(:local, "model", nil)

      new_config = %{provider: provider, model: nil}
      {:ok, "Provider set to #{provider}. Use /models to see available models.", new_config}
    end
  end

  defp execute_model_command(model_spec, config) do
    # Format: provider:model
    if String.contains?(model_spec, ":") do
      [provider | rest] = String.split(model_spec, ":", parts: 2)
      model = Enum.join(rest, ":")
      set_provider_and_model(provider, model)
    else
      # Format: model only (requires provider to be set)
      provider = config[:provider] || config["provider"]

      if provider do
        set_model_for_provider(provider, model_spec)
      else
        {:error,
         "No provider set. Use /model <provider>:<model> or set provider first with /provider <name>"}
      end
    end
  end

  defp set_provider_and_model(provider, model) do
    with :ok <- validate_provider(provider),
         :ok <- validate_model(provider, model),
         :ok <- validate_api_key(provider) do
      # Save to settings
      Settings.set(:local, "provider", provider)
      Settings.set(:local, "model", model)

      new_config = %{provider: provider, model: model}

      # Configure running agent if available
      configure_agent(new_config)

      # Broadcast config change
      broadcast_config_change(new_config)

      {:ok, "Model set to #{provider}:#{model}", new_config}
    end
  end

  defp set_model_for_provider(provider, model) do
    with :ok <- validate_model(provider, model),
         :ok <- validate_api_key(provider) do
      Settings.set(:local, "model", model)

      new_config = %{provider: provider, model: model}

      # Configure running agent if available
      configure_agent(new_config)

      # Broadcast config change
      broadcast_config_change(new_config)

      {:ok, "Model set to #{model}", new_config}
    end
  end

  defp execute_models_command(provider) do
    case validate_provider(provider) do
      :ok ->
        models = Settings.get_models(provider)

        if models == [] do
          {:ok, "No models found for provider: #{provider}", %{}}
        else
          # Return pick_list tuple to show interactive model picker
          {:pick_list, provider, models, "Select Model (#{provider})"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_providers_command do
    providers = Settings.get_providers()

    if providers == [] do
      {:ok, "No providers available", %{}}
    else
      # Return pick_list tuple to show interactive provider picker
      # Use :provider as the type to distinguish from model selection
      {:pick_list, :provider, providers, "Select Provider"}
    end
  end

  defp execute_theme_list_command do
    themes = TermUI.Theme.list_builtin()
    current = TermUI.Theme.get_theme()
    current_name = current.name

    theme_list =
      Enum.map_join(themes, "\n  ", fn name ->
        if name == current_name, do: "#{name} (current)", else: "#{name}"
      end)

    {:ok, "Available themes:\n  #{theme_list}", %{}}
  end

  defp execute_theme_command(theme_name) do
    # Convert string to atom safely (only for known themes)
    theme_atom = string_to_theme_atom(theme_name)

    if theme_atom do
      case TermUI.Theme.set_theme(theme_atom) do
        :ok ->
          # Save to settings for persistence
          Settings.set(:local, "theme", theme_name)
          {:ok, "Theme set to #{theme_name}", %{}}

        {:error, :not_found} ->
          available = TermUI.Theme.list_builtin() |> Enum.join(", ")
          {:error, "Unknown theme: #{theme_name}\n\nAvailable themes: #{available}"}

        {:error, reason} ->
          {:error, "Failed to set theme: #{inspect(reason)}"}
      end
    else
      available = TermUI.Theme.list_builtin() |> Enum.join(", ")
      {:error, "Unknown theme: #{theme_name}\n\nAvailable themes: #{available}"}
    end
  end

  # Safe string to theme atom conversion (only allow known themes)
  defp string_to_theme_atom("dark"), do: :dark
  defp string_to_theme_atom("light"), do: :light
  defp string_to_theme_atom("high_contrast"), do: :high_contrast
  defp string_to_theme_atom(_), do: nil

  # ============================================================================
  # Validation
  # ============================================================================

  defp validate_provider(provider) do
    case RegistryAdapter.list_providers() do
      {:ok, providers} ->
        # Use String.to_existing_atom/1 to avoid atom exhaustion from user input
        # Fall back to checking if the string matches a known provider atom
        provider_in_list? =
          Enum.any?(providers, fn p -> Atom.to_string(p) == provider end)

        if provider_in_list? do
          :ok
        else
          # Build helpful error message
          similar = find_similar_providers(provider, providers)

          suggestion =
            if similar != [] do
              "\n\nDid you mean: #{Enum.join(similar, ", ")}?"
            else
              "\n\nUse /providers to see available providers."
            end

          {:error, "Unknown provider: #{provider}#{suggestion}"}
        end

      {:error, _} ->
        # If registry is unavailable, allow any provider
        :ok
    end
  end

  defp validate_model(_provider, _model) do
    # Skip model validation for now - the registry may not have complete model lists
    # and users should be able to use any model their API key supports.
    # The actual validation will happen when the LLM call is made.
    :ok
  end

  # Local providers that don't require API keys
  @local_providers ["lmstudio", "llama", "ollama"]

  defp validate_api_key(provider) when provider in @local_providers do
    # Local providers don't require API keys
    :ok
  end

  defp validate_api_key(provider) do
    key_name = provider_to_key_name(provider)

    case Keyring.get(key_name) do
      nil ->
        # Use generic message - don't expose env var names
        {:error, "Provider #{provider} is not configured. Please set up API credentials."}

      "" ->
        # Use generic message - don't expose env var names
        {:error, "Provider #{provider} has empty credentials. Please configure API credentials."}

      _key ->
        :ok
    end
  end

  # Known provider to API key name mapping
  # This whitelist prevents atom exhaustion from arbitrary user input
  @known_provider_keys %{
    "openai" => :openai_api_key,
    "anthropic" => :anthropic_api_key,
    "openrouter" => :openrouter_api_key,
    "azure" => :azure_api_key,
    "google" => :google_api_key,
    "gemini" => :google_api_key,
    "cohere" => :cohere_api_key,
    "mistral" => :mistral_api_key,
    "groq" => :groq_api_key,
    "together" => :together_api_key,
    "fireworks" => :fireworks_api_key,
    "deepseek" => :deepseek_api_key,
    "perplexity" => :perplexity_api_key,
    "xai" => :xai_api_key,
    "ollama" => :ollama_api_key,
    "cerebras" => :cerebras_api_key,
    "sambanova" => :sambanova_api_key,
    # Local providers (no API key required)
    "lmstudio" => :lmstudio_api_key,
    "llama" => :llama_api_key
  }

  # Map provider names to their keyring key names
  defp provider_to_key_name(provider) do
    # Use whitelist to prevent atom exhaustion from user input
    case Map.get(@known_provider_keys, provider) do
      nil ->
        # For unknown providers, return a generic key (don't create new atoms)
        # This will likely fail API key validation, which is the correct behavior
        :unknown_provider_api_key

      key ->
        key
    end
  end

  # Simple substring matching for suggestions
  defp find_similar_providers(input, providers) do
    input_lower = String.downcase(input)

    providers
    |> Enum.map(&Atom.to_string/1)
    |> Enum.filter(fn p ->
      p_lower = String.downcase(p)
      String.contains?(p_lower, input_lower) or String.contains?(input_lower, p_lower)
    end)
    |> Enum.take(3)
  end

  # ============================================================================
  # Agent Configuration
  # ============================================================================

  defp configure_agent(config) do
    case AgentSupervisor.lookup_agent(:llm_agent) do
      {:ok, pid} ->
        # Configure the running agent with new settings
        LLMAgent.configure(pid,
          provider: config.provider,
          model: config.model
        )

      {:error, :not_found} ->
        # Agent not running - that's OK, it will use settings when started
        :ok
    end
  end

  defp broadcast_config_change(config) do
    Phoenix.PubSub.broadcast(@pubsub, PubSubTopics.tui_events(), {:config_changed, config})
  end

  # ============================================================================
  # Shell Command Execution
  # ============================================================================

  defp execute_shell_command(command_line) do
    case parse_shell_command(command_line) do
      {command, args} ->
        case Manager.shell(command, args) do
          {:ok, %{"exit_code" => 0, "stdout" => stdout, "stderr" => stderr}} ->
            output = format_shell_output(stdout, stderr)
            {:shell_output, command_line, output}

          {:ok, %{"exit_code" => code, "stdout" => stdout, "stderr" => stderr}} ->
            output = format_shell_output(stdout, stderr)
            {:shell_output, command_line, "#{output}\n\n[Exit code: #{code}]"}

          {:error, reason} when is_binary(reason) ->
            {:error, reason}

          {:error, reason} ->
            {:error, "Shell error: #{inspect(reason)}"}
        end

      :error ->
        {:error, "Invalid command format"}
    end
  end

  defp parse_shell_command(command_line) do
    case String.split(command_line, ~r/\s+/, parts: :infinity) do
      [command | args] when command != "" -> {command, args}
      _ -> :error
    end
  end

  defp format_shell_output(stdout, stderr) do
    stdout = String.trim(stdout)
    stderr = String.trim(stderr)

    cond do
      stdout != "" and stderr != "" -> "#{stdout}\n\n[stderr]\n#{stderr}"
      stdout != "" -> stdout
      stderr != "" -> "[stderr]\n#{stderr}"
      true -> "(no output)"
    end
  end

  # ============================================================================
  # Sandbox Testing
  # ============================================================================

  defp execute_sandbox_test do
    results = [
      test_sandbox_read_file(),
      test_sandbox_list_dir(),
      test_sandbox_shell(),
      test_sandbox_lua_script(),
      test_sandbox_security_block()
    ]

    passed = Enum.count(results, fn {status, _, _} -> status == :pass end)
    failed = Enum.count(results, fn {status, _, _} -> status == :fail end)

    output =
      Enum.map_join(results, "\n\n", fn {status, name, detail} ->
        icon = if status == :pass, do: "[OK]", else: "[FAIL]"
        "#{icon} #{name}\n    #{detail}"
      end)

    summary = "\n\nSandbox Test Results: #{passed} passed, #{failed} failed"
    {:ok, output <> summary, %{}}
  end

  defp test_sandbox_read_file do
    case Manager.read_file("mix.exs") do
      {:ok, content} when byte_size(content) > 0 ->
        {:pass, "Read file via sandbox",
         "Successfully read mix.exs (#{byte_size(content)} bytes)"}

      {:ok, _} ->
        {:fail, "Read file via sandbox", "File was empty"}

      {:error, reason} ->
        {:fail, "Read file via sandbox", "Error: #{inspect(reason)}"}
    end
  end

  defp test_sandbox_list_dir do
    case Manager.list_dir("lib") do
      {:ok, entries} when is_list(entries) and length(entries) > 0 ->
        {:pass, "List directory via sandbox", "Found #{length(entries)} entries in lib/"}

      {:ok, []} ->
        {:fail, "List directory via sandbox", "Directory was empty"}

      {:error, reason} ->
        {:fail, "List directory via sandbox", "Error: #{inspect(reason)}"}
    end
  end

  defp test_sandbox_shell do
    case Manager.shell("echo", ["sandbox test"]) do
      {:ok, %{"exit_code" => 0, "stdout" => stdout}} ->
        {:pass, "Shell command via sandbox", "echo returned: #{String.trim(stdout)}"}

      {:ok, %{"exit_code" => code}} ->
        {:fail, "Shell command via sandbox", "Exit code: #{code}"}

      {:ok, result} ->
        {:fail, "Shell command via sandbox", "Unexpected result: #{inspect(result)}"}

      {:error, reason} ->
        {:fail, "Shell command via sandbox", "Error: #{inspect(reason)}"}
    end
  end

  defp test_sandbox_lua_script do
    lua_script = """
    local content = jido.read_file("mix.exs")
    if content then
      return string.sub(content, 1, 20)
    else
      return nil
    end
    """

    case Manager.execute(lua_script) do
      {:ok, result} when is_binary(result) and byte_size(result) > 0 ->
        {:pass, "Execute Lua script", "Lua read file prefix: #{inspect(result)}"}

      {:ok, result} ->
        {:fail, "Execute Lua script", "Unexpected result: #{inspect(result)}"}

      {:error, reason} ->
        {:fail, "Execute Lua script", "Error: #{inspect(reason)}"}
    end
  end

  defp test_sandbox_security_block do
    case Manager.read_file("../../../etc/passwd") do
      {:error, reason} when is_binary(reason) ->
        if String.contains?(reason, "Security") or String.contains?(reason, "escapes") do
          {:pass, "Security boundary enforced", "Blocked path traversal: #{reason}"}
        else
          {:pass, "Security boundary enforced", "Blocked with: #{reason}"}
        end

      {:error, reason} ->
        {:pass, "Security boundary enforced", "Blocked with: #{inspect(reason)}"}

      {:ok, _} ->
        {:fail, "Security boundary enforced", "DANGER: Path traversal was NOT blocked!"}
    end
  end
end
