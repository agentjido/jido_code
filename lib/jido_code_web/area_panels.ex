defmodule JidoCodeWeb.AreaPanels do
  # covers: architecture.frontend_stack.root_area_shell_owns_navigation
  # covers: architecture.frontend_stack.salad_ui_liveview_and_shadcn_vue_islands
  @moduledoc """
  Server-authored overview panel data for root product areas.

  The reset shell uses these records as product-shaped entry panels while route
  bodies are rebuilt. They stay in LiveView assigns and avoid browser-side state.
  """

  alias JidoCodeWeb.Areas

  @panel_specs %{
    dashboard: %{
      posture: "Operational command",
      primary_action: %{id: "dashboard-review-workflows", label: "Review workflows", path: "/workflows"},
      metrics: [
        %{id: "runtime", label: "Runtime posture", value: "Session ready", detail: "Authenticated shell is active"},
        %{
          id: "work",
          label: "Work queue",
          value: "Route-owned",
          detail: "Runs and conversations remain server-authored"
        },
        %{id: "handoffs", label: "Handoffs", value: "8 areas", detail: "Use the area menu for major workspace changes"}
      ],
      sections: [
        %{
          id: "next-actions",
          title: "Next Actions",
          body: "Start from workflows, repository context, or workbench triage."
        },
        %{id: "readiness", title: "Readiness", body: "Runtime and setup status stay visible in the shell status strip."}
      ]
    },
    repositories: %{
      posture: "Repository control",
      primary_action: %{id: "repositories-open-workbench", label: "Open workbench", path: "/workbench"},
      metrics: [
        %{id: "inventory", label: "Inventory", value: "Managed", detail: "Repository records remain route-addressable"},
        %{
          id: "details",
          label: "Detail routes",
          value: "Preserved",
          detail: "Repository, run, evidence, and decision links stay live"
        },
        %{id: "context", label: "Context", value: "Shell-owned", detail: "Area status replaces global context chips"}
      ],
      sections: [
        %{
          id: "intake",
          title: "Repository Intake",
          body: "Use settings for GitHub import and repository authentication."
        },
        %{
          id: "continuity",
          title: "Deep Link Continuity",
          body: "Existing repository details keep their direct URLs during the reset."
        }
      ]
    },
    workbench: %{
      posture: "Triage workspace",
      primary_action: %{id: "workbench-open-repositories", label: "Open repositories", path: "/repos"},
      metrics: [
        %{id: "triage", label: "Triage", value: "Focused", detail: "Workbench remains the dense operator workspace"},
        %{id: "filters", label: "Filters", value: "Server", detail: "Route params continue to author filter state"},
        %{id: "actions", label: "Actions", value: "Governed", detail: "Workflow launch stays behind LiveView events"}
      ],
      sections: [
        %{id: "scan", title: "Scan", body: "Review repository posture and issue rows from a single area."},
        %{id: "launch", title: "Launch", body: "Start governed fixes or triage from server-confirmed context."}
      ]
    },
    conversations: %{
      posture: "Thread continuity",
      primary_action: %{id: "conversations-open-dashboard", label: "Open dashboard", path: "/dashboard"},
      metrics: [
        %{
          id: "threads",
          label: "Threads",
          value: "Productive",
          detail: "Conversation surfaces remain bounded by route state"
        },
        %{
          id: "handoff",
          label: "Handoff",
          value: "Explicit",
          detail: "Threads can hand off into workbench or repositories"
        },
        %{id: "memory", label: "Recall", value: "Governed", detail: "Durable memory stays an adopted product record"}
      ],
      sections: [
        %{
          id: "workspace",
          title: "Conversation Workspace",
          body: "Keep operator threads attached to repository and run context."
        },
        %{
          id: "handoffs",
          title: "Handoffs",
          body: "Move from discussion into workflows, memory, or semantic inspection intentionally."
        }
      ]
    },
    workflows: %{
      posture: "Governed launch",
      primary_action: %{id: "workflows-open-agents", label: "Open agents", path: "/agents"},
      metrics: [
        %{id: "launch", label: "Launch", value: "Manual", detail: "Workflow starts remain LiveView event driven"},
        %{id: "history", label: "History", value: "Addressable", detail: "Run detail links remain under repositories"},
        %{id: "policy", label: "Policy", value: "Visible", detail: "Approval posture stays explicit in product records"}
      ],
      sections: [
        %{id: "manual-runs", title: "Manual Runs", body: "Start governed work from a repository-scoped request."},
        %{id: "records", title: "Run Records", body: "Inspect each run through its preserved detail route."}
      ]
    },
    agents: %{
      posture: "Support automation",
      primary_action: %{id: "agents-open-settings", label: "Open settings", path: "/settings"},
      metrics: [
        %{
          id: "automation",
          label: "Automation",
          value: "Repo-scoped",
          detail: "Agent configuration remains per repository"
        },
        %{id: "events", label: "Events", value: "Governed", detail: "Webhook and issue bot settings stay explicit"},
        %{
          id: "controls",
          label: "Controls",
          value: "Operator",
          detail: "Enable and disable actions stay server-handled"
        }
      ],
      sections: [
        %{
          id: "support",
          title: "Support Agents",
          body: "Coordinate repository support automation from authenticated context."
        },
        %{
          id: "boundaries",
          title: "Boundaries",
          body: "Keep agent changes attached to product policy and audit records."
        }
      ]
    },
    memory: %{
      posture: "Durable recall",
      primary_action: %{id: "memory-open-conversations", label: "Open conversations", path: "/conversations"},
      metrics: [
        %{
          id: "adoption",
          label: "Adoption",
          value: "Explicit",
          detail: "Only adopted memories influence product behavior"
        },
        %{id: "provenance", label: "Provenance", value: "Bounded", detail: "Recall remains tied to workflow origins"},
        %{
          id: "degrade",
          label: "Degrade",
          value: "Legible",
          detail: "Operator flows stay readable when graph data is stale"
        }
      ],
      sections: [
        %{id: "recall", title: "Recall", body: "Inspect durable context without making it a hidden dependency."},
        %{id: "adoption", title: "Adoption", body: "Move useful findings into governed product records deliberately."}
      ]
    },
    semantic: %{
      posture: "Source inspection",
      primary_action: %{id: "semantic-open-memory", label: "Open memory", path: "/memory"},
      metrics: [
        %{id: "graph", label: "Graph", value: "Repository", detail: "Semantic analysis remains repository-scoped"},
        %{
          id: "freshness",
          label: "Freshness",
          value: "Explicit",
          detail: "Stale graph state must be visible to operators"
        },
        %{
          id: "findings",
          label: "Findings",
          value: "Governed",
          detail: "Semantic findings rejoin product records before action"
        }
      ],
      sections: [
        %{
          id: "inspection",
          title: "Inspection",
          body: "Ask structural questions about modules, functions, and runtime patterns."
        },
        %{
          id: "boundaries",
          title: "Boundaries",
          body: "Keep semantic services an enhancement rather than a hidden dependency."
        }
      ]
    },
    settings: %{
      posture: "Operator configuration",
      primary_action: %{id: "settings-open-repositories", label: "Open repositories", path: "/repos"},
      metrics: [
        %{id: "auth", label: "Auth", value: "Configured", detail: "Owner sessions and provider handoffs stay explicit"},
        %{
          id: "integrations",
          label: "Integrations",
          value: "Scoped",
          detail: "GitHub and secret settings stay product-owned"
        },
        %{id: "runtime", label: "Runtime", value: "Defaults", detail: "Environment choices remain setup-governed"}
      ],
      sections: [
        %{id: "security", title: "Security", body: "Manage auth, tokens, secrets, and integration trust boundaries."},
        %{id: "runtime", title: "Runtime Defaults", body: "Keep setup and environment defaults visible to operators."}
      ]
    }
  }

  def panel_for(area) when is_atom(area) do
    metadata = Areas.area_metadata!(area)
    spec = Map.fetch!(@panel_specs, area)

    %{
      id: metadata.id,
      area: metadata.area,
      title: metadata.label,
      summary: metadata.summary,
      posture: spec.posture,
      primary_action: spec.primary_action,
      metrics: spec.metrics,
      sections: spec.sections,
      handoffs: Areas.handoff_targets(area) |> Enum.take(4)
    }
  end
end
