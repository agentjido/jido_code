defmodule JidoCode.Actions.QueryControlPlaneDiagnostics do
  @moduledoc """
  Executes an explicitly bounded diagnostic SPARQL query against the control plane.
  """

  use Jido.Action,
    name: "jido_code_query_control_plane_diagnostics",
    description: "Execute a bounded diagnostic SPARQL query over allow-listed control-plane graphs.",
    schema: [
      sparql: [type: :string, required: true],
      allowed_graphs: [type: {:list, :string}, default: ["control_plane"]],
      limit: [type: :integer, default: 50],
      timeout: [type: :integer, default: 5_000]
    ]

  alias JidoCode.ControlPlane.StoreQuery

  @impl true
  def run(params, context) do
    opts = [
      server: context[:control_plane_store] || context["control_plane_store"] || JidoCode.ControlPlane.StoreServer,
      allowed_graphs: Map.get(params, :allowed_graphs, ["control_plane"]),
      limit: Map.get(params, :limit, 50),
      timeout: Map.get(params, :timeout, 5_000)
    ]

    case StoreQuery.diagnostics_query(params.sparql, opts) do
      {:ok, result} -> {:ok, result}
      {:error, reason, diagnostics} -> {:error, reason, diagnostics}
    end
  end
end
