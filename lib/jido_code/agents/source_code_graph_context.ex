defmodule JidoCode.Agents.SourceCodeGraphContext do
  # covers: architecture.source_code_graph_pod.repo_scoped_source_code_graph_pod
  @moduledoc """
  Eager repository-scoped state owner for source-code graph metadata.

  This agent establishes the durable pod-local contract for workspace, graph,
  ontology, and import-status metadata before later phases connect it to full
  ontology extraction and TripleStore load behavior.
  """

  use Jido.Agent,
    name: "source_code_graph_context",
    priority: :high,
    schema: [
      managed_repo_id: [
        type: :string,
        default: nil,
        doc: "ManagedRepo ID that owns this graph context."
      ],
      workspace_path: [
        type: :string,
        default: nil,
        doc: "Expanded repository workspace path."
      ],
      graph_store_path: [
        type: :string,
        default: nil,
        doc: "Repository-local TripleStore database path."
      ],
      graph_name: [
        type: :string,
        default: "source_code",
        doc: "Canonical named graph for semantic source-code data."
      ],
      ontology_profile: [
        type: :string,
        default: "full",
        doc: "Required ElixirOntologies extraction profile."
      ],
      revision_metadata: [
        type: :map,
        default: %{},
        doc: "Revision and refresh metadata for the latest requested import."
      ],
      dataset_metadata: [
        type: :map,
        default: %{},
        doc: "Repository-local dataset metadata for source graph storage."
      ],
      latest_analysis_status: [
        type: :map,
        default: %{},
        doc: "Most recent ontology-analysis summary for this repository graph."
      ],
      latest_import_status: [
        type: :map,
        default: %{},
        doc: "Most recent import/readiness summary for the named graph."
      ]
    ]
end
