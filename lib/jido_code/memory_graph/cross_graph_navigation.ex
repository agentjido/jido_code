defmodule JidoCode.MemoryGraph.CrossGraphNavigation do
  # covers: architecture.memory_graph_product_adoption.memory_and_provenance_views_can_cross_link_to_source_code
  # covers: architecture.memory_graph_product_adoption.memory_findings_rejoin_governed_product_records
  @moduledoc false

  alias JidoCode.{MemoryGraph, SourceCodeGraph}
  alias JidoCode.MemoryGraph.GovernedReference

  @spec build(String.t(), String.t(), [map()]) :: map()
  def build(managed_repo_id, workspace_path, bindings)
      when is_binary(managed_repo_id) and is_binary(workspace_path) and is_list(bindings) do
    source_code =
      bindings
      |> Enum.flat_map(&source_links(managed_repo_id, &1))
      |> uniq_by(:iri)

    governed_records =
      bindings
      |> Enum.flat_map(&governed_links(managed_repo_id, &1))
      |> uniq_by(:iri)

    related_memories =
      bindings
      |> Enum.flat_map(&related_memory_links(managed_repo_id, workspace_path, &1))
      |> uniq_by(:iri)

    %{
      source_code: source_code,
      governed_records: governed_records,
      related_memories: related_memories
    }
  end

  defp source_links(managed_repo_id, binding) do
    []
    |> add_source_link(:repository, managed_repo_id, value(binding, "repository"))
    |> add_source_link(:file, managed_repo_id, value(binding, "file"))
    |> add_source_link(:module, managed_repo_id, value(binding, "module"))
    |> add_source_link(:function, managed_repo_id, value(binding, "function"))
    |> add_source_link(:test, managed_repo_id, value(binding, "test"))
    |> add_source_link(:config, managed_repo_id, value(binding, "config"))
    |> add_source_link(:symbol, managed_repo_id, value(binding, "subject"))
  end

  defp add_source_link(links, _kind, _managed_repo_id, nil), do: links

  defp add_source_link(links, kind, managed_repo_id, iri) do
    label =
      case source_label(kind, managed_repo_id, iri) do
        nil -> compact_name(iri)
        value -> value
      end

    route =
      case kind do
        :module -> "/repos/#{managed_repo_id}#project-detail-semantic-inspection"
        :function -> "/repos/#{managed_repo_id}#project-detail-semantic-inspection"
        :symbol -> "/repos/#{managed_repo_id}#project-detail-semantic-inspection"
        _other -> nil
      end

    query =
      case kind do
        :module ->
          %{module_name: label}

        :function ->
          %{function_iri: iri}

        :symbol ->
          %{subject_iri: iri}

        _other ->
          %{}
      end

    links ++
      [
        %{
          kind: kind,
          iri: iri,
          label: label,
          route: route,
          query: query
        }
      ]
  end

  defp governed_links(managed_repo_id, binding) do
    typed_governed_iri = value(binding, "governedRecord")
    typed_governed_kind = value(binding, "governedKind")
    typed_governed_label = value(binding, "governedLabel")
    artifact_iri = value(binding, "artifact")

    typed_links =
      case {typed_governed_iri, typed_target(managed_repo_id, typed_governed_iri, typed_governed_kind)} do
        {nil, _target} ->
          []

        {typed_governed_iri, {target_kind, target_id}} ->
          [
            %{
              kind: target_kind,
              iri: typed_governed_iri,
              id: target_id,
              label:
                typed_governed_label || "#{target_kind |> Atom.to_string() |> String.replace("_", " ")} #{target_id}",
              route: governed_route(managed_repo_id, target_kind, target_id)
            }
          ]

        _other ->
          []
      end

    legacy_links =
      case {artifact_iri, artifact_target(managed_repo_id, artifact_iri)} do
        {nil, _target} ->
          []

        {artifact_iri, {target_kind, target_id}} ->
          [
            %{
              kind: target_kind,
              iri: artifact_iri,
              id: target_id,
              label: artifact_label(binding, target_kind, target_id),
              route: governed_route(managed_repo_id, target_kind, target_id)
            }
          ]

        {artifact_iri, nil} ->
          [
            %{
              kind: :artifact,
              iri: artifact_iri,
              label: value(binding, "artifactLabel") || compact_name(artifact_iri),
              route: nil
            }
          ]
      end

    typed_links ++ legacy_links
  end

  defp related_memory_links(_managed_repo_id, _workspace_path, binding) do
    case value(binding, "related") do
      nil ->
        []

      iri ->
        [%{kind: :memory, iri: iri, label: compact_name(iri), route: nil}]
    end
  end

  defp source_label(:module, managed_repo_id, iri) do
    prefix = SourceCodeGraph.base_iri(managed_repo_id)

    if String.starts_with?(iri, prefix) do
      iri
      |> String.trim_leading(prefix)
      |> String.split("/")
      |> List.first()
    else
      nil
    end
  end

  defp source_label(:function, managed_repo_id, iri) do
    prefix = SourceCodeGraph.base_iri(managed_repo_id)

    if String.starts_with?(iri, prefix) do
      case String.trim_leading(iri, prefix) |> String.split("/") do
        [module_name, function_name, arity] -> "#{module_name}.#{function_name}/#{arity}"
        _other -> compact_name(iri)
      end
    else
      nil
    end
  end

  defp source_label(_kind, _managed_repo_id, _iri), do: nil

  defp artifact_target(managed_repo_id, artifact_iri) when is_binary(artifact_iri) do
    prefix = "#{MemoryGraph.base_iri(managed_repo_id)}artifact/"

    if String.starts_with?(artifact_iri, prefix) do
      artifact_iri
      |> String.trim_leading(prefix)
      |> URI.decode()
      |> String.split("/", parts: 2)
      |> case do
        [kind, id]
        when kind in ["observation_id", "assessment_id", "work_item_id", "evidence_id", "decision_id", "run_id"] ->
          {String.to_atom(String.replace_suffix(kind, "_id", "")), id}

        _other ->
          nil
      end
    else
      nil
    end
  end

  defp artifact_target(_managed_repo_id, _artifact_iri), do: nil

  defp typed_target(managed_repo_id, governed_iri, kind) when is_binary(governed_iri) do
    case GovernedReference.parse_iri(managed_repo_id, governed_iri) do
      {:ok, %{kind: parsed_kind, id: id}} ->
        normalized_kind =
          case normalize_kind(kind) do
            nil -> parsed_kind
            explicit_kind -> explicit_kind
          end

        {normalized_kind, id}

      _other ->
        nil
    end
  end

  defp typed_target(_managed_repo_id, _governed_iri, _kind), do: nil

  defp normalize_kind(nil), do: nil

  defp normalize_kind(kind) when is_atom(kind), do: kind

  defp normalize_kind(kind) when is_binary(kind) do
    case String.trim(kind) do
      "managed_repo" -> :managed_repo
      "event" -> :event
      "observation" -> :observation
      "assessment" -> :assessment
      "work_item" -> :work_item
      "run" -> :run
      "evidence" -> :evidence
      "change_request" -> :change_request
      "decision" -> :decision
      _other -> nil
    end
  end

  defp artifact_label(binding, kind, id) do
    value(binding, "artifactLabel") ||
      "#{kind |> Atom.to_string() |> String.replace("_", " ")} #{id}"
  end

  defp governed_route(managed_repo_id, :run, id), do: "/repos/#{managed_repo_id}/runs/#{id}"
  defp governed_route(_managed_repo_id, _kind, _id), do: nil

  defp uniq_by(items, key) do
    Enum.uniq_by(items, &Map.get(&1, key))
  end

  defp value(binding, key) when is_map(binding) do
    binding
    |> Map.get(key, %{})
    |> case do
      %{value: value} -> value
      %{"value" => value} -> value
      _ -> nil
    end
  end

  defp compact_name(nil), do: nil

  defp compact_name(value) when is_binary(value) do
    value
    |> String.split(["#", "/"])
    |> List.last()
  end
end
