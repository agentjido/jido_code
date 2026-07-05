defmodule JidoCode.ControlPlane.Recovery do
  @moduledoc """
  Backup, restore, and reset helpers for the embedded control-plane store.
  """

  alias JidoCode.ControlPlane.{GraphTopology, Integrity, StoreServer}

  @type export_report :: %{
          path: String.t(),
          format: :nquads | :trig,
          exported_quad_count: non_neg_integer(),
          omitted_quad_count: non_neg_integer(),
          redacted_graphs: [GraphTopology.graph_name()]
        }

  @type restore_report :: %{
          path: String.t(),
          format: :nquads | :trig,
          restored_quad_count: non_neg_integer(),
          integrity: Integrity.report()
        }

  @spec export(Path.t(), keyword()) :: {:ok, export_report()} | {:error, term()}
  def export(path, opts \\ []) when is_binary(path), do: export(StoreServer, path, opts)

  @spec export(GenServer.server(), Path.t(), keyword()) :: {:ok, export_report()} | {:error, term()}
  def export(server, path, opts) when is_binary(path) and is_list(opts) do
    StoreServer.export(server, path, opts)
  end

  @spec restore(Path.t(), keyword()) :: {:ok, restore_report()} | {:error, term()}
  def restore(path, opts \\ []) when is_binary(path), do: restore(StoreServer, path, opts)

  @spec restore(GenServer.server(), Path.t(), keyword()) :: {:ok, restore_report()} | {:error, term()}
  def restore(server, path, opts) when is_binary(path) and is_list(opts) do
    StoreServer.restore(server, path, opts)
  end

  @spec reset() :: {:ok, StoreServer.health()} | {:error, term()}
  def reset, do: reset(StoreServer, [])

  @spec reset(keyword()) :: {:ok, StoreServer.health()} | {:error, term()}
  def reset(opts) when is_list(opts), do: reset(StoreServer, opts)

  @spec reset(GenServer.server()) :: {:ok, StoreServer.health()} | {:error, term()}
  def reset(server), do: reset(server, [])

  @spec reset(GenServer.server(), keyword()) :: {:ok, StoreServer.health()} | {:error, term()}
  def reset(server, _opts) do
    StoreServer.reset(server)
  end

  @spec export_store(map(), Path.t(), keyword()) :: {:ok, export_report()} | {:error, term()}
  def export_store(store, path, opts \\ []) when is_binary(path) and is_list(opts) do
    format = export_format(path, opts)
    redacted_graphs = if Keyword.get(opts, :redact?, true), do: redacted_graphs(opts), else: []

    with {:ok, all_quads} <- Integrity.all_quads(store),
         {exported_quads, omitted_quad_count} <- redact_quads(all_quads, redacted_graphs),
         {:ok, content} <- serialize(exported_quads, format),
         :ok <- ensure_parent(path),
         :ok <- File.write(path, content) do
      {:ok,
       %{
         path: Path.expand(path),
         format: format,
         exported_quad_count: length(exported_quads),
         omitted_quad_count: omitted_quad_count,
         redacted_graphs: redacted_graphs
       }}
    end
  end

  @spec restore_store_path(Path.t(), Path.t(), keyword()) :: {:ok, restore_report()} | {:error, term()}
  def restore_store_path(input_path, target_path, opts \\ []) when is_binary(input_path) and is_binary(target_path) do
    format = restore_format(input_path, opts)
    target_path = Path.expand(target_path)
    token = System.unique_integer([:positive]) |> Integer.to_string()
    staging_path = target_path <> ".restore-" <> token
    backup_path = target_path <> ".pre-restore-" <> token

    with {:ok, dataset} <- read_dataset(input_path, format),
         :ok <- validate_dataset(dataset),
         :ok <- ensure_parent(staging_path),
         {:ok, loaded_count, integrity} <- load_and_check_dataset(staging_path, dataset),
         :ok <- swap_store_path(staging_path, target_path, backup_path) do
      {:ok,
       %{
         path: Path.expand(input_path),
         format: format,
         restored_quad_count: loaded_count,
         integrity: integrity
       }}
    else
      {:error, _reason} = error ->
        File.rm_rf(staging_path)
        error

      reason ->
        File.rm_rf(staging_path)
        {:error, reason}
    end
  end

  @spec validate_dataset(RDF.Dataset.t()) :: :ok | {:error, term()}
  def validate_dataset(%RDF.Dataset{} = dataset) do
    with {:ok, control_plane_graph_iri} <- GraphTopology.graph_iri(:control_plane),
         {:ok, expected_version} <- Integrity.expected_control_plane_ontology_version() do
      graph_names = dataset |> RDF.Dataset.graph_names() |> Enum.map(&to_string/1)

      cond do
        control_plane_graph_iri not in graph_names ->
          {:error, {:missing_restore_graph, :control_plane}}

        not dataset_has_control_plane_version?(dataset, control_plane_graph_iri, expected_version) ->
          {:error, {:restore_ontology_version_mismatch, expected_version}}

        true ->
          :ok
      end
    end
  end

  def validate_dataset(_dataset), do: {:error, :invalid_restore_dataset}

  defp load_and_check_dataset(staging_path, dataset) do
    with {:ok, store} <- TripleStore.open(staging_path, create_if_missing: true, schema: :quad) do
      try do
        with {:ok, loaded_count} <- TripleStore.load_graph(store, dataset),
             {:ok, integrity} <- Integrity.check_store(store),
             :ok <- assert_integrity_ready(integrity) do
          {:ok, loaded_count, integrity}
        end
      after
        TripleStore.close(store)
      end
    end
  end

  defp assert_integrity_ready(%{status: :ok}), do: :ok

  defp assert_integrity_ready(%{status: status, issues: issues}),
    do: {:error, {:restore_integrity_failed, status, issues}}

  defp swap_store_path(staging_path, target_path, backup_path) do
    File.rm_rf(backup_path)

    with :ok <- maybe_move_existing(target_path, backup_path) do
      case File.rename(staging_path, target_path) do
        :ok ->
          File.rm_rf(backup_path)
          :ok

        {:error, reason} ->
          restore_backup(target_path, backup_path)
          {:error, {:restore_swap_failed, reason}}
      end
    end
  end

  defp maybe_move_existing(target_path, backup_path) do
    if File.exists?(target_path) do
      File.rename(target_path, backup_path)
    else
      :ok
    end
  end

  defp restore_backup(target_path, backup_path) do
    File.rm_rf(target_path)

    if File.exists?(backup_path) do
      File.rename(backup_path, target_path)
    else
      :ok
    end
  end

  defp redact_quads(quads, []), do: {quads, 0}

  defp redact_quads(quads, redacted_graphs) do
    redacted_graph_iris =
      redacted_graphs
      |> Enum.map(&GraphTopology.graph_iri/1)
      |> Enum.flat_map(fn
        {:ok, iri} -> [iri]
        _other -> []
      end)
      |> MapSet.new()

    exported =
      Enum.reject(quads, fn {_subject, _predicate, _object, graph} ->
        MapSet.member?(redacted_graph_iris, to_string(graph))
      end)

    {exported, length(quads) - length(exported)}
  end

  defp serialize(quads, :nquads) do
    quads
    |> RDF.Dataset.new()
    |> RDF.NQuads.write_string([])
  end

  defp serialize(quads, :trig) do
    quads
    |> RDF.Dataset.new()
    |> RDF.TriG.write_string([])
  end

  defp read_dataset(path, :nquads), do: RDF.NQuads.read_file(path)
  defp read_dataset(path, :trig), do: RDF.TriG.read_file(path)

  defp dataset_has_control_plane_version?(dataset, control_plane_graph_iri, expected_version) do
    Enum.any?(RDF.Dataset.quads(dataset), fn {subject, predicate, object, graph} ->
      to_string(graph) == control_plane_graph_iri and
        to_string(subject) == "https://jido.run/ontology/control-plane#" and
        to_string(predicate) == "http://www.w3.org/2002/07/owl#versionInfo" and
        match?(%RDF.Literal{}, object) and RDF.Literal.value(object) |> to_string() == expected_version
    end)
  end

  defp redacted_graphs(opts), do: Keyword.get(opts, :redacted_graphs, [:auth, :security])

  defp export_format(path, opts), do: format(path, opts, :nquads)
  defp restore_format(path, opts), do: format(path, opts, nil)

  defp format(path, opts, default) do
    case Keyword.get(opts, :format) || format_from_extension(path) || default do
      :nquads -> :nquads
      "nquads" -> :nquads
      "nq" -> :nquads
      :trig -> :trig
      "trig" -> :trig
      other -> raise ArgumentError, "unsupported control-plane graph format: #{inspect(other)}"
    end
  end

  defp format_from_extension(path) do
    case path |> Path.extname() |> String.downcase() do
      ".nq" -> :nquads
      ".nquads" -> :nquads
      ".trig" -> :trig
      _other -> nil
    end
  end

  defp ensure_parent(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
  end
end
