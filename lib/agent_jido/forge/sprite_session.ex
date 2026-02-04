defmodule AgentJido.Forge.SpriteSession do
  @moduledoc """
  Per-session GenServer managing a sprite lifecycle.

  Handles provisioning, bootstrapping, runner initialization, and iteration
  execution for a single forge session.
  """

  use GenServer

  require Logger

  alias AgentJido.Forge.Bootstrap
  alias AgentJido.Forge.Persistence
  alias AgentJido.Forge.PubSub, as: ForgePubSub
  alias AgentJido.Forge.SpriteClient

  @type session_id :: String.t()
  @type state_name ::
          :starting | :bootstrapping | :initializing | :ready | :running | :needs_input | :stopping

  defstruct [
    :session_id,
    :spec,
    :sprite_id,
    :client,
    :runner,
    :runner_state,
    :state,
    :iteration,
    :started_at,
    :last_activity,
    :resume_checkpoint_id,
    :sprite_client_module
  ]

  # Public API

  @doc """
  Start a new sprite session.
  """
  @spec start_link({session_id(), map(), keyword()}) :: GenServer.on_start()
  def start_link({session_id, spec, opts}) do
    GenServer.start_link(__MODULE__, {session_id, spec, opts}, name: via_tuple(session_id))
  end

  @doc """
  Run a single iteration.
  """
  @spec run_iteration(session_id(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_iteration(session_id, opts \\ []) do
    GenServer.call(via_tuple(session_id), {:run_iteration, opts}, :infinity)
  end

  @doc """
  Execute a command directly in the sprite.
  """
  @spec exec(session_id(), String.t(), keyword()) :: {String.t(), non_neg_integer()} | {:error, term()}
  def exec(session_id, command, opts \\ []) do
    GenServer.call(via_tuple(session_id), {:exec, command, opts}, :infinity)
  end

  @doc """
  Apply input when session is in :needs_input state.
  """
  @spec apply_input(session_id(), term()) :: :ok | {:error, term()}
  def apply_input(session_id, input) do
    GenServer.call(via_tuple(session_id), {:apply_input, input})
  end

  @doc """
  Get current session status.
  """
  @spec status(session_id()) :: {:ok, map()} | {:error, term()}
  def status(session_id) do
    GenServer.call(via_tuple(session_id), :status)
  end

  @doc """
  Stop the session.
  """
  @spec stop(session_id(), term()) :: :ok
  def stop(session_id, reason \\ :normal) do
    GenServer.call(via_tuple(session_id), {:stop, reason})
  end

  # GenServer Callbacks

  @impl true
  def init({session_id, spec, opts}) do
    runner_type = Map.get(spec, :runner) || Map.get(spec, :runner_type, :shell)
    runner = resolve_runner(runner_type)
    sprite_client = resolve_sprite_client(Map.get(spec, :sprite_client, :default))

    # Use runner_state from spec if resuming, otherwise use runner_config
    runner_state =
      opts[:runner_state] ||
        Map.get(spec, :runner_state) ||
        Map.get(spec, :runner_config, %{})

    # Check if we're resuming from a checkpoint
    resume_checkpoint_id = Map.get(spec, :resume_from_checkpoint)

    state = %__MODULE__{
      session_id: session_id,
      spec: spec,
      sprite_id: nil,
      client: nil,
      runner: runner,
      runner_state: runner_state,
      state: :starting,
      iteration: 0,
      started_at: DateTime.utc_now(),
      last_activity: DateTime.utc_now(),
      resume_checkpoint_id: resume_checkpoint_id,
      sprite_client_module: sprite_client
    }

    send(self(), :provision)
    {:ok, state}
  end

  @impl true
  def handle_info(:provision, state) do
    sprite_spec = Map.get(state.spec, :sprite, %{})
    sprite_client = state.sprite_client_module

    # If resuming from checkpoint, add checkpoint info to sprite spec
    sprite_spec =
      if state.resume_checkpoint_id do
        Map.put(sprite_spec, :restore_checkpoint, state.resume_checkpoint_id)
      else
        sprite_spec
      end

    case sprite_client.create(sprite_spec) do
      {:ok, client, sprite_id} ->
        if state.resume_checkpoint_id do
          Logger.debug(
            "Provisioned sprite #{sprite_id} from checkpoint #{state.resume_checkpoint_id} for session #{state.session_id}"
          )
        else
          Logger.debug("Provisioned sprite #{sprite_id} for session #{state.session_id}")
        end

        new_state = %{
          state
          | client: client,
            sprite_id: sprite_id,
            state: :bootstrapping,
            last_activity: DateTime.utc_now()
        }

        Persistence.record_provision_complete(state.session_id, sprite_id, nil)
        notify_status(new_state)

        # If resuming, skip bootstrap and go straight to runner init
        if state.resume_checkpoint_id do
          send(self(), :init_runner)
        else
          send(self(), :bootstrap)
        end

        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to provision sprite for session #{state.session_id}: #{inspect(reason)}")
        {:stop, {:provision_failed, reason}, state}
    end
  end

  def handle_info(:bootstrap, state) do
    env = Map.get(state.spec, :env, %{})
    sprite_client = state.sprite_client_module

    case sprite_client.inject_env(state.client, env) do
      :ok ->
        bootstrap_steps = Map.get(state.spec, :bootstrap, [])

        case Bootstrap.execute(state.client, bootstrap_steps, sprite_client: sprite_client, sprite_id: state.sprite_id) do
          :ok ->
            Logger.debug("Bootstrap complete for session #{state.session_id}")

            new_state = %{
              state
              | state: :initializing,
                last_activity: DateTime.utc_now()
            }

            Persistence.record_bootstrap_complete(state.session_id)
            notify_status(new_state)
            send(self(), :init_runner)
            {:noreply, new_state}

          {:error, step, reason} ->
            Logger.error("Bootstrap failed at step #{inspect(step)}: #{inspect(reason)}")
            {:stop, {:bootstrap_failed, step, reason}, state}
        end

      {:error, reason} ->
        Logger.error("Failed to inject env: #{inspect(reason)}")
        {:stop, {:env_injection_failed, reason}, state}
    end
  end

  def handle_info(:init_runner, state) do
    runner_config = Map.get(state.spec, :runner_config, %{})

    case state.runner.init(state.client, runner_config) do
      :ok ->
        Logger.debug("Runner initialized for session #{state.session_id}")

        new_state = %{
          state
          | state: :ready,
            last_activity: DateTime.utc_now()
        }

        notify_status(new_state)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Runner init failed: #{inspect(reason)}")
        {:stop, {:runner_init_failed, reason}, state}
    end
  end

  @impl true
  def handle_call({:run_iteration, opts}, from, %{state: :ready} = state) do
    server = self()
    next_iteration = state.iteration + 1
    client = state.client
    runner = state.runner
    runner_state = state.runner_state

    Persistence.record_execution_start(state.session_id, next_iteration, metadata: %{runner: runner})

    Task.start(fn ->
      result = runner.run_iteration(client, runner_state, opts)
      GenServer.cast(server, {:iteration_complete, result, from, next_iteration})
    end)

    new_state = %{
      state
      | state: :running,
        iteration: next_iteration,
        last_activity: DateTime.utc_now()
    }

    notify_status(new_state)
    {:noreply, new_state}
  end

  def handle_call({:run_iteration, _opts}, _from, state) do
    {:reply, {:error, {:invalid_state, state.state}}, state}
  end

  def handle_call({:exec, command, opts}, _from, %{state: :ready} = state) do
    sprite_client = state.sprite_client_module
    result = sprite_client.exec(state.client, command, opts)

    new_state = %{state | last_activity: DateTime.utc_now()}
    {:reply, result, new_state}
  end

  def handle_call({:exec, _command, _opts}, _from, state) do
    {:reply, {:error, {:invalid_state, state.state}}, state}
  end

  def handle_call({:apply_input, input}, _from, %{state: :needs_input} = state) do
    case state.runner.apply_input(state.client, input, state.runner_state) do
      :ok ->
        new_state = %{
          state
          | state: :ready,
            last_activity: DateTime.utc_now()
        }

        Persistence.record_input_applied(state.session_id, state.runner_state)
        {:reply, :ok, new_state}

      {:ok, new_runner_state} ->
        new_state = %{
          state
          | state: :ready,
            runner_state: new_runner_state,
            last_activity: DateTime.utc_now()
        }

        Persistence.record_input_applied(state.session_id, new_runner_state)
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:apply_input, _input}, _from, state) do
    {:reply, {:error, {:invalid_state, state.state}}, state}
  end

  def handle_call(:status, _from, state) do
    status_map = %{
      session_id: state.session_id,
      state: state.state,
      sprite_id: state.sprite_id,
      iteration: state.iteration,
      started_at: state.started_at,
      last_activity: state.last_activity
    }

    {:reply, {:ok, status_map}, state}
  end

  def handle_call({:stop, reason}, _from, state) do
    {:stop, reason, :ok, state}
  end

  @impl true
  def handle_cast({:iteration_complete, result, from, iteration}, state) do
    new_state =
      case result do
        {:ok, %{status: :needs_input} = r} ->
          ForgePubSub.broadcast_session(state.session_id, {:needs_input, %{prompt: r[:question]}})
          Persistence.record_execution_complete(state.session_id, r)
          %{state | state: :needs_input, last_activity: DateTime.utc_now()}

        {:ok, result_map} ->
          if output = result_map[:output], do: notify_output(state, output)
          Persistence.record_execution_complete(state.session_id, result_map)
          %{state | state: :ready, last_activity: DateTime.utc_now()}

        {:error, reason} ->
          Persistence.record_failure(state.session_id, reason)
          %{state | state: :ready, last_activity: DateTime.utc_now()}
      end

    new_state = %{new_state | iteration: iteration}
    notify_status(new_state)
    GenServer.reply(from, result)
    {:noreply, new_state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.warning("Terminating session #{state.session_id}: #{inspect(reason)}")

    ForgePubSub.broadcast_session(state.session_id, {:stopped, reason})

    if function_exported?(state.runner, :terminate, 2) do
      state.runner.terminate(state.client, reason)
    end

    if state.client && state.sprite_id do
      sprite_client = state.sprite_client_module

      case sprite_client.destroy(state.client, state.sprite_id) do
        :ok ->
          Logger.info("Destroyed sprite #{state.sprite_id}")

        {:error, err} ->
          Logger.warning("Failed to destroy sprite #{state.sprite_id}: #{inspect(err)}")
      end
    end

    :ok
  end

  # Private Helpers

  defp via_tuple(session_id) do
    {:via, Elixir.Registry, {AgentJido.Forge.SessionRegistry, session_id}}
  end

  defp resolve_runner(:shell), do: AgentJido.Forge.Runners.Shell
  defp resolve_runner(:claude_code), do: AgentJido.Forge.Runners.ClaudeCode
  defp resolve_runner(:workflow), do: AgentJido.Forge.Runners.Workflow
  defp resolve_runner(:custom), do: AgentJido.Forge.Runners.Custom
  defp resolve_runner(module) when is_atom(module), do: module

  defp resolve_sprite_client(:default), do: SpriteClient
  defp resolve_sprite_client(:fake), do: AgentJido.Forge.SpriteClient.Fake
  defp resolve_sprite_client(:live), do: AgentJido.Forge.SpriteClient.Live
  defp resolve_sprite_client(module) when is_atom(module), do: module

  defp notify_status(state) do
    status = %{
      session_id: state.session_id,
      state: state.state,
      sprite_id: state.sprite_id,
      iteration: state.iteration,
      started_at: state.started_at,
      last_activity: state.last_activity
    }

    ForgePubSub.broadcast_session(state.session_id, {:status, status})
  end

  defp notify_output(state, output) when is_binary(output) and output != "" do
    ForgePubSub.broadcast_session(state.session_id, {:output, %{chunk: output, seq: state.iteration}})
  end

  defp notify_output(_state, _output), do: :ok
end
