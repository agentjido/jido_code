defmodule JidoCode.SourceCodeGraph do
  # covers: architecture.source_code_graph_pod.local_triple_store_quad_schema_is_canonical_store
  # covers: architecture.source_code_graph_pod.source_code_named_graph_is_canonical_target
  # covers: architecture.source_code_graph_pod.full_elixir_ontology_profile_is_required
  # covers: architecture.source_code_graph_pod.graph_revision_state_is_explicit_and_explainable
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
  @type revision_metadata :: map()

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

  @spec current_revision_metadata(workspace_path(), keyword()) ::
          {:ok, revision_metadata()} | {:error, atom()}
  def current_revision_metadata(workspace_path, opts \\ []) when is_list(opts) do
    with {:ok, normalized_workspace_path} <- normalize_workspace_path(workspace_path) do
      requested_revision = Keyword.get(opts, :revision)
      refresh_mode = Keyword.get(opts, :refresh_mode, :replace_named_graph)
      source_commit = source_commit(normalized_workspace_path)
      workspace_snapshot_identity = workspace_snapshot_identity(normalized_workspace_path)

      {current_revision, revision_source} =
        resolve_current_revision(requested_revision, source_commit, workspace_snapshot_identity)

      {:ok,
       %{
         revision: requested_revision,
         requested_revision: requested_revision,
         analyzed_revision: current_revision,
         current_revision: current_revision,
         source_commit: source_commit,
         workspace_snapshot_identity: workspace_snapshot_identity,
         revision_source: revision_source,
         refresh_mode: refresh_mode
       }}
    end
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
    with {:ok, metadata} <- dataset_metadata(managed_repo_id, workspace_path, opts),
         {:ok, revision_metadata} <- current_revision_metadata(workspace_path, opts) do
      {:ok,
       %{
         managed_repo_id: managed_repo_id,
         workspace_path: metadata.workspace_path,
         graph_store_path: metadata.graph_store_path,
         graph_name: metadata.graph_name,
         ontology_profile: metadata.ontology_profile,
         revision_metadata: revision_metadata,
         dataset_metadata: metadata,
         latest_analysis_status: default_analysis_status(revision_metadata),
         latest_import_status: %{
           state: :not_loaded,
           ready?: false,
           graph_name: @graph_name,
           imported_revision: nil,
           imported_at: nil,
           requested_revision: nil,
           source_commit: nil,
           workspace_snapshot_identity: nil,
           revision_source: nil,
           failure: nil
         },
         latest_failure: nil
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
         latest_failure: context.latest_failure,
         dataset_metadata: context.dataset_metadata
       }}
    end
  end

  defp default_analysis_status(revision_metadata) do
    %{
      state: :not_analyzed,
      ready?: false,
      graph_name: @graph_name,
      ontology_profile: @ontology_profile,
      analyzed_revision: revision_metadata.current_revision,
      analyzed_at: nil,
      requested_revision: revision_metadata.requested_revision,
      source_commit: revision_metadata.source_commit,
      workspace_snapshot_identity: revision_metadata.workspace_snapshot_identity,
      revision_source: revision_metadata.revision_source,
      failure: nil
    }
  end

  defp resolve_current_revision(requested_revision, _source_commit, _workspace_snapshot_identity)
       when is_binary(requested_revision) do
    {requested_revision, :requested_revision}
  end

  defp resolve_current_revision(_requested_revision, _source_commit, workspace_snapshot_identity)
       when is_binary(workspace_snapshot_identity) do
    {workspace_snapshot_identity, :workspace_snapshot_identity}
  end

  defp resolve_current_revision(_requested_revision, source_commit, _workspace_snapshot_identity)
       when is_binary(source_commit) do
    {source_commit, :source_commit}
  end

  defp source_commit(workspace_path) do
    case System.cmd("git", ["-C", workspace_path, "rev-parse", "HEAD"], stderr_to_stdout: true) do
      {commit, 0} ->
        commit
        |> String.trim()
        |> case do
          "" -> nil
          value -> value
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp workspace_snapshot_identity(workspace_path) do
    manifest =
      workspace_path
      |> source_files()
      |> Enum.map(fn path ->
        stat = File.stat!(path, time: :posix)
        relative_path = Path.relative_to(path, workspace_path)
        "#{relative_path}:#{stat.size}:#{stat.mtime}"
      end)
      |> Enum.join("\n")

    case manifest do
      "" ->
        "snapshot:empty"

      data ->
        encoded =
          :sha256
          |> :crypto.hash(data)
          |> Base.encode16(case: :lower)

        "snapshot:#{encoded}"
    end
  end

  defp source_files(workspace_path) do
    workspace_path
    |> source_globs()
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.reject(&excluded_source_file?/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp source_globs(workspace_path) do
    [
      Path.join(workspace_path, "mix.exs"),
      Path.join(workspace_path, "lib/**/*.ex"),
      Path.join(workspace_path, "lib/**/*.exs"),
      Path.join(workspace_path, "test/**/*.ex"),
      Path.join(workspace_path, "test/**/*.exs"),
      Path.join(workspace_path, "config/**/*.exs")
    ]
  end

  defp excluded_source_file?(path) do
    String.contains?(path, "/deps/") or
      String.contains?(path, "/_build/") or
      String.contains?(path, "/node_modules/")
  end
end
