defmodule JidoCode.TestSupport.CodeServer.ProjectReaderFake do
  @moduledoc false

  @repo_scope_result_key {__MODULE__, :repo_scope_result}

  def put_repo_scope_result(repo_scope_result) do
    Process.put(@repo_scope_result_key, repo_scope_result)
    :ok
  end

  def clear do
    Process.delete(@repo_scope_result_key)
    :ok
  end

  def repo_scope(_identifier) do
    Process.get(@repo_scope_result_key, {:error, :repo_scope_not_found})
  end
end
