defmodule JidoCode.ControlPlane.GraphTopology do
  @moduledoc """
  Named graph topology for product-owned semantic control-plane facts.

  This module is deliberately declarative. Store adapters and projection code
  should ask this boundary where a record family belongs instead of spreading
  named graph literals through UI, workflow, or persistence code.
  """

  alias JidoCode.ControlPlane.SemanticIdentity

  @type graph_name ::
          :control_plane
          | :control_plane_events
          | :auth
          | :security
          | :conversations
          | :execution_runtime
          | :memory
          | :workflow_provenance
          | :source_code
  @type link_rule :: %{
          from: graph_name(),
          to: graph_name(),
          mode: :object_iri_only | :bounded_projection,
          stale_behavior: :degraded_projection,
          unavailable_behavior: :omit_links,
          description: String.t()
        }

  @graph_iris %{
    control_plane: "https://jido.run/graphs/control_plane",
    control_plane_events: "https://jido.run/graphs/control_plane_events",
    auth: "https://jido.run/graphs/auth",
    security: "https://jido.run/graphs/security",
    conversations: "https://jido.run/graphs/conversations",
    execution_runtime: "https://jido.run/graphs/execution_runtime",
    memory: "https://jido.run/graphs/memory",
    workflow_provenance: "https://jido.run/graphs/workflow_provenance",
    source_code: "https://jido.run/graphs/source_code"
  }

  @control_plane_record_types [
    :managed_repo,
    :source_repo,
    :project,
    :intake,
    :external_object,
    :observation,
    :assessment,
    :work_item,
    :run,
    :workflow_run,
    :execution_profile,
    :evidence,
    :change_request,
    :decision,
    :policy_set,
    :review_policy,
    :repo_posture,
    :posture_check,
    :github_repo,
    :issue_analysis,
    :system_config
  ]

  @control_plane_event_record_types [
    :event,
    :webhook_delivery
  ]

  @auth_record_types [
    :user,
    :user_identity,
    :api_key,
    :token,
    :provider_config
  ]

  @security_record_types [
    :secret_ref,
    :secret_lifecycle_audit
  ]

  @conversation_record_types [
    :conversation,
    :conversation_event,
    :conversation_snapshot
  ]

  @execution_runtime_record_types [
    :execution_workflow,
    :sandbox_session,
    :runtime_event,
    :checkpoint,
    :exec_session,
    :sprite_spec
  ]

  @record_graphs Map.new(
                   [
                     {@control_plane_record_types, :control_plane},
                     {@control_plane_event_record_types, :control_plane_events},
                     {@auth_record_types, :auth},
                     {@security_record_types, :security},
                     {@conversation_record_types, :conversations},
                     {@execution_runtime_record_types, :execution_runtime}
                   ],
                   fn {record_types, graph_name} -> {graph_name, record_types} end
                 )
                 |> Enum.flat_map(fn {graph_name, record_types} ->
                   Enum.map(record_types, &{&1, graph_name})
                 end)
                 |> Map.new()

  @link_rules [
    %{
      from: :memory,
      to: :control_plane,
      mode: :object_iri_only,
      stale_behavior: :degraded_projection,
      unavailable_behavior: :omit_links,
      description: "Durable memory links to governed product records by canonical object IRI."
    },
    %{
      from: :workflow_provenance,
      to: :control_plane,
      mode: :object_iri_only,
      stale_behavior: :degraded_projection,
      unavailable_behavior: :omit_links,
      description: "Workflow provenance links to governed work, run, evidence, and decision records by object IRI."
    },
    %{
      from: :source_code,
      to: :control_plane,
      mode: :object_iri_only,
      stale_behavior: :degraded_projection,
      unavailable_behavior: :omit_links,
      description: "Source-code entities link to work items, runs, evidence, and decisions by object IRI."
    },
    %{
      from: :source_code,
      to: :memory,
      mode: :object_iri_only,
      stale_behavior: :degraded_projection,
      unavailable_behavior: :omit_links,
      description: "Source-code entities may link to durable memory records by object IRI."
    },
    %{
      from: :conversations,
      to: :control_plane,
      mode: :object_iri_only,
      stale_behavior: :degraded_projection,
      unavailable_behavior: :omit_links,
      description: "Conversation records attach to managed repositories and work items by object IRI."
    },
    %{
      from: :execution_runtime,
      to: :control_plane,
      mode: :object_iri_only,
      stale_behavior: :degraded_projection,
      unavailable_behavior: :omit_links,
      description:
        "Execution runtime records attach to managed repositories, work items, runs, and evidence by object IRI."
    },
    %{
      from: :security,
      to: :auth,
      mode: :bounded_projection,
      stale_behavior: :degraded_projection,
      unavailable_behavior: :omit_links,
      description: "Security metadata may link to users or actors without exposing secret material."
    }
  ]

  @spec graph_names() :: [graph_name()]
  def graph_names, do: @graph_iris |> Map.keys() |> Enum.sort()

  @spec graph_iris() :: %{graph_name() => String.t()}
  def graph_iris, do: @graph_iris

  @spec graph_iri(graph_name()) :: {:ok, String.t()} | {:error, :unknown_graph}
  def graph_iri(graph_name) when is_atom(graph_name) do
    case Map.fetch(@graph_iris, graph_name) do
      {:ok, iri} -> {:ok, iri}
      :error -> {:error, :unknown_graph}
    end
  end

  def graph_iri(_graph_name), do: {:error, :unknown_graph}

  @spec graph_resource(graph_name()) :: {:ok, RDF.IRI.t()} | {:error, :unknown_graph}
  def graph_resource(graph_name) do
    with {:ok, iri} <- graph_iri(graph_name), do: {:ok, RDF.iri(iri)}
  end

  @spec graph_for_record(SemanticIdentity.record_type()) ::
          {:ok, graph_name()} | {:error, :unknown_record_type}
  def graph_for_record(record_type) when is_atom(record_type) do
    case Map.fetch(@record_graphs, record_type) do
      {:ok, graph_name} -> {:ok, graph_name}
      :error -> {:error, :unknown_record_type}
    end
  end

  def graph_for_record(_record_type), do: {:error, :unknown_record_type}

  @spec graph_iri_for_record(SemanticIdentity.record_type()) ::
          {:ok, String.t()} | {:error, :unknown_record_type | :unknown_graph}
  def graph_iri_for_record(record_type) do
    with {:ok, graph_name} <- graph_for_record(record_type),
         {:ok, graph_iri} <- graph_iri(graph_name) do
      {:ok, graph_iri}
    end
  end

  @spec record_types_for_graph(graph_name()) :: {:ok, [SemanticIdentity.record_type()]} | {:error, :unknown_graph}
  def record_types_for_graph(graph_name) do
    with {:ok, _iri} <- graph_iri(graph_name) do
      {:ok,
       @record_graphs
       |> Enum.filter(fn {_record_type, owner_graph} -> owner_graph == graph_name end)
       |> Enum.map(fn {record_type, _owner_graph} -> record_type end)
       |> Enum.sort()}
    end
  end

  @spec append_only_graph?(graph_name()) :: boolean()
  def append_only_graph?(graph_name), do: graph_name in [:control_plane_events, :conversations, :execution_runtime]

  @spec link_rules() :: [link_rule()]
  def link_rules, do: @link_rules

  @spec link_rule(graph_name(), graph_name()) :: {:ok, link_rule()} | {:error, :unknown_link_rule}
  def link_rule(from, to) when is_atom(from) and is_atom(to) do
    case Enum.find(@link_rules, &(&1.from == from and &1.to == to)) do
      nil -> {:error, :unknown_link_rule}
      rule -> {:ok, rule}
    end
  end

  def link_rule(_from, _to), do: {:error, :unknown_link_rule}
end
