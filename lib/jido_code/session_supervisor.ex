defmodule JidoCode.SessionSupervisor do
  @moduledoc """
  DynamicSupervisor for managing per-session supervision trees.

  The SessionSupervisor is the entry point for starting and stopping session
  processes. Each session gets its own supervision subtree managed by this
  supervisor.

  ## Architecture

  ```
  SessionSupervisor (DynamicSupervisor, :one_for_one)
  ├── Session.Supervisor for session_1
  │   ├── Session.Manager
  │   └── Session.State
  ├── Session.Supervisor for session_2
  │   ├── Session.Manager
  │   └── Session.State
  └── ...
  ```

  ## Usage

  The supervisor is typically started as part of the application supervision tree:

      children = [
        # ... other children ...
        JidoCode.SessionSupervisor
      ]

  Session lifecycle is managed via functions in this module (implemented in Task 1.3.2):

      # Start a new session
      {:ok, pid} = SessionSupervisor.start_session(session)

      # Stop a session
      :ok = SessionSupervisor.stop_session(session_id)

  ## Strategy

  Uses `:one_for_one` strategy because sessions are independent - if one
  session's processes crash, other sessions should continue unaffected.
  """

  use DynamicSupervisor

  @doc """
  Starts the SessionSupervisor.

  Called by the application supervision tree during startup.

  ## Options

  Currently accepts no meaningful options but follows the standard
  DynamicSupervisor interface for future extensibility.

  ## Examples

      iex> {:ok, pid} = JidoCode.SessionSupervisor.start_link([])
      iex> is_pid(pid)
      true
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
