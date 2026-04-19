defmodule JidoCodeWeb.GovernedMemoryHelpers do
  @moduledoc false

  alias JidoCode.Control.Actor

  def operator_actor(socket) do
    socket.assigns
    |> Map.get(:current_user)
    |> case do
      %{} = user ->
        Actor.operator_actor(%{
          "id" => user |> Map.get(:id) |> normalize_optional_string() || "unknown",
          "email" => user |> Map.get(:email) |> normalize_optional_string()
        })

      _other ->
        Actor.operator_actor(%{"id" => "unknown", "email" => nil})
    end
  end

  def memory_context_graph(%{assigns: %{memory_context: %{graph: graph}}}) when is_map(graph), do: graph
  def memory_context_graph(_socket), do: nil

  def memory_operator_base_opts(socket, extra_opts \\ []) do
    [
      actor: operator_actor(socket),
      workspace_path:
        socket.assigns
        |> Map.get(:memory_context, %{})
        |> Map.get(:workspace_path),
      revision:
        socket.assigns
        |> Map.get(:memory_context, %{})
        |> Map.get(:graph, %{})
        |> Map.get(:current_revision)
    ] ++ extra_opts
  end

  def latest_record([record | _rest]), do: record
  def latest_record(_records), do: nil

  def decision_memory_iri(items) when is_list(items) do
    items
    |> Enum.find(&(memory_item_kind(&1) == "Decision"))
    |> case do
      nil -> nil
      item -> memory_item_iri(item)
    end
  end

  def decision_memory_iri(_items), do: nil

  def memory_feedback_kind(%{kind: kind}) when is_atom(kind), do: kind
  def memory_feedback_kind(_feedback), do: :info

  def memory_item_iri(item) do
    present_string(map_get(item, :memory_iri, "memory_iri"))
  end

  def memory_item_kind(item) do
    present_string(map_get(item, :memory_kind, "memory_kind")) ||
      kind_from_resource_iri(memory_item_iri(item)) ||
      "Memory"
  end

  def memory_item_content(item) do
    present_string(map_get(item, :content, "content")) || "bounded durable memory"
  end

  def memory_item_freshness(item) do
    map_get(item, :freshness_score, "freshness_score") || "unknown"
  end

  def memory_item_decision_status(item) do
    present_string(map_get(item, :decision_status, "decision_status")) || "n/a"
  end

  def provenance_item_kind(item) do
    present_string(map_get(item, :provenance_kind, "provenance_kind")) ||
      kind_from_resource_iri(present_string(map_get(item, :resource_iri, "resource_iri"))) ||
      "Provenance"
  end

  def provenance_item_label(item) do
    present_string(map_get(item, :label, "label")) ||
      present_string(map_get(item, :content, "content")) ||
      "bounded provenance"
  end

  def provenance_item_revision(item) do
    present_string(map_get(item, :revision_iri, "revision_iri")) || "unknown"
  end

  def kind_from_resource_iri(nil), do: nil

  def kind_from_resource_iri(value) when is_binary(value) do
    value
    |> String.split("#")
    |> List.last()
    |> case do
      nil -> nil
      fragment -> fragment |> String.split("/") |> List.first()
    end
    |> present_string()
    |> case do
      nil -> nil
      segment -> segment |> String.replace("-", "_") |> Macro.camelize()
    end
  end

  def repo_route(repo_id) when is_binary(repo_id), do: "/repos/#{repo_id}"
  def repo_route(_repo_id), do: nil

  def run_route(repo_id, run_id) when is_binary(repo_id) and is_binary(run_id),
    do: "/repos/#{repo_id}/runs/#{run_id}"

  def run_route(_repo_id, _run_id), do: nil

  def work_item_route(repo_id, work_item_id) when is_binary(repo_id) and is_binary(work_item_id),
    do: "/repos/#{repo_id}/work-items/#{work_item_id}"

  def work_item_route(_repo_id, _work_item_id), do: nil

  def evidence_route(repo_id, evidence_id) when is_binary(repo_id) and is_binary(evidence_id),
    do: "/repos/#{repo_id}/evidence/#{evidence_id}"

  def evidence_route(_repo_id, _evidence_id), do: nil

  def decision_route(repo_id, decision_id) when is_binary(repo_id) and is_binary(decision_id),
    do: "/repos/#{repo_id}/decisions/#{decision_id}"

  def decision_route(_repo_id, _decision_id), do: nil

  def memory_anchor_route(route, anchor) when is_binary(route) and is_binary(anchor), do: route <> anchor
  def memory_anchor_route(_route, _anchor), do: nil

  def route_repo_id(scope) when is_map(scope) do
    normalize_optional_string(Map.get(scope, :route_id) || Map.get(scope, "route_id"))
  end

  def route_repo_id(_scope), do: nil

  def managed_repo_id(scope) when is_map(scope) do
    normalize_optional_string(Map.get(scope, :managed_repo_id) || Map.get(scope, "managed_repo_id"))
  end

  def managed_repo_id(_scope), do: nil

  def load_repo_workspace_path(scope) do
    scope
    |> map_get(:managed_repo, "managed_repo", %{})
    |> map_get(:workspace_settings, "workspace_settings", %{})
    |> map_get(:workspace_path, "workspace_path")
    |> normalize_optional_string()
  end

  def display_string(value, fallback \\ "Unavailable")

  def display_string(value, fallback) when is_binary(value) do
    case String.trim(value) do
      "" -> fallback
      normalized -> normalized
    end
  end

  def display_string(value, fallback) when is_atom(value),
    do: value |> Atom.to_string() |> display_string(fallback)

  def display_string(nil, fallback), do: fallback
  def display_string(value, _fallback), do: to_string(value)

  def display_atom(value) when is_atom(value), do: Atom.to_string(value)
  def display_atom(value), do: display_string(value)

  def present_string(value), do: normalize_optional_string(value)

  def map_get(map, atom_key, string_key, default \\ nil)

  def map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  def map_get(_map, _atom_key, _string_key, default), do: default

  def normalize_optional_string(nil), do: nil

  def normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  def normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  def normalize_optional_string(_value), do: nil
end
