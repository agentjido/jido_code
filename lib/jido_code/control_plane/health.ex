defmodule JidoCode.ControlPlane.Health do
  @moduledoc """
  Bounded health projection for the embedded control-plane store.
  """

  alias JidoCode.ControlPlane.{Integrity, StoreServer, Telemetry}

  @type state :: :ready | :degraded | :recovery_required | :unavailable

  @type projection :: %{
          state: state(),
          label: String.t(),
          detail: String.t(),
          remediation: String.t() | nil,
          graph_count: non_neg_integer(),
          total_quad_count: non_neg_integer(),
          issue_count: non_neg_integer(),
          kind: :info | :warning | :error,
          notice: map()
        }

  @spec status(GenServer.server()) :: projection()
  def status(server \\ StoreServer) do
    Telemetry.span(:health, %{server: inspect(server)}, fn ->
      server
      |> load_status()
      |> tap(&emit_graph_size/1)
    end)
  end

  defp load_status(server) do
    health = safe_health(server)
    integrity = safe_integrity(server)
    project_health(health, integrity)
  end

  defp safe_health(server) do
    try do
      {:ok, StoreServer.health(server)}
    rescue
      exception -> {:error, {exception.__struct__, Exception.message(exception)}}
    catch
      :exit, reason -> {:error, reason}
    end
  end

  defp safe_integrity(server) do
    try do
      Integrity.check(server)
    rescue
      exception -> {:error, {exception.__struct__, Exception.message(exception)}}
    catch
      :exit, reason -> {:error, reason}
    end
  end

  defp project_health({:error, reason}, _integrity) do
    projection(:unavailable, "Unavailable", "Embedded control-plane store is not reachable.", inspect(reason), %{})
  end

  defp project_health({:ok, %{ready?: false} = health}, _integrity) do
    projection(
      :recovery_required,
      "Recovery required",
      "Embedded control-plane store is open but not ready.",
      "Run `mix control_plane.integrity --json` and restore or reset the store before continuing.",
      health
    )
  end

  defp project_health({:ok, health}, {:ok, %{status: :ok}}) do
    projection(
      :ready,
      "Ready",
      "Embedded control-plane store is ready.",
      nil,
      health
    )
  end

  defp project_health({:ok, health}, {:ok, %{status: status, issues: issues}}) do
    state = if recovery_issue?(issues), do: :recovery_required, else: :degraded

    projection(
      state,
      label_for_state(state),
      "Embedded control-plane integrity is #{status}.",
      remediation_for_state(state),
      health,
      issues
    )
  end

  defp project_health({:ok, health}, {:error, reason}) do
    projection(
      :degraded,
      "Degraded",
      "Embedded control-plane health is available, but integrity checks could not complete.",
      inspect(reason),
      health
    )
  end

  defp projection(state, label, detail, remediation, health, issues \\ []) do
    graph_counts = Map.get(health, :graph_counts, %{})
    total_quad_count = graph_counts |> Map.values() |> Enum.sum()
    graph_count = map_size(graph_counts)
    issue_count = length(issues)
    kind = kind_for_state(state)

    %{
      state: state,
      label: label,
      detail: detail,
      remediation: remediation,
      graph_count: graph_count,
      total_quad_count: total_quad_count,
      issue_count: issue_count,
      kind: kind,
      notice: %{
        error_type: "control_plane_store_#{state}",
        detail: bounded_detail(detail, graph_count, total_quad_count, issue_count),
        remediation: remediation
      }
    }
  end

  defp bounded_detail(detail, graph_count, total_quad_count, 0) do
    "#{detail} #{graph_count} graph(s), #{total_quad_count} quad(s)."
  end

  defp bounded_detail(detail, graph_count, total_quad_count, issue_count) do
    "#{detail} #{graph_count} graph(s), #{total_quad_count} quad(s), #{issue_count} issue(s)."
  end

  defp recovery_issue?(issues) do
    Enum.any?(issues, fn issue ->
      issue.code in [
        :missing_control_plane_graph,
        :missing_control_plane_ontology_version,
        :stale_control_plane_ontology_version,
        :duplicate_record_identity,
        :dangling_control_plane_link
      ]
    end)
  end

  defp emit_graph_size(projection) do
    Telemetry.execute(
      :graph_size,
      %{graph_count: projection.graph_count, total_quad_count: projection.total_quad_count},
      %{
        state: projection.state,
        issue_count: projection.issue_count
      }
    )
  end

  defp label_for_state(:recovery_required), do: "Recovery required"
  defp label_for_state(:degraded), do: "Degraded"

  defp remediation_for_state(:recovery_required),
    do: "Run `mix control_plane.integrity --json`, then restore from a known-good export or reset the dev/test store."

  defp remediation_for_state(:degraded),
    do: "Review `mix control_plane.integrity --json` before relying on diagnostics."

  defp kind_for_state(:ready), do: :info
  defp kind_for_state(:degraded), do: :warning
  defp kind_for_state(_state), do: :error
end
