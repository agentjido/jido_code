defmodule JidoWorkflow.Workflow.Loader do
  # covers: workflow.runtime.compatibility.legacy_loader_and_engine_surface
  @moduledoc """
  Loads markdown workflow definitions into compatibility structs.
  """

  alias JidoWorkflow.Workflow.MarkdownParser
  alias JidoWorkflow.Workflow.ValidationError

  @spec load_markdown(binary()) :: {:ok, term()} | {:error, [ValidationError.t()]}
  def load_markdown(markdown) when is_binary(markdown) do
    MarkdownParser.parse(markdown)
  end
end
