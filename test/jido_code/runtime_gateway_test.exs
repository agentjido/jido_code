defmodule JidoCode.RuntimeGatewayTest do
  # covers: architecture.runtime_service_overlay.product_owned_gateways_preserve_contracts
  # covers: architecture.runtime_service_overlay.optional_runtime_capabilities_are_explicit_and_typed
  use ExUnit.Case, async: false

  alias JidoCode.CodingAssistance
  alias JidoCode.JidoOsRuntime
  alias JidoCode.RuntimeGateway

  setup do
    instance_id = "jido-code-runtime-gateway-#{System.unique_integer([:positive, :monotonic])}"
    previous_instance_id = Application.get_env(:jido_code, :jido_os_instance_id)
    previous_service_opts = Application.get_env(:jido_os, :managed_service_opts, %{})

    Application.put_env(:jido_code, :jido_os_instance_id, instance_id)

    on_exit(fn ->
      restore_env(:jido_code, :jido_os_instance_id, previous_instance_id)
      Application.put_env(:jido_os, :managed_service_opts, previous_service_opts)
    end)

    %{instance_id: instance_id}
  end

  test "runtime gateway keeps bootstrap and context construction product-owned" do
    refute RuntimeGateway.instance_ready?()
    assert JidoOsRuntime.instance_status().status == "stopped"

    context =
      RuntimeGateway.context_for("runtime-gateway-user", %{
        session_id: "session-a",
        project_id: "project-a",
        workspace_id: "/tmp/runtime-gateway"
      })

    assert context.instance_id == RuntimeGateway.instance_id()
    assert context.actor_id == "runtime-gateway-user"
    assert context.session_id == "session-a"
    assert context.project_id == "project-a"
    assert context.workspace_id == "/tmp/runtime-gateway"
    assert is_binary(context.request_id)
    assert is_binary(context.correlation_id)

    assert :ok = RuntimeGateway.ensure_instance()
    assert RuntimeGateway.instance_ready?()

    assert JidoOsRuntime.instance_status() == %{
             instance_id: RuntimeGateway.instance_id(),
             started?: true,
             ready?: true,
             status: "ready"
           }
  end

  test "runtime gateway exposes typed admitted-service availability through public runtime facades" do
    actor_id = "runtime-gateway-operator"

    assert {:ok, coding_status} = RuntimeGateway.service_status(CodingAssistance, actor_id)
    assert coding_status.service_key == CodingAssistance.runtime_service_key()
    assert coding_status.status == "available"
    assert coding_status.admitted? == true
    assert coding_status.available? == true
    assert coding_status.ready? == true
    assert coding_status.runtime_status == "running"
    assert coding_status.dependency_status == "satisfied"

    assert {:ok, missing_status} =
             RuntimeGateway.service_status("missing_runtime_service", actor_id)

    assert missing_status == %{
             service_key: "missing_runtime_service",
             status: "unavailable",
             admitted?: false,
             available?: false,
             ready?: false,
             child_spec_ready: false,
             runtime_status: "missing",
             dependency_status: "unknown",
             extension_admission: %{enabled: false, reason_code: "runtime_service_unknown"},
             registration_epoch: nil,
             reason_code: "runtime_service_unknown"
           }

    assert {:ok, false} =
             RuntimeGateway.service_available?("missing_runtime_service", actor_id)
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
