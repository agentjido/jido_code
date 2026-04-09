defmodule JidoCode.SourceCodeGraph.ProductService do
  @moduledoc """
  Product-owned semantic service boundary over AgentWorkspace.

  This module gives workbench and operator-facing features a bounded, repo-first
  semantic interface without exposing raw SPARQL, pod topology, or TripleStore
  internals.
  """

  alias JidoCode.AgentWorkspace
  alias JidoCode.SourceCodeGraph.ViewModel

  @type managed_repo_id :: String.t()
  @type workspace_path :: String.t()

  @spec status(managed_repo_id(), workspace_path(), keyword()) :: {:ok, map()} | {:error, atom(), map()}
  def status(managed_repo_id, workspace_path, opts \\ []) do
    case AgentWorkspace.source_code_graph_status(managed_repo_id, workspace_path, opts) do
      {:ok, status_result} ->
        {:ok, ViewModel.status(managed_repo_id, status_result)}

      {:error, reason} ->
        {:error, reason, ViewModel.error(:graph_status, managed_repo_id, reason, error_detail(reason), nil)}

      {:error, reason, detail} ->
        {:error, reason, ViewModel.error(:graph_status, managed_repo_id, reason, error_detail(reason, detail), nil)}
    end
  end

  @spec summary(managed_repo_id(), workspace_path(), keyword()) :: {:ok, map()} | {:error, atom(), map()}
  def summary(managed_repo_id, workspace_path, opts \\ []) do
    with {:ok, status_result} <- AgentWorkspace.source_code_graph_status(managed_repo_id, workspace_path, opts) do
      groups =
        if preview_available?(status_result, opts) do
          %{
            modules:
              preview_group(
                fn ->
                  AgentWorkspace.find_source_code_graph_modules(
                    managed_repo_id,
                    workspace_path,
                    Keyword.put_new(opts, :limit, 5)
                  )
                end,
                fn result -> ViewModel.modules(managed_repo_id, status_result, result) end
              ),
            runtime_patterns:
              preview_group(
                fn ->
                  AgentWorkspace.find_source_code_graph_runtime_patterns(
                    managed_repo_id,
                    workspace_path,
                    Keyword.put_new(opts, :limit, 5)
                  )
                end,
                fn result -> ViewModel.runtime_patterns(managed_repo_id, status_result, result) end
              )
          }
        else
          %{
            modules: %{status: :unavailable, count: 0, items: []},
            runtime_patterns: %{status: :unavailable, count: 0, items: []}
          }
        end

      {:ok, ViewModel.summary(managed_repo_id, status_result, groups)}
    else
      {:error, reason} ->
        {:error, reason, ViewModel.error(:semantic_summary, managed_repo_id, reason, error_detail(reason), nil)}

      {:error, reason, detail} ->
        {:error, reason, ViewModel.error(:semantic_summary, managed_repo_id, reason, error_detail(reason, detail), nil)}
    end
  end

  @spec modules(managed_repo_id(), workspace_path(), keyword()) :: {:ok, map()} | {:error, atom(), map()}
  def modules(managed_repo_id, workspace_path, opts \\ []) do
    semantic_lookup(managed_repo_id, workspace_path, opts, :modules, fn ->
      AgentWorkspace.find_source_code_graph_modules(managed_repo_id, workspace_path, opts)
    end)
  end

  @spec functions(managed_repo_id(), workspace_path(), keyword()) :: {:ok, map()} | {:error, atom(), map()}
  def functions(managed_repo_id, workspace_path, opts \\ []) do
    semantic_lookup(managed_repo_id, workspace_path, opts, :functions, fn ->
      AgentWorkspace.find_source_code_graph_functions(managed_repo_id, workspace_path, opts)
    end)
  end

  @spec runtime_patterns(managed_repo_id(), workspace_path(), keyword()) ::
          {:ok, map()} | {:error, atom(), map()}
  def runtime_patterns(managed_repo_id, workspace_path, opts \\ []) do
    semantic_lookup(managed_repo_id, workspace_path, opts, :runtime_patterns, fn ->
      AgentWorkspace.find_source_code_graph_runtime_patterns(managed_repo_id, workspace_path, opts)
    end)
  end

  @spec impact(managed_repo_id(), workspace_path(), keyword()) :: {:ok, map()} | {:error, atom(), map()}
  def impact(managed_repo_id, workspace_path, opts \\ []) do
    semantic_lookup(managed_repo_id, workspace_path, opts, :impact, fn ->
      AgentWorkspace.trace_source_code_graph_impact(managed_repo_id, workspace_path, opts)
    end)
  end

  defp semantic_lookup(managed_repo_id, workspace_path, opts, kind, query_fun) do
    with {:ok, status_result} <- AgentWorkspace.source_code_graph_status(managed_repo_id, workspace_path, opts) do
      case query_fun.() do
        {:ok, raw_result} ->
          {:ok, shape_result(kind, managed_repo_id, status_result, raw_result)}

        {:error, reason} ->
          {:error, reason, ViewModel.error(kind, managed_repo_id, reason, error_detail(reason), status_result)}

        {:error, reason, detail} ->
          {:error, reason, ViewModel.error(kind, managed_repo_id, reason, error_detail(reason, detail), status_result)}
      end
    else
      {:error, reason} ->
        {:error, reason, ViewModel.error(kind, managed_repo_id, reason, error_detail(reason), nil)}

      {:error, reason, detail} ->
        {:error, reason, ViewModel.error(kind, managed_repo_id, reason, error_detail(reason, detail), nil)}
    end
  end

  defp shape_result(:modules, managed_repo_id, status_result, raw_result),
    do: ViewModel.modules(managed_repo_id, status_result, raw_result)

  defp shape_result(:functions, managed_repo_id, status_result, raw_result),
    do: ViewModel.functions(managed_repo_id, status_result, raw_result)

  defp shape_result(:runtime_patterns, managed_repo_id, status_result, raw_result),
    do: ViewModel.runtime_patterns(managed_repo_id, status_result, raw_result)

  defp shape_result(:impact, managed_repo_id, status_result, raw_result),
    do: ViewModel.impact(managed_repo_id, status_result, raw_result)

  defp preview_available?(status_result, opts) do
    Map.get(status_result, :ready?, false) and
      (not Map.get(status_result, :stale?, false) or Keyword.get(opts, :allow_stale?, false))
  end

  defp preview_group(query_fun, builder) do
    case query_fun.() do
      {:ok, raw_result} -> ViewModel.summary_group(raw_result, builder)
      _other -> %{status: :unavailable, count: 0, items: []}
    end
  end

  defp error_detail(:source_code_graph_disabled), do: "Source-code graph capability is disabled for this repository."
  defp error_detail(:source_code_graph_not_ready), do: "Source-code graph data has not been loaded yet."

  defp error_detail(:source_code_graph_stale),
    do: "Source-code graph data is stale and should be refreshed before semantic inspection."

  defp error_detail(reason), do: "Semantic repository data is unavailable (#{reason})."

  defp error_detail(_reason, detail) when is_binary(detail), do: detail

  defp error_detail(_reason, detail) when is_map(detail) do
    Map.get(detail, :message) ||
      Map.get(detail, "message") ||
      Map.get(detail, :reason) ||
      Map.get(detail, "reason") ||
      inspect(detail)
  end

  defp error_detail(reason, _detail), do: error_detail(reason)
end
