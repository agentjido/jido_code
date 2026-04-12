defmodule JidoCode.Conversations.ChildWorker do
  # covers: architecture.conversation_orchestration.tool_execution_is_cancellable_child_work
  # covers: architecture.conversation_orchestration.cancellation_lifecycle_is_evented
  @moduledoc """
  Runtime wrapper for one cancellable unit of conversation child work.

  The worker isolates child-work lifecycle from the coordinator mailbox while
  exposing explicit cancellation and settlement calls back to the coordinator.
  """

  use GenServer

  alias JidoCode.Conversations.ChildWork

  @supervisor JidoCode.Conversations.ChildSupervisor

  @spec start(ChildWork.t()) :: {:ok, pid()} | {:error, term()}
  def start(%ChildWork{} = child_work) do
    DynamicSupervisor.start_child(@supervisor, {__MODULE__, child_work})
  end

  @spec snapshot(pid()) :: {:ok, ChildWork.t()}
  def snapshot(pid) when is_pid(pid), do: GenServer.call(pid, :snapshot)

  @spec request_cancel(pid()) :: {:ok, ChildWork.t()} | {:error, term()}
  def request_cancel(pid) when is_pid(pid), do: GenServer.call(pid, :request_cancel)

  @spec settle(pid(), ChildWork.settlement(), map()) :: {:ok, ChildWork.t()} | {:error, term()}
  def settle(pid, outcome, attrs \\ %{}) when is_pid(pid) and is_map(attrs) do
    GenServer.call(pid, {:settle, outcome, attrs})
  end

  def start_link(%ChildWork{} = child_work) do
    GenServer.start_link(__MODULE__, child_work)
  end

  @impl true
  def init(%ChildWork{} = child_work) do
    {:ok, running_child_work} = ChildWork.start(child_work)
    {:ok, running_child_work}
  end

  @impl true
  def handle_call(:snapshot, _from, %ChildWork{} = child_work) do
    {:reply, {:ok, child_work}, child_work}
  end

  def handle_call(:request_cancel, _from, %ChildWork{} = child_work) do
    with {:ok, requested} <- ChildWork.request_cancel(child_work),
         {:ok, acknowledged} <- ChildWork.acknowledge_cancel(requested) do
      {:reply, {:ok, acknowledged}, acknowledged}
    else
      {:error, reason} -> {:reply, {:error, reason}, child_work}
    end
  end

  def handle_call({:settle, outcome, attrs}, _from, %ChildWork{} = child_work) do
    case ChildWork.settle(child_work, outcome, attrs) do
      {:ok, updated_child_work} ->
        {:stop, :normal, {:ok, updated_child_work}, updated_child_work}

      {:error, reason} ->
        {:reply, {:error, reason}, child_work}
    end
  end
end
