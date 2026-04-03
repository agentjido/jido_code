defmodule Mix.Tasks.Frontend.Start do
  # covers: developer.workflow.host_postgres_defaults
  # covers: package.jido_code.package_quality_mix_surface_aligned
  @shortdoc "Prepares the Jido.Code frontend start path"
  @moduledoc false

  use Mix.Task

  @impl true
  def run(_args) do
    JidoCode.Mix.FrontendStart.prepare!("mix server")
  end
end
