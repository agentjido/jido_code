defmodule JidoCode.CodingAssistance do
  # covers: coding_assistance.boundary.product_local_driver_api
  @moduledoc """
  Product-local coding assistance boundary.

  This module provides the product-owned interface for coding assistance
  operations without external runtime dependencies.
  """

  @type turn_params :: %{
          optional(:session_id) => String.t(),
          optional(:project_id) => String.t(),
          optional(:request_id) => String.t(),
          optional(:correlation_id) => String.t(),
          optional(:workspace_id) => String.t(),
          optional(:objective) => String.t(),
          optional(:operation) => String.t(),
          optional(:prompt_variables) => map(),
          optional(:tool_intent) => map()
        }

  @type session_params :: %{
          optional(:project_id) => String.t(),
          optional(:request_id) => String.t(),
          optional(:correlation_id) => String.t(),
          optional(:workspace_id) => String.t()
        }

  @doc """
  Prepares a coding assistance session for the given actor and context.
  """
  @spec ensure_session(String.t(), session_params()) :: {:ok, map()} | {:error, term()}
  def ensure_session(_actor_id, _params) do
    {:ok, %{session_id: unique_id("session")}}
  end

  @doc """
  Starts a new coding turn for the given actor and parameters.
  """
  @spec start_turn(String.t(), turn_params()) :: {:ok, map()} | {:error, term()}
  def start_turn(actor_id, params) when is_binary(actor_id) and is_map(params) do
    {:ok,
     %{
       turn_id: unique_id("turn"),
       session_id: get_string(params, :session_id) || unique_id("session"),
       state: "completed",
       assistant_output: %{
         message: get_string(params, :objective) || "Coding assistance request received."
       }
     }}
  end

  @doc """
  Submits a direct coding assistance request (compatibility wrapper).
  """
  @spec assist(String.t(), turn_params()) :: {:ok, map()} | {:error, term()}
  def assist(actor_id, params) when is_binary(actor_id) and is_map(params) do
    start_turn(actor_id, params)
  end

  @doc """
  Gets an existing turn by ID.
  """
  @spec get_turn(String.t(), turn_params()) :: {:ok, map()} | {:error, term()}
  def get_turn(_actor_id, params) when is_map(params) do
    turn_id = get_string(params, :turn_id)

    if is_binary(turn_id) do
      {:ok,
       %{
         turn_id: turn_id,
         state: "completed",
         assistant_output: %{
           message: "Turn #{turn_id}"
         }
       }}
    else
      {:error, :missing_turn_id}
    end
  end

  @doc """
  Lists turns for a session.
  """
  @spec list_turns(String.t(), turn_params()) :: {:ok, [map()]} | {:error, term()}
  def list_turns(_actor_id, _params) do
    {:ok, []}
  end

  @doc """
  Lists events for a turn.
  """
  @spec list_turn_events(String.t(), turn_params()) :: {:ok, [map()]} | {:error, term()}
  def list_turn_events(_actor_id, _params) do
    {:ok, []}
  end

  @doc """
  Subscribes to live turn events.
  """
  @spec subscribe_turn_events(String.t(), turn_params()) :: {:ok, map()} | {:error, term()}
  def subscribe_turn_events(actor_id, params) when is_binary(actor_id) and is_map(params) do
    turn_id = get_string(params, :turn_id)

    {:ok,
     %{
       subscription_id: unique_id("sub"),
       turn_id: turn_id,
       status: "subscribed",
       session_id: get_string(params, :session_id)
     }}
  end

  @doc """
  Unsubscribes from live turn events.
  """
  @spec unsubscribe_turn_events(String.t(), turn_params()) :: {:ok, map()} | {:error, term()}
  def unsubscribe_turn_events(_actor_id, _params) do
    {:ok, %{status: "detached"}}
  end

  @doc """
  Lists artifacts for a turn.
  """
  @spec list_turn_artifacts(String.t(), turn_params()) :: {:ok, [map()]} | {:error, term()}
  def list_turn_artifacts(_actor_id, _params) do
    {:ok, []}
  end

  @doc """
  Cancels a turn.
  """
  @spec cancel_turn(String.t(), turn_params()) :: {:ok, map()} | {:error, term()}
  def cancel_turn(_actor_id, params) when is_map(params) do
    turn_id = get_string(params, :turn_id)

    if is_binary(turn_id) do
      {:ok, %{turn_id: turn_id, state: "cancelled"}}
    else
      {:error, :missing_turn_id}
    end
  end

  @doc """
  Reviews a turn for operator inspection.
  """
  @spec review_turn(String.t(), turn_params()) :: {:ok, map()} | {:error, term()}
  def review_turn(_actor_id, params) when is_map(params) do
    turn_id = get_string(params, :turn_id)

    if is_binary(turn_id) do
      {:ok,
       %{
         turn_id: turn_id,
         review_summary: "Turn review placeholder."
       }}
    else
      {:error, :missing_turn_id}
    end
  end

  @doc """
  Looks up an existing session.
  """
  @spec lookup_session(String.t(), session_params()) :: {:ok, map()} | {:error, term()}
  def lookup_session(_actor_id, _params) do
    {:ok, %{session_id: unique_id("session")}}
  end

  @doc """
  Binds a session to a project.
  """
  @spec bind_project(String.t(), String.t(), String.t(), session_params()) :: {:ok, map()} | {:error, term()}
  def bind_project(_session_id, _actor_id, _project_id, _params) do
    {:ok, %{}}
  end

  @doc """
  Rebinds a session to a different project.
  """
  @spec rebind_project(String.t(), String.t(), String.t(), session_params()) :: {:ok, map()} | {:error, term()}
  def rebind_project(_session_id, _actor_id, _project_id, _params) do
    {:ok, %{}}
  end

  @doc """
  Unbinds a session from its project.
  """
  @spec unbind_project(String.t(), String.t(), session_params()) :: {:ok, map()} | {:error, term()}
  def unbind_project(_session_id, _actor_id, _params) do
    {:ok, %{}}
  end

  @doc """
  Updates AI selection for a session.
  """
  @spec update_ai_selection(String.t(), String.t(), map(), session_params()) :: {:ok, map()} | {:error, term()}
  def update_ai_selection(_session_id, _actor_id, _selection, _params) do
    {:ok, %{}}
  end

  @doc """
  Gets AI selection for a session.
  """
  @spec get_ai_selection(String.t(), String.t(), session_params()) :: {:ok, map()} | {:error, term()}
  def get_ai_selection(_session_id, _actor_id, _params) do
    {:ok, %{model_profile: "balanced"}}
  end

  # Helper functions

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp get_string(map, key) when is_map(map) do
    value = Map.get(map, key) || Map.get(map, Atom.to_string(key))

    if is_binary(value) and value != "", do: value, else: nil
  end

  defp get_string(_map, _key), do: nil
end
