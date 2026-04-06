defmodule JidoCode.KG.Adapter do
  @moduledoc """
  Behaviour for Knowledge Graph backend adapters.

  The KG adapter provides a pluggable interface for different KG backends:
  - In-memory store for development/testing
  - Persistent store for production
  - External services (future)
  """

  @doc """
  Query the knowledge graph using SPARQL.

  Returns structured results matching the query.
  """
  @callback query(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}

  @doc """
  Update the knowledge graph with new code information.

  Supported operations:
  - `:index` - Index files and build/update the KG
  - `:add_facts` - Add facts to the KG
  - `:remove_facts` - Remove facts from the KG
  """
  @callback update(keyword(), [String.t()] | :index, keyword()) :: :ok | {:error, term()}

  @doc """
  Explore relationships from a starting node.

  Returns a list of connected nodes and relationships.
  """
  @callback explore(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
end
