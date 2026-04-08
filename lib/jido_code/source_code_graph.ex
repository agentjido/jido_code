defmodule JidoCode.SourceCodeGraph do
  # covers: architecture.source_code_graph_pod.local_triple_store_quad_schema_is_canonical_store
  # covers: architecture.source_code_graph_pod.source_code_named_graph_is_canonical_target
  # covers: architecture.source_code_graph_pod.full_elixir_ontology_profile_is_required
  @moduledoc """
  Product-owned boundary helpers for repository-scoped source-code graph state.

  The boundary fixes the canonical graph identity, ontology profile, repository-
  local storage boundary, and repository-scoped ontology analysis defaults.
  """

  @pod_id "source_code_graph"
  @graph_name "source_code"
  @ontology_profile "full"
  @named_graph_iri "https://jido.run/graphs/source_code"
  @ontology_schema_filenames [
    "elixir-core.ttl",
    "elixir-structure.ttl",
    "elixir-otp.ttl",
    "elixir-evolution.ttl",
    "elixir-shapes.ttl"
  ]

  @type managed_repo_id :: String.t()
  @type workspace_path :: String.t()

  @spec pod_id() :: String.t()
  def pod_id, do: @pod_id

  @spec graph_name() :: String.t()
  def graph_name, do: @graph_name

  @spec ontology_profile() :: String.t()
  def ontology_profile, do: @ontology_profile

  @spec ontology_schema_filenames() :: [String.t()]
  def ontology_schema_filenames, do: @ontology_schema_filenames

  @spec named_graph_iri() :: String.t()
  def named_graph_iri, do: @named_graph_iri

  @spec named_graph_resource() :: RDF.IRI.t()
  def named_graph_resource, do: RDF.iri(@named_graph_iri)

  @spec capability_enabled?(keyword()) :: boolean()
  def capability_enabled?(opts \\ []) do
    Keyword.get(opts, :enabled?, Application.get_env(:jido_code, :source_code_graph_enabled, false))
  end

  @spec normalize_workspace_path(workspace_path() | nil) :: {:ok, workspace_path()} | {:error, atom()}
  def normalize_workspace_path(path) when is_binary(path) do
    case String.trim(path) do
      "" -> {:error, :missing_workspace_path}
      expanded -> {:ok, Path.expand(expanded)}
    end
  end

  def normalize_workspace_path(_path), do: {:error, :missing_workspace_path}

  @spec graph_store_path(workspace_path()) :: String.t()
  def graph_store_path(workspace_path) when is_binary(workspace_path) do
    workspace_path
    |> Path.expand()
    |> then(&Path.join([&1, ".jido_code", "source_code_graph", "triple_store"]))
  end

  @spec base_iri(managed_repo_id()) :: String.t()
  def base_iri(managed_repo_id) when is_binary(managed_repo_id) do
    "https://jido.run/managed_repos/#{managed_repo_id}/source_code#"
  end

  @spec ontology_artifacts() :: [map()]
  def ontology_artifacts do
    Enum.map(@ontology_schema_filenames, fn filename ->
      %{
        kind: :ontology_schema,
        filename: filename,
        format: :turtle,
        path: ElixirOntologies.ontology_path(filename)
      }
    end)
  end

  @spec dataset_metadata(managed_repo_id(), workspace_path(), keyword()) ::
          {:ok, map()} | {:error, atom()}
  def dataset_metadata(managed_repo_id, workspace_path, opts \\ []) when is_binary(managed_repo_id) do
    with {:ok, normalized_workspace_path} <- normalize_workspace_path(workspace_path) do
      {:ok,
       %{
         managed_repo_id: managed_repo_id,
         dataset_id: "#{managed_repo_id}:#{@graph_name}",
         graph_name: @graph_name,
         named_graph_iri: @named_graph_iri,
         ontology_profile: @ontology_profile,
         base_iri: base_iri(managed_repo_id),
         workspace_path: normalized_workspace_path,
         graph_store_path: graph_store_path(normalized_workspace_path),
         revision: Keyword.get(opts, :revision),
         triple_store_schema: :quad
       }}
    end
  end

  @spec graph_context(managed_repo_id(), workspace_path(), keyword()) :: {:ok, map()} | {:error, atom()}
  def graph_context(managed_repo_id, workspace_path, opts \\ []) when is_binary(managed_repo_id) do
    with {:ok, metadata} <- dataset_metadata(managed_repo_id, workspace_path, opts) do
      {:ok,
       %{
         managed_repo_id: managed_repo_id,
         workspace_path: metadata.workspace_path,
         graph_store_path: metadata.graph_store_path,
         graph_name: metadata.graph_name,
         ontology_profile: metadata.ontology_profile,
         revision_metadata: %{
           revision: metadata.revision,
           refresh_mode: Keyword.get(opts, :refresh_mode, :replace_named_graph)
         },
         dataset_metadata: metadata,
         latest_analysis_status: default_analysis_status(metadata),
         latest_import_status: %{
           state: :not_loaded,
           ready?: false,
           graph_name: @graph_name,
           imported_revision: nil,
           imported_at: nil
         }
       }}
    end
  end

  @spec pod_metadata(managed_repo_id(), workspace_path(), keyword()) :: {:ok, map()} | {:error, atom()}
  def pod_metadata(managed_repo_id, workspace_path, opts \\ []) when is_binary(managed_repo_id) do
    with {:ok, context} <- graph_context(managed_repo_id, workspace_path, opts) do
      {:ok,
       %{
         scope: :repository,
         graph_name: context.graph_name,
         ontology_profile: context.ontology_profile,
         workspace_path: context.workspace_path,
         graph_store_path: context.graph_store_path,
         latest_analysis_status: context.latest_analysis_status,
         latest_import_status: context.latest_import_status,
         dataset_metadata: context.dataset_metadata
       }}
    end
  end

  defp default_analysis_status(metadata) do
    %{
      state: :not_analyzed,
      ready?: false,
      graph_name: @graph_name,
      ontology_profile: @ontology_profile,
      analyzed_revision: metadata.revision,
      analyzed_at: nil,
      failure: nil
    }
  end
end
