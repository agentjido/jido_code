defmodule JidoCode.PhaseFiftyFiveIntegrationTest do
  # covers: architecture.memory_ontology.coding_memory_types_extend_core_memory_model
  # covers: package.jido_code.spec_led_workspace
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.{CaptureEnvelope, DurableMemoryEnvelope, ProductService}
  alias JidoCode.Projects.Project

  @memory_kinds [
    :invariant,
    :convention,
    :known_issue,
    :open_question,
    :pattern,
    :anti_pattern
  ]

  setup do
    previous = Application.get_env(:jido_code, :memory_graph_enabled, false)
    Application.put_env(:jido_code, :memory_graph_enabled, true)

    workspace_path = create_workspace_path!()

    on_exit(fn ->
      Application.put_env(:jido_code, :memory_graph_enabled, previous)
      File.rm_rf!(workspace_path)
    end)

    {:ok, workspace_path: workspace_path}
  end

  describe "Section 55.6.1 - Ontology type definitions scenarios" do
    test "Invariant class exists and is a Memory subclass" do
      assert {:ok, projection} =
               query_by_kind(
                 "invariant-ontology-test",
                 :invariant,
                 "Invariant ontology class is properly defined."
               )

      assert_invariant_ontology(projection)
    end

    test "Convention class exists and is a Memory subclass" do
      assert {:ok, projection} =
               query_by_kind(
                 "convention-ontology-test",
                 :convention,
                 "Convention ontology class is properly defined."
               )

      assert_convention_ontology(projection)
    end

    test "KnownIssue class exists and is a Memory subclass" do
      assert {:ok, projection} =
               query_by_kind(
                 "known-issue-ontology-test",
                 :known_issue,
                 "KnownIssue ontology class is properly defined."
               )

      assert_known_issue_ontology(projection)
    end

    test "OpenQuestion class exists and is a Memory subclass" do
      assert {:ok, projection} =
               query_by_kind(
                 "open-question-ontology-test",
                 :open_question,
                 "OpenQuestion ontology class is properly defined."
               )

      assert_open_question_ontology(projection)
    end

    test "Pattern class exists and is a Memory subclass" do
      assert {:ok, projection} =
               query_by_kind(
                 "pattern-ontology-test",
                 :pattern,
                 "Pattern ontology class is properly defined."
               )

      assert_pattern_ontology(projection)
    end

    test "AntiPattern class exists and is a Memory subclass" do
      assert {:ok, projection} =
               query_by_kind(
                 "anti-pattern-ontology-test",
                 :anti_pattern,
                 "AntiPattern ontology class is properly defined."
               )

      assert_anti_pattern_ontology(projection)
    end
  end

  describe "Section 55.6.2 - Envelope normalization scenarios" do
    test "normalize/2 accepts invariant kind" do
      assert {:ok, envelope} =
               DurableMemoryEnvelope.normalize(
                 DurableMemoryEnvelope.invariant(
                   session_id: "session-55-invariant",
                   actor_id: "system:test",
                   revision: "rev-55",
                   content: "All function inputs must be validated.",
                   classification: %{source: "test", reason: "Section 55.6.2 envelope test."}
                 ),
                 graph_context("repo-55", "rev-55")
               )

      assert envelope.kind == :invariant
      assert envelope.resource_class_iri == RDF.iri("https://jido.run/ontology/memory#Invariant")
    end

    test "normalize/2 accepts convention kind" do
      assert {:ok, envelope} =
               DurableMemoryEnvelope.normalize(
                 DurableMemoryEnvelope.convention(
                   session_id: "session-55-convention",
                   actor_id: "system:test",
                   revision: "rev-55",
                   content: "Use descriptive variable names.",
                   classification: %{source: "test", reason: "Section 55.6.2 envelope test."}
                 ),
                 graph_context("repo-55", "rev-55")
               )

      assert envelope.kind == :convention
      assert envelope.resource_class_iri == RDF.iri("https://jido.run/ontology/memory#Convention")
    end

    test "normalize/2 accepts known_issue kind" do
      assert {:ok, envelope} =
               DurableMemoryEnvelope.normalize(
                 DurableMemoryEnvelope.known_issue(
                   session_id: "session-55-known-issue",
                   actor_id: "system:test",
                   revision: "rev-55",
                   content: "Memory leak in long-running processes.",
                   classification: %{source: "test", reason: "Section 55.6.2 envelope test."}
                 ),
                 graph_context("repo-55", "rev-55")
               )

      assert envelope.kind == :known_issue
      assert envelope.resource_class_iri == RDF.iri("https://jido.run/ontology/memory#KnownIssue")
    end

    test "normalize/2 accepts open_question kind" do
      assert {:ok, envelope} =
               DurableMemoryEnvelope.normalize(
                 DurableMemoryEnvelope.open_question(
                   session_id: "session-55-open-question",
                   actor_id: "system:test",
                   revision: "rev-55",
                   content: "Should we migrate to Elixir 1.17?",
                   classification: %{source: "test", reason: "Section 55.6.2 envelope test."}
                 ),
                 graph_context("repo-55", "rev-55")
               )

      assert envelope.kind == :open_question
      assert envelope.resource_class_iri == RDF.iri("https://jido.run/ontology/memory#OpenQuestion")
    end

    test "normalize/2 accepts pattern kind" do
      assert {:ok, envelope} =
               DurableMemoryEnvelope.normalize(
                 DurableMemoryEnvelope.pattern(
                   session_id: "session-55-pattern",
                   actor_id: "system:test",
                   revision: "rev-55",
                   content: "Use GenServer for stateful processes.",
                   classification: %{source: "test", reason: "Section 55.6.2 envelope test."}
                 ),
                 graph_context("repo-55", "rev-55")
               )

      assert envelope.kind == :pattern
      assert envelope.resource_class_iri == RDF.iri("https://jido.run/ontology/memory#Pattern")
    end

    test "normalize/2 accepts anti_pattern kind" do
      assert {:ok, envelope} =
               DurableMemoryEnvelope.normalize(
                 DurableMemoryEnvelope.anti_pattern(
                   session_id: "session-55-anti-pattern",
                   actor_id: "system:test",
                   revision: "rev-55",
                   content: "Avoid global mutable state.",
                   classification: %{source: "test", reason: "Section 55.6.2 envelope test."}
                 ),
                 graph_context("repo-55", "rev-55")
               )

      assert envelope.kind == :anti_pattern
      assert envelope.resource_class_iri == RDF.iri("https://jido.run/ontology/memory#AntiPattern")
    end
  end

  describe "Section 55.6.3 - Writer triple emission scenarios" do
    setup %{workspace_path: workspace_path} do
      {_project, managed_repo} = create_managed_repo!(workspace_path)
      revision = "rev-55-writer"

      {:ok, _} =
        AgentWorkspace.refresh_memory_graph(
          managed_repo.id,
          workspace_path,
          revision: revision
        )

      {:ok, managed_repo: managed_repo, revision: revision, workspace_path: workspace_path}
    end

    test "write/2 emits correct types for Invariant", %{
      managed_repo: managed_repo,
      revision: revision,
      workspace_path: workspace_path
    } do
      memory_iri =
        record_memory!(
          managed_repo.id,
          workspace_path,
          revision,
          DurableMemoryEnvelope.invariant(
            session_id: "session-55-invariant-write",
            actor_id: "system:test",
            revision: revision,
            content: "All public functions must have @spec.",
            classification: %{source: "test", reason: "Section 55.6.3 writer test."}
          )
        )

      assert_invariant_triples(managed_repo.id, workspace_path, revision, memory_iri)
    end

    test "write/2 emits correct types for Convention", %{
      managed_repo: managed_repo,
      revision: revision,
      workspace_path: workspace_path
    } do
      memory_iri =
        record_memory!(
          managed_repo.id,
          workspace_path,
          revision,
          DurableMemoryEnvelope.convention(
            session_id: "session-55-convention-write",
            actor_id: "system:test",
            revision: revision,
            content: "Use snake_case for function names.",
            classification: %{source: "test", reason: "Section 55.6.3 writer test."}
          )
        )

      assert_convention_triples(managed_repo.id, workspace_path, revision, memory_iri)
    end

    test "write/2 emits correct types for KnownIssue", %{
      managed_repo: managed_repo,
      revision: revision,
      workspace_path: workspace_path
    } do
      memory_iri =
        record_memory!(
          managed_repo.id,
          workspace_path,
          revision,
          DurableMemoryEnvelope.known_issue(
            session_id: "session-55-known-issue-write",
            actor_id: "system:test",
            revision: revision,
            content: "Race condition in cache invalidation.",
            classification: %{source: "test", reason: "Section 55.6.3 writer test."}
          )
        )

      assert_known_issue_triples(managed_repo.id, workspace_path, revision, memory_iri)
    end

    test "write/2 emits correct types for OpenQuestion", %{
      managed_repo: managed_repo,
      revision: revision,
      workspace_path: workspace_path
    } do
      memory_iri =
        record_memory!(
          managed_repo.id,
          workspace_path,
          revision,
          DurableMemoryEnvelope.open_question(
            session_id: "session-55-open-question-write",
            actor_id: "system:test",
            revision: revision,
            content: "What is the performance impact of this change?",
            classification: %{source: "test", reason: "Section 55.6.3 writer test."}
          )
        )

      assert_open_question_triples(managed_repo.id, workspace_path, revision, memory_iri)
    end

    test "write/2 emits correct types for Pattern", %{
      managed_repo: managed_repo,
      revision: revision,
      workspace_path: workspace_path
    } do
      memory_iri =
        record_memory!(
          managed_repo.id,
          workspace_path,
          revision,
          DurableMemoryEnvelope.pattern(
            session_id: "session-55-pattern-write",
            actor_id: "system:test",
            revision: revision,
            content: "Use struct for defining data types.",
            classification: %{source: "test", reason: "Section 55.6.3 writer test."}
          )
        )

      assert_pattern_triples(managed_repo.id, workspace_path, revision, memory_iri)
    end

    test "write/2 emits correct types for AntiPattern", %{
      managed_repo: managed_repo,
      revision: revision,
      workspace_path: workspace_path
    } do
      memory_iri =
        record_memory!(
          managed_repo.id,
          workspace_path,
          revision,
          DurableMemoryEnvelope.anti_pattern(
            session_id: "session-55-anti-pattern-write",
            actor_id: "system:test",
            revision: revision,
            content: "Avoid god objects with too many responsibilities.",
            classification: %{source: "test", reason: "Section 55.6.3 writer test."}
          )
        )

      assert_anti_pattern_triples(managed_repo.id, workspace_path, revision, memory_iri)
    end
  end

  describe "Section 55.6.4 - Query and retrieval scenarios" do
    setup %{workspace_path: workspace_path} do
      {_project, managed_repo} = create_managed_repo!(workspace_path)
      revision = "rev-55-query"

      {:ok, _} =
        AgentWorkspace.refresh_memory_graph(
          managed_repo.id,
          workspace_path,
          revision: revision
        )

      session_id = "session-55-query-test"

      # Record one of each new type
      Enum.each(@memory_kinds, fn kind ->
        builder = apply(DurableMemoryEnvelope, kind, [
          [
            session_id: session_id,
            actor_id: "system:test",
            revision: revision,
            content: "#{Atom.to_string(kind)} content for query test.",
            classification: %{source: "test", reason: "Section 55.6.4 query test."}
          ]
        ])

        record_memory!(managed_repo.id, workspace_path, revision, builder)
      end)

      {:ok, managed_repo: managed_repo, revision: revision, session_id: session_id, workspace_path: workspace_path}
    end

    test "memories/2 returns all new memory types", %{
      managed_repo: managed_repo,
      revision: revision,
      workspace_path: workspace_path
    } do
      assert {:ok, projection} =
               ProductService.memories(
                 managed_repo.id,
                 workspace_path,
                 revision: revision
               )

      assert projection.result_group.count >= length(@memory_kinds)

      returned_kinds =
        projection.items
        |> Enum.map(fn item -> item.memory_kind end)
        |> Enum.uniq()

      # Check that all new kinds are present
      assert "Invariant" in returned_kinds
      assert "Convention" in returned_kinds
      assert "KnownIssue" in returned_kinds
      assert "OpenQuestion" in returned_kinds
      assert "Pattern" in returned_kinds
      assert "AntiPattern" in returned_kinds
    end

    test "SPARQL queries can filter by new types", %{
      managed_repo: managed_repo,
      revision: revision,
      workspace_path: workspace_path
    } do
      for {kind, class_name} <- [
            {:invariant, "Invariant"},
            {:convention, "Convention"},
            {:known_issue, "KnownIssue"},
            {:open_question, "OpenQuestion"},
            {:pattern, "Pattern"},
            {:anti_pattern, "AntiPattern"}
          ] do
        assert {:ok, query_result} =
                 AgentWorkspace.query_memory_graph(
                   managed_repo.id,
                   workspace_path,
                   """
                   SELECT ?memory ?content
                   WHERE {
                     ?memory a jido:#{class_name} ;
                       jido:content ?content .
                   }
                   """,
                   revision: revision
                 )

        assert query_result.row_count >= 1,
               "Expected at least one #{class_name} memory"

        assert Enum.any?(query_result.bindings, fn binding ->
                 get_in(binding, ["content", :value])
                 |> String.contains?("#{kind} content for query test")
               end)
      end
    end

    test "ViewModel formats new types correctly", %{
      managed_repo: managed_repo,
      revision: revision,
      workspace_path: workspace_path
    } do
      assert {:ok, projection} =
               ProductService.memories(
                 managed_repo.id,
                 workspace_path,
                 revision: revision
               )

      # Find items of each new type and verify formatting
      for kind_name <- ["Invariant", "Convention", "KnownIssue", "OpenQuestion", "Pattern", "AntiPattern"] do
        item = Enum.find(projection.items, fn i -> i.memory_kind == kind_name end)

        refute item == nil, "Expected to find a #{kind_name} memory"
        assert item.memory_kind == kind_name
        assert is_binary(item.memory_iri)
        assert is_binary(item.content)
        assert item.memory_kind_iri =~ ~r/##{kind_name}$/
      end
    end
  end

  # Helper functions

  defp create_managed_repo!(workspace_path) do
    name = "phase-55-#{System.unique_integer([:positive])}"

    {:ok, project} =
      Project.create(%{
        name: name,
        github_full_name: "owner/#{name}",
        default_branch: "main",
        settings: %{workspace: %{workspace_path: workspace_path}}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {project, managed_repo}
  end

  defp create_workspace_path! do
    workspace_path =
      System.tmp_dir!()
      |> Path.join("jido_code_phase_55_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseFiftyFive.MixProject do
        use Mix.Project

        def project do
          [app: :phase_fifty_five, version: "0.1.0"]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/phase_fifty_five.ex"),
      """
      defmodule PhaseFiftyFive do
        def test_function, do: :ok
      end
      """
    )

    workspace_path
  end

  defp graph_context(managed_repo_id, revision) do
    %{
      managed_repo_id: managed_repo_id,
      workspace_path: "/tmp/jido_code_phase_55",
      selected_graph_name: MemoryGraph.memory_graph_name(),
      revision_metadata: %{current_revision: revision, requested_revision: revision}
    }
  end

  defp query_by_kind(_id, kind, content) do
    managed_repo_id = "repo-55-ontology"
    revision = "rev-55-ontology"

    workspace_path =
      System.tmp_dir!()
      |> Path.join("jido_code_phase_55_query_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseFiftyFiveQuery.MixProject do
        use Mix.Project

        def project do
          [app: :phase_fifty_five_query, version: "0.1.0"]
        end
      end
      """
    )

    try do
      {:ok, _} =
        AgentWorkspace.refresh_memory_graph(
          managed_repo_id,
          workspace_path,
          revision: revision
        )

      builder = apply(DurableMemoryEnvelope, kind, [[
        session_id: "session-55-ontology",
        actor_id: "system:test",
        revision: revision,
        content: content,
        classification: %{source: "test", reason: "Section 55.6.1 ontology test."}
      ]])

      record_memory!(managed_repo_id, workspace_path, revision, builder)

      ProductService.memories(
        managed_repo_id,
        workspace_path,
        revision: revision
      )
    after
      File.rm_rf!(workspace_path)
    end
  end

  defp record_memory!(managed_repo_id, workspace_path, revision, capture) do
    assert {:ok, result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               capture,
               revision: revision
             )

    result.capture.resource_iri
  end

  # Ontology assertion helpers

  defp assert_invariant_ontology(projection) do
    item = Enum.find(projection.items, fn i -> i.memory_kind == "Invariant" end)
    assert item, "Invariant memory not found"
    assert item.memory_kind_iri =~ ~r/#Invariant$/
  end

  defp assert_convention_ontology(projection) do
    item = Enum.find(projection.items, fn i -> i.memory_kind == "Convention" end)
    assert item, "Convention memory not found"
    assert item.memory_kind_iri =~ ~r/#Convention$/
  end

  defp assert_known_issue_ontology(projection) do
    item = Enum.find(projection.items, fn i -> i.memory_kind == "KnownIssue" end)
    assert item, "KnownIssue memory not found"
    assert item.memory_kind_iri =~ ~r/#KnownIssue$/
  end

  defp assert_open_question_ontology(projection) do
    item = Enum.find(projection.items, fn i -> i.memory_kind == "OpenQuestion" end)
    assert item, "OpenQuestion memory not found"
    assert item.memory_kind_iri =~ ~r/#OpenQuestion$/
  end

  defp assert_pattern_ontology(projection) do
    item = Enum.find(projection.items, fn i -> i.memory_kind == "Pattern" end)
    assert item, "Pattern memory not found"
    assert item.memory_kind_iri =~ ~r/#Pattern$/
  end

  defp assert_anti_pattern_ontology(projection) do
    item = Enum.find(projection.items, fn i -> i.memory_kind == "AntiPattern" end)
    assert item, "AntiPattern memory not found"
    assert item.memory_kind_iri =~ ~r/#AntiPattern$/
  end

  # Triple assertion helpers

  defp assert_invariant_triples(managed_repo_id, workspace_path, revision, memory_iri) do
    assert_memory_triple(managed_repo_id, workspace_path, revision, memory_iri, "Invariant", "jido:Invariant")
  end

  defp assert_convention_triples(managed_repo_id, workspace_path, revision, memory_iri) do
    assert_memory_triple(managed_repo_id, workspace_path, revision, memory_iri, "Convention", "jido:Convention")
  end

  defp assert_known_issue_triples(managed_repo_id, workspace_path, revision, memory_iri) do
    assert_memory_triple(managed_repo_id, workspace_path, revision, memory_iri, "KnownIssue", "jido:KnownIssue")
  end

  defp assert_open_question_triples(managed_repo_id, workspace_path, revision, memory_iri) do
    assert_memory_triple(managed_repo_id, workspace_path, revision, memory_iri, "OpenQuestion", "jido:OpenQuestion")
  end

  defp assert_pattern_triples(managed_repo_id, workspace_path, revision, memory_iri) do
    assert_memory_triple(managed_repo_id, workspace_path, revision, memory_iri, "Pattern", "jido:Pattern")
  end

  defp assert_anti_pattern_triples(managed_repo_id, workspace_path, revision, memory_iri) do
    assert_memory_triple(managed_repo_id, workspace_path, revision, memory_iri, "AntiPattern", "jido:AntiPattern")
  end

  defp assert_memory_triple(managed_repo_id, workspace_path, _revision, memory_iri, class_name, _jido_class) do
    # First verify the specific type
    assert {:ok, type_query} =
             AgentWorkspace.query_memory_graph(
               managed_repo_id,
               workspace_path,
               """
               SELECT ?type
               WHERE {
                 <#{memory_iri}> rdf:type ?type .
                 FILTER (?type = <https://jido.run/ontology/memory##{class_name}>)
               }
               """,
               allow_stale?: true
             )

    assert type_query.row_count >= 1,
           "Expected #{class_name} type triple for #{memory_iri}"

    # Also verify it's a subclass of Memory
    assert {:ok, memory_query} =
             AgentWorkspace.query_memory_graph(
               managed_repo_id,
               workspace_path,
               """
               SELECT ?memoryType
               WHERE {
                 <#{memory_iri}> rdf:type ?memoryType .
                 FILTER (?memoryType = <https://jido.run/ontology/memory#Memory>)
               }
               """,
               allow_stale?: true
             )

    assert memory_query.row_count >= 1,
           "Expected Memory type triple for #{memory_iri}"
  end
end
