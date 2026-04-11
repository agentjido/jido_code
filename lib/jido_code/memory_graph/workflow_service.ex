defmodule JidoCode.MemoryGraph.WorkflowService do
  # covers: architecture.memory_graph_product_adoption.product_owned_memory_service_boundary
  # covers: architecture.memory_graph_product_adoption.memory_workflows_request_explicit_memory_context
  # covers: architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals
  # covers: architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
  # covers: architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
  @moduledoc """
  Product-owned memory workflow boundary over AgentWorkspace.

  This module keeps planning, review, and explanation flows explicit about when
  durable memory or workflow provenance context is requested and returns
  bounded memory input maps rather than raw graph query details.
  """

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.Actor
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.{CaptureEnvelope, ProductFeedback, ProductService, RetrievalPolicy}

  @type workflow_kind :: :plan | :review | :explain
  @type workflow_result :: {:ok, map()} | {:error, term()} | {:error, atom(), map()}
  @workflow_provenance_actor Actor.factory_system_actor(%{
                               "id" => "system:memory-graph-workflow-provenance",
                               "email" => "memory-graph-workflow-provenance@system.local"
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

  @spec follow_up_context(map()) :: map() | nil
  def follow_up_context(%{follow_up_context: %{} = context}), do: context
  def follow_up_context(_result), do: nil

  defp run_workflow(workflow, managed_repo_id, work_item_id, instruction, opts)
       when workflow in [:plan, :review, :explain] and is_list(opts) do
    with {:ok, memory_opts} <- normalize_memory_opts(Keyword.get(opts, :memory)),
         {:ok, workflow_provenance} <-
           workflow_provenance_context(
             workflow,
             managed_repo_id,
             work_item_id,
             instruction,
             opts,
             memory_opts
           ),
         {:ok, memory_input, runtime_memory_opts} <-
           prepare_memory_input(workflow, managed_repo_id, opts, memory_opts),
         {:ok, raw_result} <-
           invoke_workspace(
             workflow,
             managed_repo_id,
             work_item_id,
             instruction,
             workspace_opts(opts, workflow_provenance, memory_input, runtime_memory_opts)
           ) do
      {:ok,
       shape_result(
         workflow,
         managed_repo_id,
         work_item_id,
         instruction,
         raw_result,
         memory_input,
         workflow_provenance
       )}
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

  defp prepare_memory_input(_workflow, _managed_repo_id, _opts, nil), do: {:ok, nil, nil}

  defp prepare_memory_input(workflow, managed_repo_id, opts, memory_opts) when is_list(memory_opts) do
    with {:ok, workspace_path} <-
           MemoryGraph.normalize_workspace_path(
             Keyword.get(memory_opts, :workspace_path) || Keyword.get(opts, :workspace_path)
           ),
         :ok <- ensure_supported_memory_requests(memory_opts),
         {:ok, retrieval_policy} <- retrieval_policy(workflow, memory_opts),
         runtime_memory_opts = RetrievalPolicy.apply_defaults(memory_opts, retrieval_policy),
         {:ok, status_projection, runtime_memory_opts} <-
           prepare_graph(workflow, managed_repo_id, workspace_path, runtime_memory_opts),
         {:ok, result_projections} <-
           memory_result_projections(managed_repo_id, workspace_path, runtime_memory_opts) do
      selection = RetrievalPolicy.selection(retrieval_policy, result_projections)

      {:ok,
       %{
         workflow: workflow,
         graph: status_projection.graph,
         freshness: ProductFeedback.for_graph(status_projection.graph, status_projection.error),
         policy: RetrievalPolicy.summary(retrieval_policy),
         results: result_projections,
         selection: selection
       }, runtime_memory_opts}
    end
  end

  defp prepare_graph(workflow, managed_repo_id, workspace_path, memory_opts) do
    prepare_mode = Keyword.get(memory_opts, :prepare, :recover_if_needed)
    runtime_opts = product_lookup_opts(memory_opts) ++ [workspace_path: workspace_path]

    result =
      case prepare_mode do
        :none ->
          ProductService.status(managed_repo_id, workspace_path, product_lookup_opts(memory_opts))

        :refresh ->
          case AgentWorkspace.refresh_memory_graph(managed_repo_id, workspace_path, runtime_opts) do
            {:ok, result} ->
              {:ok, ProductService.status(managed_repo_id, workspace_path, product_lookup_opts(memory_opts)), result}

            {:error, reason, detail} ->
              {:error, reason, detail}

            {:error, reason} ->
              {:error, reason}
          end

        :validate ->
          case AgentWorkspace.validate_memory_graph(managed_repo_id, workspace_path, runtime_opts) do
            {:ok, _result} -> ProductService.status(managed_repo_id, workspace_path, product_lookup_opts(memory_opts))
            {:error, reason, detail} -> {:error, reason, detail}
            {:error, reason} -> {:error, reason}
          end

        :recover ->
          case ProductService.recover(managed_repo_id, workspace_path, product_lookup_opts(memory_opts)) do
            {:ok, projection} -> {:ok, projection}
            {:error, reason, detail} -> {:error, reason, detail}
          end

        :recover_if_needed ->
          with {:ok, status_projection} <-
                 ProductService.status(managed_repo_id, workspace_path, product_lookup_opts(memory_opts)) do
            maybe_recover(workflow, managed_repo_id, workspace_path, status_projection, memory_opts)
          end

        other ->
          {:error, :unsupported_memory_prepare_mode,
           %{
             workflow: workflow,
             prepare: other
           }}
      end

    case result do
      {:ok, projection} -> {:ok, projection, memory_opts}
      {:ok, {:ok, projection}, _ignored} -> {:ok, projection, memory_opts}
      {:error, reason, detail} -> {:error, reason, detail}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_recover(_workflow, managed_repo_id, workspace_path, status_projection, memory_opts) do
    graph = status_projection.graph

    cond do
      graph.ready? and graph.state == :ready ->
        {:ok, status_projection}

      graph.ready? and graph.state in [:stale, :invalidated, :degraded] ->
        case ProductService.recover(managed_repo_id, workspace_path, product_lookup_opts(memory_opts)) do
          {:ok, projection} -> {:ok, projection}
          {:error, reason, detail} -> {:error, reason, detail}
        end

      true ->
        case AgentWorkspace.refresh_memory_graph(
               managed_repo_id,
               workspace_path,
               product_lookup_opts(memory_opts)
             ) do
          {:ok, _result} -> ProductService.status(managed_repo_id, workspace_path, product_lookup_opts(memory_opts))
          {:error, reason, detail} -> {:error, reason, detail}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp memory_result_projections(managed_repo_id, workspace_path, memory_opts) do
    projections =
      []
      |> maybe_add_projection(:memories, Keyword.get(memory_opts, :memories), fn request_opts ->
        ProductService.memories(managed_repo_id, workspace_path, merge_lookup_opts(memory_opts, request_opts))
      end)
      |> maybe_add_projection(:provenance, Keyword.get(memory_opts, :provenance), fn request_opts ->
        ProductService.provenance(managed_repo_id, workspace_path, merge_lookup_opts(memory_opts, request_opts))
      end)
      |> maybe_add_projection(:cross_links, Keyword.get(memory_opts, :cross_links), fn request_opts ->
        with {:ok, resource_iri} <- required_resource_iri(request_opts) do
          ProductService.cross_links(
            managed_repo_id,
            workspace_path,
            resource_iri,
            merge_lookup_opts(memory_opts, request_opts)
          )
        end
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

  defp required_resource_iri(request_opts) when is_list(request_opts) do
    case normalize_optional_string(Keyword.get(request_opts, :resource_iri)) do
      nil -> {:error, :missing_memory_resource_iri}
      resource_iri -> {:ok, resource_iri}
    end
  end

  defp required_resource_iri(_request_opts), do: {:error, :missing_memory_resource_iri}

  defp maybe_add_projection(projections, _name, nil, _fun), do: projections

  defp maybe_add_projection(projections, name, request_opts, fun) when is_list(request_opts) do
    projections ++ [{name, fn -> fun.(request_opts) end}]
  end

  defp normalize_memory_opts(nil), do: {:ok, nil}
  defp normalize_memory_opts(opts) when is_list(opts), do: {:ok, opts}
  defp normalize_memory_opts(_opts), do: {:error, :invalid_memory_options}

  defp ensure_supported_memory_requests(memory_opts) do
    if Keyword.has_key?(memory_opts, :query) or Keyword.has_key?(memory_opts, :sparql) do
      {:error, :unsupported_raw_memory_query}
    else
      :ok
    end
  end

  defp retrieval_policy(workflow, memory_opts) do
    RetrievalPolicy.normalize(workflow, Keyword.get(memory_opts, :policy))
  end

  defp workspace_opts(opts, nil, nil, _runtime_memory_opts), do: Keyword.delete(opts, :memory)

  defp workspace_opts(opts, workflow_provenance, memory_input, runtime_memory_opts) do
    related_resources =
      memory_input
      |> memory_related_resources()
      |> Enum.uniq()

    provenance =
      [
        session_id: workflow_provenance.session_id,
        actor_id: workflow_provenance.actor_id,
        revision: workflow_provenance.revision,
        related_resources: related_resources
      ]
      |> maybe_put_provenance_value(:governed_references, memory_governed_references(memory_input))
      |> maybe_put_provenance_value(:memory_policy, memory_policy(memory_input))
      |> maybe_put_provenance_value(:follow_up_intent, memory_follow_up_intent(memory_input))

    opts
    |> Keyword.delete(:memory)
    |> Keyword.put(:memory_graph, memory_workspace_context(memory_input, runtime_memory_opts))
    |> Keyword.put(:provenance, provenance)
  end

  defp merge_lookup_opts(memory_opts, request_opts) do
    product_lookup_opts(memory_opts) ++ request_opts
  end

  defp product_lookup_opts(memory_opts) do
    Keyword.take(memory_opts, [:revision, :allow_stale?, :graph_name])
  end

  defp memory_workspace_context(nil, _runtime_memory_opts), do: %{}

  defp memory_workspace_context(memory_input, _runtime_memory_opts) do
    %{
      workflow: memory_input.workflow,
      graph: memory_input.graph,
      freshness: memory_input.freshness,
      policy: memory_input.policy,
      selection: memory_input.selection
    }
  end

  defp memory_policy(nil), do: nil
  defp memory_policy(memory_input), do: Map.get(memory_input, :policy)

  defp memory_follow_up_intent(nil), do: nil

  defp memory_follow_up_intent(memory_input) do
    get_in(memory_input, [:policy, :follow_up_intent])
  end

  defp memory_related_resources(nil), do: []

  defp memory_related_resources(memory_input) do
    memory_input
    |> get_in([:selection, :related_resources])
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
  end

  defp memory_governed_references(nil), do: []

  defp memory_governed_references(memory_input) do
    memory_input
    |> get_in([:selection, :governed_references])
    |> List.wrap()
  end

  defp maybe_put_provenance_value(keyword, _key, nil), do: keyword
  defp maybe_put_provenance_value(keyword, key, value), do: Keyword.put(keyword, key, value)

  defp shape_result(:plan, managed_repo_id, work_item_id, instruction, raw_result, memory_input, workflow_provenance) do
    %{
      workflow: :plan,
      managed_repo_id: managed_repo_id,
      work_item_id: work_item_id,
      instruction: instruction,
      plan: Map.get(raw_result, :plan),
      memory_input: memory_input,
      workflow_provenance: provenance_summary(workflow_provenance),
      follow_up_context: follow_up_context(:plan, memory_input, workflow_provenance)
    }
  end

  defp shape_result(:review, managed_repo_id, work_item_id, instruction, raw_result, memory_input, workflow_provenance) do
    %{
      workflow: :review,
      managed_repo_id: managed_repo_id,
      work_item_id: work_item_id,
      instruction: instruction,
      feedback: Map.get(raw_result, :feedback),
      memory_input: memory_input,
      workflow_provenance: provenance_summary(workflow_provenance),
      follow_up_context: follow_up_context(:review, memory_input, workflow_provenance)
    }
  end

  defp shape_result(:explain, managed_repo_id, work_item_id, instruction, raw_result, memory_input, workflow_provenance) do
    %{
      workflow: :explain,
      managed_repo_id: managed_repo_id,
      work_item_id: work_item_id,
      instruction: instruction,
      explanation: Map.get(raw_result, :explanation),
      memory_input: memory_input,
      workflow_provenance: provenance_summary(workflow_provenance),
      follow_up_context: follow_up_context(:explain, memory_input, workflow_provenance)
    }
  end

  defp follow_up_context(_workflow, nil, _workflow_provenance), do: nil

  defp follow_up_context(workflow, memory_input, workflow_provenance) do
    related_resources = get_in(memory_input, [:selection, :related_resources]) || []

    memory_resources =
      case get_in(memory_input, [:selection, :memory_resources]) || [] do
        [] -> Enum.filter(related_resources, &String.contains?(&1, "/memory#"))
        values -> values
      end

    provenance_resources =
      case get_in(memory_input, [:selection, :provenance_resources]) || [] do
        [] -> Enum.filter(related_resources, &String.contains?(&1, "/workflow_provenance#"))
        values -> values
      end

    normalize_map(%{
      workflow: workflow,
      session_id: workflow_provenance && workflow_provenance.session_id,
      revision: workflow_provenance && workflow_provenance.revision,
      retrieval_policy: Map.get(memory_input, :policy),
      freshness: normalize_map(Map.get(memory_input, :freshness, %{})),
      graph: normalize_map(Map.get(memory_input, :graph, %{})),
      selection: normalize_map(Map.get(memory_input, :selection, %{})),
      governed_references: memory_governed_references(memory_input),
      memory_resources: memory_resources,
      provenance_resources: provenance_resources,
      related_resources: related_resources
    })
  end

  defp workflow_provenance_context(_workflow, _managed_repo_id, _work_item_id, _instruction, _opts, nil),
    do: {:ok, nil}

  defp workflow_provenance_context(workflow, managed_repo_id, work_item_id, instruction, opts, memory_opts)
       when is_list(memory_opts) do
    workspace_path =
      Keyword.get(memory_opts, :workspace_path) ||
        Keyword.get(opts, :workspace_path)

    with {:ok, workspace_path} <- MemoryGraph.normalize_workspace_path(workspace_path) do
      context = %{
        enabled?: MemoryGraph.capability_enabled?(opts),
        session_id: provenance_session_id(workflow, work_item_id, opts),
        actor_id: provenance_actor_id(opts),
        revision: Keyword.get(memory_opts, :revision),
        workflow: workflow
      }

      _ =
        capture_workflow_preparation(
          managed_repo_id,
          work_item_id,
          workspace_path,
          instruction,
          memory_opts,
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
         memory_opts,
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
          outcome: "memory-preparation",
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
                memory_requests: Keyword.drop(memory_opts, [:workspace_path])
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

      {:ok, _status} ->
        case AgentWorkspace.recover_memory_graph(
               managed_repo_id,
               workspace_path,
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             ) do
          {:ok, %{graph_status: %{ready?: true, stale?: false}}} -> :ok
          _other -> :ok
        end

      _other ->
        :ok
    end
  end

  defp provenance_session_id(workflow, work_item_id, opts) do
    opts
    |> Keyword.get(:provenance, [])
    |> Keyword.get(:session_id, "memory-#{workflow}-#{work_item_id}-#{System.unique_integer([:positive])}")
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
      workflow: provenance.workflow,
      related_resources: Map.get(provenance, :related_resources, []),
      governed_references: Map.get(provenance, :governed_references, []),
      memory_policy: Map.get(provenance, :memory_policy)
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

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      normalized_value =
        cond do
          is_boolean(nested_value) or is_nil(nested_value) -> nested_value
          match?(%DateTime{}, nested_value) -> DateTime.to_iso8601(nested_value)
          is_map(nested_value) -> normalize_map(nested_value)
          is_list(nested_value) -> Enum.map(nested_value, &normalize_nested_value/1)
          is_atom(nested_value) -> Atom.to_string(nested_value)
          true -> nested_value
        end

      Map.put(acc, normalized_key, normalized_value)
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(value) when is_boolean(value) or is_nil(value), do: value
  defp normalize_nested_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_nested_value(value), do: value
end
