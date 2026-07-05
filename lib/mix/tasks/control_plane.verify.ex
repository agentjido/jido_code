defmodule Mix.Tasks.ControlPlane.Verify do
  @shortdoc "Runs focused embedded control-plane verification"
  @moduledoc false

  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("test", test_args(args))
  end

  defp test_args(args) do
    [
      "test/jido_code/control_plane/ontology_topology_integration_test.exs",
      "test/jido_code/control_plane/codecs_test.exs",
      "test/jido_code/control_plane/store_contract_integration_test.exs",
      "test/jido_code/control_plane/integrity_recovery_test.exs",
      "test/jido_code/control_plane/observability_diagnostics_test.exs",
      "test/jido_code/control_plane/backup_recovery_integration_test.exs",
      "test/jido_code/embedded_store_removal_gate_test.exs",
      "test/jido_code_web/integration/embedded_store_cutover_smoke_test.exs"
    ] ++ args
  end
end
