defmodule JidoCode.Actions.MemoryGraphSupport do
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  # covers: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  @moduledoc false

  alias JidoCode.MemoryGraph

  @default_graph_name "memory"

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
    graph_name = params[:graph_name] || context[:graph_name] || @default_graph_name

    with {:ok, managed_repo_id} <- normalize_managed_repo_id(managed_repo_id),
         {:ok, graph_name} <- MemoryGraph.normalize_graph_name(graph_name),
         {:ok, graph_context} <- MemoryGraph.graph_context(managed_repo_id, workspace_path, revision: revision) do
      {:ok,
       graph_context
       |> Map.put(:selected_graph_name, graph_name)
       |> Map.put(:selected_named_graph_iri, MemoryGraph.named_graph_iri(graph_name))
       |> Map.put(
         :latest_record_status,
         latest_record_status(context, graph_context.latest_record_status)
       )
       |> Map.put(
         :latest_query_status,
         latest_query_status(context, graph_context.latest_query_status)
       )
       |> Map.put(
         :latest_validation_status,
         latest_validation_status(context, graph_context.latest_validation_status)
       )
       |> Map.put(
         :latest_failure,
         latest_failure(context, graph_context.latest_failure)
       )}
    end
  end

  @spec latest_record_status(map(), map()) :: map()
  def latest_record_status(context, default_status) do
    context[:latest_record_status] ||
      get_in(context, [:graph, :latest_record_status]) ||
      default_status
  end

  @spec latest_query_status(map(), map()) :: map()
  def latest_query_status(context, default_status) do
    context[:latest_query_status] ||
      get_in(context, [:graph, :latest_query_status]) ||
      default_status
  end

  @spec latest_validation_status(map(), map()) :: map()
  def latest_validation_status(context, default_status) do
    context[:latest_validation_status] ||
      get_in(context, [:graph, :latest_validation_status]) ||
      default_status
  end

  @spec latest_failure(map(), map() | nil) :: map() | nil
  def latest_failure(context, default_failure) do
    context[:latest_failure] ||
      get_in(context, [:graph, :latest_failure]) ||
      default_failure
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
    validated_revision = Map.get(status, :validated_revision)
    ready? = ready?(status)

    cond do
      not ready? or is_nil(validated_revision) ->
        %{
          stale?: false,
          stale_reason: nil,
          validated_revision: validated_revision,
          current_revision: requested_revision,
          queryable_when_stale?: false
        }

      validated_revision == requested_revision ->
        %{
          stale?: false,
          stale_reason: nil,
          validated_revision: validated_revision,
          current_revision: requested_revision,
          queryable_when_stale?: false
        }

      true ->
        %{
          stale?: true,
          stale_reason: :workspace_revision_changed,
          validated_revision: validated_revision,
          current_revision: requested_revision,
          queryable_when_stale?: true
        }
    end
  end

  def stale_status(status, _requested_revision) when is_map(status) do
    %{
      stale?: false,
      stale_reason: nil,
      validated_revision: Map.get(status, :validated_revision),
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
