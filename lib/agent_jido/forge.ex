defmodule AgentJido.Forge do
  @moduledoc """
  Jido Forge - Generic parallel sandbox execution.

  Forge manages sprite sessions with pluggable runners.
  """

  alias AgentJido.Forge.{Manager, Operations, SpriteSession}

  defmodule SessionHandle do
    @moduledoc """
    A handle to an active Forge session for ergonomic command execution.
    """
    defstruct [:session_id, :pid]

    @type t :: %__MODULE__{
            session_id: String.t(),
            pid: pid()
          }
  end

  # Session management

  @doc """
  Starts a new forge session and returns a handle.
  """
  @spec start_session(String.t(), map()) :: {:ok, SessionHandle.t()} | {:error, term()}
  def start_session(session_id, spec) do
    case Manager.start_session(session_id, spec) do
      {:ok, pid} -> {:ok, %SessionHandle{session_id: session_id, pid: pid}}
      error -> error
    end
  end

  @doc """
  Gets a handle to an existing session for ergonomic command execution.

  ## Example

      {:ok, handle} = Forge.get_handle(session_id)
      {output, 0} = Forge.cmd(handle, "ls", ["-la"])
  """
  @spec get_handle(String.t()) :: {:ok, SessionHandle.t()} | {:error, term()}
  def get_handle(session_id) do
    case Manager.get_session(session_id) do
      {:ok, pid} -> {:ok, %SessionHandle{session_id: session_id, pid: pid}}
      error -> error
    end
  end

  @doc """
  Stops a session.
  """
  @spec stop_session(String.t(), term()) :: :ok | {:error, term()}
  def stop_session(session_id, reason \\ :normal) do
    Manager.stop_session(session_id, reason)
  end

  @doc """
  Lists all active session IDs.
  """
  @spec list_sessions() :: [String.t()]
  def list_sessions do
    Manager.list_sessions()
  end

  @doc """
  Gets the current status of a session.
  """
  @spec status(String.t()) :: {:ok, map()} | {:error, term()}
  def status(session_id) do
    SpriteSession.status(session_id)
  end

  # Execution

  @doc """
  Runs a single iteration on the session.
  """
  @spec run_iteration(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_iteration(session_id, opts \\ []) do
    SpriteSession.run_iteration(session_id, opts)
  end

  @doc """
  Executes a command directly in the sprite.
  """
  @spec exec(String.t(), String.t(), keyword()) ::
          {String.t(), non_neg_integer()} | {:error, term()}
  def exec(session_id, command, opts \\ []) do
    SpriteSession.exec(session_id, command, opts)
  end

  @doc """
  Execute a command synchronously in the session's sprite (Sprites-style API).

  Unlike `exec/3` which takes a raw command string, this takes command and args
  separately for proper escaping and consistency with the Sprites SDK.

  ## Example

      {:ok, handle} = Forge.get_handle(session_id)
      {output, exit_code} = Forge.cmd(handle, "ls", ["-la", "/app"])
  """
  @spec cmd(SessionHandle.t() | String.t(), String.t(), [String.t()], keyword()) ::
          {String.t(), non_neg_integer()} | {:error, term()}
  def cmd(handle_or_session_id, command, args, opts \\ [])

  def cmd(%SessionHandle{session_id: session_id}, command, args, opts) do
    cmd(session_id, command, args, opts)
  end

  def cmd(session_id, command, args, opts) when is_binary(session_id) do
    escaped_args = Enum.map(args, &shell_escape/1)
    full_command = Enum.join([command | escaped_args], " ")
    exec(session_id, full_command, opts)
  end

  defp shell_escape(arg) do
    if String.contains?(arg, [" ", "'", "\"", "$", "`", "\\", "\n"]) do
      "'" <> String.replace(arg, "'", "'\"'\"'") <> "'"
    else
      arg
    end
  end

  @doc """
  Applies input when session is in :needs_input state.
  """
  @spec apply_input(String.t(), term()) :: :ok | {:error, term()}
  def apply_input(session_id, input) do
    SpriteSession.apply_input(session_id, input)
  end

  @doc """
  Runs iterations in a loop until done, blocked, needs_input, or error.

  ## Options

    * `:max_iterations` - Maximum number of iterations (default: 50)
    * `:return_error_result?` - If true, returns `{:ok, result}` even when status is :error,
      allowing callers to inspect error details. Default: false.

  Returns the final iteration result.
  """
  @spec run_loop(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_loop(session_id, opts \\ []) do
    max_iterations = Keyword.get(opts, :max_iterations, 50)
    return_error_result? = Keyword.get(opts, :return_error_result?, false)
    do_run_loop(session_id, opts, max_iterations, 0, return_error_result?)
  end

  defp do_run_loop(_session_id, _opts, max_iterations, iteration, _return_error_result?)
       when iteration >= max_iterations do
    {:error, :max_iterations_reached}
  end

  defp do_run_loop(session_id, opts, max_iterations, iteration, return_error_result?) do
    case run_iteration(session_id, opts) do
      {:ok, %{status: status} = result} when status in [:done, :needs_input, :blocked] ->
        {:ok, result}

      {:ok, %{status: :error} = result} ->
        handle_error_result(result, return_error_result?)

      {:ok, %{continue: true}} ->
        do_run_loop(session_id, opts, max_iterations, iteration + 1, return_error_result?)

      {:ok, %{status: :continue}} ->
        do_run_loop(session_id, opts, max_iterations, iteration + 1, return_error_result?)

      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_error_result(result, true = _return_error_result?), do: {:ok, result}
  defp handle_error_result(result, false = _return_error_result?), do: {:error, {:iteration_error, result}}

  # Session lifecycle operations

  @doc """
  Resume a session from its last checkpoint.

  Returns `{:ok, pid}` on success.
  """
  @spec resume(String.t()) :: {:ok, pid()} | {:error, term()}
  defdelegate resume(session_id), to: Operations

  @doc """
  Cancel a running session.

  Returns `:ok` on success.
  """
  @spec cancel(String.t()) :: :ok | {:error, term()}
  defdelegate cancel(session_id), to: Operations

  @doc """
  Create a checkpoint for an active session.

  ## Options

    * `:name` - Human-readable checkpoint name

  Returns `{:ok, checkpoint}` on success.
  """
  @spec create_checkpoint(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  defdelegate create_checkpoint(session_id, opts \\ []), to: Operations

  @doc """
  Mark a session as failed with error details.
  """
  @spec mark_failed(String.t(), map()) :: {:ok, term()} | {:error, term()}
  defdelegate mark_failed(session_id, error_details), to: Operations

  @doc """
  Mark a session as completed.
  """
  @spec complete(String.t()) :: {:ok, term()} | {:error, term()}
  defdelegate complete(session_id), to: Operations
end
