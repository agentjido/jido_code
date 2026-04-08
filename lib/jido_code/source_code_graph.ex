defmodule JidoCode.SourceCodeGraph do
  # covers: architecture.source_code_graph_pod.local_triple_store_quad_schema_is_canonical_store
  # covers: architecture.source_code_graph_pod.source_code_named_graph_is_canonical_target
  # covers: architecture.source_code_graph_pod.full_elixir_ontology_profile_is_required
  @moduledoc """
  Product-owned boundary helpers for repository-scoped source-code graph state.

  Phase 20 establishes the canonical graph identity, ontology profile, and
  repository-local storage boundary before the later ontology and TripleStore
  integrations land.
  """

  @pod_id "source_code_graph"
  @graph_name "source_code"
  @ontology_profile "full"

  @type managed_repo_id :: String.t()
  @type workspace_path :: String.t()

  @spec pod_id() :: String.t()
  def pod_id, do: @pod_id

  @spec graph_name() :: String.t()
  def graph_name, do: @graph_name

  @spec ontology_profile() :: String.t()
  def ontology_profile, do: @ontology_profile

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

  @spec dataset_metadata(managed_repo_id(), workspace_path(), keyword()) ::
          {:ok, map()} | {:error, atom()}
  def dataset_metadata(managed_repo_id, workspace_path, opts \\ []) when is_binary(managed_repo_id) do
    with {:ok, normalized_workspace_path} <- normalize_workspace_path(workspace_path) do
      {:ok,
       %{
         managed_repo_id: managed_repo_id,
         dataset_id: "#{managed_repo_id}:#{@graph_name}",
         graph_name: @graph_name,
         ontology_profile: @ontology_profile,
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
         latest_import_status: context.latest_import_status,
         dataset_metadata: context.dataset_metadata
       }}
    end
  end
end
