defmodule JidoCode.ControlPlane.Validation.Validator do
  @moduledoc """
  Reusable validators for product-owned control-plane commands.
  """

  @type field_error :: %{field: atom() | String.t(), reason: atom(), detail: term()}

  @spec required_string(map(), atom() | String.t() | [atom() | String.t()]) :: [field_error()]
  def required_string(record, fields) do
    fields
    |> List.wrap()
    |> Enum.find_value(&field_value(record, &1))
    |> case do
      value when is_binary(value) ->
        if String.trim(value) == "", do: [error(List.first(List.wrap(fields)), :required)], else: []

      value when is_integer(value) ->
        []

      _other ->
        [error(List.first(List.wrap(fields)), :required)]
    end
  end

  @spec atom_enum(map(), atom() | String.t(), [atom() | String.t()]) :: [field_error()]
  def atom_enum(record, field, allowed_values) do
    case field_value(record, field) do
      nil ->
        []

      value when is_atom(value) ->
        allowed_strings = Enum.map(allowed_values, &to_string/1)
        if Atom.to_string(value) in allowed_strings, do: [], else: [error(field, :invalid_enum, allowed_values)]

      value when is_binary(value) ->
        allowed_strings = Enum.map(allowed_values, &to_string/1)
        if value in allowed_strings, do: [], else: [error(field, :invalid_enum, allowed_values)]

      value ->
        if value in allowed_values do
          []
        else
          [error(field, :invalid_enum, allowed_values)]
        end
    end
  end

  @spec map_field(map(), atom() | String.t()) :: [field_error()]
  def map_field(record, field) do
    case field_value(record, field) do
      nil -> []
      value when is_map(value) -> []
      _other -> [error(field, :invalid_map)]
    end
  end

  @spec datetime_field(map(), atom() | String.t()) :: [field_error()]
  def datetime_field(record, field) do
    case field_value(record, field) do
      nil -> []
      %DateTime{} -> []
      %NaiveDateTime{} -> []
      value when is_binary(value) -> validate_datetime_string(field, value)
      _other -> [error(field, :invalid_datetime)]
    end
  end

  @spec relationship_field(map(), atom() | String.t() | [atom() | String.t()]) :: [field_error()]
  def relationship_field(record, fields), do: required_string(record, fields)

  @spec field_value(map(), atom() | String.t()) :: term()
  def field_value(record, field) when is_atom(field),
    do: Map.get(record, field) || Map.get(record, Atom.to_string(field))

  def field_value(record, field) when is_binary(field) do
    Map.get(record, field) || existing_atom_value(record, Macro.underscore(field))
  end

  @spec error(atom() | String.t(), atom(), term()) :: field_error()
  def error(field, reason, detail \\ nil), do: %{field: field, reason: reason, detail: detail}

  defp validate_datetime_string(field, value) do
    case DateTime.from_iso8601(value) do
      {:ok, _datetime, _offset} -> []
      {:error, _reason} -> [error(field, :invalid_datetime)]
    end
  end

  defp existing_atom_value(record, field) do
    field_atom = String.to_existing_atom(field)
    Map.get(record, field_atom)
  rescue
    ArgumentError -> nil
  end
end
