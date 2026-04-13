defmodule JidoCode.Conversations.Driver do
  # covers: architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state
  # covers: architecture.conversation_orchestration.control_and_work_commands_are_distinct
  @moduledoc """
  Product-owned conversation driver that manages coordinator runtime without exposing pod topology.
  """

  alias JidoCode.Control.Actor
  alias JidoCode.Conversations
  alias JidoCode.Conversations.{ChildWork, Conversation, Coordinator, Persistence}

  @supervisor JidoCode.Conversations.DynamicSupervisor
  @registry JidoCode.Conversations.Registry

  @spec start_conversation(map()) :: {:ok, map()} | {:error, term()}
  def start_conversation(attrs) when is_map(attrs) do
    with {:ok, %{conversation: %Conversation{} = conversation} = result} <- Conversations.start(attrs),
         {:ok, _pid} <- ensure_coordinator(conversation),
         {:ok, snapshot} <- Coordinator.snapshot(conversation.id) do
      _ = Persistence.persist_snapshot(snapshot)
      {:ok, Map.put(result, :snapshot, snapshot)}
    end
  end

  @spec handle_command(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def handle_command(conversation_id, command, opts \\ [])
      when is_binary(conversation_id) and is_map(command) and is_list(opts) do
    actor = normalize_actor(Keyword.get(opts, :actor))

    with {:ok, %Conversation{} = conversation} <- Conversations.resume(conversation_id, actor: actor),
         {:ok, _pid} <- ensure_coordinator(conversation),
         {:ok, snapshot} <- Coordinator.admit_command(conversation_id, command, actor) do
      {:ok, snapshot}
    end
  end

  @spec transition_turn(String.t(), String.t(), atom(), keyword()) :: {:ok, map()} | {:error, term()}
  def transition_turn(conversation_id, turn_id, next_state, opts \\ [])
      when is_binary(conversation_id) and is_binary(turn_id) and is_atom(next_state) and is_list(opts) do
    actor = normalize_actor(Keyword.get(opts, :actor))

    with {:ok, %Conversation{} = conversation} <- Conversations.resume(conversation_id, actor: actor),
         {:ok, _pid} <- ensure_coordinator(conversation),
         {:ok, snapshot} <- Coordinator.transition_turn(conversation_id, turn_id, next_state, actor) do
      {:ok, snapshot}
    end
  end

  @spec cancel_child_work(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def cancel_child_work(conversation_id, child_work_id, opts \\ [])
      when is_binary(conversation_id) and is_binary(child_work_id) and is_list(opts) do
    actor = normalize_actor(Keyword.get(opts, :actor))

    with {:ok, %Conversation{} = conversation} <- Conversations.resume(conversation_id, actor: actor),
         {:ok, _pid} <- ensure_coordinator(conversation),
         {:ok, snapshot} <- Coordinator.cancel_child_work(conversation_id, child_work_id, actor) do
      {:ok, snapshot}
    end
  end

  @spec settle_child_work(String.t(), String.t(), ChildWork.settlement(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def settle_child_work(conversation_id, child_work_id, outcome, attrs \\ %{}, opts \\ [])
      when is_binary(conversation_id) and is_binary(child_work_id) and is_atom(outcome) and is_map(attrs) and
             is_list(opts) do
    actor = normalize_actor(Keyword.get(opts, :actor))

    with {:ok, %Conversation{} = conversation} <- Conversations.resume(conversation_id, actor: actor),
         {:ok, _pid} <- ensure_coordinator(conversation),
         {:ok, snapshot} <- Coordinator.settle_child_work(conversation_id, child_work_id, outcome, attrs, actor) do
      {:ok, snapshot}
    end
  end

  @spec events_since(String.t(), non_neg_integer(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def events_since(conversation_id, after_sequence, opts \\ [])
      when is_binary(conversation_id) and is_integer(after_sequence) and after_sequence >= 0 and is_list(opts) do
    actor = normalize_actor(Keyword.get(opts, :actor))

    with {:ok, %Conversation{} = conversation} <- Conversations.resume(conversation_id, actor: actor),
         {:ok, events} <- fetch_events(conversation, after_sequence) do
      {:ok, events}
    end
  end

  @spec snapshot(String.t()) :: {:ok, map()} | {:error, term()}
  def snapshot(conversation_id) when is_binary(conversation_id) do
    case Registry.lookup(@registry, conversation_id) do
      [{_pid, _value}] -> Coordinator.snapshot(conversation_id)
      [] -> Persistence.fetch_snapshot(conversation_id)
    end
  end

  @spec stop(String.t()) :: :ok
  def stop(conversation_id) when is_binary(conversation_id) do
    case Registry.lookup(@registry, conversation_id) do
      [{pid, _value}] ->
        DynamicSupervisor.terminate_child(@supervisor, pid)
        :ok

      [] ->
        :ok
    end
  end

  @spec ensure_coordinator(Conversation.t()) :: {:ok, pid()} | {:error, term()}
  def ensure_coordinator(%Conversation{} = conversation) do
    case Registry.lookup(@registry, conversation.id) do
      [{pid, _value}] ->
        {:ok, pid}

      [] ->
        sandbox_owner = Process.get({JidoCode.Repo, :sandbox_owner})

        case DynamicSupervisor.start_child(
               @supervisor,
               {Coordinator,
                {conversation, starter_pid: self(), sandbox_owner: sandbox_owner}}
             ) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          other -> other
        end
    end
  end

  defp fetch_events(%Conversation{} = conversation, after_sequence) do
    case Registry.lookup(@registry, conversation.id) do
      [{_pid, _value}] -> Coordinator.events_since(conversation.id, after_sequence)
      [] -> Persistence.events_since(conversation.id, after_sequence)
    end
  end

  defp normalize_actor(nil), do: Actor.operator_actor()
  defp normalize_actor(%{} = actor), do: Actor.operator_actor(actor)
end
