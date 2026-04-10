defmodule JidoCode.SourceCodeGraph.GovernedAdoption do
  # covers: architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records
  # covers: architecture.factory_control_plane.semantic_repository_insights_rejoin_control_plane
  @moduledoc """
  Explicit governed adoption flows for semantic source-code graph findings.

  This boundary makes semantic findings influence factory behavior only through
  durable control-plane records such as Assessment, WorkItem, and Evidence.
  """

  alias JidoCode.Control.Actor
  alias JidoCode.Operations.{WorkItem, WorkSynthesis}
  alias JidoCode.SourceCodeGraph.{Finding, Materialization, ProductFeedback}

  @adoption_actor Actor.factory_system_actor(%{
                    "id" => "system:source-code-graph-governed-adoption",
                    "email" => "source-code-graph-governed-adoption@system.local"
                  })

  @spec adopt_work_item(map(), keyword()) ::
          {:ok,
           %{
             finding: map(),
             observation: map(),
             event: map(),
             assessment: map(),
             work_item: WorkItem.t() | nil,
             action: atom()
           }}
          | {:error, term()}
  def adopt_work_item(projection_or_finding, opts \\ []) do
    with {:ok, finding} <- ensure_finding(projection_or_finding, opts),
         {:ok, %{observation: observation, event: event, assessment: assessment}} <-
           Materialization.materialize_assessment(finding, opts),
         {:ok, %{work_item: work_item, action: action}} <-
           WorkSynthesis.from_assessment(assessment, observation: observation, event: event),
         {:ok, adopted_work_item} <- preserve_work_item_metadata(work_item, finding, action, opts) do
      {:ok,
       %{
         finding: finding,
         observation: observation,
         event: event,
         assessment: assessment,
         work_item: adopted_work_item,
         action: action
       }}
    end
  end

  @spec review_support(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def review_support(projection_or_finding, opts \\ []) do
    with {:ok, finding} <- ensure_finding(projection_or_finding, opts),
         {:ok, evidence_input} <- Materialization.evidence_input(finding, opts) do
      {:ok,
       %{
         finding: finding,
         summary: finding.summary,
         evidence_input: evidence_input,
         review_metadata: %{
           "graph" => normalize_map(finding.graph),
           "provenance" => normalize_map(finding.provenance),
           "freshness" => normalize_map(ProductFeedback.for_graph(finding.graph))
         }
       }}
    end
  end

  @spec adopt_evidence(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def adopt_evidence(projection_or_finding, opts \\ []) do
    Materialization.materialize_evidence(projection_or_finding, opts)
  end

  defp ensure_finding(%{kind: :semantic_finding} = finding, _opts), do: {:ok, finding}
  defp ensure_finding(projection, opts), do: Finding.from_projection(projection, opts)

  defp preserve_work_item_metadata(nil, _finding, _action, _opts), do: {:ok, nil}

  defp preserve_work_item_metadata(%WorkItem{} = work_item, finding, action, opts) do
    metadata =
      work_item.work_metadata
      |> normalize_map()
      |> Map.put(
        "semantic_finding",
        %{
          "digest" => finding.digest,
          "summary" => finding.summary,
          "category" => finding.category,
          "recommended_action" => finding.recommended_action,
          "adoption_action" => Atom.to_string(action),
          "graph" => normalize_map(finding.graph),
          "freshness" => normalize_map(ProductFeedback.for_graph(finding.graph)),
          "provenance" => normalize_map(finding.provenance),
          "payload" => normalize_map(finding.payload)
        }
      )

    WorkItem.update(work_item, %{work_metadata: metadata}, actor: actor(opts))
  end

  defp actor(opts) do
    opts
    |> Keyword.get(:actor)
    |> Actor.effective_actor()
    |> case do
      nil -> @adoption_actor
      actor -> actor
    end
  end

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      normalized_value =
        cond do
          is_boolean(nested_value) or is_nil(nested_value) -> nested_value
          is_map(nested_value) -> normalize_map(nested_value)
          is_list(nested_value) -> Enum.map(nested_value, &normalize_nested_value/1)
          is_atom(nested_value) -> Atom.to_string(nested_value)
          true -> nested_value
        end

      Map.put(acc, normalized_key, normalized_value)
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(value) when is_boolean(value) or is_nil(value), do: value
  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_nested_value(value), do: value
end
