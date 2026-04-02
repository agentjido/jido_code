defmodule JidoCode.RuntimeIntegration do
  # covers: architecture.runtime_service_overlay.public_service_facades_are_only_product_runtime_seam
  # covers: architecture.runtime_service_overlay.product_owned_gateways_preserve_contracts
  # covers: architecture.runtime_service_overlay.integration_service_is_canonical_external_runtime_boundary
  # covers: architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product
  # covers: architecture.policy_layers.runtime_policy_governs_session_and_turn_capability
  # covers: architecture.policy_layers.runtime_integration_gateways_preserve_actor_bound_policy
  # covers: package.jido_code.primary_implementation_repo
  @moduledoc """
  Product-owned gateway over the public `Jido.Os.Integration.Service`.

  This keeps repo-scoped runtime integration behavior inside a stable
  `JidoCode.*` boundary while preserving managed-repo identity, explicit actor
  context, and typed runtime-service availability at the product seam.
  """

  alias Jido.Os.Integration.Service, as: IntegrationService
  alias JidoCode.Control.RepoBridge
  alias JidoCode.RuntimeGateway

  @runtime_service_module IntegrationService

  def runtime_service_module, do: @runtime_service_module

  def runtime_service_key do
    RuntimeGateway.runtime_service_key(@runtime_service_module)
  end

  def runtime_service_status(actor_id, attrs \\ %{}) when is_binary(actor_id) and is_map(attrs) do
    RuntimeGateway.service_status(@runtime_service_module, actor_id, attrs)
  end

  def runtime_service_available?(actor_id, attrs \\ %{})
      when is_binary(actor_id) and is_map(attrs) do
    RuntimeGateway.service_available?(@runtime_service_module, actor_id, attrs)
  end

  def supported_providers, do: IntegrationService.supported_providers()
  def supported_binding_statuses, do: IntegrationService.supported_binding_statuses()
  def supported_install_states, do: IntegrationService.supported_install_states()

  def begin_install(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_repo_runtime_scope(actor_id, params, fn scope, runtime_scope, _status ->
      IntegrationService.begin_install(
        RuntimeGateway.instance_id(),
        install_payload(params, runtime_scope),
        runtime_scope.context
      )
      |> normalize_gateway_result(fn install_session ->
        normalize_install_session(install_session, scope, actor_id, runtime_scope)
      end)
    end)
  end

  def complete_install(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_repo_runtime_scope(actor_id, params, fn scope, runtime_scope, _status ->
      IntegrationService.complete_install(
        RuntimeGateway.instance_id(),
        complete_install_payload(params, runtime_scope),
        runtime_scope.context
      )
      |> normalize_gateway_result(fn binding ->
        normalize_binding(binding, scope, actor_id, runtime_scope)
      end)
    end)
  end

  def list_project_bindings(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_repo_runtime_scope(actor_id, params, fn scope, runtime_scope, _status ->
      IntegrationService.list_project_bindings(
        RuntimeGateway.instance_id(),
        binding_payload(params, runtime_scope),
        runtime_scope.context
      )
      |> normalize_gateway_result(fn bindings ->
        Enum.map(bindings, &normalize_binding(&1, scope, actor_id, runtime_scope))
      end)
    end)
  end

  def get_project_binding(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_repo_runtime_scope(actor_id, params, fn scope, runtime_scope, _status ->
      IntegrationService.get_project_binding(
        RuntimeGateway.instance_id(),
        binding_payload(params, runtime_scope),
        runtime_scope.context
      )
      |> normalize_gateway_result(fn binding ->
        normalize_binding(binding, scope, actor_id, runtime_scope)
      end)
    end)
  end

  def set_default_project_binding(actor_id, params)
      when is_binary(actor_id) and is_map(params) do
    with_repo_runtime_scope(actor_id, params, fn scope, runtime_scope, _status ->
      IntegrationService.set_default_project_binding(
        RuntimeGateway.instance_id(),
        binding_payload(params, runtime_scope),
        runtime_scope.context
      )
      |> normalize_gateway_result(fn binding ->
        normalize_binding(binding, scope, actor_id, runtime_scope)
      end)
    end)
  end

  def revoke_project_binding(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_repo_runtime_scope(actor_id, params, fn scope, runtime_scope, _status ->
      IntegrationService.revoke_project_binding(
        RuntimeGateway.instance_id(),
        binding_payload(params, runtime_scope),
        runtime_scope.context
      )
      |> normalize_gateway_result(fn binding ->
        normalize_binding(binding, scope, actor_id, runtime_scope)
      end)
    end)
  end

  def list_provider_operations(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_repo_runtime_scope(actor_id, params, fn scope, runtime_scope, _status ->
      IntegrationService.list_provider_operations(
        RuntimeGateway.instance_id(),
        operation_list_payload(params, runtime_scope),
        runtime_scope.context
      )
      |> normalize_gateway_result(fn operations ->
        %{
          provider: get_string(params, :provider),
          managed_repo_id: scope.managed_repo_id,
          legacy_project_id: scope.project_id,
          runtime_project_id: runtime_scope.runtime_project_id,
          route_id: scope.route_id,
          context: gateway_context(actor_id, runtime_scope),
          operations: Enum.map(operations, &normalize_operation_descriptor/1)
        }
      end)
    end)
  end

  def invoke_operation(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_repo_runtime_scope(actor_id, params, fn scope, runtime_scope, _status ->
      IntegrationService.invoke_operation(
        RuntimeGateway.instance_id(),
        invocation_payload(params, runtime_scope),
        runtime_scope.context
      )
      |> normalize_gateway_result(fn invocation_result ->
        normalize_invocation_result(invocation_result, scope, actor_id, runtime_scope)
      end)
    end)
  end

  def binding_health_snapshot(actor_id, params) when is_binary(actor_id) and is_map(params) do
    with_runtime_scope(actor_id, params, fn scope, runtime_scope, status ->
      capability_posture =
        RuntimeGateway.capability_posture(@runtime_service_module, actor_id, runtime_scope.attrs)
        |> case do
          {:ok, posture} -> posture
          {:error, _reason} -> unavailable_capability_posture(status)
        end

      bindings =
        if status.available? do
          case IntegrationService.list_project_bindings(
                 RuntimeGateway.instance_id(),
                 binding_payload(params, runtime_scope),
                 runtime_scope.context
               ) do
            {:ok, listed_bindings} ->
              Enum.map(listed_bindings, &normalize_binding(&1, scope, actor_id, runtime_scope))

            {:error, _reason} ->
              []
          end
        else
          []
        end

      {:ok, binding_health_snapshot(scope, runtime_scope, actor_id, capability_posture, bindings)}
    end)
  end

  defp with_repo_runtime_scope(actor_id, params, fun)
       when is_binary(actor_id) and is_map(params) and is_function(fun, 3) do
    with_runtime_scope(actor_id, params, fn scope, runtime_scope, status ->
      with :ok <- ensure_runtime_service_available(status),
           {:ok, result} <- fun.(scope, runtime_scope, status) do
        {:ok, result}
      end
    end)
  end

  defp with_runtime_scope(actor_id, params, fun)
       when is_binary(actor_id) and is_map(params) and is_function(fun, 3) do
    with {:ok, scope} <- resolve_repo_scope(params),
         {:ok, runtime_scope} <- build_runtime_scope(scope, params),
         runtime_context <- RuntimeGateway.context_for(actor_id, runtime_scope.attrs),
         runtime_scope <- Map.put(runtime_scope, :context, runtime_context),
         {:ok, status} <- runtime_service_status(actor_id, runtime_scope.attrs),
         {:ok, result} <- fun.(scope, runtime_scope, status) do
      {:ok, result}
    end
  end

  defp ensure_runtime_service_available(%{available?: true}), do: :ok

  defp ensure_runtime_service_available(%{} = status) do
    {:error, {:runtime_service_unavailable, status}}
  end

  defp resolve_repo_scope(params) do
    case scope_identifier(params) do
      nil ->
        {:error, :missing_repo_identifier}

      identifier ->
        RepoBridge.repo_scope(identifier)
    end
  end

  defp build_runtime_scope(scope, params) when is_map(scope) and is_map(params) do
    runtime_project_id =
      normalize_optional_string(Map.get(scope, :project_id) || Map.get(scope, "project_id")) ||
        normalize_optional_string(Map.get(scope, :managed_repo_id) || Map.get(scope, "managed_repo_id"))

    workspace_id = workspace_id(scope, params)

    if is_binary(runtime_project_id) do
      {:ok,
       %{
         runtime_project_id: runtime_project_id,
         workspace_id: workspace_id,
         attrs:
           compact_nil_values(%{
             project_id: runtime_project_id,
             workspace_id: workspace_id,
             request_id: get_string(params, :request_id),
             correlation_id: get_string(params, :correlation_id)
           })
       }}
    else
      {:error, :missing_runtime_project_id}
    end
  end

  defp install_payload(params, runtime_scope) do
    %{
      project_id: runtime_scope.runtime_project_id,
      provider: get_string(params, :provider),
      binding_alias: get_string(params, :binding_alias),
      redirect_uri: get_string(params, :redirect_uri),
      metadata: get_map(params, :metadata)
    }
    |> compact_nil_values()
  end

  defp complete_install_payload(params, runtime_scope) do
    %{
      project_id: runtime_scope.runtime_project_id,
      provider: get_string(params, :provider),
      install_id: get_string(params, :install_id),
      authorization_code: get_string(params, :authorization_code),
      metadata: get_map(params, :metadata)
    }
    |> compact_nil_values()
  end

  defp binding_payload(params, runtime_scope) do
    %{
      project_id: runtime_scope.runtime_project_id,
      provider: get_string(params, :provider),
      binding: binding_selector(params),
      metadata: get_map(params, :metadata)
    }
    |> compact_nil_values()
  end

  defp operation_list_payload(params, runtime_scope) do
    %{
      project_id: runtime_scope.runtime_project_id,
      provider: get_string(params, :provider),
      metadata: get_map(params, :metadata)
    }
    |> compact_nil_values()
  end

  defp invocation_payload(params, runtime_scope) do
    %{
      project_id: runtime_scope.runtime_project_id,
      operation: normalize_operation(params),
      input: get_map(params, :input),
      options: get_map(params, :options),
      metadata: get_map(params, :metadata)
    }
    |> compact_nil_values()
  end

  defp binding_selector(params) do
    %{
      binding_id: get_string(params, :binding_id),
      binding_alias: get_string(params, :binding_alias),
      use_default: truthy?(Map.get(params, :use_default) || Map.get(params, "use_default"))
    }
    |> compact_nil_values()
    |> case do
      empty when empty == %{} -> nil
      selector -> selector
    end
  end

  defp normalize_operation(params) do
    operation = get_map(params, :operation)

    %{
      provider: get_string(operation, :provider) || get_string(params, :provider),
      operation_id: get_string(operation, :operation_id),
      version: get_string(operation, :version),
      binding:
        operation
        |> get_map(:binding)
        |> case do
          %{} = binding when map_size(binding) > 0 -> binding
          _other -> binding_selector(params)
        end
    }
    |> compact_nil_values()
  end

  defp normalize_gateway_result({:ok, result}, normalizer) when is_function(normalizer, 1) do
    {:ok, normalizer.(result)}
  end

  defp normalize_gateway_result({:error, _reason} = error, _normalizer), do: error

  defp normalize_install_session(install_session, scope, actor_id, runtime_scope) do
    install_session
    |> sanitize_nested_map()
    |> Map.drop([:project_id, "project_id"])
    |> Map.put(:managed_repo_id, scope.managed_repo_id)
    |> Map.put(:legacy_project_id, scope.project_id)
    |> Map.put(:runtime_project_id, runtime_scope.runtime_project_id)
    |> Map.put(:route_id, scope.route_id)
    |> Map.put(:context, gateway_context(actor_id, runtime_scope))
  end

  defp normalize_binding(binding, scope, actor_id, runtime_scope) do
    binding
    |> sanitize_nested_map()
    |> Map.drop([:project_id, "project_id"])
    |> Map.put(:managed_repo_id, scope.managed_repo_id)
    |> Map.put(:legacy_project_id, scope.project_id)
    |> Map.put(:runtime_project_id, runtime_scope.runtime_project_id)
    |> Map.put(:route_id, scope.route_id)
    |> Map.put(:context, gateway_context(actor_id, runtime_scope))
  end

  defp normalize_operation_descriptor(operation) do
    operation = sanitize_nested_map(operation)

    %{
      provider: map_get(operation, :provider, "provider"),
      operation_id: map_get(operation, :operation_id, "operation_id"),
      display_name: map_get(operation, :display_name, "display_name"),
      runtime_class: map_get(operation, :runtime_class, "runtime_class"),
      required_scopes: map_get(operation, :required_scopes, "required_scopes", []),
      input_schema: map_get(operation, :input_schema, "input_schema", %{}),
      output_schema: map_get(operation, :output_schema, "output_schema", %{}),
      metadata: map_get(operation, :metadata, "metadata", %{})
    }
    |> compact_nil_values()
  end

  defp normalize_invocation_result(invocation_result, scope, actor_id, runtime_scope) do
    invocation_result = sanitize_nested_map(invocation_result)

    %{
      managed_repo_id: scope.managed_repo_id,
      legacy_project_id: scope.project_id,
      runtime_project_id: runtime_scope.runtime_project_id,
      route_id: scope.route_id,
      context: gateway_context(actor_id, runtime_scope),
      project_binding: normalize_binding_ref(map_get(invocation_result, :project_binding, "project_binding", %{})),
      operation: normalize_operation_ref(map_get(invocation_result, :operation, "operation", %{})),
      output: map_get(invocation_result, :output, "output", %{}),
      auth_state: normalize_auth_state(map_get(invocation_result, :auth_state, "auth_state", %{})),
      evidence_ref: normalize_evidence_ref(map_get(invocation_result, :evidence_ref, "evidence_ref", %{})),
      metadata: map_get(invocation_result, :metadata, "metadata", %{})
    }
    |> compact_nil_values()
  end

  defp normalize_binding_ref(binding) do
    %{
      binding_id: map_get(binding, :binding_id, "binding_id"),
      binding_alias: map_get(binding, :binding_alias, "binding_alias"),
      provider: map_get(binding, :provider, "provider"),
      status: map_get(binding, :status, "status"),
      is_default: map_get(binding, :is_default, "is_default"),
      install_state: map_get(binding, :install_state, "install_state"),
      metadata: map_get(binding, :metadata, "metadata", %{})
    }
    |> compact_nil_values()
  end

  defp normalize_operation_ref(operation) do
    %{
      provider: map_get(operation, :provider, "provider"),
      operation_id: map_get(operation, :operation_id, "operation_id"),
      version: map_get(operation, :version, "version"),
      binding: map_get(operation, :binding, "binding", %{})
    }
    |> compact_nil_values()
  end

  defp normalize_auth_state(auth_state) do
    %{
      status: map_get(auth_state, :status, "status"),
      reason_code: map_get(auth_state, :reason_code, "reason_code"),
      metadata: map_get(auth_state, :metadata, "metadata", %{})
    }
    |> compact_nil_values()
  end

  defp normalize_evidence_ref(evidence_ref) do
    %{
      evidence_id: map_get(evidence_ref, :evidence_id, "evidence_id"),
      event_ref: map_get(evidence_ref, :event_ref, "event_ref"),
      correlation_id: map_get(evidence_ref, :correlation_id, "correlation_id")
    }
    |> compact_nil_values()
  end

  defp binding_health_snapshot(scope, runtime_scope, actor_id, capability_posture, bindings) do
    providers =
      bindings
      |> Enum.group_by(& &1.provider)
      |> Enum.map(fn {provider, provider_bindings} ->
        %{
          provider: provider,
          binding_count: length(provider_bindings),
          connected_binding_count: Enum.count(provider_bindings, &(&1.status == "connected")),
          default_binding_aliases:
            provider_bindings
            |> Enum.filter(&truthy?(&1.is_default))
            |> Enum.map(& &1.binding_alias),
          statuses: provider_bindings |> Enum.map(& &1.status) |> Enum.uniq() |> Enum.sort(),
          summary: provider_summary(provider, provider_bindings)
        }
      end)
      |> Enum.sort_by(& &1.provider)

    %{
      managed_repo_id: scope.managed_repo_id,
      legacy_project_id: scope.project_id,
      runtime_project_id: runtime_scope.runtime_project_id,
      route_id: scope.route_id,
      context: gateway_context(actor_id, runtime_scope),
      runtime_capability: capability_posture,
      status: binding_health_status(capability_posture, bindings),
      binding_count: length(bindings),
      connected_binding_count: Enum.count(bindings, &(&1.status == "connected")),
      default_binding_count: Enum.count(bindings, &truthy?(&1.is_default)),
      providers: providers,
      summary: binding_health_summary(capability_posture, providers, bindings)
    }
  end

  defp unavailable_capability_posture(status) do
    %{
      service_key: runtime_service_key(),
      status: status.status,
      rollout_source: "repo_local_compatibility_surface",
      denial_reason: status.reason_code,
      degraded_path_evidence: %{
        runtime_status: status.runtime_status,
        dependency_status: status.dependency_status,
        child_spec_ready: status.child_spec_ready,
        reason_code: status.reason_code
      },
      available?: status.available?,
      ready?: status.ready?,
      admitted?: status.admitted?,
      governance_effect:
        if(status.status in ["unavailable", "withheld", "denied"], do: "blocked", else: "review_required"),
      summary: "Runtime service #{status.service_key} is #{status.status} for integration work."
    }
  end

  defp binding_health_status(%{status: status}, _bindings)
       when status in ["unavailable", "withheld", "denied"] do
    "blocked"
  end

  defp binding_health_status(_capability_posture, bindings) do
    cond do
      bindings == [] -> "needs_binding"
      Enum.any?(bindings, &(&1.status == "connected")) -> "ready"
      true -> "degraded"
    end
  end

  defp binding_health_summary(capability_posture, providers, bindings) do
    cond do
      capability_posture.status in ["unavailable", "withheld", "denied"] ->
        capability_posture.summary

      bindings == [] ->
        "Integration runtime is available, but no project bindings are connected yet."

      true ->
        provider_summary =
          providers
          |> Enum.map(& &1.summary)
          |> Enum.join(" ")

        "Integration runtime is available. #{provider_summary}"
    end
  end

  defp provider_summary(provider, bindings) do
    connected_count = Enum.count(bindings, &(&1.status == "connected"))

    cond do
      connected_count > 0 ->
        "Provider #{provider} has #{connected_count} connected binding(s)."

      true ->
        "Provider #{provider} has no connected bindings."
    end
  end

  defp gateway_context(actor_id, runtime_scope) do
    compact_nil_values(%{
      actor_id: actor_id || get_string(runtime_scope.context, :actor_id),
      request_id: get_string(runtime_scope.context, :request_id),
      correlation_id: get_string(runtime_scope.context, :correlation_id),
      workspace_id: runtime_scope.workspace_id
    })
  end

  defp workspace_id(scope, params) do
    get_string(params, :workspace_id) ||
      scope
      |> map_get(:managed_repo, "managed_repo", %{})
      |> map_get(:workspace_settings, "workspace_settings", %{})
      |> map_get(:workspace_path, "workspace_path") ||
      scope
      |> map_get(:project, "project", %{})
      |> map_get(:settings, "settings", %{})
      |> get_in_workspace_path()
  end

  defp get_in_workspace_path(settings) when is_map(settings) do
    settings
    |> map_get(:workspace, "workspace", %{})
    |> map_get(:workspace_path, "workspace_path")
    |> normalize_optional_string()
  end

  defp get_in_workspace_path(_settings), do: nil

  defp scope_identifier(params) when is_map(params) do
    get_string(params, :managed_repo_id) ||
      get_string(params, :project_id) ||
      get_string(params, :repo_id) ||
      get_string(params, :route_id) ||
      get_string(params, :id)
  end

  defp sanitize_nested_map(%_{} = value) do
    value
    |> Map.from_struct()
    |> sanitize_nested_map()
  end

  defp sanitize_nested_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_value =
        cond do
          is_map(nested_value) -> sanitize_nested_map(nested_value)
          is_list(nested_value) -> Enum.map(nested_value, &sanitize_nested_item/1)
          true -> nested_value
        end

      case key do
        :connection_id -> acc
        "connection_id" -> acc
        :connector_id -> acc
        "connector_id" -> acc
        :credential_lease_handle -> acc
        "credential_lease_handle" -> acc
        :lease_handle -> acc
        "lease_handle" -> acc
        _other -> Map.put(acc, key, normalized_value)
      end
    end)
  end

  defp sanitize_nested_map(value), do: value

  defp sanitize_nested_item(%{} = value), do: sanitize_nested_map(value)
  defp sanitize_nested_item(value), do: value

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(%{} = map, atom_key, string_key, default) do
    case Map.fetch(map, atom_key) do
      {:ok, value} -> value
      :error -> Map.get(map, string_key, default)
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp get_map(map, key) when is_map(map) do
    case Map.get(map, key) || Map.get(map, Atom.to_string(key)) do
      %{} = value -> value
      _other -> %{}
    end
  end

  defp get_map(_map, _key), do: %{}

  defp get_string(map, key) when is_map(map) do
    case Map.get(map, key) || Map.get(map, Atom.to_string(key)) do
      nil ->
        nil

      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          normalized -> normalized
        end

      value when is_atom(value) ->
        value
        |> Atom.to_string()
        |> String.trim()
        |> case do
          "" -> nil
          normalized -> normalized
        end

      value when is_integer(value) ->
        Integer.to_string(value)

      _other ->
        nil
    end
  end

  defp get_string(_map, _key), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil

  defp compact_nil_values(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc -> acc
      {_key, value}, acc when is_map(value) and map_size(value) == 0 -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp truthy?(value) when value in [true, "true", 1, "1"], do: true
  defp truthy?(_value), do: false
end
