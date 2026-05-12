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

  @spec source_file_patterns(workspace_path()) :: [String.t()]
  def source_file_patterns(workspace_path) when is_binary(workspace_path), do: source_globs(Path.expand(workspace_path))

  @spec source_files(workspace_path()) :: [String.t()]
  def source_files(workspace_path) when is_binary(workspace_path) do
    workspace_path
    |> Path.expand()
    |> source_globs()
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.filter(&source_file?(workspace_path, &1))
    |> Enum.uniq()
    |> Enum.sort()
  end

  @spec source_file?(workspace_path(), String.t()) :: boolean()
  def source_file?(workspace_path, path) when is_binary(workspace_path) and is_binary(path) do
    workspace_path = Path.expand(workspace_path)
    path = Path.expand(path)

    inside_workspace?(workspace_path, path) and
      source_relative_file?(Path.relative_to(path, workspace_path)) and
      not excluded_source_file?(path)
  end

  def source_file?(_workspace_path, _path), do: false

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
         source_graph_refresh: default_refresh_status(managed_repo_id),
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
         source_graph_refresh: context.source_graph_refresh,
         latest_failure: context.latest_failure,
         dataset_metadata: context.dataset_metadata
       }}
    end
  end

  @spec default_refresh_status(managed_repo_id() | nil) :: map()
  def default_refresh_status(managed_repo_id \\ nil) do
    %{
      managed_repo_id: managed_repo_id,
      state: :idle,
      auto_refresh_enabled?: Application.get_env(:jido_code, :source_code_graph_auto_refresh_enabled, false),
      file_watcher_enabled?: Application.get_env(:jido_code, :source_code_graph_file_watcher_enabled, false),
      file_watcher_debounce_ms: Application.get_env(:jido_code, :source_code_graph_file_watcher_debounce_ms, 500),
      file_watcher_max_pending_paths:
        Application.get_env(:jido_code, :source_code_graph_file_watcher_max_pending_paths, 500),
      refresh_debounce_ms: Application.get_env(:jido_code, :source_code_graph_refresh_debounce_ms, 250),
      refresh_max_coalesce_ms: Application.get_env(:jido_code, :source_code_graph_refresh_max_coalesce_ms, 2_500),
      refresh_max_pending_paths: Application.get_env(:jido_code, :source_code_graph_refresh_max_pending_paths, 500),
      missing_graph_policy:
        Application.get_env(:jido_code, :source_code_graph_auto_refresh_missing_graph_policy, :skip),
      max_refresh_attempts: Application.get_env(:jido_code, :source_code_graph_auto_refresh_max_attempts, 1),
      refresh_queued?: false,
      refresh_in_flight?: false,
      pending_changed_paths: [],
      last_source_change_at: nil,
      last_refresh_started_at: nil,
      last_refresh_completed_at: nil,
      last_result: nil,
      last_failure: nil
    }
  end

  @spec merge_refresh_status(map() | nil, managed_repo_id() | nil) :: map()
  def merge_refresh_status(status, managed_repo_id \\ nil) do
    default_refresh_status(managed_repo_id)
    |> Map.merge(if(is_map(status), do: status, else: %{}))
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

  defp inside_workspace?(workspace_path, path) do
    path == workspace_path or String.starts_with?(path, workspace_path <> "/")
  end

  defp source_relative_file?("mix.exs"), do: true

  defp source_relative_file?(relative_path) do
    segments = Path.split(relative_path)
    extension = Path.extname(relative_path)

    case segments do
      ["lib" | _] when extension in [".ex", ".exs"] -> true
      ["test" | _] when extension in [".ex", ".exs"] -> true
      ["config" | _] when extension == ".exs" -> true
      _ -> false
    end
  end

  defp excluded_source_file?(path) do
    String.contains?(path, "/deps/") or
      String.contains?(path, "/_build/") or
      String.contains?(path, "/node_modules/") or
      String.contains?(path, "/.jido_code/")
  end
end
