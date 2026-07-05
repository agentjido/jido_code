defmodule JidoCode.ControlPlane.Codecs.Scalar do
  @moduledoc """
  Shared scalar mapping for control-plane RDF projections.
  """

  @spec normalize_id(term()) :: {:ok, String.t()} | {:error, :missing_id | :invalid_id}
  def normalize_id(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: {:error, :missing_id}, else: {:ok, value}
  end

  def normalize_id(value) when is_integer(value), do: {:ok, Integer.to_string(value)}
  def normalize_id(value) when is_atom(value) and not is_nil(value), do: {:ok, Atom.to_string(value)}
  def normalize_id(nil), do: {:error, :missing_id}
  def normalize_id(_value), do: {:error, :invalid_id}

  @spec normalize_atom(atom() | String.t()) :: {:ok, String.t()} | {:error, :invalid_atom}
  def normalize_atom(value) when is_atom(value), do: {:ok, Atom.to_string(value)}

  def normalize_atom(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: {:error, :invalid_atom}, else: {:ok, value}
  end

  def normalize_atom(_value), do: {:error, :invalid_atom}

  @spec literal(term()) :: {:ok, RDF.Literal.t()} | {:error, :nil_literal | {:unsupported_scalar, term()}}
  def literal(nil), do: {:error, :nil_literal}
  def literal(%RDF.Literal{} = literal), do: {:ok, literal}
  def literal(%DateTime{} = value), do: {:ok, RDF.XSD.dateTime(value)}
  def literal(%NaiveDateTime{} = value), do: {:ok, RDF.XSD.dateTime(value)}
  def literal(value) when is_binary(value), do: {:ok, RDF.literal(value)}
  def literal(value) when is_boolean(value), do: {:ok, RDF.literal(value)}
  def literal(value) when is_atom(value), do: {:ok, RDF.literal(Atom.to_string(value))}
  def literal(value) when is_integer(value), do: {:ok, RDF.literal(value)}
  def literal(value) when is_float(value), do: {:ok, RDF.literal(value)}
  def literal(value) when is_map(value) or is_list(value), do: {:ok, RDF.literal(Jason.encode!(canonical_json(value)))}
  def literal(value), do: {:error, {:unsupported_scalar, value}}

  @spec decode(term()) :: term()
  def decode(%RDF.Literal{} = literal), do: RDF.Literal.value(literal)
  def decode(%{type: :literal, value: value}), do: value
  def decode(%{"type" => "literal", "value" => value}), do: value
  def decode(%{value: value}), do: value
  def decode(value), do: value

  @spec canonical_json(term()) :: term()
  def canonical_json(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested_value} -> {to_string(key), canonical_json(nested_value)} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Map.new()
  end

  def canonical_json(value) when is_list(value), do: Enum.map(value, &canonical_json/1)
  def canonical_json(value), do: value
end
