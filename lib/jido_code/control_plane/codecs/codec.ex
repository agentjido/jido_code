defmodule JidoCode.ControlPlane.Codecs.Codec do
  @moduledoc """
  Behaviour for product record RDF projection codecs.
  """

  @type encoded :: %{
          record_type: atom(),
          graph_name: atom(),
          graph_iri: String.t(),
          class_iri: String.t(),
          subject_iri: String.t(),
          triples: [{RDF.IRI.t(), RDF.IRI.t(), RDF.Term.t()}],
          identity_queries: [map()]
        }

  @callback record_type() :: atom()
  @callback graph_name() :: atom()
  @callback graph_iri() :: {:ok, String.t()} | {:error, term()}
  @callback class_iri() :: {:ok, RDF.IRI.t()} | {:error, term()}
  @callback subject_iri(map()) :: {:ok, String.t()} | {:error, term()}
  @callback identity_queries(map()) :: [map()]
  @callback encode(map()) :: {:ok, encoded()} | {:error, term()}
  @callback decode(map()) :: {:ok, map()} | {:error, term()}
end
