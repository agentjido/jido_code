defmodule JidoCode.SourceCodeGraph.WorkflowService do
  # covers: architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
  # covers: architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_graph_context
  # covers: architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals
  # covers: architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
  # covers: architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
  # covers: architecture.policy_layers.runtime_policy_governs_runtime_capability
  # covers: architecture.policy_layers.runtime_entrypoints_seed_explicit_collaboration_context
  @moduledoc """
  Product-owned semantic workflow boundary over AgentWorkspace.

  This module keeps planning, review, and explanation flows explicit about when
  semantic graph context is requested and returns bounded product-shaped
  semantic input maps rather than raw graph query details.
  """

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.Actor
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.CaptureEnvelope
  alias JidoCode.SourceCodeGraph.{MemoryCapture, ProductFeedback, ProductService}

  @type workflow_kind :: :plan | :review | :explain
  @type workflow_result :: {:ok, map()} | {:error, term()} | {:error, atom(), map()}
  @workflow_provenance_actor Actor.factory_system_actor(%{
                               "id" => "system:source-code-graph-workflow-provenance",
                               "email" => "source-code-graph-workflow-provenance@system.local"
                             })

  @spec plan(String.t(), String.t(), String.t(), keyword()) :: workflow_result()
  def plan(managed_repo_id, work_item_id, instruction, opts \\ []) do
    run_workflow(:plan, managed_repo_id, work_item_id, instruction, opts)
  end

  @spec review(String.t(), String.t(), String.t(), keyword()) :: workflow_result()
  def review(managed_repo_id, work_item_id, instruction, opts \\ []) do
    run_workflow(:review, managed_repo_id, work_item_id, instruction, opts)
  end

  @spec explain(String.t(), String.t(), String.t(), keyword()) :: workflow_result()
  def explain(managed_repo_id, work_item_id, instruction, opts \\ []) do
    run_workflow(:explain, managed_repo_id, work_item_id, instruction, opts)
  end

  @spec record_memory(map(), keyword()) :: {:ok, map()} | {:error, term()} | {:error, atom(), map()}
  def record_memory(projection_or_finding, opts \\ []) do
    MemoryCapture.record(
      projection_or_finding,
      Keyword.put_new(opts, :classification_source, "semantic_workflow")
    )
  end

  defp run_workflow(workflow, managed_repo_id, work_item_id, instruction, opts)
       when workflow in [:plan, :review, :explain] and is_list(opts) do
    with {:ok, semantic_opts} <- normalize_semantic_opts(Keyword.get(opts, :semantic)),
         {:ok, workflow_provenance} <-
           workflow_provenance_context(
             workflow,
             managed_repo_id,
             work_item_id,
             instruction,
             opts,
             semantic_opts
           ),
         {:ok, semantic_input, runtime_semantic_opts} <-
           prepare_semantic_input(workflow, managed_repo_id, opts, semantic_opts),
         workspace_opts <- workspace_opts(opts, runtime_semantic_opts, workflow_provenance),
         {:ok, raw_result} <-
           invoke_workspace(workflow, managed_repo_id, work_item_id, instruction, workspace_opts) do
      {:ok, shape_result(workflow, managed_repo_id, work_item_id, raw_result, semantic_input, workflow_provenance)}
    else
      {:error, reason, detail} ->
        {:error, reason, workflow_error(workflow, managed_repo_id, work_item_id, reason, detail)}

      {:error, reason} ->
        {:error, reason, workflow_error(workflow, managed_repo_id, work_item_id, reason, nil)}
    end
  end

  defp invoke_workspace(:plan, managed_repo_id, work_item_id, instruction, opts),
    do: AgentWorkspace.plan_work(managed_repo_id, work_item_id, instruction, opts)

  defp invoke_workspace(:review, managed_repo_id, work_item_id, instruction, opts),
    do: AgentWorkspace.review_work(managed_repo_id, work_item_id, instruction, opts)

  defp invoke_workspace(:explain, managed_repo_id, work_item_id, instruction, opts),
    do: AgentWorkspace.explain_work(managed_repo_id, work_item_id, instruction, opts)

  defp prepare_semantic_input(_workflow, _managed_repo_id, _opts, nil), do: {:ok, nil, nil}

  defp prepare_semantic_input(workflow, managed_repo_id, opts, semantic_opts) when is_list(semantic_opts) do
    with {:ok, workspace_path} <-
           normalize_workspace_path(Keyword.get(semantic_opts, :workspace_path) || Keyword.get(opts, :workspace_path)),
         :ok <- ensure_supported_semantic_requests(semantic_opts),
         {:ok, _status_result, runtime_semantic_opts} <-
           prepare_graph(workflow, managed_repo_id, workspace_path, semantic_opts),
         {:ok, status_projection} <-
           ProductService.status(managed_repo_id, workspace_path, product_lookup_opts(runtime_semantic_opts)),
         {:ok, result_projections} <-
           semantic_result_projections(managed_repo_id, workspace_path, runtime_semantic_opts) do
      {:ok,
       %{
         workflow: workflow,
         graph: status_projection.graph,
         freshness: ProductFeedback.for_graph(status_projection.graph, status_projection.error),
         results: result_projections
       }, runtime_semantic_opts}
    end
  end

  defp prepare_graph(workflow, managed_repo_id, workspace_path, semantic_opts) do
    prepare_mode = Keyword.get(semantic_opts, :prepare, :load_if_missing)

    runtime_semantic_opts =
      semantic_opts
      |> Keyword.put(:workspace_path, workspace_path)
      |> Keyword.put(:prepare, :none)

    runtime_lookup_opts = product_lookup_opts(Keyword.put(semantic_opts, :workspace_path, workspace_path))

    result =
      case prepare_mode do
        :none ->
          AgentWorkspace.source_code_graph_status(managed_repo_id, workspace_path, runtime_lookup_opts)

        :load ->
          AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path, runtime_lookup_opts)

        :refresh ->
          AgentWorkspace.refresh_source_code_graph(managed_repo_id, workspace_path, runtime_lookup_opts)

        :recover ->
          with {:ok, recovery_result} <-
                 AgentWorkspace.recover_source_code_graph(managed_repo_id, workspace_path, runtime_lookup_opts) do
            {:ok, recovery_result.graph_status}
          end

        :load_if_missing ->
          with {:ok, status} <-
                 AgentWorkspace.source_code_graph_status(managed_repo_id, workspace_path, runtime_lookup_opts) do
            cond do
              status.ready? and status.stale? ->
                AgentWorkspace.refresh_source_code_graph(managed_repo_id, workspace_path, runtime_lookup_opts)

              status.ready? ->
                {:ok, status}

              true ->
                AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path, runtime_lookup_opts)
            end
          end

        other ->
          {:error, :unsupported_semantic_prepare_mode,
           %{
             workflow: workflow,
             prepare: other
           }}
      end

    case result do
      {:ok, status_result} -> {:ok, status_result, runtime_semantic_opts}
      {:error, reason, detail} -> {:error, reason, detail}
      {:error, reason} -> {:error, reason}
    end
  end

  defp semantic_result_projections(managed_repo_id, workspace_path, semantic_opts) do
    projections =
      []
      |> maybe_add_projection(:modules, Keyword.get(semantic_opts, :modules), fn request_opts ->
        ProductService.modules(managed_repo_id, workspace_path, merge_lookup_opts(semantic_opts, request_opts))
      end)
      |> maybe_add_projection(:functions, Keyword.get(semantic_opts, :functions), fn request_opts ->
        ProductService.functions(managed_repo_id, workspace_path, merge_lookup_opts(semantic_opts, request_opts))
      end)
      |> maybe_add_projection(:runtime_patterns, Keyword.get(semantic_opts, :runtime_patterns), fn request_opts ->
        ProductService.runtime_patterns(
          managed_repo_id,
          workspace_path,
          merge_lookup_opts(semantic_opts, request_opts)
        )
      end)
      |> maybe_add_projection(:impact, Keyword.get(semantic_opts, :impact), fn request_opts ->
        ProductService.impact(managed_repo_id, workspace_path, merge_lookup_opts(semantic_opts, request_opts))
      end)

    Enum.reduce_while(projections, {:ok, %{}}, fn {name, fun}, {:ok, acc} ->
      case fun.() do
        {:ok, projection} ->
          {:cont, {:ok, Map.put(acc, name, projection)}}

        {:error, reason, projection} ->
          {:halt, {:error, reason, projection}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp maybe_add_projection(projections, _name, nil, _fun), do: projections

  defp maybe_add_projection(projections, name, request_opts, fun) when is_list(request_opts) do
    projections ++ [{name, fn -> fun.(request_opts) end}]
  end

  defp normalize_semantic_opts(nil), do: {:ok, nil}
  defp normalize_semantic_opts(opts) when is_list(opts), do: {:ok, opts}
  defp normalize_semantic_opts(_opts), do: {:error, :invalid_semantic_options}

  defp ensure_supported_semantic_requests(semantic_opts) do
    if Keyword.has_key?(semantic_opts, :query) or Keyword.has_key?(semantic_opts, :sparql) do
      {:error, :unsupported_raw_semantic_query}
    else
      :ok
    end
  end

  defp workspace_opts(opts, nil, nil), do: Keyword.delete(opts, :semantic)

  defp workspace_opts(opts, runtime_semantic_opts, workflow_provenance) do
    opts
    |> Keyword.delete(:semantic)
    |> Keyword.put(:source_code_graph, runtime_semantic_opts)
    |> maybe_put_provenance(workflow_provenance)
  end

  defp merge_lookup_opts(semantic_opts, request_opts) do
    product_lookup_opts(semantic_opts) ++ request_opts
  end

  defp product_lookup_opts(semantic_opts) do
    Keyword.take(semantic_opts, [:revision, :allow_stale?])
  end

  defp normalize_workspace_path(path) when is_binary(path) do
    case String.trim(path) do
      "" -> {:error, :missing_workspace_path}
      normalized -> {:ok, normalized}
    end
  end

  defp normalize_workspace_path(_path), do: {:error, :missing_workspace_path}

  defp shape_result(:plan, managed_repo_id, work_item_id, raw_result, semantic_input, workflow_provenance) do
    %{
      workflow: :plan,
      managed_repo_id: managed_repo_id,
      work_item_id: work_item_id,
      instruction: Map.get(raw_result, :instruction),
      plan: Map.get(raw_result, :plan),
      semantic_input: semantic_input,
      workflow_provenance: provenance_summary(workflow_provenance)
    }
  end

  defp shape_result(:review, managed_repo_id, work_item_id, raw_result, semantic_input, workflow_provenance) do
    %{
      workflow: :review,
      managed_repo_id: managed_repo_id,
      work_item_id: work_item_id,
      instruction: Map.get(raw_result, :instruction),
      feedback: Map.get(raw_result, :feedback),
      semantic_input: semantic_input,
      workflow_provenance: provenance_summary(workflow_provenance)
    }
  end

  defp shape_result(:explain, managed_repo_id, work_item_id, raw_result, semantic_input, workflow_provenance) do
    %{
      workflow: :explain,
      managed_repo_id: managed_repo_id,
      work_item_id: work_item_id,
      instruction: Map.get(raw_result, :instruction),
      explanation: Map.get(raw_result, :explanation),
      semantic_input: semantic_input,
      workflow_provenance: provenance_summary(workflow_provenance)
    }
  end

  defp workflow_provenance_context(_workflow, _managed_repo_id, _work_item_id, _instruction, _opts, nil),
    do: {:ok, nil}

  defp workflow_provenance_context(workflow, managed_repo_id, work_item_id, instruction, opts, semantic_opts)
       when is_list(semantic_opts) do
    workspace_path =
      Keyword.get(semantic_opts, :workspace_path) ||
        Keyword.get(opts, :workspace_path)

    with {:ok, workspace_path} <- normalize_workspace_path(workspace_path) do
      context = %{
        enabled?: MemoryGraph.capability_enabled?(opts),
        session_id: provenance_session_id(workflow, work_item_id, opts),
        actor_id: provenance_actor_id(opts),
        revision: Keyword.get(semantic_opts, :revision),
        workflow: workflow
      }

      _ =
        capture_workflow_preparation(
          managed_repo_id,
          work_item_id,
          workspace_path,
          instruction,
          semantic_opts,
          context
        )

      {:ok, context}
    else
      _other -> {:ok, nil}
    end
  end

  defp capture_workflow_preparation(
         managed_repo_id,
         work_item_id,
         workspace_path,
         instruction,
         semantic_opts,
         context
       ) do
    if context.enabled? do
      revision = context.revision
      _ = ensure_workflow_provenance_ready(managed_repo_id, workspace_path, revision)

      session_capture =
        CaptureEnvelope.work_session(
          session_id: context.session_id,
          actor_id: context.actor_id,
          workflow: context.workflow,
          work_item_id: work_item_id,
          goal: instruction,
          outcome: "semantic-preparation",
          revision: revision
        )

      prompt_capture =
        CaptureEnvelope.prompt_turn(
          session_id: context.session_id,
          actor_id: context.actor_id,
          workflow: context.workflow,
          work_item_id: work_item_id,
          content:
            inspect(
              %{
                instruction: instruction,
                semantic_requests: Keyword.drop(semantic_opts, [:workspace_path])
              },
              pretty: true,
              limit: :infinity
            ),
          revision: revision
        )

      _ =
        AgentWorkspace.record_memory_graph(
          managed_repo_id,
          workspace_path,
          session_capture,
          graph_name: MemoryGraph.workflow_provenance_graph_name(),
          revision: revision
        )

      _ =
        AgentWorkspace.record_memory_graph(
          managed_repo_id,
          workspace_path,
          prompt_capture,
          graph_name: MemoryGraph.workflow_provenance_graph_name(),
          revision: revision
        )

      :ok
    else
      :ok
    end
  end

  defp ensure_workflow_provenance_ready(managed_repo_id, workspace_path, revision) do
    case AgentWorkspace.memory_graph_status(
           managed_repo_id,
           workspace_path,
           graph_name: MemoryGraph.workflow_provenance_graph_name(),
           revision: revision
         ) do
      {:ok, %{ready?: true, stale?: false}} ->
        :ok

      _other ->
        case AgentWorkspace.refresh_memory_graph(
               managed_repo_id,
               workspace_path,
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             ) do
          {:ok, _result} -> :ok
          _other -> :ok
        end
    end
  end

  defp maybe_put_provenance(opts, nil), do: opts

  defp maybe_put_provenance(opts, workflow_provenance) do
    Keyword.put(
      opts,
      :provenance,
      session_id: workflow_provenance.session_id,
      actor_id: workflow_provenance.actor_id,
      revision: workflow_provenance.revision
    )
  end

  defp provenance_session_id(workflow, work_item_id, opts) do
    opts
    |> Keyword.get(:provenance, [])
    |> Keyword.get(:session_id, "#{workflow}-#{work_item_id}-#{System.unique_integer([:positive])}")
  end

  defp provenance_actor_id(opts) do
    case Keyword.get(opts, :actor) do
      %{} = actor -> actor["id"] || actor[:id] || @workflow_provenance_actor["id"]
      _other -> @workflow_provenance_actor["id"]
    end
  end

  defp provenance_summary(nil), do: nil
  defp provenance_summary(%{enabled?: false}), do: nil

  defp provenance_summary(provenance) do
    %{
      session_id: provenance.session_id,
      actor_id: provenance.actor_id,
      revision: provenance.revision,
      workflow: provenance.workflow
    }
  end

  defp workflow_error(workflow, managed_repo_id, work_item_id, reason, detail) do
    {graph, error} =
      case detail do
        %{graph: graph, error: error} -> {graph, error}
        %{graph: graph} -> {graph, nil}
        _other -> {ProductFeedback.fallback_graph(reason), nil}
      end

    feedback =
      case {detail, error} do
        {%{feedback: feedback}, _error} when is_map(feedback) -> feedback
        _other -> ProductFeedback.for_graph(graph, error)
      end

    %{
      workflow: workflow,
      managed_repo_id: managed_repo_id,
      work_item_id: work_item_id,
      graph: ProductFeedback.normalize_graph(graph, reason),
      feedback: feedback,
      error: %{
        type: reason,
        detail: feedback.detail,
        remediation: feedback.remediation
      }
    }
  end
end
