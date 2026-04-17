defmodule JidoWorkflow.Workflow.Loader do
  # covers: workflow.runtime.compatibility.legacy_loader_and_engine_surface
  @moduledoc """
  Loads markdown workflow definitions into compatibility structs.
  """

  alias JidoWorkflow.Workflow.MarkdownParser
  alias JidoWorkflow.Workflow.ValidationError

  @spec load_markdown(binary()) :: {:ok, term()} | {:error, [ValidationError.t()]}
  def load_markdown(path_or_markdown) when is_binary(path_or_markdown) do
    if File.regular?(path_or_markdown) do
      case File.read(path_or_markdown) do
        {:ok, markdown} ->
          MarkdownParser.parse(markdown)

        {:error, reason} ->
          {:error,
           [
             %ValidationError{
               path: [path_or_markdown],
               code: :file_read_error,
               message: "failed to read workflow markdown: #{inspect(reason)}"
             }
           ]}
      end
    else
      MarkdownParser.parse(path_or_markdown)
    end
  end
end
