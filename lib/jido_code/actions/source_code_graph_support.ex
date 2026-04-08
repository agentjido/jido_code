defmodule JidoCode.Actions.SourceCodeGraphSupport do
  @moduledoc false

  alias JidoCode.SourceCodeGraph

  @spec resolve_graph_context(map(), map()) :: {:ok, map()} | {:error, atom()}
  def resolve_graph_context(params, context) when is_map(params) and is_map(context) do
    managed_repo_id = params[:managed_repo_id] || context[:managed_repo_id]

    workspace_path =
      params[:workspace_path] ||
        context[:workspace_path] ||
        get_in(context, [:project, :workspace_path]) ||
        get_in(context, [:tool_context, :workspace_path]) ||
        get_in(context, [:tool_context, "workspace_path"])

    revision = params[:revision] || get_in(context, [:graph, :revision])

    with {:ok, managed_repo_id} <- normalize_managed_repo_id(managed_repo_id),
         {:ok, graph_context} <- SourceCodeGraph.graph_context(managed_repo_id, workspace_path, revision: revision) do
      {:ok,
       Map.put(
         graph_context,
         :latest_import_status,
         latest_import_status(context, graph_context.latest_import_status)
       )}
    end
  end

  @spec latest_import_status(map(), map()) :: map()
  def latest_import_status(context, default_status) do
    context[:latest_import_status] ||
      get_in(context, [:graph, :latest_import_status]) ||
      default_status
  end

  @spec ready?(map()) :: boolean()
  def ready?(status) when is_map(status), do: Map.get(status, :ready?, false)

  defp normalize_managed_repo_id(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, :missing_managed_repo_id}
      managed_repo_id -> {:ok, managed_repo_id}
    end
  end

  defp normalize_managed_repo_id(_value), do: {:error, :missing_managed_repo_id}
end
