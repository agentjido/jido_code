defmodule JidoCode.Runtime.InstanceManagers do
  @moduledoc """
  Static Jido instance managers used by repository runtimes.

  Manager names are application-owned atoms. Repository and work-item identity
  is supplied later through manager keys, not generated atom names.
  """

  alias Jido.Agent.InstanceManager

  alias JidoCode.Agents.{
    BudgetMonitor,
    Coder,
    CompactionStore,
    ContextCompactor,
    Explainer,
    MemoryGraphContext,
    MemoryGraphQuerier,
    MemoryGraphRecorder,
    MemoryGraphValidator,
    Planner,
    ProjectContext,
    Refactorer,
    RepoMonitor,
    Reviewer,
    SourceCodeGraphAnalyzer,
    SourceCodeGraphContext,
    SourceCodeGraphLoader,
    SourceCodeGraphQuerier,
    TaskBoard,
    WorkRegistry
  }

  alias JidoCode.Pods.{
    CodingPod,
    ContextManagementPod,
    MemoryGraphPod,
    RepoPod,
    SourceCodeGraphPod
  }

  @pod_managers [
    {:jido_code_repo_pods, RepoPod},
    {:jido_code_coding_pods, CodingPod},
    {:jido_code_source_code_graph_pods, SourceCodeGraphPod},
    {:jido_code_memory_graph_pods, MemoryGraphPod},
    {:jido_code_context_management_pods, ContextManagementPod}
  ]

  @node_managers [
    {:jido_code_repo_monitors, RepoMonitor},
    {:jido_code_work_registries, WorkRegistry},
    {:jido_code_task_boards, TaskBoard},
    {:jido_code_project_contexts, ProjectContext},
    {:jido_code_planners, Planner},
    {:jido_code_coders, Coder},
    {:jido_code_reviewers, Reviewer},
    {:jido_code_refactorers, Refactorer},
    {:jido_code_explainers, Explainer},
    {:jido_code_source_code_graph_contexts, SourceCodeGraphContext},
    {:jido_code_source_code_graph_analyzers, SourceCodeGraphAnalyzer},
    {:jido_code_source_code_graph_loaders, SourceCodeGraphLoader},
    {:jido_code_source_code_graph_queriers, SourceCodeGraphQuerier},
    {:jido_code_memory_graph_contexts, MemoryGraphContext},
    {:jido_code_memory_graph_recorders, MemoryGraphRecorder},
    {:jido_code_memory_graph_queriers, MemoryGraphQuerier},
    {:jido_code_memory_graph_validators, MemoryGraphValidator},
    {:jido_code_budget_monitors, BudgetMonitor},
    {:jido_code_compaction_stores, CompactionStore},
    {:jido_code_context_compactors, ContextCompactor}
  ]

  @spec pod_managers() :: [{atom(), module()}]
  def pod_managers, do: @pod_managers

  @spec node_managers() :: [{atom(), module()}]
  def node_managers, do: @node_managers

  @spec child_specs() :: [Supervisor.child_spec()]
  def child_specs do
    (@pod_managers ++ @node_managers)
    |> Enum.map(fn {name, agent} ->
      InstanceManager.child_spec(
        name: name,
        agent: agent,
        jido: JidoCode.Jido,
        idle_timeout: :infinity,
        storage: nil
      )
    end)
  end
end
