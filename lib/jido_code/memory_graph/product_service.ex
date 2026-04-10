defmodule JidoCode.MemoryGraph.ProductService do
  # covers: architecture.memory_graph_product_adoption.product_owned_memory_service_boundary
  # covers: architecture.memory_graph_product_adoption.memory_operator_surfaces_show_freshness_validation_and_recovery
  # covers: architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals
  # covers: architecture.memory_graph_product_adoption.memory_and_provenance_views_can_cross_link_to_source_code
  @moduledoc """
  Product-owned memory service boundary over AgentWorkspace.

  This module gives product callers bounded access to repository memory and
  workflow provenance without exposing raw SPARQL, pod topology, or store
  handles in UI-owned code.
  """

  alias JidoCode.AgentWorkspace
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.{CrossGraphNavigation, HelperQueries, ViewModel}

  @type managed_repo_id :: String.t()
  @type workspace_path :: String.t()

  @spec status(managed_repo_id(), workspace_path(), keyword()) :: {:ok, map()} | {:error, atom(), map()}
  def status(managed_repo_id, workspace_path, opts \\ []) do
    case AgentWorkspace.memory_graph_status(managed_repo_id, workspace_path, opts) do
      {:ok, status_result} ->
        {:ok, ViewModel.status(managed_repo_id, status_result)}

      {:error, reason} ->
        {:error, reason, ViewModel.error(:memory_graph_status, managed_repo_id, reason, error_detail(reason), nil)}

      {:error, reason, detail} ->
        {:error, reason, ViewModel.error(:memory_graph_status, managed_repo_id, reason, error_detail(reason, detail), nil)}
    end
  end

  @spec recover(managed_repo_id(), workspace_path(), keyword()) :: {:ok, map()} | {:error, atom(), map()}
  def recover(managed_repo_id, workspace_path, opts \\ []) do
    case AgentWorkspace.recover_memory_graph(managed_repo_id, workspace_path, opts) do
      {:ok, %{graph_status: graph_status}} ->
        {:ok, ViewModel.recovery(managed_repo_id, graph_status)}

      {:ok, graph_status} when is_map(graph_status) ->
        {:ok, ViewModel.recovery(managed_repo_id, graph_status)}

      {:error, reason} ->
        {:error, reason, ViewModel.error(:memory_graph_recovery, managed_repo_id, reason, error_detail(reason), nil)}

      {:error, reason, detail} ->
        {:error, reason, ViewModel.error(:memory_graph_recovery, managed_repo_id, reason, error_detail(reason, detail), nil)}
    end
  end

  @spec summary(managed_repo_id(), workspace_path(), keyword()) :: {:ok, map()} | {:error, atom(), map()}
  def summary(managed_repo_id, workspace_path, opts \\ []) do
    with {:ok, status_result} <- AgentWorkspace.memory_graph_status(managed_repo_id, workspace_path, opts) do
      groups =
        if preview_available?(status_result, opts) do
          %{
            memories:
              preview_group(
                fn -> memories(managed_repo_id, workspace_path, Keyword.put_new(opts, :limit, 5)) end,
                fn result -> result end
              ),
            provenance:
              preview_group(
                fn -> provenance(managed_repo_id, workspace_path, Keyword.put_new(opts, :limit, 5)) end,
                fn result -> result end
              )
          }
        else
          %{
            memories: %{status: :unavailable, count: 0, items: []},
            provenance: %{status: :unavailable, count: 0, items: []}
          }
        end

      {:ok, ViewModel.summary(managed_repo_id, status_result, groups)}
    else
      {:error, reason} ->
        {:error, reason, ViewModel.error(:memory_graph_summary, managed_repo_id, reason, error_detail(reason), nil)}

      {:error, reason, detail} ->
        {:error, reason, ViewModel.error(:memory_graph_summary, managed_repo_id, reason, error_detail(reason, detail), nil)}
    end
  end

  @spec memories(managed_repo_id(), workspace_path(), keyword()) :: {:ok, map()} | {:error, atom(), map()}
  def memories(managed_repo_id, workspace_path, opts \\ []) do
    memory_lookup(managed_repo_id, workspace_path, opts, :memories, MemoryGraph.memory_graph_name(), fn ->
      HelperQueries.memories(managed_repo_id, Map.new(opts))
    end)
  end

  @spec provenance(managed_repo_id(), workspace_path(), keyword()) :: {:ok, map()} | {:error, atom(), map()}
  def provenance(managed_repo_id, workspace_path, opts \\ []) do
    memory_lookup(
      managed_repo_id,
      workspace_path,
      opts,
      :provenance,
      MemoryGraph.workflow_provenance_graph_name(),
      fn ->
        HelperQueries.provenance(managed_repo_id, Map.new(opts))
      end
    )
  end

  @spec cross_links(managed_repo_id(), workspace_path(), String.t(), keyword()) ::
          {:ok, map()} | {:error, atom(), map()}
  def cross_links(managed_repo_id, workspace_path, resource_iri, opts \\ []) when is_binary(resource_iri) do
    status_opts = Keyword.take(opts, [:revision, :allow_stale?])

    with {:ok, graph_name} <- graph_name_for_resource(managed_repo_id, resource_iri),
         {:ok, status_result} <-
           AgentWorkspace.memory_graph_status(managed_repo_id, workspace_path, status_opts ++ [graph_name: graph_name]),
         true <- preview_available?(status_result, opts) or
                   {:error, graph_reason(status_result), ViewModel.error(:cross_links, managed_repo_id, graph_reason(status_result), error_detail(graph_reason(status_result)), status_result)},
         {:ok, query_result} <-
           AgentWorkspace.query_memory_graph(
             managed_repo_id,
             workspace_path,
             HelperQueries.cross_links(managed_repo_id, resource_iri),
             status_opts ++ [graph_name: graph_name]
           ) do
      navigation = CrossGraphNavigation.build(managed_repo_id, workspace_path, Map.get(query_result, :bindings, []))
      {:ok, ViewModel.cross_links(managed_repo_id, status_result, resource_iri, navigation)}
    else
      {:error, reason, detail} ->
        if is_map(detail) and Map.has_key?(detail, :kind) do
          {:error, reason, detail}
        else
          {:error, reason, ViewModel.error(:cross_links, managed_repo_id, reason, error_detail(reason, detail), nil)}
        end

      {:error, reason} ->
        {:error, reason, ViewModel.error(:cross_links, managed_repo_id, reason, error_detail(reason), nil)}
    end
  end

  defp memory_lookup(managed_repo_id, workspace_path, opts, kind, graph_name, query_builder) do
    status_opts = Keyword.take(opts, [:revision, :allow_stale?]) ++ [graph_name: graph_name]

    with {:ok, status_result} <- AgentWorkspace.memory_graph_status(managed_repo_id, workspace_path, status_opts),
         :ok <- ensure_queryable(status_result, opts),
         {:ok, raw_result} <-
           AgentWorkspace.query_memory_graph(
             managed_repo_id,
             workspace_path,
             query_builder.(),
             Keyword.take(opts, [:revision, :allow_stale?]) ++ [graph_name: graph_name]
           ) do
      {:ok, shape_result(kind, managed_repo_id, status_result, raw_result)}
    else
      {:error, reason} ->
        {:error, reason, ViewModel.error(kind, managed_repo_id, reason, error_detail(reason), nil)}

      {:error, reason, detail} ->
        {:error, reason, ViewModel.error(kind, managed_repo_id, reason, error_detail(reason, detail), nil)}
    end
  end

  defp shape_result(:memories, managed_repo_id, status_result, raw_result),
    do: ViewModel.memories(managed_repo_id, status_result, raw_result)

  defp shape_result(:provenance, managed_repo_id, status_result, raw_result),
    do: ViewModel.provenance(managed_repo_id, status_result, raw_result)

  defp preview_available?(status_result, opts) do
    allow_stale? = Keyword.get(opts, :allow_stale?, false)

    cond do
      Map.get(status_result, :ready?, false) and not Map.get(status_result, :stale?, false) ->
        true

      Map.get(status_result, :stale?, false) and allow_stale? and
          Map.get(status_result, :queryable_when_stale?, false) ->
        true

      true ->
        false
    end
  end

  defp preview_group(query_fun, builder) do
    case query_fun.() do
      {:ok, projection} ->
        ViewModel.summary_group(projection, builder)

      _other ->
        %{status: :unavailable, count: 0, items: []}
    end
  end

  defp ensure_queryable(status_result, opts) do
    if preview_available?(status_result, opts) do
      :ok
    else
      {:error, graph_reason(status_result)}
    end
  end

  defp graph_reason(status_result) do
    cond do
      Map.get(status_result, :latest_failure) -> :memory_graph_failed
      Map.get(status_result, :state) == :invalidated -> :memory_graph_invalidated
      Map.get(status_result, :stale?, false) -> :memory_graph_stale
      Map.get(status_result, :ready?, false) == false -> :memory_graph_not_ready
      true -> :memory_graph_unavailable
    end
  end

  defp graph_name_for_resource(managed_repo_id, resource_iri) do
    cond do
      String.starts_with?(resource_iri, MemoryGraph.base_iri(managed_repo_id)) ->
        {:ok, MemoryGraph.memory_graph_name()}

      String.starts_with?(resource_iri, MemoryGraph.workflow_provenance_base_iri(managed_repo_id)) ->
        {:ok, MemoryGraph.workflow_provenance_graph_name()}

      true ->
        {:error, :memory_graph_cross_link_not_found}
    end
  end

  defp error_detail(:memory_graph_disabled), do: "Repository memory is disabled for this managed repository."
  defp error_detail(:memory_graph_not_ready), do: "Repository memory has not been prepared yet."
  defp error_detail(:memory_graph_stale), do: "Repository memory is stale and should be validated before bounded recall."
  defp error_detail(:memory_graph_invalidated), do: "Repository memory was invalidated and should be revalidated before bounded recall."
  defp error_detail(:memory_graph_failed), do: "Repository memory recovery is required before bounded recall."
  defp error_detail(:memory_graph_cross_link_not_found), do: "Cross-graph navigation is unavailable for the requested resource."
  defp error_detail(reason), do: "Repository memory is unavailable (#{reason})."

  defp error_detail(_reason, detail) when is_binary(detail), do: detail

  defp error_detail(_reason, detail) when is_map(detail) do
    Map.get(detail, :message) ||
      Map.get(detail, "message") ||
      get_in(detail, [:feedback, :detail]) ||
      get_in(detail, ["feedback", "detail"]) ||
      Map.get(detail, :reason) ||
      Map.get(detail, "reason") ||
      inspect(detail)
  end

  defp error_detail(reason, _detail), do: error_detail(reason)
end
