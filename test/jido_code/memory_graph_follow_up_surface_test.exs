defmodule JidoCode.MemoryGraphFollowUpSurfaceTest do
  use ExUnit.Case, async: true

  alias JidoCode.MemoryGraph.FollowUpSurface

  test "builds a bounded follow-up preview from product memory projections" do
    projection = %{
      kind: :memories,
      managed_repo_id: "repo-1",
      items: [
        %{
          memory_iri: "https://jido.run/managed_repos/repo-1/memory#decision/primary",
          content: "Keep the governed approval path explicit."
        },
        %{
          memory_iri: "https://jido.run/managed_repos/repo-1/memory#known_issue/follow-up",
          content: "Operators still need a bounded follow-up path."
        }
      ]
    }

    preview = FollowUpSurface.preview(projection, route: "/repos/repo-1/runs/run-1#run-detail-memory-context")

    assert preview.available? == true
    assert preview.recommended_action == "promote_memory_follow_up"
    assert preview.recommended_action_label == "Promote governed follow-up"
    assert preview.route == "/repos/repo-1/runs/run-1#run-detail-memory-context"
    assert preview.route_label == "Review bounded follow-up context"
    assert preview.selected_count == 2
    assert "KnownIssue" in preview.memory_kinds
    assert "Decision" in preview.memory_kinds
    assert preview.workflow_context["memory_resources"] != []
  end

  test "returns an unavailable preview when no durable memory is selected" do
    preview = FollowUpSurface.preview(%{kind: :memories, items: []})

    assert preview.available? == false
    assert preview.selected_count == 0
    assert preview.memory_kinds == []
  end
end
