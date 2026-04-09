defmodule JidoCodeWeb.ProjectDetailLive do
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.frontend_stack.server_authored_props_streams_and_events
  # covers: setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language
  use JidoCodeWeb, :live_view

  alias JidoCode.Workbench.ProjectDetail
  alias JidoCode.Workbench.ProjectSemanticInspection
  alias JidoCode.Workbench.ProjectDetailWorkflowKickoff

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:project_detail, nil)
     |> assign(:project_load_error, nil)
     |> assign(:semantic_inspection, nil)
     |> assign(:semantic_action_feedback, nil)
     |> assign(:workflow_launch_states, %{})
     |> assign(:return_to_path, "/workbench")
     |> assign(:supported_workflows, ProjectDetailWorkflowKickoff.supported_workflows())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_id = Map.get(params, "id")
    return_to_path = normalize_return_to_path(Map.get(params, "return_to"))

    socket =
      case ProjectDetail.load(project_id) do
        {:ok, project_detail} ->
          socket
          |> assign(:project_detail, project_detail)
          |> assign(:project_load_error, nil)
          |> assign(:semantic_inspection, ProjectSemanticInspection.load_repo_detail(project_detail))
          |> assign(:semantic_action_feedback, nil)

        {:error, project_load_error} ->
          socket
          |> assign(:project_detail, nil)
          |> assign(:project_load_error, project_load_error)
          |> assign(:semantic_inspection, nil)
          |> assign(:semantic_action_feedback, nil)
      end

    {:noreply,
     socket
     |> assign(:workflow_launch_states, %{})
     |> assign(:return_to_path, return_to_path)}
  end

  @impl true
  def handle_event("kickoff_workflow", %{"workflow_name" => workflow_name}, socket) do
    workflow_key = normalize_workflow_name(workflow_name)

    kickoff_result =
      ProjectDetailWorkflowKickoff.kickoff(
        socket.assigns.project_detail,
        workflow_name,
        initiating_actor(socket)
      )

    {:noreply, put_workflow_launch_state(socket, workflow_key, kickoff_result)}
  end

  @impl true
  def handle_event("recover_semantic_graph", _params, socket) do
    project_detail = Map.get(socket.assigns, :project_detail)

    case ProjectSemanticInspection.recover(project_detail) do
      {:ok, %{inspection: inspection, feedback: feedback}} ->
        {:noreply,
         socket
         |> assign(:semantic_inspection, inspection)
         |> assign(:semantic_action_feedback, feedback)}

      {:error, %{inspection: inspection, feedback: feedback}} ->
        {:noreply,
         socket
         |> assign(:semantic_inspection, inspection)
         |> assign(:semantic_action_feedback, feedback)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <section class="space-y-2">
        <h1 id="project-detail-title" class="text-2xl font-bold">Managed repo detail</h1>
        <p class="text-base-content/70">
          Launch builtin workflows from the managed-repository control view with governed run traceability.
        </p>
      </section>

      <.operator_state_notice
        :if={@project_load_error}
        id="project-detail-load-error"
        title="Managed repository detail is unavailable"
        state={@project_load_error}
        kind={:error}
      />

      <section
        :if={@project_detail}
        id={"project-detail-panel-#{@project_detail.id}"}
        class="space-y-4 rounded-lg border border-base-300 bg-base-100 p-4"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p id="project-detail-github-full-name" class="text-lg font-semibold">
              {@project_detail.github_full_name}
            </p>
            <p id="project-detail-project-name" class="text-sm text-base-content/70">
              {@project_detail.name}
            </p>
          </div>
          <.link id="project-detail-return-link" class="btn btn-sm btn-outline" navigate={@return_to_path}>
            Back
          </.link>
        </div>

        <.vue_surface
          id="project-detail-overview-widget"
          component="ProjectDetailOverviewWidget"
          socket={@socket}
          props={project_detail_overview_props(assigns)}
        />

        <section id="project-detail-semantic-inspection" class="space-y-4">
          <div class="space-y-1">
            <h2 class="text-lg font-semibold">Semantic repository inspection</h2>
            <p class="text-sm text-base-content/70">
              Semantic source-code graph insights stay repo-scoped, bounded, and product-owned on this managed-repository route.
            </p>
          </div>

          <.operator_state_notice
            :if={@semantic_action_feedback}
            id="project-detail-semantic-feedback"
            title="Semantic graph recovery update"
            state={@semantic_action_feedback}
            kind={:info}
          />

          <.operator_state_notice
            :if={semantic_notice_visible?(@semantic_inspection)}
            id="project-detail-semantic-notice"
            title="Semantic graph status"
            state={@semantic_inspection.notice}
            kind={semantic_notice_kind(@semantic_inspection)}
          >
            <:actions>
              <button
                :if={semantic_recovery_available?(@semantic_inspection)}
                id="project-detail-semantic-recover"
                type="button"
                class="btn btn-sm btn-outline"
                phx-click="recover_semantic_graph"
              >
                {semantic_recovery_label(@semantic_inspection)}
              </button>
            </:actions>
          </.operator_state_notice>

          <.vue_surface
            id="project-detail-semantic-explorer-widget"
            component="ProjectDetailSemanticExplorerWidget"
            socket={@socket}
            props={project_detail_semantic_explorer_props(assigns)}
            events={%{"requestRecovery" => "recover_semantic_graph"}}
            fallback_title="Interactive semantic explorer temporarily unavailable"
            fallback_detail="This repository is using the server-rendered semantic summary while the richer explorer is unavailable."
          >
            <section id="project-detail-semantic-fallback" class="space-y-3">
              <div class="grid gap-3 md:grid-cols-4">
                <article
                  id="project-detail-semantic-fallback-modules"
                  class="rounded-lg border border-base-300/70 bg-base-100 p-3"
                >
                  <p class="text-xs uppercase text-base-content/60">Modules</p>
                  <p class="mt-1 text-xl font-semibold">{semantic_group_count(@semantic_inspection.summary, :modules)}</p>
                </article>
                <article
                  id="project-detail-semantic-fallback-functions"
                  class="rounded-lg border border-base-300/70 bg-base-100 p-3"
                >
                  <p class="text-xs uppercase text-base-content/60">Functions</p>
                  <p class="mt-1 text-xl font-semibold">{semantic_result_count(@semantic_inspection.functions)}</p>
                </article>
                <article
                  id="project-detail-semantic-fallback-runtime-patterns"
                  class="rounded-lg border border-base-300/70 bg-base-100 p-3"
                >
                  <p class="text-xs uppercase text-base-content/60">Runtime patterns</p>
                  <p class="mt-1 text-xl font-semibold">
                    {semantic_result_count(@semantic_inspection.runtime_patterns)}
                  </p>
                </article>
                <article
                  id="project-detail-semantic-fallback-impact"
                  class="rounded-lg border border-base-300/70 bg-base-100 p-3"
                >
                  <p class="text-xs uppercase text-base-content/60">Impact relationships</p>
                  <p class="mt-1 text-xl font-semibold">{semantic_result_count(@semantic_inspection.impact)}</p>
                </article>
              </div>

              <div class="grid gap-3 lg:grid-cols-2">
                <section id="project-detail-semantic-fallback-module-list" class="space-y-2">
                  <h3 class="font-medium">Modules</h3>
                  <p
                    :if={Enum.empty?(semantic_items(@semantic_inspection.modules))}
                    class="text-sm text-base-content/70"
                  >
                    No module summaries are currently available.
                  </p>
                  <ul :if={!Enum.empty?(semantic_items(@semantic_inspection.modules))} class="space-y-1 text-sm">
                    <li :for={item <- semantic_items(@semantic_inspection.modules)}>
                      {Map.get(item, :module_name) || "Unnamed module"}
                    </li>
                  </ul>
                </section>

                <section id="project-detail-semantic-fallback-impact-list" class="space-y-2">
                  <h3 class="font-medium">Impact</h3>
                  <p
                    :if={Enum.empty?(semantic_items(@semantic_inspection.impact))}
                    class="text-sm text-base-content/70"
                  >
                    No bounded impact relationships are currently available.
                  </p>
                  <ul :if={!Enum.empty?(semantic_items(@semantic_inspection.impact))} class="space-y-1 text-sm">
                    <li :for={item <- semantic_items(@semantic_inspection.impact)}>
                      {Map.get(item, :predicate_name) || "relationship"}
                    </li>
                  </ul>
                </section>
              </div>
            </section>
          </.vue_surface>
        </section>

        <section
          id="project-detail-workflow-defaults"
          class="rounded-lg border border-base-300 bg-base-200/40 p-3 space-y-1"
        >
          <p class="text-sm font-medium">Managed repository launch defaults</p>
          <p id="project-detail-default-branch" class="text-sm text-base-content/80">
            Default branch: {@project_detail.default_branch}
          </p>
          <p id="project-detail-default-repository" class="text-sm text-base-content/80">
            Repository: {@project_detail.github_full_name}
          </p>
          <p
            :if={@project_detail.managed_repo_id}
            id="project-detail-managed-repo-id"
            class="text-xs text-base-content/70"
          >
            Managed repo: {@project_detail.managed_repo_id}
          </p>
        </section>

        <section
          :if={!project_ready_for_launch?(@project_detail)}
          id="project-detail-launch-disabled-guidance"
          class="rounded-lg border border-warning/60 bg-warning/10 p-3 space-y-1"
        >
          <p id="project-detail-launch-disabled-label" class="font-semibold">
            Workflow launch controls are disabled
          </p>
          <p id="project-detail-launch-disabled-type" class="text-xs">
            Typed readiness state: {project_readiness(@project_detail).error_type}
          </p>
          <p id="project-detail-launch-disabled-detail" class="text-sm">
            {project_readiness(@project_detail).detail}
          </p>
          <p id="project-detail-launch-disabled-remediation" class="text-sm">
            {project_readiness(@project_detail).remediation}
          </p>
        </section>

        <section id="project-detail-workflow-controls" class="grid gap-3 md:grid-cols-2">
          <article
            :for={workflow <- @supported_workflows}
            id={"project-detail-workflow-card-#{workflow_dom_id(workflow.name)}"}
            class="rounded-lg border border-base-300 p-3 space-y-2"
          >
            <div>
              <h2
                id={"project-detail-workflow-label-#{workflow_dom_id(workflow.name)}"}
                class="font-semibold"
              >
                {workflow.label}
              </h2>
              <p
                id={"project-detail-workflow-name-#{workflow_dom_id(workflow.name)}"}
                class="text-xs font-mono text-base-content/70"
              >
                {workflow.name}
              </p>
            </div>

            <%= if project_ready_for_launch?(@project_detail) do %>
              <button
                id={"project-detail-launch-#{workflow_dom_id(workflow.name)}"}
                type="button"
                class="btn btn-sm btn-primary"
                phx-click="kickoff_workflow"
                phx-value-workflow_name={workflow.name}
              >
                Launch workflow
              </button>
            <% else %>
              <span
                id={"project-detail-launch-disabled-#{workflow_dom_id(workflow.name)}"}
                class="btn btn-sm btn-disabled cursor-not-allowed"
                aria-disabled="true"
              >
                Launch workflow
              </span>
            <% end %>

            <.workflow_launch_feedback
              feedback={workflow_launch_feedback(@workflow_launch_states, workflow.name)}
              dom_prefix={"project-detail-launch-#{workflow_dom_id(workflow.name)}"}
            />
          </article>
        </section>
      </section>
    </Layouts.app>
    """
  end

  attr(:feedback, :map, default: nil)
  attr(:dom_prefix, :string, required: true)

  defp workflow_launch_feedback(assigns) do
    ~H"""
    <section :if={@feedback} id={"#{@dom_prefix}-feedback"} class="space-y-1">
      <%= case @feedback.status do %>
        <% :ok -> %>
          <p id={"#{@dom_prefix}-run-id"} class="text-xs text-success">
            Run: <span class="font-mono">{@feedback.run.run_id}</span>
          </p>
          <.link
            id={"#{@dom_prefix}-run-link"}
            class="link link-primary text-xs"
            href={@feedback.run.detail_path}
          >
            Open run detail
          </.link>
        <% :error -> %>
          <p id={"#{@dom_prefix}-error-type"} class="text-xs text-error">
            Typed kickoff error: {@feedback.error.error_type}
          </p>
          <p id={"#{@dom_prefix}-error-detail"} class="text-xs text-error">
            {@feedback.error.detail}
          </p>
          <p id={"#{@dom_prefix}-error-remediation"} class="text-xs text-base-content/70">
            {@feedback.error.remediation}
          </p>
      <% end %>
    </section>
    """
  end

  defp put_workflow_launch_state(socket, workflow_name, kickoff_result) do
    state_value =
      case kickoff_result do
        {:ok, kickoff_run} ->
          %{status: :ok, run: kickoff_run}

        {:error, kickoff_error} ->
          %{status: :error, error: kickoff_error}
      end

    update(socket, :workflow_launch_states, &Map.put(&1, workflow_name, state_value))
  end

  defp workflow_launch_feedback(states, workflow_name) when is_map(states) do
    states
    |> Map.get(normalize_workflow_name(workflow_name))
  end

  defp workflow_launch_feedback(_states, _workflow_name), do: nil

  defp project_detail_overview_props(assigns) do
    project_detail = Map.get(assigns, :project_detail, %{})
    supported_workflows = Map.get(assigns, :supported_workflows, [])

    %{
      githubFullName:
        project_detail
        |> map_get(:github_full_name, "github_full_name")
        |> normalize_optional_string() || "unknown/repository",
      projectName:
        project_detail
        |> map_get(:name, "name")
        |> normalize_optional_string() || "Unnamed project",
      defaultBranch:
        project_detail
        |> map_get(:default_branch, "default_branch")
        |> normalize_optional_string() || "main",
      managedRepoId:
        project_detail
        |> map_get(:managed_repo_id, "managed_repo_id")
        |> normalize_optional_string(),
      launchReady: project_ready_for_launch?(project_detail),
      launchSummary: project_launch_summary(project_detail),
      workflowCards:
        Enum.map(supported_workflows, fn workflow ->
          workflow_feedback =
            workflow_launch_feedback(Map.get(assigns, :workflow_launch_states, %{}), workflow.name)

          %{
            id: workflow_dom_id(workflow.name),
            label: workflow.label,
            name: workflow.name,
            launchable: project_ready_for_launch?(project_detail),
            feedbackStatus: workflow_feedback_status(workflow_feedback),
            feedbackMessage: workflow_feedback_message(workflow_feedback)
          }
        end)
    }
  end

  defp project_launch_summary(project_detail) do
    if project_ready_for_launch?(project_detail) do
      "Managed-repository launch defaults are ready for builtin workflow kickoff."
    else
      readiness = project_readiness(project_detail)

      readiness
      |> map_get(:detail, "detail")
      |> normalize_optional_string() ||
        "Managed-repository launch controls remain blocked until workspace readiness is restored."
    end
  end

  defp workflow_feedback_status(%{status: :ok}), do: "ok"
  defp workflow_feedback_status(%{status: :error}), do: "error"
  defp workflow_feedback_status(_feedback), do: nil

  defp workflow_feedback_message(%{status: :ok, run: run}) do
    run
    |> map_get(:run_id, "run_id")
    |> normalize_optional_string()
    |> case do
      nil -> "Workflow kickoff succeeded."
      run_id -> "Latest kickoff run: #{run_id}"
    end
  end

  defp workflow_feedback_message(%{status: :error, error: error}) do
    error
    |> map_get(:detail, "detail")
    |> normalize_optional_string() || "Workflow kickoff failed."
  end

  defp workflow_feedback_message(_feedback), do: nil

  defp project_detail_semantic_explorer_props(assigns) do
    inspection = Map.get(assigns, :semantic_inspection) || %{}
    graph = Map.get(inspection, :graph, %{})

    %{
      managedRepoId: Map.get(inspection, :managed_repo_id),
      graph: %{
        state: graph |> Map.get(:state, :unavailable) |> to_string(),
        ready: Map.get(graph, :ready?, false),
        stale: Map.get(graph, :stale?, false),
        degraded: Map.get(graph, :degraded?, false),
        importedRevision: Map.get(graph, :imported_revision),
        currentRevision: Map.get(graph, :current_revision)
      },
      summaryCards: [
        %{
          id: "modules",
          label: "Modules",
          count: semantic_group_count(Map.get(inspection, :summary), :modules),
          detail: "Bounded module summaries from the managed repository semantic graph."
        },
        %{
          id: "functions",
          label: "Functions",
          count: semantic_result_count(Map.get(inspection, :functions)),
          detail: "Function summaries stay bounded to product-authored semantic projections."
        },
        %{
          id: "runtime_patterns",
          label: "Runtime patterns",
          count: semantic_result_count(Map.get(inspection, :runtime_patterns)),
          detail: "Runtime patterns remain explainable without exposing raw graph internals."
        },
        %{
          id: "impact",
          label: "Impact",
          count: semantic_result_count(Map.get(inspection, :impact)),
          detail: "Impact relationships stay repo-scoped and recovery-aware."
        }
      ],
      modules:
        Enum.map(semantic_items(Map.get(inspection, :modules)), fn item ->
          %{
            moduleName: Map.get(item, :module_name),
            moduleIri: Map.get(item, :module_iri)
          }
        end),
      functions:
        Enum.map(semantic_items(Map.get(inspection, :functions)), fn item ->
          %{
            moduleName: Map.get(item, :module_name),
            functionName: Map.get(item, :function_name),
            arity: Map.get(item, :arity)
          }
        end),
      runtimePatterns:
        Enum.map(semantic_items(Map.get(inspection, :runtime_patterns)), fn item ->
          %{
            patternName: Map.get(item, :pattern_name),
            patternIri: Map.get(item, :pattern_iri)
          }
        end),
      impact:
        Enum.map(semantic_items(Map.get(inspection, :impact)), fn item ->
          %{
            predicateName: Map.get(item, :predicate_name),
            sourceIri: Map.get(item, :source_iri),
            targetIri: Map.get(item, :target_iri)
          }
        end),
      recovery: %{
        available: semantic_recovery_available?(inspection),
        label: semantic_recovery_label(inspection)
      }
    }
  end

  defp semantic_notice_visible?(%{notice: notice}) when is_map(notice), do: true
  defp semantic_notice_visible?(_inspection), do: false

  defp semantic_notice_kind(%{notice_kind: notice_kind}) when is_atom(notice_kind), do: notice_kind
  defp semantic_notice_kind(_inspection), do: :warning

  defp semantic_recovery_available?(%{recovery: %{available?: true}}), do: true
  defp semantic_recovery_available?(_inspection), do: false

  defp semantic_recovery_label(%{recovery: %{label: label}}) when is_binary(label), do: label
  defp semantic_recovery_label(_inspection), do: "Recover semantic graph"

  defp semantic_group_count(%{groups: groups}, group_key) when is_map(groups) do
    groups
    |> Map.get(group_key, %{})
    |> Map.get(:count, 0)
  end

  defp semantic_group_count(_summary, _group_key), do: 0

  defp semantic_result_count(%{result_group: result_group}) when is_map(result_group),
    do: Map.get(result_group, :count, 0)

  defp semantic_result_count(_projection), do: 0

  defp semantic_items(%{items: items}) when is_list(items), do: items
  defp semantic_items(_projection), do: []

  defp project_ready_for_launch?(project_detail) do
    ProjectDetail.ready_for_execution?(project_detail)
  end

  defp project_readiness(project_detail) do
    project_detail
    |> Map.get(:execution_readiness, %{})
    |> case do
      %{} = readiness -> readiness
      _other -> %{}
    end
  end

  defp workflow_dom_id(workflow_name) do
    workflow_name
    |> normalize_workflow_name()
    |> String.replace("_", "-")
  end

  defp normalize_workflow_name(workflow_name) do
    normalize_optional_string(workflow_name) || "unknown-workflow"
  end

  defp initiating_actor(socket) do
    socket.assigns
    |> Map.get(:current_user)
    |> case do
      %{} = user ->
        %{
          id:
            user
            |> Map.get(:id)
            |> normalize_optional_string() || "unknown",
          email:
            user
            |> Map.get(:email)
            |> normalize_optional_string()
        }

      _other ->
        %{id: "unknown", email: nil}
    end
  end

  defp normalize_return_to_path(return_to) do
    case normalize_optional_string(return_to) do
      nil ->
        "/workbench"

      "/" <> _path = normalized_path ->
        normalized_path

      _other ->
        "/workbench"
    end
  end

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_boolean(value), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(value) when is_float(value), do: :erlang.float_to_binary(value)
  defp normalize_optional_string(_value), do: nil
end
