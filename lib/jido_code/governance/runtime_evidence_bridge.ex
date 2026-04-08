defmodule JidoCode.Governance.RuntimeEvidenceBridge do
  @moduledoc """
  Projects runtime delivery and degraded-path evidence into governed observations.
  """

  alias JidoCode.Control.Actor
  alias JidoCode.Operations.Observation

  @observer Actor.factory_system_actor(%{
              "id" => "system:runtime-evidence-bridge",
              "email" => "runtime-evidence-bridge@system.local"
            })
  @source "runtime_service_evidence"
  @category "runtime_service_evidence_state"

  @spec sync_managed_repo(map(), keyword()) ::
          {:ok, %{observation: Observation.t(), runtime_evidence: map()}} | {:error, term()}
  def sync_managed_repo(managed_repo, opts \\ [])

  def sync_managed_repo(%{} = managed_repo, opts) do
    managed_repo_id = map_get(managed_repo, :id, "id")

    with true <- is_binary(managed_repo_id) or {:error, :missing_managed_repo_id},
         runtime_capability_state <- Keyword.get(opts, :runtime_capability_state, %{}) |> normalize_map(),
         runtime_capability_observation <- Keyword.get(opts, :runtime_capability_observation),
         runtime_evidence <- runtime_evidence(runtime_capability_state, runtime_capability_observation),
         {:ok, observation} <- sync_observation(managed_repo_id, runtime_evidence) do
      {:ok, %{observation: observation, runtime_evidence: runtime_evidence}}
    else
      false -> {:error, :missing_managed_repo_id}
      {:error, reason} -> {:error, reason}
    end
  end

  def sync_managed_repo(_managed_repo, _opts), do: {:error, :invalid_managed_repo}

  @spec operator_summary(map() | nil) :: String.t()
  def operator_summary(%{} = runtime_evidence) do
    Map.get(runtime_evidence, "summary") || absent_runtime_evidence()["summary"]
  end

  def operator_summary(_runtime_evidence), do: absent_runtime_evidence()["summary"]

  defp runtime_evidence(runtime_capability_state, runtime_capability_observation) do
    capability_status = Map.get(runtime_capability_state, "status")
    capability_observation_id = runtime_capability_observation && runtime_capability_observation.id

    case capability_status do
      "blocked" ->
        %{
          "status" => "degraded",
          "summary" =>
            "Runtime service evidence indicates degraded execution trust due to blocked runtime capabilities.",
          "review_required" => true,
          "runtime_delivery" => %{
            "delivery_mode" => "replay_recovery",
            "reason_code" => "runtime_capability_blocked",
            "terminal_handoff_kind" => "bounded_fallback"
          },
          "integration_outcomes" => %{},
          "latest_refs" => %{
            "runtime_capability_observation_id" => capability_observation_id
          }
        }

      "ready" ->
        %{
          "status" => "ready",
          "summary" => "Runtime service evidence indicates admitted runtime capabilities are available.",
          "review_required" => false,
          "runtime_delivery" => %{
            "delivery_mode" => "live_or_direct",
            "reason_code" => "runtime_capability_ready",
            "terminal_handoff_kind" => "none"
          },
          "integration_outcomes" => %{},
          "latest_refs" => %{
            "runtime_capability_observation_id" => capability_observation_id
          }
        }

      _other ->
        absent_runtime_evidence()
    end
  end

  defp absent_runtime_evidence do
    %{
      "status" => "absent",
      "summary" => "Runtime service evidence is unavailable.",
      "review_required" => false,
      "runtime_delivery" => %{},
      "integration_outcomes" => %{},
      "latest_refs" => %{}
    }
  end

  defp sync_observation(managed_repo_id, runtime_evidence) do
    digest = digest(runtime_evidence)

    case latest_observation(managed_repo_id) do
      %Observation{} = observation ->
        if get_in(observation.source_metadata || %{}, ["digest"]) == digest do
          {:ok, observation}
        else
          create_observation(managed_repo_id, runtime_evidence, digest)
        end

      _other ->
        create_observation(managed_repo_id, runtime_evidence, digest)
    end
  end

  defp create_observation(managed_repo_id, runtime_evidence, digest) do
    Observation.create(
      %{
        managed_repo_id: managed_repo_id,
        source: @source,
        category: @category,
        summary: runtime_evidence["summary"],
        payload: runtime_evidence,
        source_metadata: %{"digest" => digest},
        captured_by: @observer,
        observed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      },
      actor: @observer
    )
  end

  defp latest_observation(managed_repo_id) do
    case Observation.read(
           query: [
             filter: [managed_repo_id: managed_repo_id, source: @source, category: @category],
             sort: [observed_at: :desc],
             limit: 1
           ],
           actor: @observer
         ) do
      {:ok, [%Observation{} = observation | _rest]} -> observation
      _other -> nil
    end
  end

  defp digest(payload) do
    payload
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
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

  defp normalize_map(_value), do: %{}

  defp map_get(value, atom_key, string_key, default \\ nil)

  defp map_get(value, atom_key, string_key, default) when is_map(value) do
    Map.get(value, atom_key) || Map.get(value, string_key) || default
  end

  defp map_get(_value, _atom_key, _string_key, default), do: default
end
