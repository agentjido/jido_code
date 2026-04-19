defmodule JidoCode.MemoryGraph.GovernedReference do
  # covers: architecture.memory_graph.memory_graph_supports_cross_graph_provenance
  # covers: architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
  # covers: architecture.memory_capture_plane.typed_governed_reference_contract_is_canonical
  @moduledoc """
  Canonical repository-scoped governed reference helpers for semantic links.

  This boundary gives memory, provenance, query, and UI shaping code one
  normalized reference contract for governed product records. It is the
  replacement target for older generic artifact-path assumptions.
  """

  @type managed_repo_id :: String.t()
  @type kind ::
          :managed_repo
          | :event
          | :observation
          | :assessment
          | :work_item
          | :run
          | :evidence
          | :change_request
          | :decision
  @type normalized_reference :: %{
          kind: kind(),
          id: String.t(),
          iri: String.t(),
          label: String.t()
        }

  @kind_path %{
    managed_repo: "managed_repo",
    event: "event",
    observation: "observation",
    assessment: "assessment",
    work_item: "work_item",
    run: "run",
    evidence: "evidence",
    change_request: "change_request",
    decision: "decision"
  }

  @memory_ns "https://jido.run/ontology/memory#"
  @control_plane_ns "https://jido.run/ontology/control-plane#"

  @kind_labels %{
    managed_repo: "Managed repo",
    event: "Event",
    observation: "Observation",
    assessment: "Assessment",
    work_item: "Work item",
    run: "Run",
    evidence: "Evidence",
    change_request: "Change request",
    decision: "Decision"
  }

  @shorthand_keys [
    {:managed_repo_id, :managed_repo},
    {"managed_repo_id", :managed_repo},
    {:event_id, :event},
    {"event_id", :event},
    {:observation_id, :observation},
    {"observation_id", :observation},
    {:assessment_id, :assessment},
    {"assessment_id", :assessment},
    {:work_item_id, :work_item},
    {"work_item_id", :work_item},
    {:run_id, :run},
    {"run_id", :run},
    {:evidence_id, :evidence},
    {"evidence_id", :evidence},
    {:change_request_id, :change_request},
    {"change_request_id", :change_request},
    {:decision_id, :decision},
    {"decision_id", :decision}
  ]

  @legacy_artifact_segments %{
    "managed_repo_id" => :managed_repo,
    "event_id" => :event,
    "observation_id" => :observation,
    "assessment_id" => :assessment,
    "work_item_id" => :work_item,
    "run_id" => :run,
    "evidence_id" => :evidence,
    "change_request_id" => :change_request,
    "decision_id" => :decision
  }

  @kind_predicates %{
    managed_repo: "aboutManagedRepo",
    event: "aboutEvent",
    observation: "aboutObservation",
    assessment: "aboutAssessment",
    work_item: "aboutWorkItem",
    run: "aboutRun",
    evidence: "aboutEvidence",
    change_request: "aboutChangeRequest",
    decision: "aboutDecision"
  }

  @kind_classes %{
    managed_repo: "ManagedRepo",
    event: "Event",
    observation: "Observation",
    assessment: "Assessment",
    work_item: "WorkItem",
    run: "Run",
    evidence: "Evidence",
    change_request: "ChangeRequest",
    decision: "Decision"
  }

  @kind_id_predicates %{
    managed_repo: "managedRepoId",
    event: "eventId",
    observation: "observationId",
    assessment: "assessmentId",
    work_item: "workItemId",
    run: "runId",
    evidence: "evidenceId",
    change_request: "changeRequestId",
    decision: "decisionId"
  }

  @spec kinds() :: [kind()]
  def kinds, do: Map.keys(@kind_path)

  @spec base_iri(managed_repo_id()) :: String.t()
  def base_iri(managed_repo_id) when is_binary(managed_repo_id) do
    "https://jido.run/managed_repos/#{managed_repo_id}/governed#"
  end

  @spec iri(managed_repo_id(), kind(), String.t()) :: String.t()
  def iri(managed_repo_id, kind, id) when is_binary(managed_repo_id) and is_binary(id) do
    "#{base_iri(managed_repo_id)}#{kind_segment(kind)}/#{URI.encode(id, &URI.char_unreserved?/1)}"
  end

  @spec resource(managed_repo_id(), kind(), String.t()) :: RDF.IRI.t()
  def resource(managed_repo_id, kind, id), do: RDF.iri(iri(managed_repo_id, kind, id))

  @spec label(kind(), String.t()) :: String.t()
  def label(kind, id) when is_binary(id), do: "#{kind_label(kind)} #{id}"

  @spec route(managed_repo_id(), kind(), String.t()) :: String.t() | nil
  def route(_managed_repo_id, :managed_repo, id)
      when is_binary(id),
      do: "/repos/#{id}"

  def route(managed_repo_id, :work_item, id)
      when is_binary(managed_repo_id) and is_binary(id),
      do: "/repos/#{managed_repo_id}/work-items/#{id}"

  def route(managed_repo_id, :run, id) when is_binary(managed_repo_id) and is_binary(id),
    do: "/repos/#{managed_repo_id}/runs/#{id}"

  def route(managed_repo_id, :evidence, id)
      when is_binary(managed_repo_id) and is_binary(id),
      do: "/repos/#{managed_repo_id}/evidence/#{id}"

  def route(managed_repo_id, :decision, id)
      when is_binary(managed_repo_id) and is_binary(id),
      do: "/repos/#{managed_repo_id}/decisions/#{id}"

  def route(_managed_repo_id, _kind, _id), do: nil

  @spec route(managed_repo_id(), normalized_reference()) :: String.t() | nil
  def route(managed_repo_id, %{kind: kind, id: id})
      when is_binary(managed_repo_id) and is_atom(kind) and is_binary(id),
      do: route(managed_repo_id, kind, id)

  @spec predicate_iri(kind()) :: RDF.IRI.t()
  def predicate_iri(kind), do: RDF.iri(@memory_ns <> Map.fetch!(@kind_predicates, kind))

  @spec class_iri(kind()) :: RDF.IRI.t()
  def class_iri(kind), do: RDF.iri(@control_plane_ns <> Map.fetch!(@kind_classes, kind))

  @spec governed_record_class_iri() :: RDF.IRI.t()
  def governed_record_class_iri, do: RDF.iri(@control_plane_ns <> "GovernedRecord")

  @spec id_predicate_iri(kind()) :: RDF.IRI.t()
  def id_predicate_iri(kind), do: RDF.iri(@control_plane_ns <> Map.fetch!(@kind_id_predicates, kind))

  @spec record_label_predicate_iri() :: RDF.IRI.t()
  def record_label_predicate_iri, do: RDF.iri(@control_plane_ns <> "recordLabel")

  @spec for_managed_repo_predicate_iri() :: RDF.IRI.t()
  def for_managed_repo_predicate_iri, do: RDF.iri(@control_plane_ns <> "forManagedRepo")

  @spec normalize(managed_repo_id(), map() | keyword() | {kind(), String.t()}) ::
          {:ok, normalized_reference()} | {:error, atom()}
  def normalize(managed_repo_id, {kind, id}) when is_binary(managed_repo_id) and is_binary(id) do
    build_reference(managed_repo_id, %{kind: kind, id: id})
  end

  def normalize(managed_repo_id, reference) when is_binary(managed_repo_id) and is_list(reference) do
    normalize(managed_repo_id, Enum.into(reference, %{}))
  end

  def normalize(managed_repo_id, reference) when is_binary(managed_repo_id) and is_map(reference) do
    with {:ok, kind, id} <- extract_kind_and_id(reference),
         :ok <- validate_repo_scope(managed_repo_id, kind, id) do
      build_reference(managed_repo_id, %{
        kind: kind,
        id: id,
        iri: first_present(reference, [:iri, "iri"]),
        label: first_present(reference, [:label, "label"])
      })
    end
  end

  def normalize(_managed_repo_id, _reference), do: {:error, :invalid_governed_reference}

  @spec parse_iri(managed_repo_id(), String.t()) :: {:ok, normalized_reference()} | {:error, atom()}
  def parse_iri(managed_repo_id, iri) when is_binary(managed_repo_id) and is_binary(iri) do
    prefix = base_iri(managed_repo_id)

    if String.starts_with?(iri, prefix) do
      iri
      |> String.trim_leading(prefix)
      |> String.split("/", parts: 2)
      |> case do
        [kind_segment, encoded_id] ->
          with {:ok, kind} <- kind_from_segment(kind_segment),
               id when is_binary(id) <- URI.decode(encoded_id) do
            normalize(managed_repo_id, %{kind: kind, id: id, iri: iri})
          else
            _other -> {:error, :invalid_governed_reference}
          end

        _other ->
          {:error, :invalid_governed_reference}
      end
    else
      {:error, :invalid_governed_reference}
    end
  end

  def parse_iri(_managed_repo_id, _iri), do: {:error, :invalid_governed_reference}

  @spec from_artifact_path(managed_repo_id(), String.t()) :: {:ok, normalized_reference()} | {:error, atom()}
  def from_artifact_path(managed_repo_id, path) when is_binary(managed_repo_id) and is_binary(path) do
    path
    |> String.trim()
    |> URI.decode()
    |> String.split("/", parts: 2)
    |> case do
      [segment, id] ->
        with {:ok, kind} <- legacy_kind_from_segment(segment),
             true <- present?(id) or {:error, :invalid_governed_reference} do
          normalize(managed_repo_id, %{kind: kind, id: id})
        else
          _other -> {:error, :invalid_governed_reference}
        end

      _other ->
        {:error, :invalid_governed_reference}
    end
  end

  def from_artifact_path(_managed_repo_id, _path), do: {:error, :invalid_governed_reference}

  @spec normalize_many(managed_repo_id(), [map() | keyword() | {kind(), String.t()}]) ::
          {:ok, [normalized_reference()]} | {:error, atom()}
  def normalize_many(managed_repo_id, references)
      when is_binary(managed_repo_id) and is_list(references) do
    references
    |> Enum.reduce_while({:ok, []}, fn reference, {:ok, normalized} ->
      case normalize(managed_repo_id, reference) do
        {:ok, result} -> {:cont, {:ok, [result | normalized]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized} ->
        normalized
        |> Enum.reverse()
        |> Enum.uniq_by(& &1.iri)
        |> then(&{:ok, &1})

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec explicit_many(nil | map() | keyword() | {kind(), String.t()} | [map() | keyword() | {kind(), String.t()}]) ::
          [map()]
  def explicit_many(nil), do: []

  def explicit_many({kind, id}) when is_binary(id) do
    [%{kind: kind, id: id}]
  end

  def explicit_many(references) when is_list(references) do
    if Keyword.keyword?(references) do
      references
      |> Enum.into(%{})
      |> explicit_many()
    else
      references
      |> Enum.flat_map(&explicit_many/1)
      |> Enum.uniq_by(fn reference ->
        {Map.get(reference, :kind) || Map.get(reference, "kind"), Map.get(reference, :id) || Map.get(reference, "id")}
      end)
    end
  end

  def explicit_many(reference) when is_map(reference) do
    cond do
      explicit_reference?(reference) ->
        [normalize_explicit_reference(reference)]

      true ->
        reference
        |> normalize_map()
        |> Enum.flat_map(fn {key, id} ->
          case normalize_shorthand_key(key) do
            {:ok, kind} ->
              case normalize_identifier(id) do
                nil -> []
                normalized_id -> [%{kind: kind, id: normalized_id}]
              end

            :error ->
              []
          end
        end)
        |> Enum.uniq_by(&{&1.kind, &1.id})
    end
  end

  def explicit_many(_reference), do: []

  @spec normalize_context(
          managed_repo_id(),
          nil | map() | keyword() | {kind(), String.t()} | [map() | keyword() | {kind(), String.t()}]
        ) ::
          {:ok, [normalized_reference()]} | {:error, atom()}
  def normalize_context(managed_repo_id, references) when is_binary(managed_repo_id) do
    explicit = explicit_many(references)

    cond do
      is_nil(references) ->
        {:ok, []}

      references == [] ->
        {:ok, []}

      is_map(references) and map_size(references) == 0 ->
        {:ok, []}

      explicit == [] ->
        {:error, :invalid_governed_reference}

      true ->
        normalize_many(managed_repo_id, explicit)
    end
  end

  defp build_reference(managed_repo_id, %{kind: kind, id: id} = attrs) do
    with {:ok, normalized_kind} <- normalize_kind(kind),
         true <- present?(id) or {:error, :invalid_governed_reference} do
      {:ok,
       %{
         kind: normalized_kind,
         id: id,
         iri: attrs[:iri] || iri(managed_repo_id, normalized_kind, id),
         label: attrs[:label] || label(normalized_kind, id)
       }}
    end
  end

  defp extract_kind_and_id(reference) do
    explicit_kind = first_present(reference, [:kind, "kind"])
    explicit_id = first_present(reference, [:id, "id"])

    cond do
      explicit_kind && explicit_id ->
        with {:ok, kind} <- normalize_kind(explicit_kind) do
          {:ok, kind, explicit_id}
        end

      true ->
        shorthand(reference)
    end
  end

  defp shorthand(reference) do
    Enum.find_value(@shorthand_keys, {:error, :invalid_governed_reference}, fn {key, kind} ->
      case first_present(reference, [key]) do
        nil -> nil
        id -> {:ok, kind, id}
      end
    end)
  end

  defp validate_repo_scope(managed_repo_id, :managed_repo, id) when managed_repo_id != id do
    {:error, :managed_repo_scope_mismatch}
  end

  defp validate_repo_scope(_managed_repo_id, _kind, _id), do: :ok

  defp kind_segment(kind), do: Map.fetch!(@kind_path, kind)
  defp kind_label(kind), do: Map.fetch!(@kind_labels, kind)

  defp kind_from_segment(segment) when is_binary(segment) do
    case Enum.find(@kind_path, fn {_kind, value} -> value == segment end) do
      {kind, _value} -> {:ok, kind}
      nil -> {:error, :invalid_governed_reference_kind}
    end
  end

  defp legacy_kind_from_segment(segment) when is_binary(segment) do
    case Map.fetch(@legacy_artifact_segments, segment) do
      {:ok, kind} -> {:ok, kind}
      :error -> {:error, :invalid_governed_reference_kind}
    end
  end

  defp normalize_kind(kind) when is_atom(kind) do
    if Map.has_key?(@kind_path, kind) do
      {:ok, kind}
    else
      {:error, :invalid_governed_reference_kind}
    end
  end

  defp normalize_kind(kind) when is_binary(kind) do
    case String.trim(kind) do
      "managed_repo" -> {:ok, :managed_repo}
      "event" -> {:ok, :event}
      "observation" -> {:ok, :observation}
      "assessment" -> {:ok, :assessment}
      "work_item" -> {:ok, :work_item}
      "run" -> {:ok, :run}
      "evidence" -> {:ok, :evidence}
      "change_request" -> {:ok, :change_request}
      "decision" -> {:ok, :decision}
      _other -> {:error, :invalid_governed_reference_kind}
    end
  end

  defp normalize_kind(_kind), do: {:error, :invalid_governed_reference_kind}

  defp explicit_reference?(reference) do
    present?(first_present(reference, [:kind, "kind"])) and present?(first_present(reference, [:id, "id"]))
  end

  defp normalize_explicit_reference(reference) do
    %{}
    |> maybe_put(:kind, first_present(reference, [:kind, "kind"]))
    |> maybe_put(:id, normalize_identifier(first_present(reference, [:id, "id"])))
    |> maybe_put(:iri, normalize_identifier(first_present(reference, [:iri, "iri"])))
    |> maybe_put(:label, normalize_identifier(first_present(reference, [:label, "label"])))
  end

  defp normalize_shorthand_key(key) when is_atom(key), do: normalize_shorthand_key(Atom.to_string(key))

  defp normalize_shorthand_key(key) when is_binary(key) do
    case String.trim(key) do
      "managed_repo_id" -> {:ok, :managed_repo}
      "event_id" -> {:ok, :event}
      "observation_id" -> {:ok, :observation}
      "assessment_id" -> {:ok, :assessment}
      "work_item_id" -> {:ok, :work_item}
      "run_id" -> {:ok, :run}
      "evidence_id" -> {:ok, :evidence}
      "change_request_id" -> {:ok, :change_request}
      "decision_id" -> {:ok, :decision}
      _other -> :error
    end
  end

  defp normalize_shorthand_key(_key), do: :error

  defp normalize_identifier(nil), do: nil

  defp normalize_identifier(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_identifier(value) when is_atom(value), do: normalize_identifier(Atom.to_string(value))
  defp normalize_identifier(value), do: value |> to_string() |> normalize_identifier()

  defp first_present(map, keys) do
    Enum.find_value(keys, fn key ->
      value = Map.get(map, key)
      if present?(value), do: value
    end)
  end

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      Map.put(acc, normalized_key, nested_value)
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)
end
