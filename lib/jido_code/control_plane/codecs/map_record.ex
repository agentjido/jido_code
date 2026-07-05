defmodule JidoCode.ControlPlane.Codecs.MapRecord do
  @moduledoc """
  Shared implementation for map-backed product record codecs.
  """

  alias JidoCode.ControlPlane.{GraphTopology, SemanticIdentity}
  alias JidoCode.ControlPlane.Codecs.Scalar

  @control_plane_ns SemanticIdentity.ontology_namespace()

  @spec encode(atom(), map(), String.t(), %{atom() => String.t()}, [map()]) ::
          {:ok, map()} | {:error, term()}
  def encode(record_type, record, subject_iri, field_mappings, identity_queries) do
    with {:ok, graph_name} <- GraphTopology.graph_for_record(record_type),
         {:ok, graph_iri} <- GraphTopology.graph_iri(graph_name),
         {:ok, class_iri} <- SemanticIdentity.class_iri(record_type),
         {:ok, triples} <- triples(subject_iri, class_iri, record, field_mappings) do
      {:ok,
       %{
         record_type: record_type,
         graph_name: graph_name,
         graph_iri: graph_iri,
         class_iri: to_string(class_iri),
         subject_iri: subject_iri,
         triples: triples,
         identity_queries: identity_queries
       }}
    end
  end

  @spec decode(atom(), map(), %{atom() => String.t()}) :: {:ok, map()} | {:error, term()}
  def decode(record_type, projection, field_mappings) do
    attributes = Map.get(projection, :attributes) || Map.get(projection, "attributes") || %{}

    decoded =
      field_mappings
      |> Map.new(fn {field, predicate_local} ->
        {field, decode_attribute(attributes, predicate_local)}
      end)
      |> Enum.reject(fn {_field, value} -> is_nil(value) end)
      |> Map.new()
      |> Map.put(:record_type, record_type)
      |> Map.put(:subject_iri, Map.get(projection, :subject_iri) || Map.get(projection, "subject_iri"))

    {:ok, decoded}
  end

  @spec subject_iri(atom(), map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def subject_iri(record_type, record, opts \\ []) do
    attrs =
      record
      |> canonical_attrs(record_type, opts)
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    SemanticIdentity.canonical_iri(record_type, attrs)
  end

  @spec graph_iri(atom()) :: {:ok, String.t()} | {:error, term()}
  def graph_iri(record_type) do
    with {:ok, graph_name} <- GraphTopology.graph_for_record(record_type) do
      GraphTopology.graph_iri(graph_name)
    end
  end

  @spec field_triples(String.t(), map(), %{atom() => String.t()}) ::
          {:ok, [{RDF.IRI.t(), RDF.IRI.t(), RDF.Term.t()}]} | {:error, term()}
  def field_triples(subject_iri, record, field_mappings) do
    field_mappings
    |> Enum.reduce_while({:ok, []}, fn {field, predicate_local}, {:ok, acc} ->
      case value_for(record, field) do
        nil ->
          {:cont, {:ok, acc}}

        value ->
          case Scalar.literal(value) do
            {:ok, literal} -> {:cont, {:ok, [{RDF.iri(subject_iri), predicate(predicate_local), literal} | acc]}}
            {:error, reason} -> {:halt, {:error, {:invalid_field_scalar, field, reason}}}
          end
      end
    end)
    |> case do
      {:ok, triples} -> {:ok, Enum.reverse(triples)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp triples(subject_iri, class_iri, record, field_mappings) do
    with {:ok, field_triples} <- field_triples(subject_iri, record, field_mappings) do
      {:ok, [{RDF.iri(subject_iri), RDF.type(), class_iri} | field_triples]}
    end
  end

  defp canonical_attrs(record, record_type, opts) do
    id_field = Keyword.get(opts, :id_field)
    id = value_for(record, id_field) || value_for(record, :id) || Map.get(record, "#{record_type}_id")

    %{
      id: id,
      key: value_for(record, :key) || id,
      managed_repo_id: value_for(record, :managed_repo_id),
      provider: value_for(record, :provider),
      provider_host: value_for(record, :provider_host),
      object_type: value_for(record, :object_type),
      external_id: value_for(record, :external_id)
    }
  end

  defp decode_attribute(attributes, predicate_local) do
    case Map.get(attributes, predicate_local) || Map.get(attributes, to_string(predicate_local)) do
      [value | _rest] -> Scalar.decode(value)
      value -> Scalar.decode(value)
    end
  end

  defp value_for(_record, nil), do: nil
  defp value_for(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))
  defp predicate(local), do: RDF.iri(@control_plane_ns <> local)
end
