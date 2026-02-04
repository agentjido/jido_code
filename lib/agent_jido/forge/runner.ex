defmodule AgentJido.Forge.Runner do
  @moduledoc """
  Behaviour for Forge runners that execute iterations in a sprite environment.

  Runners implement the core loop of the Forge system, handling initialization,
  iteration execution, input handling, and cleanup.
  """

  @type iteration_status :: :continue | :done | :needs_input | :blocked | :error

  @type iteration_result :: %{
          status: iteration_status(),
          output: String.t() | nil,
          summary: String.t() | nil,
          question: String.t() | nil,
          error: String.t() | nil,
          metadata: map()
        }

  @type state :: term()
  @type sprite_client :: term()
  @type config :: map()
  @type opts :: keyword()
  @type chunk :: term()
  @type stream :: term()
  @type events :: [term()]
  @type input :: term()

  @doc """
  Initialize the runner with a sprite client and configuration.

  Called once before any iterations begin. Use this to set up initial state,
  inject environment variables, or run bootstrap commands.
  """
  @callback init(sprite_client(), config()) :: :ok | {:error, term()}

  @doc """
  Execute a single iteration of the runner.

  Returns an iteration result indicating the status and any output.
  The runner should continue to be called while status is `:continue`.
  """
  @callback run_iteration(sprite_client(), state(), opts()) ::
              {:ok, iteration_result()} | {:error, term()}

  @doc """
  Apply external input to the runner.

  Called when the runner is in `:needs_input` status and input has been provided.
  Return `{:ok, new_state}` to update the runner state after applying input.
  """
  @callback apply_input(sprite_client(), input(), state()) ::
              :ok | {:ok, state()} | {:error, term()}

  @doc """
  Handle streaming output from the sprite.

  Optional callback for processing chunks of output as they arrive.
  Returns events to emit and updated state.
  """
  @callback handle_output(chunk(), stream(), state()) :: {:ok, events(), state()}

  @doc """
  Clean up resources when the runner terminates.

  Optional callback for cleanup on normal or abnormal termination.
  """
  @callback terminate(sprite_client(), reason :: term()) :: :ok

  @optional_callbacks handle_output: 3, terminate: 2

  @doc """
  Returns a new iteration result struct with defaults.
  """
  @spec new_result(iteration_status(), keyword()) :: iteration_result()
  def new_result(status, opts \\ []) do
    %{
      status: status,
      output: Keyword.get(opts, :output),
      summary: Keyword.get(opts, :summary),
      question: Keyword.get(opts, :question),
      error: Keyword.get(opts, :error),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a :continue result.
  """
  @spec continue(keyword()) :: iteration_result()
  def continue(opts \\ []), do: new_result(:continue, opts)

  @doc """
  Creates a :done result.
  """
  @spec done(keyword()) :: iteration_result()
  def done(opts \\ []), do: new_result(:done, opts)

  @doc """
  Creates a :needs_input result with a question.
  """
  @spec needs_input(String.t(), keyword()) :: iteration_result()
  def needs_input(question, opts \\ []) do
    new_result(:needs_input, Keyword.put(opts, :question, question))
  end

  @doc """
  Creates a :blocked result.
  """
  @spec blocked(keyword()) :: iteration_result()
  def blocked(opts \\ []), do: new_result(:blocked, opts)

  @doc """
  Creates an :error result.
  """
  @spec error(String.t(), keyword()) :: iteration_result()
  def error(message, opts \\ []) do
    new_result(:error, Keyword.put(opts, :error, message))
  end
end
