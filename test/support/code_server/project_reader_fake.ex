defmodule JidoCode.TestSupport.CodeServer.ProjectReaderFake do
  @moduledoc false

  @read_result_key {__MODULE__, :read_result}

  def put_read_result(read_result) do
    Process.put(@read_result_key, read_result)
    :ok
  end

  def clear do
    Process.delete(@read_result_key)
    :ok
  end

  def read(_opts) do
    Process.get(@read_result_key, {:ok, []})
  end
end
