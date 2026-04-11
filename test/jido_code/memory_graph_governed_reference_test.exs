defmodule JidoCode.MemoryGraph.GovernedReferenceTest do
  # covers: architecture.memory_graph.memory_graph_supports_cross_graph_provenance
  # covers: architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
  # covers: architecture.memory_capture_plane.typed_governed_reference_contract_is_canonical
  use ExUnit.Case, async: true

  alias JidoCode.MemoryGraph.GovernedReference

  test "builds stable repository-scoped IRIs for governed record kinds" do
    assert GovernedReference.base_iri("repo-123") ==
             "https://jido.run/managed_repos/repo-123/governed#"

    assert GovernedReference.iri("repo-123", :run, "run-42") ==
             "https://jido.run/managed_repos/repo-123/governed#run/run-42"

    assert GovernedReference.iri("repo-123", :work_item, "work item/42") ==
             "https://jido.run/managed_repos/repo-123/governed#work_item/work%20item%2F42"
  end

  test "normalizes shorthand governed references into a typed contract" do
    assert {:ok,
            %{
              kind: :run,
              id: "run-42",
              iri: "https://jido.run/managed_repos/repo-123/governed#run/run-42",
              label: "Run run-42"
            }} =
             GovernedReference.normalize("repo-123", %{run_id: "run-42"})

    assert {:ok,
            %{
              kind: :decision,
              id: "decision-42",
              iri: "https://jido.run/managed_repos/repo-123/governed#decision/decision-42",
              label: "Decision approval needed"
            }} =
             GovernedReference.normalize("repo-123", %{
               kind: "decision",
               id: "decision-42",
               label: "Decision approval needed"
             })
  end

  test "normalizes and deduplicates multiple references" do
    assert {:ok, normalized} =
             GovernedReference.normalize_many("repo-123", [
               %{run_id: "run-42"},
               %{kind: :run, id: "run-42"},
               %{work_item_id: "work-42"}
             ])

    assert Enum.map(normalized, & &1.kind) == [:run, :work_item]
  end

  test "normalizes shorthand governed context into typed references" do
    assert GovernedReference.explicit_many(%{run_id: "run-42", decision_id: "decision-42"})
           |> Enum.sort_by(&{&1.kind, &1.id}) == [
             %{kind: :decision, id: "decision-42"},
             %{kind: :run, id: "run-42"}
           ]

    assert {:ok, normalized} =
             GovernedReference.normalize_context("repo-123", %{run_id: "run-42", decision_id: "decision-42"})

    assert normalized |> Enum.map(& &1.kind) |> Enum.sort() == [:decision, :run]
  end

  test "rejects mismatched managed repo scope" do
    assert {:error, :managed_repo_scope_mismatch} =
             GovernedReference.normalize("repo-123", %{managed_repo_id: "repo-456"})
  end
end
