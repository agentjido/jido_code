defmodule JidoCode.Agents.MemoryGraphContext do
  # covers: architecture.memory_graph.repo_scoped_memory_graph_pod
  @moduledoc """
  Eager repository-scoped state owner for memory graph metadata.

  This agent establishes the durable pod-local contract for graph identity,
  revision metadata, validation state, and latest failure details before later
  phases connect it to capture, query, and invalidation behavior.
  """

  use Jido.Agent,
    name: "memory_graph_context",
    priority: :high,
    schema: [
      managed_repo_id: [
        type: :string,
        default: nil,
        doc: "ManagedRepo ID that owns this memory graph context."
      ],
      workspace_path: [
        type: :string,
        default: nil,
        doc: "Expanded repository workspace path."
      ],
      graph_store_path: [
        type: :string,
        default: nil,
        doc: "Repository-local TripleStore database path shared with the semantic stack."
      ],
      graph_names: [
        type: {:list, :string},
        default: ["memory", "workflow_provenance"],
        doc: "Canonical named graphs owned by the memory graph capability."
      ],
      named_graph_iris: [
        type: :map,
        default: %{},
        doc: "Canonical IRIs for the memory and workflow provenance named graphs."
      ],
      revision_metadata: [
        type: :map,
        default: %{},
        doc: "Revision metadata used to reason about freshness and validation."
      ],
      dataset_metadata: [
        type: :map,
        default: %{},
        doc: "Repository-local dataset metadata for the memory graph store."
      ],
      latest_record_status: [
        type: :map,
        default: %{},
        doc: "Most recent durable memory record summary for this repository graph."
      ],
      latest_query_status: [
        type: :map,
        default: %{},
        doc: "Most recent bounded memory recall summary for this repository graph."
      ],
      latest_validation_status: [
        type: :map,
        default: %{},
        doc: "Most recent validation or freshness summary for this repository graph."
      ],
      latest_failure: [
        type: :map,
        default: %{},
        doc: "Most recent typed failure observed by the repository memory graph."
      ]
    ]
end
