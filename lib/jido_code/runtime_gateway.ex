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
end
