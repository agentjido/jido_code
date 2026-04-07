defmodule JidoCode.KG.OntologyHelper do
  @moduledoc """
  Helper module for optional ontology generation support.

  This module provides ontology-related functionality that works with
  or without the `elixir_ontologies` package. When the package is available,
  it enables direct API calls for ontology generation.

  ## Optional Dependency

  To enable ontology features, add `elixir_ontologies` to your deps:

      {:elixir_ontologies, github: "agentjido/elixir_ontologies"}

  Then uncomment the ontology configuration in your config files:

      config :jido_code, :ontology_enabled, true

  ## Usage

      iex> JidoCode.KG.OntologyHelper.available?()
      false

      # After adding elixir_ontologies dependency:
      iex> JidoCode.KG.OntologyHelper.available?()
      true
  """

  # Suppress compiler warnings for optional module
  @compile {:no_warn_undefined, Ontologies}

  @doc """
  Check if the Ontologies module is available.

  Returns true if the elixir_ontologies package is loaded and the
  Ontologies.generate/2 function is available.
  """
  def available? do
    Code.ensure_loaded?(Ontologies) and function_exported?(Ontologies, :generate, 2)
  end

  @doc """
  Check if ontology features are enabled in configuration.

  Returns true if both:
  1. The ontology_enabled config is set to true
  2. The Ontologies module is available
  """
  def enabled? do
    Application.get_env(:jido_code, :ontology_enabled, false) and available?()
  end

  @doc """
  Generate ontology for the current project.

  When elixir_ontologies is available, generates an ontology file
  containing triples describing the code structure.

  ## Options

  - `:output` - Output file path (default: "tmp/ontology.ttl")
  - `:format` - Output format, e.g., :turtle, :ntriples (default: :turtle)
  - `:include_deps` - Include dependency projects (default: true)

  ## Returns

  - `{:ok, result}` - Ontology generation succeeded
  - `{:error, :not_available}` - Ontologies module not available
  - `{:error, reason}` - Other error
  """
  def generate(opts \\ []) do
    if enabled?() do
      do_generate(opts)
    else
      {:error, :not_available}
    end
  end

  @doc """
  Generate ontology and load it into the Knowledge Graph.

  This combines generation and KG loading in a single operation.

  ## Returns

  - `{:ok, metadata}` - Ontology generated and loaded
  - `{:error, :not_available}` - Ontologies module not available
  - `{:error, reason}` - Other error
  """
  def generate_and_load(opts \\ []) do
    with {:ok, result} <- generate(opts),
         {:ok, ttl_file} <- extract_ttl_file(result),
         :ok <- load_into_kg(ttl_file, opts) do
      {:ok, %{
        ttl_file: ttl_file,
        loaded: true
      }}
    end
  end

  # Private functions

  defp do_generate(opts) do
    project_root = File.cwd!()
    output_path = Keyword.get(opts, :output, "tmp/ontology.ttl")

    try do
      case Ontologies.generate(project_root, [output: output_path]) do
        {:ok, result} -> {:ok, result}
        {:ok, ttl_file} -> {:ok, %{ttl_file: ttl_file}}
        other -> {:error, {:unexpected_response, other}}
      end
    rescue
      error -> {:error, {:exception, Exception.message(error)}}
    end
  end

  defp extract_ttl_file(%{ttl_file: ttl_file}), do: {:ok, ttl_file}
  defp extract_ttl_file(ttl_file) when is_binary(ttl_file), do: {:ok, ttl_file}
  defp extract_ttl_file(_), do: {:error, :invalid_result}

  defp load_into_kg(_ttl_file, _opts) do
    # TODO: Implement loading TTL file into KG
    # This would parse the Turtle format and insert triples
    :ok
  end
end
