defmodule JidoCode.Memory.Actions do
  @moduledoc """
  Memory actions for LLM agent memory management.

  This module provides a registry and discovery mechanism for memory-related
  Jido Actions. These actions allow the LLM agent to explicitly manage its
  long-term memory through tool calls.

  ## Available Actions

  - `Remember` - Persist important information to long-term memory
  - `Recall` - Query and retrieve memories from long-term storage
  - `Forget` - Mark memories as superseded (soft delete)

  ## Usage

  To get all available memory actions:

      JidoCode.Memory.Actions.all()
      # => [Remember, Recall, Forget]

  To get a specific action by name:

      {:ok, module} = JidoCode.Memory.Actions.get("remember")
      module.run(%{content: "...", type: :fact}, context)

  To get tool definitions for LLM integration:

      JidoCode.Memory.Actions.to_tool_definitions()
      # => [%{name: "remember", description: "...", parameters_schema: %{...}}, ...]

  """

  alias JidoCode.Memory.Actions.{Remember, Recall, Forget}

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Returns all memory action modules.

  ## Examples

      iex> JidoCode.Memory.Actions.all()
      [JidoCode.Memory.Actions.Remember, JidoCode.Memory.Actions.Recall, JidoCode.Memory.Actions.Forget]

  """
  @spec all() :: [module()]
  def all do
    [Remember, Recall, Forget]
  end

  @doc """
  Returns the action module for the given name.

  ## Examples

      iex> JidoCode.Memory.Actions.get("remember")
      {:ok, JidoCode.Memory.Actions.Remember}

      iex> JidoCode.Memory.Actions.get("recall")
      {:ok, JidoCode.Memory.Actions.Recall}

      iex> JidoCode.Memory.Actions.get("forget")
      {:ok, JidoCode.Memory.Actions.Forget}

      iex> JidoCode.Memory.Actions.get("unknown")
      {:error, :not_found}

  """
  @spec get(String.t()) :: {:ok, module()} | {:error, :not_found}
  def get(name) when is_binary(name) do
    case name do
      "remember" -> {:ok, Remember}
      "recall" -> {:ok, Recall}
      "forget" -> {:ok, Forget}
      _ -> {:error, :not_found}
    end
  end

  def get(_), do: {:error, :not_found}

  @doc """
  Returns all memory action names.

  ## Examples

      iex> JidoCode.Memory.Actions.names()
      ["remember", "recall", "forget"]

  """
  @spec names() :: [String.t()]
  def names do
    ["remember", "recall", "forget"]
  end

  @doc """
  Checks if the given name is a memory action.

  ## Examples

      iex> JidoCode.Memory.Actions.memory_action?("remember")
      true

      iex> JidoCode.Memory.Actions.memory_action?("read_file")
      false

  """
  @spec memory_action?(String.t()) :: boolean()
  def memory_action?(name) when is_binary(name) do
    name in names()
  end

  def memory_action?(_), do: false

  @doc """
  Returns tool definitions for all memory actions.

  Each tool definition includes:
  - `name` - The action name (e.g., "remember")
  - `description` - What the action does
  - `parameters_schema` - JSON Schema for the action parameters
  - `function` - The function to execute the action

  ## Examples

      iex> defs = JidoCode.Memory.Actions.to_tool_definitions()
      iex> length(defs)
      3
      iex> Enum.map(defs, & &1.name)
      ["remember", "recall", "forget"]

  """
  @spec to_tool_definitions() :: [map()]
  def to_tool_definitions do
    Enum.map(all(), &action_to_tool_def/1)
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  defp action_to_tool_def(action_module) do
    action_module.to_tool()
  end
end
