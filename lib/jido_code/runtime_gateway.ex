defmodule JidoCode.RuntimeGateway do
  # covers: architecture.runtime_service_overlay.public_service_facades_are_only_product_runtime_seam
  # covers: architecture.runtime_service_overlay.optional_runtime_capabilities_are_explicit_and_typed
  # covers: architecture.runtime_service_overlay.product_owned_gateways_preserve_contracts
  # covers: architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product
  @moduledoc """
  Shared product-owned helpers for gateways over public `Jido.Os.*` runtime services.

  Product-facing runtime integration should stay in `JidoCode.*` gateways while
  this helper centralizes runtime bootstrap, context construction, and admitted
  service status reads through documented public runtime facades.
  """

  alias JidoCode.JidoOsRuntime

  def instance_id, do: JidoOsRuntime.instance_id()

  def ensure_instance, do: JidoOsRuntime.ensure_instance()

  def instance_status, do: JidoOsRuntime.instance_status()

  def instance_ready?, do: JidoOsRuntime.instance_ready?()

  def context_for(actor_id, attrs \\ %{}), do: JidoOsRuntime.context_for(actor_id, attrs)

  def runtime_service_key(service_ref), do: JidoOsRuntime.runtime_service_key(service_ref)

  def service_status(service_ref, actor_id, attrs \\ %{}) do
    JidoOsRuntime.service_status(service_ref, actor_id, attrs)
  end

  def service_available?(service_ref, actor_id, attrs \\ %{}) do
    JidoOsRuntime.service_available?(service_ref, actor_id, attrs)
  end

  def capability_posture(service_ref, actor_id, attrs \\ %{}) do
    with {:ok, status} <- service_status(service_ref, actor_id, attrs) do
      {:ok, normalize_capability_posture(status)}
    end
  end

  def capability_posture_snapshot(service_refs, actor_id, attrs \\ %{})

  def capability_posture_snapshot(service_refs, actor_id, attrs)
      when is_list(service_refs) do
    service_refs
    |> Enum.reduce_while({:ok, []}, fn service_ref, {:ok, acc} ->
      case capability_posture(service_ref, actor_id, attrs) do
        {:ok, posture} -> {:cont, {:ok, [posture | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, service_postures} ->
        service_postures = Enum.reverse(service_postures)

        {:ok,
         %{
           status: snapshot_status(service_postures),
           rollout_source: snapshot_rollout_source(service_postures),
           summary: snapshot_summary(service_postures),
           services: service_postures,
           service_count: length(service_postures),
           available_service_count: Enum.count(service_postures, &(&1.status == "available")),
           review_required_service_count: Enum.count(service_postures, &(&1.governance_effect == "review_required")),
           blocked_service_count: Enum.count(service_postures, &(&1.governance_effect == "blocked"))
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def capability_posture_snapshot(_service_refs, _actor_id, _attrs),
    do: {:error, :invalid_service_refs}

  def operator_summary(%{summary: summary}) when is_binary(summary), do: summary
  def operator_summary(%{"summary" => summary}) when is_binary(summary), do: summary
  def operator_summary(_snapshot), do: "Runtime capability posture is unavailable."

  defp normalize_capability_posture(status) do
    %{
      service_key: status.service_key,
      status: status.status,
      rollout_source: rollout_source(status),
      denial_reason: denial_reason(status),
      degraded_path_evidence: degraded_path_evidence(status),
      available?: status.available?,
      ready?: status.ready?,
      admitted?: status.admitted?,
      governance_effect: governance_effect(status.status),
      summary: capability_summary(status)
    }
  end

  defp rollout_source(%{registration_epoch: registration_epoch}) when is_binary(registration_epoch),
    do: "runtime_admission_registry"

  defp rollout_source(_status), do: "repo_local_compatibility_surface"

  defp denial_reason(%{status: status, reason_code: reason_code})
       when status in ["unavailable", "withheld", "denied"] and is_binary(reason_code),
       do: reason_code

  defp denial_reason(_status), do: nil

  defp degraded_path_evidence(%{status: "available"}), do: %{}

  defp degraded_path_evidence(status) do
    %{
      runtime_status: status.runtime_status,
      dependency_status: status.dependency_status,
      child_spec_ready: status.child_spec_ready,
      reason_code: status.reason_code
    }
  end

  defp governance_effect(status) when status in ["unavailable", "withheld", "denied"], do: "blocked"
  defp governance_effect(status) when status in ["degraded", "starting"], do: "review_required"
  defp governance_effect(_status), do: "none"

  defp capability_summary(status) do
    case status.status do
      "available" -> "Runtime service #{status.service_key} is admitted and available."
      "starting" -> "Runtime service #{status.service_key} is still starting and requires review."
      "degraded" -> "Runtime service #{status.service_key} is degraded and requires review."
      "withheld" -> "Runtime service #{status.service_key} is withheld from the current runtime rollout."
      "denied" -> "Runtime service #{status.service_key} is denied for the current runtime context."
      "unavailable" -> "Runtime service #{status.service_key} is unavailable to the product runtime gateway."
      _other -> "Runtime service #{status.service_key} returned an unknown posture."
    end
  end

  defp snapshot_status(service_postures) do
    cond do
      Enum.any?(service_postures, &(&1.governance_effect == "blocked")) ->
        "blocked"

      Enum.any?(service_postures, &(&1.governance_effect == "review_required")) ->
        "degraded"

      service_postures != [] and Enum.all?(service_postures, &(&1.status == "available")) ->
        "available"

      true ->
        "unavailable"
    end
  end

  defp snapshot_rollout_source(service_postures) do
    service_postures
    |> Enum.map(& &1.rollout_source)
    |> Enum.uniq()
    |> case do
      [single_source] -> single_source
      multiple_sources when multiple_sources != [] -> "mixed_runtime_sources"
      _other -> "product_runtime_gateway"
    end
  end

  defp snapshot_summary(service_postures) do
    case service_postures do
      [] ->
        "No runtime capabilities were configured for this product gateway check."

      _services ->
        service_postures
        |> Enum.map(& &1.summary)
        |> Enum.join(" ")
    end
  end
end
