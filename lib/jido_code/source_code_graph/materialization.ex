defmodule JidoCode.SourceCodeGraph.Materialization do
  # covers: architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records
  # covers: architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_graph_context
  @moduledoc """
  Explicit product-owned materialization entrypoints for semantic findings.
  """

  alias JidoCode.Control.Actor
  alias JidoCode.Governance.Evidence
  alias JidoCode.Governance.RecordStore, as: GovernanceRecordStore
  alias JidoCode.Operations.{Assessment, Event, Observation}
  alias JidoCode.Operations.RecordStore, as: OperationsRecordStore
  alias JidoCode.SourceCodeGraph.{Finding, ProductFeedback}

  @materialization_actor Actor.factory_system_actor(%{
                           "id" => "system:source-code-graph-materialization",
                           "email" => "source-code-graph-materialization@system.local"
                         })

  @spec materialize_observation(map(), keyword()) :: {:ok, Observation.t()} | {:error, term()}
  def materialize_observation(projection_or_finding, opts \\ []) do
    with {:ok, finding} <- ensure_finding(projection_or_finding, opts) do
      OperationsRecordStore.create(:observation, observation_attrs(finding, opts), actor: actor(opts))
    end
  end

  @spec materialize_assessment(map(), keyword()) ::
          {:ok, %{finding: map(), observation: Observation.t(), event: Event.t(), assessment: Assessment.t()}}
          | {:error, term()}
  def materialize_assessment(projection_or_finding, opts \\ []) do
    with {:ok, finding} <- ensure_finding(projection_or_finding, opts),
         {:ok, observation} <- materialize_observation(finding, opts),
         {:ok, event} <- OperationsRecordStore.create(:event, event_attrs(finding, observation), actor: actor(opts)),
         {:ok, assessment} <-
           OperationsRecordStore.create(:assessment, assessment_attrs(finding, observation, event), actor: actor(opts)) do
      {:ok, %{finding: finding, observation: observation, event: event, assessment: assessment}}
    end
  end

  @spec work_item_seed(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def work_item_seed(projection_or_finding, opts \\ []) do
    with {:ok, finding} <- ensure_finding(projection_or_finding, opts) do
      {:ok,
       %{
         managed_repo_id: finding.managed_repo_id,
         category: finding.category,
         priority: finding.priority,
         recommended_action: finding.recommended_action,
         summary: finding.summary,
         dedup_key: "semantic_finding:#{finding.digest}",
         initiating_actor: normalize_map(actor(opts)),
         work_metadata: %{
           "source" => "source_code_graph",
           "finding_digest" => finding.digest,
           "graph" => normalize_map(finding.graph),
           "freshness" => normalize_map(ProductFeedback.for_graph(finding.graph)),
           "provenance" => normalize_map(finding.provenance),
           "payload" => normalize_map(finding.payload)
         }
       }}
    end
  end

  @spec evidence_input(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def evidence_input(projection_or_finding, opts \\ []) do
    with {:ok, finding} <- ensure_finding(projection_or_finding, opts) do
      key = Keyword.get(opts, :key, "semantic_finding:#{finding.digest}")

      {:ok,
       %{
         managed_repo_id: finding.managed_repo_id,
         work_item_id: Keyword.get(opts, :work_item_id),
         run_id: Keyword.get(opts, :run_id),
         key: key,
         evidence_type: "source_code_graph_finding",
         summary: finding.summary,
         evidence_details: %{
           "finding_digest" => finding.digest,
           "graph" => normalize_map(finding.graph),
           "freshness" => normalize_map(ProductFeedback.for_graph(finding.graph)),
           "provenance" => normalize_map(finding.provenance),
           "payload" => normalize_map(finding.payload)
         },
         source: "source_code_graph"
       }}
    end
  end

  @spec materialize_evidence(map(), keyword()) :: {:ok, Evidence.t()} | {:error, term()}
  def materialize_evidence(projection_or_finding, opts \\ []) do
    with {:ok, finding} <- ensure_finding(projection_or_finding, opts),
         run_id when is_binary(run_id) <-
           normalize_optional_string(Keyword.get(opts, :run_id)) || {:error, :missing_run_id},
         {:ok, attrs} <- evidence_input(finding, opts),
         {:ok, evidence} <-
           GovernanceRecordStore.upsert_evidence(
             Map.merge(attrs, %{run_id: run_id, recorded_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)}),
             actor: actor(opts)
           ) do
      {:ok, evidence}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_finding(%{kind: :semantic_finding} = finding, _opts), do: {:ok, finding}
  defp ensure_finding(projection, opts), do: Finding.from_projection(projection, opts)

  defp observation_attrs(finding, opts) do
    %{
      managed_repo_id: finding.managed_repo_id,
      source: "source_code_graph",
      category: finding.category,
      summary: finding.summary,
      payload: %{
        "finding_type" => to_string(finding.finding_type),
        "graph" => normalize_map(finding.graph),
        "provenance" => normalize_map(finding.provenance),
        "payload" => normalize_map(finding.payload)
      },
      source_metadata: %{
        "finding_digest" => finding.digest,
        "requested_by" => normalize_map(Keyword.get(opts, :requested_by, %{})),
        "materialization" => "explicit"
      },
      captured_by: normalize_map(actor(opts)),
      observed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }
  end

  defp event_attrs(finding, observation) do
    %{
      managed_repo_id: finding.managed_repo_id,
      observation_id: observation.id,
      category: "semantic.source_code_graph.#{finding.category}",
      summary: finding.summary,
      correlation_key: "semantic_finding:#{finding.digest}",
      payload: %{
        "observation_id" => observation.id,
        "finding_digest" => finding.digest,
        "finding_type" => to_string(finding.finding_type)
      },
      source_metadata: %{
        "source_record_type" => "semantic_finding",
        "finding_digest" => finding.digest
      },
      occurred_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }
  end

  defp assessment_attrs(finding, observation, event) do
    %{
      managed_repo_id: finding.managed_repo_id,
      event_id: event.id,
      category: finding.category,
      summary: "Assess #{finding.summary}",
      priority: finding.priority,
      urgency: finding.urgency,
      recommended_action: finding.recommended_action,
      rationale:
        "An operator or product workflow explicitly materialized a semantic source-code graph finding into governed assessment state.",
      inputs: %{
        "observation_id" => observation.id,
        "event_id" => event.id,
        "graph" => normalize_map(finding.graph),
        "provenance" => normalize_map(finding.provenance),
        "payload" => normalize_map(finding.payload)
      },
      assessment_metadata: %{
        "semantic_finding_digest" => finding.digest,
        "materialization" => "explicit"
      },
      assessed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }
  end

  defp actor(opts) do
    opts
    |> Keyword.get(:actor)
    |> Actor.effective_actor()
    |> case do
      nil -> @materialization_actor
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
