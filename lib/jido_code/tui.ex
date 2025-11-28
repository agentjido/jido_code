defmodule JidoCode.TUI do
  @moduledoc """
  Terminal User Interface for JidoCode using TermUI's Elm Architecture.

  This module implements the main TUI application following the Elm Architecture
  pattern: `init/1` for initial state, `update/2` for state transitions, and
  `view/1` for rendering.

  ## Architecture

  The TUI connects to the agent system via Phoenix PubSub, receiving events for:
  - Agent responses
  - Status changes (idle, processing, error)
  - Reasoning steps (Chain-of-Thought progress)
  - Tool calls and results

  ## Usage

      # Start the TUI (blocks until quit)
      JidoCode.TUI.run()

      # Or start via Runtime directly
      TermUI.Runtime.run(root: JidoCode.TUI)

  ## Model

  The TUI state contains:
  - `input_buffer` - Current text being typed
  - `messages` - Conversation history
  - `agent_status` - Current agent state (:idle, :processing, :error, :unconfigured)
  - `config` - Provider and model configuration
  - `reasoning_steps` - Chain-of-Thought progress
  - `window` - Terminal dimensions
  """

  use TermUI.Elm

  alias JidoCode.Settings
  alias TermUI.Renderer.Style

  # ============================================================================
  # Model
  # ============================================================================

  defmodule Model do
    @moduledoc """
    The TUI application state.
    """

    @type message :: %{
            role: :user | :assistant | :system,
            content: String.t(),
            timestamp: DateTime.t()
          }

    @type reasoning_step :: %{
            step: String.t(),
            status: :pending | :active | :complete
          }

    @type agent_status :: :idle | :processing | :error | :unconfigured

    @type t :: %__MODULE__{
            input_buffer: String.t(),
            messages: [message()],
            agent_status: agent_status(),
            config: %{provider: String.t() | nil, model: String.t() | nil},
            reasoning_steps: [reasoning_step()],
            window: {non_neg_integer(), non_neg_integer()}
          }

    @enforce_keys []
    defstruct input_buffer: "",
              messages: [],
              agent_status: :unconfigured,
              config: %{provider: nil, model: nil},
              reasoning_steps: [],
              window: {80, 24}
  end

  # ============================================================================
  # Elm Callbacks
  # ============================================================================

  @doc """
  Initializes the TUI state.

  Loads settings from disk, subscribes to PubSub events, and determines
  initial agent status based on configuration.
  """
  @impl true
  def init(_opts) do
    # Subscribe to TUI events
    Phoenix.PubSub.subscribe(JidoCode.PubSub, "tui.events")

    # Load configuration from settings
    config = load_config()

    # Determine initial status based on config
    status = determine_status(config)

    %Model{
      input_buffer: "",
      messages: [],
      agent_status: status,
      config: config,
      reasoning_steps: [],
      window: {80, 24}
    }
  end

  @doc """
  Converts terminal events to TUI messages.

  Currently returns :ignore for all events. Event handling will be
  implemented in task 4.1.2.
  """
  @impl true
  def event_to_msg(_event, _state) do
    :ignore
  end

  @doc """
  Updates state based on messages.

  Currently returns state unchanged. Full message handling will be
  implemented in task 4.1.2.
  """
  @impl true
  def update(_msg, state) do
    {state, []}
  end

  @doc """
  Renders the current state to a render tree.

  Currently renders a minimal placeholder UI. Full view rendering will be
  implemented in task 4.2.x.
  """
  @impl true
  def view(state) do
    stack(:vertical, [
      render_status_bar(state),
      text("", nil),
      text("JidoCode - Agentic Coding Assistant", Style.new(fg: :cyan, attrs: [:bold])),
      text("", nil),
      render_config_info(state),
      text("", nil),
      text("Press Ctrl+C to quit", Style.new(fg: :bright_black))
    ])
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Runs the TUI application.

  This blocks the calling process until the TUI exits (e.g., user presses Ctrl+C).
  """
  @spec run() :: :ok
  def run do
    TermUI.Runtime.run(root: __MODULE__)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  @spec load_config() :: %{provider: String.t() | nil, model: String.t() | nil}
  defp load_config do
    {:ok, settings} = Settings.load()

    %{
      provider: Map.get(settings, "provider"),
      model: Map.get(settings, "model")
    }
  end

  @doc false
  @spec determine_status(%{provider: String.t() | nil, model: String.t() | nil}) :: Model.agent_status()
  def determine_status(config) do
    cond do
      is_nil(config.provider) -> :unconfigured
      is_nil(config.model) -> :unconfigured
      true -> :idle
    end
  end

  # ============================================================================
  # View Helpers (Minimal)
  # ============================================================================

  defp render_status_bar(state) do
    status_text = format_status(state.agent_status)
    config_text = format_config(state.config)

    text("#{config_text} | #{status_text}", Style.new(fg: :white, bg: :blue))
  end

  defp format_status(:idle), do: "Status: Idle"
  defp format_status(:processing), do: "Status: Processing..."
  defp format_status(:error), do: "Status: Error"
  defp format_status(:unconfigured), do: "Status: Not Configured"

  defp format_config(%{provider: nil}), do: "No provider configured"
  defp format_config(%{model: nil, provider: p}), do: "#{p} (no model)"
  defp format_config(%{provider: p, model: m}), do: "#{p}:#{m}"

  defp render_config_info(state) do
    case state.agent_status do
      :unconfigured ->
        stack(:vertical, [
          text("Configuration Required", Style.new(fg: :yellow, attrs: [:bold])),
          text("", nil),
          text("No provider or model configured.", nil),
          text("Create ~/.jido_code/settings.json with:", nil),
          text("", nil),
          text("  {", Style.new(fg: :bright_black)),
          text(~s(    "provider": "anthropic",), Style.new(fg: :bright_black)),
          text(~s(    "model": "claude-3-5-sonnet"), Style.new(fg: :bright_black)),
          text("  }", Style.new(fg: :bright_black))
        ])

      _ ->
        stack(:vertical, [
          text("Ready", Style.new(fg: :green, attrs: [:bold])),
          text("", nil),
          text("Provider: #{state.config.provider || "none"}", nil),
          text("Model: #{state.config.model || "none"}", nil)
        ])
    end
  end
end
