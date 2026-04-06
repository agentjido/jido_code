defmodule JidoCode.AgentOS.Manager.Server do
  @moduledoc """
  GenServer that owns and manages the ETS table for tracking kernels.
  """
  use GenServer
  @table_name JidoCode.AgentOS.Manager

  @doc false
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Create the ETS table - owned by this GenServer
    :ets.new(@table_name, [:named_table, :public, :set])
    {:ok, nil}
  end
end
