defmodule JidoCode.Conversations.ChildWorker do
  # covers: architecture.conversation_orchestration.tool_execution_is_cancellable_child_work
  # covers: architecture.conversation_orchestration.cancellation_lifecycle_is_evented
  @moduledoc """
  Runtime wrapper for one cancellable unit of conversation child work.

  The worker isolates child-work lifecycle from the coordinator mailbox while
  exposing explicit cancellation, snapshot, and settlement calls back to the
  coordinator. When enabled by the coordinator, it can also run the bounded
  conversation runtime and route updates back through the canonical driver.
  """

  use GenServer

  alias JidoCode.Conversations.{ChildWork, Driver, Runtime}
  alias JidoCode.Control.Actor

  @supervisor JidoCode.Conversations.ChildSupervisor
  @supervisor_start_attempts 2

  @type runtime_spec :: map()
  @type state :: %{
          child_work: ChildWork.t(),
          runtime_pid: pid() | nil,
          runtime_ref: reference() | nil,
          runtime_spec: runtime_spec() | nil,
          runtime_status: :idle | :running,
          runtime_managed?: boolean()
        }

  @runtime_actor Actor.managed_repo_orchestrator_actor(%{
                   "id" => "system:conversation-runtime",
                   "email" => "conversation-runtime@system.local"
                 })

  @spec start(ChildWork.t()) :: {:ok, pid()} | {:error, term()}
  def start(%ChildWork{} = child_work) do
    start(child_work, @supervisor_start_attempts)
  end

  defp start(%ChildWork{} = child_work, attempts_remaining) do
    case start_once(child_work) do
      {:error, {:child_supervisor_unavailable, _reason}} when attempts_remaining > 0 ->
        wait_for_supervisor_recovery()
        start(child_work, attempts_remaining - 1)

      {:error, {:child_supervisor_unavailable, reason}} ->
        start_without_supervisor(child_work, reason)

      result ->
        result
    end
  end

  defp start_once(%ChildWork{} = child_work) do
    case Process.whereis(@supervisor) do
      supervisor_pid when is_pid(supervisor_pid) ->
        try do
          DynamicSupervisor.start_child(@supervisor, {__MODULE__, child_work})
        catch
          :exit, reason -> {:error, {:child_supervisor_unavailable, reason}}
        end

      _other ->
        {:error, {:child_supervisor_unavailable, :not_started}}
    end
  end

  defp wait_for_supervisor_recovery do
    case Process.whereis(@supervisor) do
      supervisor_pid when is_pid(supervisor_pid) ->
        ref = Process.monitor(supervisor_pid)

        receive do
          {:DOWN, ^ref, :process, ^supervisor_pid, _reason} -> :ok
        after
          25 -> Process.demonitor(ref, [:flush])
        end

      _other ->
        :ok
    end
  end

  defp start_without_supervisor(%ChildWork{} = child_work, supervisor_reason) do
    try do
      GenServer.start(__MODULE__, child_work)
    catch
      :exit, reason ->
        {:error, {:child_supervisor_unavailable, supervisor_reason, {:isolated_start_failed, reason}}}
    end
  end

  @spec snapshot(pid()) :: {:ok, ChildWork.t()}
  def snapshot(pid) when is_pid(pid), do: GenServer.call(pid, :snapshot)

  @spec request_cancel(pid()) :: {:ok, ChildWork.t()} | {:error, term()}
  def request_cancel(pid) when is_pid(pid), do: GenServer.call(pid, :request_cancel)

  @spec settle(pid(), ChildWork.settlement(), map()) :: {:ok, ChildWork.t()} | {:error, term()}
  def settle(pid, outcome, attrs \\ %{}) when is_pid(pid) and is_map(attrs) do
    GenServer.call(pid, {:settle, outcome, attrs})
  end

  @spec begin_runtime(pid(), runtime_spec()) :: {:ok, ChildWork.t()} | {:error, term()}
  def begin_runtime(pid, runtime_spec) when is_pid(pid) and is_map(runtime_spec) do
    GenServer.call(pid, {:begin_runtime, runtime_spec})
  end

  def start_link(%ChildWork{} = child_work) do
    GenServer.start_link(__MODULE__, child_work)
  end

  @impl true
  def init(%ChildWork{} = child_work) do
    with {:ok, running_child_work} <- start_or_restore(child_work) do
      {:ok,
       %{
         child_work: running_child_work,
         runtime_pid: nil,
         runtime_ref: nil,
         runtime_spec: nil,
         runtime_status: :idle,
         runtime_managed?: false
       }}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, %{child_work: %ChildWork{} = child_work} = state) do
    {:reply, {:ok, child_work}, state}
  end

  def handle_call(:request_cancel, _from, %{child_work: %ChildWork{} = child_work} = state) do
    with {:ok, requested} <- ChildWork.request_cancel(child_work),
         {:ok, acknowledged} <- ChildWork.acknowledge_cancel(requested) do
      next_state =
        state
        |> Map.put(:child_work, acknowledged)
        |> maybe_cancel_runtime()

      if is_nil(next_state.runtime_pid) and next_state.runtime_managed? do
        send(self(), :dispatch_cancelled_without_runtime)
      end

      {:reply, {:ok, acknowledged}, next_state}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:settle, outcome, attrs}, _from, %{child_work: %ChildWork{} = child_work} = state) do
    case ChildWork.settle(child_work, outcome, attrs) do
      {:ok, updated_child_work} ->
        {:stop, :normal, {:ok, updated_child_work}, %{state | child_work: updated_child_work}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:begin_runtime, _runtime_spec}, _from, %{runtime_pid: pid} = state) when is_pid(pid) do
    {:reply, {:error, :runtime_already_running}, state}
  end

  def handle_call({:begin_runtime, runtime_spec}, _from, %{child_work: %ChildWork{} = child_work} = state) do
    parent = self()

    {runtime_pid, runtime_ref} =
      spawn_monitor(fn ->
        emit = fn payload -> send(parent, {:runtime_event, payload}) end
        result = Runtime.run(runtime_spec, emit)
        send(parent, {:runtime_finished, result})
      end)

    maybe_allow_test_sandbox(runtime_pid, runtime_spec)

    {:reply, {:ok, child_work},
     %{
       state
       | runtime_pid: runtime_pid,
         runtime_ref: runtime_ref,
         runtime_spec: runtime_spec,
         runtime_status: :running,
         runtime_managed?: true
     }}
  end

  @impl true
  def handle_info({:runtime_event, payload}, %{child_work: %ChildWork{} = child_work} = state)
      when is_map(payload) do
    with {:ok, updated_child_work} <- apply_runtime_update(child_work, payload),
         :ok <- dispatch_runtime_payload(updated_child_work, payload) do
      {:noreply, %{state | child_work: updated_child_work}}
    else
      _other ->
        {:noreply, state}
    end
  end

  def handle_info({:runtime_finished, {terminal_kind, payload}}, state)
      when terminal_kind in [:completed, :failed] and is_map(payload) do
    with {:ok, updated_child_work} <- apply_runtime_terminal_update(state.child_work, payload),
         :ok <- dispatch_runtime_payload(updated_child_work, payload) do
      {:stop, :normal, clear_runtime(%{state | child_work: updated_child_work, runtime_status: :idle})}
    else
      _other ->
        {:stop, :normal, clear_runtime(%{state | runtime_status: :idle})}
    end
  end

  def handle_info({:runtime_finished, {:awaiting_input, payload}}, %{child_work: %ChildWork{} = child_work} = state)
      when is_map(payload) do
    with {:ok, updated_child_work} <- apply_runtime_update(child_work, payload),
         :ok <- dispatch_runtime_payload(updated_child_work, payload) do
      {:noreply, clear_runtime(%{state | child_work: updated_child_work, runtime_status: :idle})}
    else
      _other ->
        {:noreply, clear_runtime(%{state | runtime_status: :idle})}
    end
  end

  def handle_info(
        {:DOWN, runtime_ref, :process, runtime_pid, reason},
        %{runtime_ref: runtime_ref, runtime_pid: runtime_pid} = state
      ) do
    next_state = clear_runtime(%{state | runtime_status: :idle})

    cond do
      terminal_reason?(reason) ->
        {:noreply, next_state}

      cancelling?(next_state.child_work) ->
        send(self(), :dispatch_cancelled_without_runtime)
        {:noreply, next_state}

      true ->
        failed_payload = %{
          "kind" => "failed",
          "error" => %{
            "error_type" => "conversation_runtime_process_failed",
            "detail" => "Real conversation runtime exited unexpectedly (#{inspect(reason)}).",
            "remediation" => "Retry the conversation turn after runtime services recover."
          }
        }

        send(self(), {:runtime_finished, {:failed, failed_payload}})
        {:noreply, next_state}
    end
  end

  def handle_info(:dispatch_cancelled_without_runtime, %{child_work: %ChildWork{} = child_work} = state) do
    payload = %{
      "kind" => "cancelled",
      "result" => %{
        "reason" => "The active repository conversation work was cancelled before completion."
      }
    }

    with {:ok, updated_child_work} <- apply_runtime_terminal_update(child_work, payload),
         :ok <- dispatch_runtime_payload(updated_child_work, payload) do
      {:stop, :normal, %{state | child_work: updated_child_work}}
    else
      _other ->
        {:stop, :normal, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    _ = terminate_runtime(state)
    :ok
  end

  defp start_or_restore(%ChildWork{state: :queued} = child_work), do: ChildWork.start(child_work)

  defp start_or_restore(%ChildWork{} = child_work)
       when child_work.state in [:running, :cancel_requested, :cancel_acknowledged] do
    {:ok, child_work}
  end

  defp start_or_restore(%ChildWork{} = child_work), do: {:ok, child_work}

  defp maybe_cancel_runtime(%{runtime_pid: pid} = state) when is_pid(pid) do
    Process.exit(pid, :kill)
    state
  end

  defp maybe_cancel_runtime(state), do: state

  defp terminate_runtime(%{runtime_pid: pid, runtime_ref: ref} = state)
       when is_pid(pid) and is_reference(ref) do
    Process.exit(pid, :kill)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> clear_runtime(state)
    after
      500 -> clear_runtime(state)
    end
  end

  defp terminate_runtime(state), do: clear_runtime(state)

  defp apply_runtime_update(%ChildWork{} = child_work, payload) do
    case payload["kind"] do
      "progress" -> ChildWork.record_update(child_work, :progress, payload)
      "stdout" -> ChildWork.record_update(child_work, :stdout, payload)
      "delta" -> ChildWork.record_update(child_work, :delta, payload)
      "needs_input" -> ChildWork.record_update(child_work, :needs_input, payload)
      _other -> {:ok, child_work}
    end
  end

  defp apply_runtime_terminal_update(%ChildWork{} = child_work, payload) do
    case payload["kind"] do
      "completed" -> ChildWork.settle(child_work, :completed, terminal_attrs(payload))
      "cancelled" -> ChildWork.settle(child_work, :cancelled, terminal_attrs(payload))
      "cancel_failed" -> ChildWork.settle(child_work, :cancel_failed, terminal_attrs(payload))
      "failed" -> ChildWork.settle(child_work, :failed, terminal_attrs(payload))
      _other -> {:ok, child_work}
    end
  end

  defp terminal_attrs(payload) do
    %{}
    |> maybe_put(:result, Map.get(payload, "result"))
    |> maybe_put(:error, Map.get(payload, "error"))
  end

  defp dispatch_runtime_payload(%ChildWork{} = child_work, payload) when is_map(payload) do
    Driver.handle_command(
      child_work.conversation_id,
      %{
        type: "tool_result.submit",
        payload: Map.put(payload, "child_work_id", child_work.id)
      },
      actor: @runtime_actor
    )
    |> case do
      {:ok, _snapshot} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp clear_runtime(state) do
    %{
      state
      | runtime_pid: nil,
        runtime_ref: nil,
        runtime_spec: nil,
        runtime_status: :idle
    }
  end

  defp cancelling?(%ChildWork{state: state}), do: state in [:cancel_requested, :cancel_acknowledged]
  defp cancelling?(_child_work), do: false

  defp terminal_reason?(:normal), do: true
  defp terminal_reason?(:shutdown), do: true
  defp terminal_reason?({:shutdown, _reason}), do: true
  defp terminal_reason?(_reason), do: false

  defp maybe_allow_test_sandbox(runtime_pid, runtime_spec) when is_pid(runtime_pid) and is_map(runtime_spec) do
    [Map.get(runtime_spec, :sandbox_owner), Map.get(runtime_spec, :starter_pid)]
    |> Enum.filter(&is_pid/1)
    |> Enum.uniq()
    |> Enum.each(&allow_test_sandbox(&1, runtime_pid))
  end

  defp maybe_allow_test_sandbox(_runtime_pid, _runtime_spec), do: :ok

  defp allow_test_sandbox(owner_pid, runtime_pid) when is_pid(owner_pid) and is_pid(runtime_pid) do
    _ = {owner_pid, runtime_pid}
    :ok
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
