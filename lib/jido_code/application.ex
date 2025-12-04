defmodule JidoCode.Application do
  @moduledoc """
  OTP Application for JidoCode.

  The supervision tree is organized into three main subsystems:

  1. **Infrastructure** - PubSub, Registry for core communication
  2. **Agents** - Dynamic supervisor for LLM and tool agents
  3. **TUI** - Terminal user interface (started last, optional)

  ## Supervision Strategy

  Uses `:one_for_one` at the top level to ensure independent failure handling.
  Agent crashes don't affect the TUI, and vice versa.

  ## Default Session

  On startup, a default session is automatically created for the current working
  directory. This allows users to immediately start working without manually
  creating a session. If session creation fails, the application continues
  to start normally with a warning logged.

  ## TUI Configuration

  The TUI is not started by default during application startup. To run the TUI:

      JidoCode.TUI.run()

  This allows tests to run without TUI interference and gives control to the
  main script for when to take over the terminal.
  """

  use Application

  require Logger

  alias JidoCode.Settings
  alias JidoCode.SessionSupervisor

  @impl true
  def start(_type, _args) do
    # ARCH-3 Fix: Initialize ETS tables during application startup
    # This prevents race conditions from on-demand table creation
    initialize_ets_tables()

    children = [
      # Settings cache (must start before anything that might use Settings)
      JidoCode.Settings.Cache,

      # Model registry cache for Jido.AI (must start before model listings)
      Jido.AI.Model.Registry.Cache,

      # Theme server for TUI styling (load from settings or default to dark)
      {TermUI.Theme, theme: load_theme_from_settings()},

      # PubSub for agent-TUI communication
      {Phoenix.PubSub, name: JidoCode.PubSub},

      # Registry for agent lookup
      {Registry, keys: :unique, name: JidoCode.AgentRegistry},

      # Registry for session process lookup (Session.Supervisor, Manager, State)
      {Registry, keys: :unique, name: JidoCode.SessionProcessRegistry},

      # Tool registry for LLM function calling
      JidoCode.Tools.Registry,

      # Lua sandbox for tool execution
      JidoCode.Tools.Manager,

      # ARCH-1 Fix: Task.Supervisor for monitored async tasks
      # Used by LLMAgent for chat operations to prevent silent failures
      {Task.Supervisor, name: JidoCode.TaskSupervisor},

      # DynamicSupervisor for agent processes
      JidoCode.AgentSupervisor,

      # DynamicSupervisor for session processes (per-session supervisors)
      JidoCode.SessionSupervisor

      # Note: TUI is not started automatically.
      # Call JidoCode.TUI.run() to start the TUI interactively.
    ]

    opts = [strategy: :one_for_one, name: JidoCode.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        create_default_session()
        {:ok, pid}

      error ->
        error
    end
  end

  # Create a default session for the current working directory
  # Called after supervision tree is started
  defp create_default_session do
    cwd = File.cwd!()
    name = Path.basename(cwd)

    case SessionSupervisor.create_session(project_path: cwd, name: name) do
      {:ok, session} ->
        Logger.info("Created default session '#{session.name}' for #{session.project_path}")
        {:ok, session}

      {:error, reason} ->
        Logger.warning("Failed to create default session: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ARCH-3 Fix: Initialize all ETS tables during application startup
  # This prevents race conditions from concurrent on-demand table creation
  defp initialize_ets_tables do
    # Initialize agent instrumentation ETS table
    # This table tracks agent restart counts and start times for telemetry
    JidoCode.Telemetry.AgentInstrumentation.setup()

    # Initialize session registry ETS table
    # This table tracks active sessions for the work-session feature
    JidoCode.SessionRegistry.create_table()
  end

  # Load theme from settings, defaulting to :dark if not set
  defp load_theme_from_settings do
    # Settings.Cache must be started before this is called
    # However, at this point it hasn't started yet, so we read directly from file
    case Settings.read_file(Settings.local_path()) do
      {:ok, settings} ->
        get_theme_atom(Map.get(settings, "theme"))

      {:error, _} ->
        # Try global settings
        case Settings.read_file(Settings.global_path()) do
          {:ok, settings} -> get_theme_atom(Map.get(settings, "theme"))
          {:error, _} -> :dark
        end
    end
  end

  defp get_theme_atom(nil), do: :dark
  defp get_theme_atom("dark"), do: :dark
  defp get_theme_atom("light"), do: :light
  defp get_theme_atom("high_contrast"), do: :high_contrast
  defp get_theme_atom(_), do: :dark
end
