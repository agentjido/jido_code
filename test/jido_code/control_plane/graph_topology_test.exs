defmodule JidoCode.ControlPlane.GraphTopologyTest do
  use ExUnit.Case, async: true

  alias JidoCode.ControlPlane.{GraphTopology, SemanticIdentity}

  @expected_graph_iris %{
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

  test "exposes one product-owned registry for named graph IRIs" do
    assert GraphTopology.graph_iris() == @expected_graph_iris
    assert GraphTopology.graph_names() == @expected_graph_iris |> Map.keys() |> Enum.sort()

    Enum.each(@expected_graph_iris, fn {graph_name, iri} ->
      assert {:ok, ^iri} = GraphTopology.graph_iri(graph_name)
      assert {:ok, graph_resource} = GraphTopology.graph_resource(graph_name)
      assert to_string(graph_resource) == iri
    end)
  end

  test "assigns every semantic record type to exactly one owner graph" do
    Enum.each(SemanticIdentity.record_types(), fn record_type ->
      assert {:ok, graph_name} = GraphTopology.graph_for_record(record_type)
      assert graph_name in GraphTopology.graph_names()
      assert {:ok, _graph_iri} = GraphTopology.graph_iri_for_record(record_type)
    end)
  end

  test "keeps product records, events, auth, security, conversations, and runtime isolated" do
    assert {:ok, :control_plane} = GraphTopology.graph_for_record(:managed_repo)
    assert {:ok, :control_plane} = GraphTopology.graph_for_record(:run)
    assert {:ok, :control_plane_events} = GraphTopology.graph_for_record(:event)
    assert {:ok, :control_plane_events} = GraphTopology.graph_for_record(:webhook_delivery)
    assert {:ok, :auth} = GraphTopology.graph_for_record(:user)
    assert {:ok, :security} = GraphTopology.graph_for_record(:secret_ref)
    assert {:ok, :conversations} = GraphTopology.graph_for_record(:conversation_event)
    assert {:ok, :execution_runtime} = GraphTopology.graph_for_record(:runtime_event)

    assert GraphTopology.append_only_graph?(:control_plane_events)
    assert GraphTopology.append_only_graph?(:conversations)
    assert GraphTopology.append_only_graph?(:execution_runtime)
    refute GraphTopology.append_only_graph?(:control_plane)
  end

  test "exposes cross-graph link rules with degraded behavior" do
    assert {:ok, memory_rule} = GraphTopology.link_rule(:memory, :control_plane)
    assert memory_rule.mode == :object_iri_only
    assert memory_rule.stale_behavior == :degraded_projection
    assert memory_rule.unavailable_behavior == :omit_links

    assert {:ok, source_rule} = GraphTopology.link_rule(:source_code, :memory)
    assert source_rule.mode == :object_iri_only

    assert {:ok, runtime_rule} = GraphTopology.link_rule(:execution_runtime, :control_plane)
    assert runtime_rule.description =~ "managed repositories"

    assert {:error, :unknown_link_rule} = GraphTopology.link_rule(:auth, :source_code)
  end

  test "lists record types by graph for fixture and projection setup" do
    assert {:ok, control_records} = GraphTopology.record_types_for_graph(:control_plane)
    assert :managed_repo in control_records
    assert :work_item in control_records
    assert :runtime_event not in control_records

    assert {:ok, runtime_records} = GraphTopology.record_types_for_graph(:execution_runtime)

    assert runtime_records == [
             :checkpoint,
             :exec_session,
             :execution_workflow,
             :runtime_event,
             :sandbox_session,
             :sprite_spec
           ]
  end
end
