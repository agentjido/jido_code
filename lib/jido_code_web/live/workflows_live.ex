defmodule JidoCodeWeb.WorkflowsLive do
  use JidoCodeWeb, :live_view

  alias JidoCode.WorkflowRuntime.ManualRunKickoff

  @impl true
  def mount(_params, _session, socket) do
    workflows = ManualRunKickoff.supported_workflows()
    repositories = ManualRunKickoff.repository_options()
    run_form_values = default_run_form_values(workflows, repositories)

    {:ok,
     socket
     |> assign(:workflows, workflows)
     |> assign(:repository_count, length(repositories))
     |> assign(:repository_options, repository_select_options(repositories))
     |> assign(:run_feedback, nil)
     |> assign(:run_count, 0)
     |> assign(:run_form_values, run_form_values)
     |> assign(:run_form, to_form(run_form_values, as: :run))
     |> stream_configure(:runs, dom_id: &run_dom_id/1)
     |> stream(:runs, [], reset: true)}
  end

  @impl true
  def handle_event("change_run_form", %{"run" => run_params}, socket) do
    run_form_values = normalize_run_form_values(run_params, socket.assigns.run_form_values)

    {:noreply,
     socket
     |> assign(:run_feedback, nil)
     |> assign(:run_form_values, run_form_values)
     |> assign(:run_form, to_form(run_form_values, as: :run))}
  end

  @impl true
  def handle_event("change_run_form", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("start_workflow", %{"run" => run_params}, socket) do
    run_form_values = normalize_run_form_values(run_params, socket.assigns.run_form_values)

    case ManualRunKickoff.kickoff(run_form_values, initiating_actor(socket)) do
      {:ok, kickoff_run} ->
        refreshed_form_values =
          clear_required_inputs(
            run_form_values,
            kickoff_run.workflow_name,
            socket.assigns.workflows
          )

        {:noreply,
         socket
         |> assign(:run_feedback, %{status: :ok, run: kickoff_run})
         |> assign(:run_form_values, refreshed_form_values)
         |> assign(:run_form, to_form(refreshed_form_values, as: :run))
         |> stream_insert(:runs, kickoff_run, at: 0)
         |> update(:run_count, &(&1 + 1))}

      {:error, kickoff_error} ->
        {:noreply,
         socket
         |> assign(:run_feedback, %{status: :error, error: kickoff_error})
         |> assign(:run_form_values, run_form_values)
         |> assign(:run_form, to_form(run_form_values, as: :run))}
    end
  end

  @impl true
  def handle_event("start_workflow", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={%{}}
      operator_navigation={JidoCodeWeb.OperatorNavigation.from_view(__MODULE__, assigns)}
    >
      <section class="space-y-2">
        <h1 class="text-2xl font-bold">Workflows</h1>
        <p class="text-base-content/70">
          Start manual workflow runs with explicit repo scope and required input metadata.
        </p>
      </section>

      <section
        id="workflows-manual-run-form-panel"
        class="rounded-lg border border-base-300 bg-base-100 p-4 space-y-3"
      >
        <.form
          for={@run_form}
          id="workflows-manual-run-form"
          phx-change="change_run_form"
          phx-submit="start_workflow"
          class="space-y-3"
        >
          <div class="grid gap-3 md:grid-cols-2">
            <.input
              id="workflows-project-id"
              field={@run_form[:repo_id]}
              type="select"
              label="Repo scope"
              options={@repository_options}
            />
            <.input
              id="workflows-workflow-name"
              field={@run_form[:workflow_name]}
              type="select"
              label="Workflow template"
              options={workflow_select_options(@workflows)}
            />
          </div>

          <% selected_workflow = selected_workflow(@workflows, @run_form_values) %>
          <%= if selected_workflow do %>
            <section
              id="workflows-selected-template"
              class="rounded-lg border border-base-300 bg-base-200/40 p-3 space-y-2"
            >
              <p id="workflows-selected-template-label" class="text-sm font-semibold">
                Required inputs for {selected_workflow.label}
              </p>
              <p id="workflows-selected-template-description" class="text-sm text-base-content/70">
                {selected_workflow.description}
              </p>

              <.input
                :for={input <- selected_workflow.required_inputs}
                id={"workflows-input-#{workflow_input_dom_id(input.name)}"}
                field={workflow_input_form_field(@run_form, input.name)}
                type="textarea"
                label={input.label}
                placeholder={input.placeholder}
              />
            </section>
          <% end %>

          <div class="flex flex-wrap items-center gap-3">
            <%= if @repository_count > 0 do %>
              <button id="workflows-start-run" type="submit" class="btn btn-primary">
                Start workflow run
              </button>
            <% else %>
              <span
                id="workflows-start-run-disabled"
                class="btn btn-disabled cursor-not-allowed"
                aria-disabled="true"
              >
                Start workflow run
              </span>
              <p id="workflows-start-run-disabled-reason" class="text-sm text-warning">
                Import at least one repository before starting manual workflow runs.
              </p>
            <% end %>
          </div>
        </.form>

        <section :if={@run_feedback} id="workflows-run-feedback" class="space-y-1">
          <%= case @run_feedback.status do %>
            <% :ok -> %>
              <p id="workflows-run-feedback-status" class="text-sm text-success">
                Run creation succeeded.
              </p>
              <p id="workflows-run-feedback-run-id" class="text-sm text-success">
                Run: <span class="font-mono">{@run_feedback.run.run_id}</span>
              </p>
              <p id="workflows-run-feedback-workflow-version" class="text-sm text-success">
                Workflow version: {run_workflow_version_summary(@run_feedback.run.workflow_version)}
              </p>
              <.link
                id="workflows-run-feedback-run-link"
                class="link link-primary text-sm"
                href={@run_feedback.run.detail_path}
              >
                Open run detail
              </.link>
            <% :error -> %>
              <p id="workflows-run-feedback-status" class="text-sm text-error">
                Run creation failed.
              </p>
              <p id="workflows-run-feedback-error-type" class="text-sm text-error">
                Typed validation error: {@run_feedback.error.error_type}
              </p>
              <p id="workflows-run-feedback-error-detail" class="text-sm text-error">
                {@run_feedback.error.detail}
              </p>
              <p id="workflows-run-feedback-error-remediation" class="text-sm text-base-content/70">
                {@run_feedback.error.remediation}
              </p>
              <ul
                :if={@run_feedback.error.field_errors != []}
                id="workflows-run-feedback-field-errors"
                class="list-disc pl-5 text-xs text-error space-y-1"
              >
                <li
                  :for={{field_error, index} <- Enum.with_index(@run_feedback.error.field_errors, 1)}
                  id={"workflows-run-feedback-field-error-#{index}"}
                >
                  <span class="font-medium">{field_error.field}</span>: {field_error.detail}
                </li>
              </ul>
          <% end %>
        </section>
      </section>

      <section id="workflows-runs-panel" class="rounded-lg border border-base-300 bg-base-100 overflow-x-auto">
        <table id="workflows-runs-table" class="table table-zebra w-full">
          <thead>
            <tr>
              <th>Run ID</th>
              <th>Workflow</th>
              <th>Version</th>
              <th>Repository</th>
              <th>Trigger</th>
              <th>Inputs</th>
              <th>Route</th>
            </tr>
          </thead>
          <tbody :if={@run_count == 0} id="workflows-runs-empty-body">
            <tr id="workflows-runs-empty-state">
              <td colspan="7" class="py-8 text-center text-sm text-base-content/70">
                No workflow runs started from this page yet.
              </td>
            </tr>
          </tbody>
          <tbody id="workflows-runs-rows" phx-update="stream">
            <tr :for={{dom_id, run} <- @streams.runs} id={dom_id}>
              <td id={"workflows-run-id-#{run_dom_token(run.run_id)}"} class="font-mono text-xs">
                {run.run_id}
              </td>
              <td id={"workflows-run-workflow-#{run_dom_token(run.run_id)}"}>{run.workflow_name}</td>
              <td id={"workflows-run-workflow-version-#{run_dom_token(run.run_id)}"} class="text-xs">
                {run_workflow_version_summary(run.workflow_version)}
              </td>
              <td id={"workflows-run-project-#{run_dom_token(run.run_id)}"}>{run.repository_name}</td>
              <td id={"workflows-run-trigger-#{run_dom_token(run.run_id)}"} class="text-xs">
                {run_trigger_summary(run.trigger)}
              </td>
              <td id={"workflows-run-inputs-#{run_dom_token(run.run_id)}"} class="text-xs">
                {run_input_summary(run.inputs)}
              </td>
              <td id={"workflows-run-route-#{run_dom_token(run.run_id)}"}>
                <.link
                  id={"workflows-run-detail-link-#{run_dom_token(run.run_id)}"}
                  class="link link-primary"
                  href={run.detail_path}
                >
                  Open run detail
                </.link>
              </td>
            </tr>
          </tbody>
        </table>
      </section>
    </Layouts.app>
    """
  end

  defp default_run_form_values(workflows, repositories) do
    %{
      "repo_id" =>
        repositories
        |> List.first()
        |> map_get(:id, "id", ""),
      "workflow_name" =>
        workflows
        |> List.first()
        |> map_get(:name, "name", ""),
      "task_summary" => "",
      "failure_signal" => "",
      "issue_reference" => ""
    }
  end

  defp normalize_run_form_values(run_params, current_values) when is_map(run_params) do
    %{
      "repo_id" => form_value(run_params, current_values, :repo_id, "repo_id"),
      "workflow_name" => form_value(run_params, current_values, :workflow_name, "workflow_name"),
      "task_summary" => form_value(run_params, current_values, :task_summary, "task_summary"),
      "failure_signal" => form_value(run_params, current_values, :failure_signal, "failure_signal"),
      "issue_reference" => form_value(run_params, current_values, :issue_reference, "issue_reference")
    }
  end

  defp normalize_run_form_values(_run_params, current_values), do: current_values

  defp form_value(run_params, current_values, atom_key, string_key) do
    if Map.has_key?(run_params, atom_key) or Map.has_key?(run_params, string_key) do
      run_params
      |> map_get(atom_key, string_key, "")
      |> normalize_form_value()
    else
      Map.get(current_values, string_key, "")
    end
  end

  defp clear_required_inputs(run_form_values, workflow_name, workflows) do
    required_input_keys =
      workflows
      |> Enum.find(fn workflow ->
        Map.get(workflow, :name) == workflow_name
      end)
      |> case do
        nil ->
          []

        workflow ->
          workflow
          |> Map.get(:required_inputs, [])
          |> Enum.map(fn input -> Atom.to_string(Map.fetch!(input, :name)) end)
      end

    Enum.reduce(required_input_keys, run_form_values, fn key, acc ->
      Map.put(acc, key, "")
    end)
  end

  defp repository_select_options([]), do: [{"Select a repository", ""}]

  defp repository_select_options(repositories) do
    Enum.map(repositories, fn repository ->
      label = Map.get(repository, :github_full_name) || Map.get(repository, :name) || Map.get(repository, :id)
      {label, Map.get(repository, :id)}
    end)
  end

  defp workflow_select_options(workflows) do
    Enum.map(workflows, fn workflow ->
      {workflow.label, workflow.name}
    end)
  end

  defp selected_workflow(workflows, run_form_values) when is_list(workflows) and is_map(run_form_values) do
    selected_workflow_name =
      run_form_values
      |> map_get(:workflow_name, "workflow_name")
      |> normalize_optional_string()

    Enum.find(workflows, fn workflow ->
      workflow.name == selected_workflow_name
    end) || List.first(workflows)
  end

  defp selected_workflow(_workflows, _run_form_values), do: nil

  defp workflow_input_form_field(run_form, :task_summary), do: run_form[:task_summary]
  defp workflow_input_form_field(run_form, :failure_signal), do: run_form[:failure_signal]
  defp workflow_input_form_field(run_form, :issue_reference), do: run_form[:issue_reference]

  defp workflow_input_form_field(run_form, input_name) do
    run_form[normalize_input_key(input_name)]
  end

  defp normalize_input_key(:task_summary), do: :task_summary
  defp normalize_input_key(:failure_signal), do: :failure_signal
  defp normalize_input_key(:issue_reference), do: :issue_reference
  defp normalize_input_key(_input_name), do: :task_summary

  defp workflow_input_dom_id(input_name) do
    input_name
    |> normalize_input_key()
    |> Atom.to_string()
    |> String.replace("_", "-")
  end

  defp run_dom_id(run) do
    "workflow-run-#{run |> Map.get(:run_id) |> run_dom_token()}"
  end

  defp run_dom_token(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil -> "unknown"
      token -> token
    end
    |> String.replace(~r/[^a-zA-Z0-9_-]/, "-")
  end

  defp run_trigger_summary(trigger) when is_map(trigger) do
    source = trigger |> map_get(:source, "source") |> normalize_optional_string() || "unknown"
    mode = trigger |> map_get(:mode, "mode") |> normalize_optional_string() || "unknown"

    source_row =
      trigger
      |> map_get(:source_row, "source_row", %{})
      |> map_get(:route, "route")
      |> normalize_optional_string() || "/workflows"

    "#{mode} via #{source} (#{source_row})"
  end

  defp run_trigger_summary(_trigger), do: "manual via workflows (/workflows)"

  defp run_input_summary(inputs) when is_map(inputs) do
    inputs
    |> Enum.sort_by(fn {name, _value} -> name end)
    |> Enum.map(fn {name, value} ->
      "#{name}=#{summary_value(value)}"
    end)
    |> Enum.join("; ")
  end

  defp run_input_summary(_inputs), do: "no inputs"

  defp run_workflow_version_summary(version) when is_integer(version) and version > 0,
    do: "v#{version}"

  defp run_workflow_version_summary(_version), do: "unknown"

  defp summary_value(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil ->
        "n/a"

      normalized_value when byte_size(normalized_value) > 72 ->
        normalized_value
        |> binary_part(0, 72)
        |> Kernel.<>("...")

      normalized_value ->
        normalized_value
    end
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

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp normalize_form_value(value) when is_binary(value), do: String.trim(value)

  defp normalize_form_value(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_form_value()

  defp normalize_form_value(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_form_value(value) when is_float(value), do: :erlang.float_to_binary(value)
  defp normalize_form_value(_value), do: ""

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
