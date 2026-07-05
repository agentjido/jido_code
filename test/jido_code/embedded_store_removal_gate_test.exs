defmodule JidoCode.EmbeddedStoreRemovalGateTest do
  use ExUnit.Case, async: true

  alias JidoCode.ControlPlane.Codecs.Registry
  alias JidoCode.ControlPlane.{SemanticIdentity, StoreCommand, StoreServer}

  @runtime_paths ["lib", "config", "test/support", "test/e2e", "mix.exs"]
  @lib_paths ["lib"]
  @control_plane_ns SemanticIdentity.ontology_namespace()

  @triple_store_boundary_prefixes [
    "lib/jido_code/control_plane/",
    "lib/jido_code/memory_graph/",
    "lib/jido_code/source_code_graph/"
  ]

  @forbidden_runtime_patterns [
    {~r/\balias\s+Ash(?:\.|\b)/, "alias Ash.*"},
    {~r/\bimport\s+Ash(?:\.|\b)/, "import Ash.*"},
    {~r/\brequire\s+Ash(?:\.|\b)/, "require Ash.*"},
    {~r/\buse\s+Ash\.Resource\b/, "use Ash.Resource"},
    {~r/\buse\s+Ash\.Domain\b/, "use Ash.Domain"},
    {~r/\bAshAuthentication\b/, "AshAuthentication"},
    {~r/\balias\s+Ecto(?:\.|\b)/, "alias Ecto.*"},
    {~r/\bimport\s+Ecto(?:\.|\b)/, "import Ecto.*"},
    {~r/\brequire\s+Ecto(?:\.|\b)/, "require Ecto.*"},
    {~r/\bJidoCode\.Repo\b/, "JidoCode.Repo"},
    {~r/\bEcto\.Adapters\.SQL\.Sandbox\b/, "Ecto.Adapters.SQL.Sandbox"},
    {~r/\becto_repos\b/, "ecto_repos"},
    {~r/\bash_domains\b/, "ash_domains"},
    {~r/\bmix\s+ecto\./, "mix ecto.*"}
  ]

  @direct_triple_store_patterns [
    {~r/\bTripleStore\.[A-Za-z_]/, "TripleStore.* call"},
    {~r/\balias\s+TripleStore(?:\.|\b)/, "alias TripleStore.*"},
    {~r/\bimport\s+TripleStore(?:\.|\b)/, "import TripleStore.*"},
    {~r/\brequire\s+TripleStore(?:\.|\b)/, "require TripleStore.*"},
    {~r/\buse\s+TripleStore(?:\.|\b)/, "use TripleStore.*"}
  ]

  @forbidden_direct_deps [
    :ash,
    :ash_postgres,
    :ash_json_api,
    :ash_authentication,
    :ash_authentication_phoenix,
    :ash_phoenix,
    :ecto_sql,
    :phoenix_ecto,
    :postgrex
  ]

  test "runtime and launch paths do not reference Ash, Repo, Ecto sandbox, or Ecto tasks" do
    assert [] = runtime_violations()
  end

  test "direct TripleStore access stays behind graph and store boundary modules" do
    assert [] = direct_triple_store_violations()
  end

  test "codec registry covers every planned control-plane record type" do
    coverage = Registry.planned_coverage()

    assert Registry.coverage_complete?(),
           "codec coverage drifted: #{inspect(coverage)}"

    assert coverage.missing_record_types == []
    assert coverage.extra_record_types == []
  end

  test "default graph export redacts auth and security records" do
    store_name = unique_store_name()
    path = store_path(store_name)
    export_path = Path.join(path <> "_exports", "control-plane.nq")

    on_exit(fn ->
      File.rm_rf(path)
      File.rm_rf(path <> "_exports")
    end)

    start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    insert_auth_user!(store_name)
    insert_security_secret_ref!(store_name)

    assert {:ok, report} = StoreServer.export(store_name, export_path)
    content = File.read!(export_path)

    assert report.redacted_graphs == [:auth, :security]
    assert report.omitted_quad_count > 0
    refute content =~ "redacted-user@example.test"
    refute content =~ "secret-ref-redacted"
    refute content =~ "github-token"
  end

  test "direct dependencies do not reintroduce Ash or Postgres packages" do
    direct_deps =
      Mix.Project.config()
      |> Keyword.fetch!(:deps)
      |> Enum.map(fn
        {name, _requirement} -> name
        {name, _requirement, _opts} -> name
      end)
      |> MapSet.new()

    forbidden = MapSet.new(@forbidden_direct_deps)

    assert MapSet.disjoint?(direct_deps, forbidden),
           "forbidden direct deps found: #{inspect(MapSet.intersection(direct_deps, forbidden) |> MapSet.to_list())}"
  end

  test "application config has no Ecto repo configuration" do
    assert Application.get_env(:jido_code, :ecto_repos) in [nil, []]
    refute Application.get_env(:jido_code, JidoCode.Repo)
  end

  defp runtime_violations do
    @runtime_paths
    |> Enum.flat_map(&path_files/1)
    |> Enum.flat_map(&file_violations(&1, @forbidden_runtime_patterns))
  end

  defp direct_triple_store_violations do
    @lib_paths
    |> Enum.flat_map(&path_files/1)
    |> Enum.filter(&(Path.extname(&1) == ".ex"))
    |> Enum.reject(&triple_store_boundary_path?/1)
    |> Enum.flat_map(&file_violations(&1, @direct_triple_store_patterns))
  end

  defp path_files(path) do
    cond do
      File.regular?(path) ->
        [path]

      File.dir?(path) ->
        path
        |> Path.join("**/*")
        |> Path.wildcard()
        |> Enum.filter(&File.regular?/1)
        |> Enum.filter(&text_file?/1)

      true ->
        []
    end
  end

  defp text_file?(path) do
    Path.extname(path) in [".ex", ".exs", ".ts", ".js", ".json", ".md"]
  end

  defp triple_store_boundary_path?(path) do
    Enum.any?(@triple_store_boundary_prefixes, &String.starts_with?(path, &1))
  end

  defp file_violations(path, patterns) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      patterns
      |> Enum.filter(fn {pattern, _label} -> line =~ pattern end)
      |> Enum.map(fn {_pattern, label} -> "#{path}:#{line_no}: #{label}" end)
    end)
  end

  defp insert_auth_user!(store_name) do
    subject_iri = canonical_iri!(:user, "user-redacted")

    assert {:ok, _outcome} =
             StoreCommand.execute(
               StoreCommand.insert(
                 graph_name: :auth,
                 subject_iri: subject_iri,
                 triples: [
                   {RDF.iri(subject_iri), RDF.type(), control_iri("User")},
                   {RDF.iri(subject_iri), control_iri("userId"), RDF.literal("user-redacted")},
                   {RDF.iri(subject_iri), control_iri("sourceKey"), RDF.literal("redacted-user@example.test")}
                 ]
               ),
               store_name
             )
  end

  defp insert_security_secret_ref!(store_name) do
    subject_iri = canonical_iri!(:secret_ref, "secret-ref-redacted")

    assert {:ok, _outcome} =
             StoreCommand.execute(
               StoreCommand.insert(
                 graph_name: :security,
                 subject_iri: subject_iri,
                 triples: [
                   {RDF.iri(subject_iri), RDF.type(), control_iri("SecretRef")},
                   {RDF.iri(subject_iri), control_iri("secretRefId"), RDF.literal("secret-ref-redacted")},
                   {RDF.iri(subject_iri), control_iri("canonicalKey"), RDF.literal("prod/github-token")},
                   {RDF.iri(subject_iri), control_iri("sourceKey"), RDF.literal("github-token")}
                 ]
               ),
               store_name
             )
  end

  defp canonical_iri!(record_type, id) do
    {:ok, iri} = SemanticIdentity.canonical_iri(record_type, id)
    iri
  end

  defp control_iri(local), do: RDF.iri(@control_plane_ns <> local)

  defp unique_store_name do
    :"embedded_store_removal_gate_#{System.unique_integer([:positive])}"
  end

  defp store_path(store_name) do
    Path.join([
      System.tmp_dir!(),
      "jido_code_embedded_store_removal_gate",
      Atom.to_string(store_name)
    ])
  end
end
