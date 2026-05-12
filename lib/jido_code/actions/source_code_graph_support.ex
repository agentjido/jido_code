defmodule JidoCode.Actions.SourceCodeGraphSupport do
  # covers: architecture.source_code_graph_pod.graph_revision_state_is_explicit_and_explainable
  # covers: architecture.source_code_graph_pod.stale_queries_and_failures_remain_bounded
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
       )
       |> then(fn graph_context ->
         Map.put(
           graph_context,
           :latest_analysis_status,
           latest_analysis_status(context, graph_context.latest_analysis_status)
         )
       end)
       |> then(fn graph_context ->
         Map.put(
           graph_context,
           :latest_failure,
           latest_failure(context, graph_context.latest_failure)
         )
       end)
       |> then(fn graph_context ->
         Map.put(
           graph_context,
           :source_graph_refresh,
           source_graph_refresh(context, graph_context.source_graph_refresh, managed_repo_id)
         )
       end)}
    end
  end

  @spec latest_import_status(map(), map()) :: map()
  def latest_import_status(context, default_status) do
    context[:latest_import_status] ||
      get_in(context, [:graph, :latest_import_status]) ||
      default_status
  end

  @spec latest_analysis_status(map(), map()) :: map()
  def latest_analysis_status(context, default_status) do
    context[:latest_analysis_status] ||
      get_in(context, [:graph, :latest_analysis_status]) ||
      default_status
  end

  @spec latest_failure(map(), map() | nil) :: map() | nil
  def latest_failure(context, default_failure) do
    context[:latest_failure] ||
      get_in(context, [:graph, :latest_failure]) ||
      default_failure
  end

  @spec source_graph_refresh(map(), map() | nil, String.t() | nil) :: map()
  def source_graph_refresh(context, default_refresh, managed_repo_id \\ nil) do
    refresh =
      context[:source_graph_refresh] ||
        get_in(context, [:graph, :source_graph_refresh]) ||
        default_refresh

    SourceCodeGraph.merge_refresh_status(refresh, managed_repo_id)
  end

  @spec ready?(map()) :: boolean()
  def ready?(status) when is_map(status), do: Map.get(status, :ready?, false)

  @spec stale_status(map(), map() | String.t() | nil) :: map()
  def stale_status(status, revision_metadata) when is_map(status) and is_map(revision_metadata) do
    current_revision = Map.get(revision_metadata, :current_revision) || Map.get(revision_metadata, :revision)

    target_revision =
      Map.get(revision_metadata, :requested_revision) ||
        Map.get(status, :requested_revision) ||
        current_revision

    status
    |> stale_status(target_revision)
    |> Map.put(:current_revision, current_revision)
  end

  def stale_status(status, requested_revision) when is_map(status) and is_binary(requested_revision) do
    imported_revision = Map.get(status, :imported_revision)
    ready? = ready?(status)

    cond do
      not ready? or is_nil(imported_revision) ->
        %{
          stale?: false,
          stale_reason: nil,
          imported_revision: imported_revision,
          current_revision: requested_revision,
          queryable_when_stale?: false
        }

      imported_revision == requested_revision ->
        %{
          stale?: false,
          stale_reason: nil,
          imported_revision: imported_revision,
          current_revision: requested_revision,
          queryable_when_stale?: false
        }

      true ->
        %{
          stale?: true,
          stale_reason: :workspace_revision_changed,
          imported_revision: imported_revision,
          current_revision: requested_revision,
          queryable_when_stale?: true
        }
    end
  end

  def stale_status(status, _requested_revision) when is_map(status) do
    %{
      stale?: false,
      stale_reason: nil,
      imported_revision: Map.get(status, :imported_revision),
      current_revision: nil,
      queryable_when_stale?: false
    }
  end

  @spec stale?(map(), map() | String.t() | nil) :: boolean()
  def stale?(status, revision_metadata), do: stale_status(status, revision_metadata).stale?

  defp normalize_managed_repo_id(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, :missing_managed_repo_id}
      managed_repo_id -> {:ok, managed_repo_id}
    end
  end

  defp normalize_managed_repo_id(_value), do: {:error, :missing_managed_repo_id}
end
