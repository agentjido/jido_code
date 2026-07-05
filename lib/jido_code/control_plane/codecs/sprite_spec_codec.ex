defmodule JidoCode.ControlPlane.Codecs.SpriteSpecCodec do
  @moduledoc """
  RDF projection codec for sprite specification records.
  """

  @behaviour JidoCode.ControlPlane.Codecs.Codec

  alias JidoCode.ControlPlane.Codecs.MapRecord
  alias JidoCode.ControlPlane.SemanticIdentity

  @record_type :sprite_spec
  @field_mappings %{
    sprite_spec_id: "spriteSpecId",
    name: "name",
    description: "description",
    runner: "runnerType",
    runner_config: "runnerConfigJson",
    base_image: "baseImage",
    env: "envJson",
    bootstrap_steps: "bootstrapStepsJson",
    file_injection: "fileInjectionJson",
    timeouts: "timeoutsJson",
    resource_limits: "resourceLimitsJson",
    inserted_at: "insertedAt",
    updated_at: "updatedAt",
    metadata: "metadataJson"
  }

  @impl true
  def record_type, do: @record_type
  @impl true
  def graph_name, do: :execution_runtime
  @impl true
  def graph_iri, do: MapRecord.graph_iri(@record_type)
  @impl true
  def class_iri, do: SemanticIdentity.class_iri(@record_type)
  @impl true
  def subject_iri(record), do: MapRecord.subject_iri(@record_type, normalized_record(record), id_field: :sprite_spec_id)

  @impl true
  def identity_queries(record) do
    record = normalized_record(record)

    [
      %{
        identity: :unique_name,
        predicate: "name",
        value: value_for(record, :name)
      }
    ]
  end

  @impl true
  def encode(record) do
    record = normalized_record(record)

    with {:ok, subject_iri} <- subject_iri(record) do
      MapRecord.encode(@record_type, record, subject_iri, @field_mappings, identity_queries(record))
    end
  end

  @impl true
  def decode(projection), do: MapRecord.decode(@record_type, projection, @field_mappings)

  defp normalized_record(record) do
    Map.put_new(record, :sprite_spec_id, value_for(record, :sprite_spec_id) || value_for(record, :id))
  end

  defp value_for(record, key), do: Map.get(record, key) || Map.get(record, to_string(key))
end
