defmodule JidoCode.ControlPlane.Codecs.UserCodec do
  @moduledoc """
  RDF projection codec for auth user records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :user
  @field_mappings %{
    user_id: "userId",
    email: "sourceKey",
    is_admin: "isAdmin",
    confirmed_at: "confirmedAt",
    display_name: "displayName",
    updated_at: "updatedAt",
    metadata: "metadataJson"
  }

  @impl true
  def record_type, do: @record_type
  @impl true
  def graph_name, do: :auth
  @impl true
  def graph_iri, do: MapRecord.graph_iri(@record_type)
  @impl true
  def class_iri, do: SemanticIdentity.class_iri(@record_type)
  @impl true
  def subject_iri(record), do: MapRecord.subject_iri(@record_type, record, id_field: :user_id)
  @impl true
  def identity_queries(record),
    do: [%{identity: :unique_email, predicate: "sourceKey", value: record[:email] || record["email"]}]

  @impl true
  def encode(record),
    do:
      with(
        {:ok, subject_iri} <- subject_iri(record),
        do: MapRecord.encode(@record_type, record, subject_iri, @field_mappings, identity_queries(record))
      )

  @impl true
  def decode(projection), do: MapRecord.decode(@record_type, projection, @field_mappings)
end
