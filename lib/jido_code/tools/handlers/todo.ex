defmodule JidoCode.Tools.Handlers.Todo do
  @moduledoc """
  Handler for the todo_write tool.

  Manages a structured task list with status tracking. The tool allows the
  LLM agent to maintain visibility into its work progress and plan multi-step
  tasks effectively.

  ## Todo Structure

  Each todo item has:
  - `content` - The task description (what needs to be done)
  - `status` - One of: "pending", "in_progress", "completed"
  - `active_form` - Present tense description shown during execution

  ## Usage

  The handler is invoked by the Executor when the LLM calls the todo_write tool:

      Executor.execute(%{
        id: "call_123",
        name: "todo_write",
        arguments: %{
          "todos" => [
            %{"content" => "Fix bug", "status" => "in_progress", "active_form" => "Fixing bug"},
            %{"content" => "Write tests", "status" => "pending", "active_form" => "Writing tests"}
          ]
        }
      })

  ## PubSub Integration

  Todo updates are broadcast via PubSub for TUI display:

      Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events", {:todo_update, todos})
  """

  alias JidoCode.PubSubHelpers

  @valid_statuses ["pending", "in_progress", "completed"]

  @doc """
  Writes/updates the todo list.

  ## Arguments

  - `"todos"` - Array of todo objects, each with:
    - `"content"` - Task description (required)
    - `"status"` - Status: "pending", "in_progress", or "completed" (required)
    - `"active_form"` - Present tense description (required)

  ## Returns

  - `{:ok, message}` - Success message
  - `{:error, reason}` - Validation error
  """
  def execute(%{"todos" => todos}, context) when is_list(todos) do
    with {:ok, validated_todos} <- validate_todos(todos) do
      # Broadcast the update via PubSub
      session_id = Map.get(context, :session_id)
      broadcast_todos(validated_todos, session_id)

      {:ok, format_success_message(validated_todos)}
    end
  end

  def execute(_args, _context) do
    {:error, "todo_write requires a todos array argument"}
  end

  # Validate all todos in the list
  defp validate_todos(todos) do
    validated =
      Enum.reduce_while(todos, {:ok, []}, fn todo, {:ok, acc} ->
        case validate_todo(todo) do
          {:ok, validated_todo} -> {:cont, {:ok, [validated_todo | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case validated do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp validate_todo(todo) when is_map(todo) do
    content = Map.get(todo, "content")
    status = Map.get(todo, "status")
    active_form = Map.get(todo, "active_form")

    cond do
      not is_binary(content) or content == "" ->
        {:error, "Each todo must have a non-empty 'content' string"}

      not is_binary(status) or status not in @valid_statuses ->
        {:error,
         "Each todo must have a valid 'status' (pending, in_progress, or completed), got: #{inspect(status)}"}

      not is_binary(active_form) or active_form == "" ->
        {:error, "Each todo must have a non-empty 'active_form' string"}

      true ->
        {:ok,
         %{
           content: content,
           status: String.to_atom(status),
           active_form: active_form
         }}
    end
  end

  defp validate_todo(_todo) do
    {:error, "Each todo must be a map with content, status, and active_form"}
  end

  defp broadcast_todos(todos, session_id) do
    message = {:todo_update, todos}
    PubSubHelpers.broadcast(session_id, message)
  end

  defp format_success_message(todos) do
    counts = count_by_status(todos)

    parts =
      [
        format_count(counts[:in_progress], "in progress"),
        format_count(counts[:pending], "pending"),
        format_count(counts[:completed], "completed")
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    if parts == "" do
      "Todo list cleared"
    else
      "Todo list updated: #{parts}"
    end
  end

  defp count_by_status(todos) do
    todos
    |> Enum.group_by(& &1.status)
    |> Map.new(fn {status, items} -> {status, length(items)} end)
  end

  defp format_count(nil, _label), do: nil
  defp format_count(0, _label), do: nil
  defp format_count(1, label), do: "1 #{label}"
  defp format_count(n, label), do: "#{n} #{label}"
end
