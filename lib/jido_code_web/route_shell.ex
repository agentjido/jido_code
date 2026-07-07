defmodule JidoCodeWeb.RouteShell do
  @moduledoc false

  @type badge :: %{
          required(:label) => String.t(),
          required(:tone) => atom()
        }

  @type breadcrumb :: %{
          required(:id) => String.t(),
          required(:label) => String.t(),
          optional(:navigate) => String.t() | nil,
          optional(:patch) => String.t() | nil,
          optional(:current?) => boolean()
        }

  @type section_item :: %{
          required(:id) => atom() | String.t(),
          required(:label) => String.t(),
          optional(:summary) => String.t() | nil,
          optional(:description) => String.t() | nil,
          optional(:badge) => badge() | nil,
          optional(:pane_id) => String.t() | nil,
          optional(:selected?) => boolean(),
          optional(:navigate) => String.t() | nil,
          optional(:patch) => String.t() | nil
        }

  @type pane :: %{
          required(:id) => String.t(),
          required(:title) => String.t(),
          required(:summary) => String.t()
        }

  @spec breadcrumb(map()) :: breadcrumb()
  def breadcrumb(attrs) when is_map(attrs) do
    %{
      id: fetch_string!(attrs, :id),
      label: fetch_string!(attrs, :label),
      navigate: optional_string(attrs, :navigate),
      patch: optional_string(attrs, :patch),
      current?: Map.get(attrs, :current?, false)
    }
  end

  @spec section_group(map()) :: section_item()
  def section_group(attrs) when is_map(attrs) do
    normalize_section_item(attrs)
  end

  @spec section_item(map()) :: section_item()
  def section_item(attrs) when is_map(attrs) do
    normalize_section_item(attrs)
  end

  @spec pane(map()) :: pane()
  def pane(attrs) when is_map(attrs) do
    %{
      id: fetch_string!(attrs, :id),
      title: fetch_string!(attrs, :title),
      summary: fetch_string!(attrs, :summary)
    }
  end

  defp normalize_section_item(attrs) do
    %{
      id: Map.fetch!(attrs, :id),
      label: fetch_string!(attrs, :label),
      summary: optional_string(attrs, :summary),
      description: optional_string(attrs, :description),
      badge: Map.get(attrs, :badge),
      pane_id: optional_string(attrs, :pane_id),
      selected?: Map.get(attrs, :selected?, false),
      navigate: optional_string(attrs, :navigate),
      patch: optional_string(attrs, :patch)
    }
  end

  defp fetch_string!(attrs, key) do
    attrs
    |> Map.fetch!(key)
    |> to_string()
  end

  defp optional_string(attrs, key) do
    case Map.get(attrs, key) do
      nil -> nil
      value -> to_string(value)
    end
  end
end
