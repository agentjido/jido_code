defmodule JidoCodeWeb.DashboardLive do
  # covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
  # covers: setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language
  use JidoCodeWeb, :live_view

  alias JidoCode.Orchestration.{RunPubSub, RunSummaryFeed}

  @onboarding_next_actions [
    "Run your first workflow",
    "Review the security playbook",
    "Test the RPC client"
  ]

  @run_events_for_refresh MapSet.new(["run_started", "run_completed", "run_failed"])

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:onboarding_next_actions, [])
      |> assign(:run_summary_count, 0)
      |> assign(:run_summary_warning, nil)
      |> assign(:run_summary_last_refreshed_at, nil)
      |> stream_configure(:run_summaries, dom_id: &run_summary_dom_id/1)
      |> stream(:run_summaries, [], reset: true)
      |> load_run_summaries()
      |> maybe_subscribe_run_events()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    onboarding_next_actions =
      if Map.get(params, "onboarding") == "completed" do
        @onboarding_next_actions
      else
        []
      end

    {:noreply, assign(socket, :onboarding_next_actions, onboarding_next_actions)}
  end

  @impl true
  def handle_event("refresh_run_summaries", _params, socket) do
    {:noreply, load_run_summaries(socket)}
  end

  @impl true
  def handle_info({:run_event, payload}, socket) do
    event_name =
      payload
      |> map_get(:event, "event")
      |> normalize_optional_string()

    if MapSet.member?(@run_events_for_refresh, event_name) do
      {:noreply, load_run_summaries(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <div class="max-w-4xl mx-auto py-8">
        <h1 class="text-2xl font-bold mb-4">Dashboard</h1>
        <p class="text-base-content/70">Welcome, {@current_user.email}</p>

        <section
          id="dashboard-run-summaries"
          class="mt-6 rounded-lg border border-base-300 bg-base-100 p-4 space-y-3"
        >
          <div class="flex flex-wrap items-center justify-between gap-3">
            <h2 class="text-lg font-semibold">Recent governed runs</h2>
            <p id="dashboard-run-summary-last-refreshed" class="text-xs text-base-content/70">
              Last refreshed: {summary_refreshed_label(@run_summary_last_refreshed_at)}
            </p>
          </div>

          <section
            :if={@run_summary_warning}
            id="dashboard-run-summary-warning"
            class="rounded-lg border border-warning/60 bg-warning/10 p-3 space-y-2"
          >
            <p id="dashboard-run-summary-warning-label" class="font-semibold">
              Run summary feed may be stale
            </p>
            <p id="dashboard-run-summary-warning-type" class="text-sm">
              Typed warning: {@run_summary_warning.error_type}
            </p>
            <p id="dashboard-run-summary-warning-detail" class="text-sm">{@run_summary_warning.detail}</p>
            <p id="dashboard-run-summary-warning-remediation" class="text-sm">
              {@run_summary_warning.remediation}
            </p>
            <button
              id="dashboard-run-summary-refresh"
              type="button"
              class="btn btn-sm btn-warning"
              phx-click="refresh_run_summaries"
            >
              Refresh run summaries
            </button>
          </section>

          <div class="overflow-x-auto rounded border border-base-300">
            <table id="dashboard-run-summaries-table" class="table w-full">
              <thead>
                <tr>
                  <th>Run</th>
                  <th>Status</th>
                  <th>Recency</th>
                </tr>
              </thead>
              <tbody :if={@run_summary_count == 0} id="dashboard-run-summaries-empty">
                <tr id="dashboard-run-summaries-empty-state">
                  <td colspan="3" class="py-6 text-center text-sm text-base-content/70">
                    No recent runs available.
                  </td>
                </tr>
              </tbody>
              <tbody id="dashboard-run-summaries-rows" phx-update="stream">
                <tr :for={{dom_id, run_summary} <- @streams.run_summaries} id={dom_id}>
                  <td id={"dashboard-run-id-#{run_summary_dom_token(run_summary.run_id)}"} class="font-mono text-xs">
                    <.link
                      id={"dashboard-run-link-#{run_summary_dom_token(run_summary.run_id)}"}
                      class="link link-primary"
                      navigate={run_detail_path(run_summary)}
                    >
                      {run_summary.run_id}
                    </.link>
                    <p class="text-xs text-base-content/70">{run_summary.workflow_name}</p>
                  </td>
                  <td id={"dashboard-run-status-#{run_summary_dom_token(run_summary.run_id)}"}>
                    <span class={run_status_badge_class(run_summary.status)}>
                      {run_summary.status}
                    </span>
                    <p
                      :if={run_governance_summary(run_summary)}
                      id={"dashboard-run-governance-#{run_summary_dom_token(run_summary.run_id)}"}
                      class="pt-1 text-xs text-base-content/70"
                    >
                      {run_governance_summary(run_summary)}
                    </p>
                  </td>
                  <td id={"dashboard-run-recency-#{run_summary_dom_token(run_summary.run_id)}"} class="text-xs">
                    {run_recency_label(run_summary)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section
          :if={!Enum.empty?(@onboarding_next_actions)}
          id="dashboard-onboarding-next-actions"
          class="mt-6 rounded-lg border border-base-300 bg-base-100 p-4"
        >
          <h2 class="text-lg font-semibold">Onboarding next actions</h2>
          <ul class="mt-2 space-y-1 text-sm text-base-content/80">
            <li
              :for={{next_action, index} <- Enum.with_index(@onboarding_next_actions, 1)}
              id={"dashboard-next-action-#{index}"}
            >
              {next_action}
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp load_run_summaries(socket) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case RunSummaryFeed.load() do
      {:ok, run_summaries, warning} ->
        socket
        |> assign(:run_summary_count, length(run_summaries))
        |> assign(:run_summary_warning, warning)
        |> assign(:run_summary_last_refreshed_at, now)
        |> stream(:run_summaries, run_summaries, reset: true)

      {:error, warning} ->
        socket
        |> assign(:run_summary_count, 0)
        |> assign(:run_summary_warning, warning)
        |> assign(:run_summary_last_refreshed_at, now)
        |> stream(:run_summaries, [], reset: true)
    end
  end

  defp maybe_subscribe_run_events(socket) do
    if connected?(socket) do
      :ok = RunPubSub.subscribe_runs()
      socket
    else
      socket
    end
  end

  defp summary_refreshed_label(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp summary_refreshed_label(_datetime), do: "not yet"

  defp run_summary_dom_id(run_summary) do
    "dashboard-run-summary-#{run_summary_dom_token(run_summary.id)}"
  end

  defp run_summary_dom_token(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil -> "unknown"
      token -> token
    end
    |> String.replace(~r/[^a-zA-Z0-9_-]/, "-")
  end

  defp run_status_badge_class("completed"), do: "badge badge-success"
  defp run_status_badge_class("running"), do: "badge badge-info"
  defp run_status_badge_class("failed"), do: "badge badge-error"
  defp run_status_badge_class("cancelled"), do: "badge badge-warning"
  defp run_status_badge_class("awaiting_approval"), do: "badge badge-warning"
  defp run_status_badge_class("pending"), do: "badge badge-outline"
  defp run_status_badge_class(_status), do: "badge badge-outline"

  defp run_recency_label(run_summary) do
    case Map.get(run_summary, :started_at) do
      %DateTime{} = started_at ->
        started_iso8601 = DateTime.to_iso8601(DateTime.truncate(started_at, :second))
        "Started #{relative_time_label(started_at)} (#{started_iso8601})"

      _other ->
        "Recency unavailable"
    end
  end

  defp run_governance_summary(run_summary) do
    evidence_count =
      run_summary
      |> Map.get(:evidence_count, 0)
      |> normalize_non_negative_integer()

    current_stage =
      run_summary
      |> Map.get(:current_stage)
      |> normalize_optional_string()

    change_request_status =
      run_summary
      |> Map.get(:change_request_status)
      |> normalize_optional_string()

    latest_decision =
      run_summary
      |> Map.get(:latest_decision)
      |> normalize_optional_string()

    [
      current_stage && "Stage: #{current_stage}",
      evidence_count > 0 && "Evidence: #{evidence_count}",
      change_request_status && "Review: #{change_request_status}",
      latest_decision && "Decision: #{latest_decision}"
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  defp relative_time_label(%DateTime{} = datetime) do
    seconds = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      seconds < 0 ->
        "in the future"

      seconds < 60 ->
        "just now"

      seconds < 3_600 ->
        "#{div(seconds, 60)}m ago"

      seconds < 86_400 ->
        "#{div(seconds, 3_600)}h ago"

      true ->
        "#{div(seconds, 86_400)}d ago"
    end
  end

  defp run_detail_path(run_summary) do
    project_id =
      run_summary
      |> Map.get(:project_id)
      |> normalize_optional_string()

    run_id =
      run_summary
      |> Map.get(:run_id)
      |> normalize_optional_string()

    if project_id && run_id do
      ~p"/projects/#{project_id}/runs/#{run_id}"
    else
      ~p"/dashboard"
    end
  end

  defp normalize_non_negative_integer(value) when is_integer(value) and value >= 0, do: value

  defp normalize_non_negative_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {count, ""} when count >= 0 -> count
      _other -> 0
    end
  end

  defp normalize_non_negative_integer(_value), do: 0

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
