defmodule JidoCode.ManagedRepoRoutes do
  @moduledoc false

  @dashboard_work_overview_path "/dashboard?subject=work&section=overview"

  @spec dashboard_work_overview_path() :: String.t()
  def dashboard_work_overview_path, do: @dashboard_work_overview_path

  @spec normalize_return_to_path(term(), String.t()) :: String.t()
  def normalize_return_to_path(return_to, fallback \\ @dashboard_work_overview_path) do
    normalized_fallback = normalize_path(fallback) || @dashboard_work_overview_path

    case normalize_path(return_to) do
      nil -> normalized_fallback
      normalized_path -> normalized_path
    end
  end

  @spec project_detail_path(map() | term(), keyword()) :: String.t()
  def project_detail_path(project_or_id, opts \\ []) do
    project_id = extract_project_id(project_or_id)

    if is_binary(project_id) do
      query =
        %{}
        |> maybe_put("return_to", Keyword.get(opts, :return_to))
        |> maybe_put("subject", Keyword.get(opts, :subject))
        |> maybe_put("section", Keyword.get(opts, :section))
        |> maybe_put("work_item_id", Keyword.get(opts, :work_item_id))

      "/repos/#{URI.encode(project_id)}" <>
        query_suffix(query) <>
        anchor_suffix(Keyword.get(opts, :anchor))
    else
      "/repos"
    end
  end

  @spec run_detail_path(map() | term(), map() | term(), keyword()) :: String.t()
  def run_detail_path(project_or_id, run_or_id, opts \\ []) do
    project_id = extract_project_id(project_or_id)
    run_id = extract_run_id(run_or_id)

    if is_binary(project_id) and is_binary(run_id) do
      query =
        %{}
        |> maybe_put("return_to", Keyword.get(opts, :return_to))

      "/repos/#{URI.encode(project_id)}/runs/#{URI.encode(run_id)}" <> query_suffix(query)
    else
      "/dashboard"
    end
  end

  @spec repo_detail_parent_return_to(term(), String.t()) :: String.t()
  def repo_detail_parent_return_to(return_to, fallback \\ @dashboard_work_overview_path) do
    normalized_fallback = normalize_return_to_path(nil, fallback)

    case normalize_path(return_to) do
      nil ->
        normalized_fallback

      normalized_path ->
        case repo_detail_return_to(normalized_path) do
          {:repo_detail, nested_return_to} ->
            normalize_return_to_path(nested_return_to, normalized_fallback)

          :error ->
            normalize_return_to_path(normalized_path, normalized_fallback)
        end
    end
  end

  defp repo_detail_return_to(path) do
    uri = URI.parse(path)
    uri_path = normalize_path(uri.path)

    if repo_detail_path?(uri_path) do
      {:repo_detail, uri.query |> decode_query_value("return_to")}
    else
      :error
    end
  end

  defp repo_detail_path?(path) when is_binary(path) do
    String.starts_with?(path, "/repos/") and not String.contains?(path, "/runs/")
  end

  defp repo_detail_path?(_path), do: false

  defp decode_query_value(nil, _key), do: nil

  defp decode_query_value(query, key) when is_binary(query) and is_binary(key) do
    query
    |> URI.decode_query()
    |> Map.get(key)
    |> normalize_optional_string()
  end

  defp extract_project_id(%{} = project) do
    normalize_optional_string(
      Map.get(project, :id) ||
        Map.get(project, "id") ||
        Map.get(project, :project_id) ||
        Map.get(project, "project_id")
    )
  end

  defp extract_project_id(project_id), do: normalize_optional_string(project_id)

  defp extract_run_id(%{} = run) do
    normalize_optional_string(Map.get(run, :run_id) || Map.get(run, "run_id"))
  end

  defp extract_run_id(run_id), do: normalize_optional_string(run_id)

  defp maybe_put(params, key, value) when is_map(params) and is_binary(key) do
    case normalize_optional_string(value) do
      nil -> params
      normalized_value -> Map.put(params, key, normalized_value)
    end
  end

  defp query_suffix(query) when map_size(query) == 0, do: ""
  defp query_suffix(query), do: "?" <> URI.encode_query(query)

  defp anchor_suffix(anchor) do
    case normalize_optional_string(anchor) do
      nil -> ""
      normalized_anchor -> "##{normalized_anchor}"
    end
  end

  defp normalize_path(value) do
    case normalize_optional_string(value) do
      <<"/", _::binary>> = normalized_path -> normalized_path
      _other -> nil
    end
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil
end
