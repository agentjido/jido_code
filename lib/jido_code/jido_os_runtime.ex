defmodule JidoCode.JidoOsRuntime do
  # covers: coding_assistance.boundary.runtime_bootstrap_defaults
  # covers: architecture.runtime_service_overlay.optional_runtime_capabilities_are_explicit_and_typed
  # covers: architecture.jido_os_session_turn_runtime.public_turn_live_subscription_surface
  # covers: architecture.jido_os_session_turn_runtime.fail_closed_on_scope_or_policy_violation
  # covers: architecture.policy_layers.runtime_policy_governs_session_and_turn_capability
  # covers: architecture.policy_layers.policy_layers_interlock_without_collapsing
  @moduledoc """
  Helpers for bootstrapping and accessing the embedded `jido_os` runtime.

  The helper keeps `jido_os` instance startup, runtime context construction,
  and development/test-only default seeding behind one product-local boundary.
  """

  alias Jido.Os.AI.Runtime, as: AIRuntime
  alias Jido.Os.CodingAssist.Service, as: CodingAssistService
  alias Jido.Os.Policy.Runtime, as: PolicyRuntime
  alias Jido.Os.Scope.Registry, as: ScopeRegistry
  alias Jido.Os.SystemInstanceSupervisor
  alias Jido.Os.SystemInstanceSupervisor.Instance

  @default_instance_id "jido_code_default"
  @default_coding_capabilities [
    "analyze",
    "plan",
    "implement",
    "review",
    "refactor",
    "explain",
    "onboard"
  ]
  @default_allowed_actions [
    "ai_model_catalog_discover",
    "ai_strategy_discover",
    "ai_strategy_execute",
    "coding_assist_ai_strategy_delegate",
    "coding_assist_capability_use",
    "coding_assist_execute",
    "coding_assist_operation_profile_use",
    "prompt_read",
    "prompt_render",
    "scope_registry_register",
    "session_ai_preferences_get",
    "session_ai_preferences_update"
  ]
  @wait_attempts 100
  @wait_interval_ms 25
  @seed_defaults_enabled Application.compile_env(:jido_code, :runtime_mode, :prod) in [:dev, :test]
  @known_runtime_services %{"coding_assistance_service" => CodingAssistService}
  @service_status_override_keys %{
    "status" => :status,
    "admitted?" => :admitted?,
    "available?" => :available?,
    "ready?" => :ready?,
    "child_spec_ready" => :child_spec_ready,
    "runtime_status" => :runtime_status,
    "dependency_status" => :dependency_status,
    "extension_admission" => :extension_admission,
    "registration_epoch" => :registration_epoch,
    "reason_code" => :reason_code
  }
  @extension_admission_override_keys %{"enabled" => :enabled, "reason_code" => :reason_code}

  def instance_id do
    Application.get_env(:jido_code, :jido_os_instance_id, @default_instance_id)
  end

  def ensure_instance do
    configure_managed_service_opts()

    with {:ok, _apps} <- Application.ensure_all_started(:jido_os),
         {:ok, _instance_id} <- ensure_instance_started(instance_id()) do
      :ok
    end
  end

  def context_for(actor_id, attrs \\ %{}) when is_binary(actor_id) do
    %{
      instance_id: instance_id(),
      actor_id: actor_id,
      request_id: get_string(attrs, :request_id) || unique_id("req"),
      correlation_id: get_string(attrs, :correlation_id) || unique_id("corr"),
      session_id: get_string(attrs, :session_id),
      project_id: get_string(attrs, :project_id),
      workspace_id: get_string(attrs, :workspace_id)
    }
  end

  def instance_status do
    instance_id = instance_id()
    started? = match?({:ok, _pid}, SystemInstanceSupervisor.lookup_instance(instance_id))
    ready? = started? and Instance.ready?(instance_id)

    %{
      instance_id: instance_id,
      started?: started?,
      ready?: ready?,
      status: instance_runtime_status(started?, ready?)
    }
  end

  def instance_ready? do
    instance_status().ready?
  end

  def runtime_service_key(service_ref) do
    case resolve_runtime_service_key(service_ref) do
      {:ok, service_key} ->
        service_key

      {:error, {:runtime_service_key_unsupported, ref}} ->
        raise ArgumentError,
              "runtime service reference must be a service key or module exporting runtime_service_key/0, got: #{inspect(ref)}"

      {:error, {:runtime_service_key_invalid, ref}} ->
        raise ArgumentError,
              "runtime service reference must resolve to a non-empty service key, got: #{inspect(ref)}"
    end
  end

  def service_status(service_ref, actor_id, attrs \\ %{})
      when is_binary(actor_id) and is_map(attrs) do
    with {:ok, service} <- resolve_runtime_service(service_ref),
         :ok <- ensure_instance() do
      _context = context_for(actor_id, attrs)
      {:ok, normalize_service_status(service, instance_status()) |> apply_test_service_status_override()}
    else
      {:error, {:runtime_service_unknown, service_key}} ->
        {:ok, unavailable_service_status(service_key, "runtime_service_unknown")}
    end
  end

  def service_available?(service_ref, actor_id, attrs \\ %{})
      when is_binary(actor_id) and is_map(attrs) do
    with {:ok, status} <- service_status(service_ref, actor_id, attrs) do
      {:ok, status.available?}
    end
  end

  defp ensure_instance_started(instance_id) do
    context = bootstrap_context(instance_id)

    {result, started_new?} =
      case SystemInstanceSupervisor.lookup_instance(instance_id) do
        {:ok, _pid} ->
          result =
            if wait_until(fn -> Instance.ready?(instance_id) end),
              do: :ok,
              else: {:error, :instance_not_ready}

          {result, false}

        :error ->
          case SystemInstanceSupervisor.start_instance(instance_id, context) do
            {:ok, _pid} ->
              result =
                if wait_until(fn -> Instance.ready?(instance_id) end),
                  do: :ok,
                  else: {:error, :instance_not_ready}

              {result, true}

            {:error, {:already_started, _pid}} ->
              result =
                if wait_until(fn -> Instance.ready?(instance_id) end),
                  do: :ok,
                  else: {:error, :instance_not_ready}

              {result, false}

            {:error, reason} ->
              {{:error, reason}, false}
          end
      end

    case result do
      :ok ->
        if started_new? and seed_defaults_enabled?() do
          seed_default_policies(instance_id, context)
          seed_default_capabilities(instance_id, context)
        end

        {:ok, instance_id}

      other ->
        other
    end
  end

  defp configure_managed_service_opts do
    existing = Application.get_env(:jido_os, :managed_service_opts, %{})

    if Map.has_key?(existing, AIRuntime) or Map.has_key?(existing, Jido.Os.AI.AdapterService) do
      :ok
    else
      Application.put_env(
        :jido_os,
        :managed_service_opts,
        Map.put(existing, AIRuntime, default_ai_runtime_opts())
      )
    end
  end

  defp default_ai_runtime_opts do
    [
      model_provider_descriptors: [
        %{provider_key: "anthropic", display_name: "Anthropic", status: "active"},
        %{provider_key: "openai", display_name: "OpenAI", status: "active"}
      ],
      model_descriptors: [
        %{
          provider_key: "anthropic",
          model_key: "claude-3-7-sonnet",
          display_name: "Claude 3.7 Sonnet",
          lifecycle_status: "active",
          supports_streaming: true,
          supports_tool_calling: true,
          supports_structured_output: true
        },
        %{
          provider_key: "openai",
          model_key: "gpt-5",
          display_name: "GPT-5",
          lifecycle_status: "active",
          supports_streaming: true,
          supports_tool_calling: true,
          supports_structured_output: true
        },
        %{
          provider_key: "openai",
          model_key: "gpt-5-mini",
          display_name: "GPT-5 Mini",
          lifecycle_status: "active",
          supports_streaming: true,
          supports_tool_calling: true,
          supports_structured_output: true
        }
      ],
      model_profile_bindings: [
        %{model_profile: "balanced", provider_key: "openai", model_key: "gpt-5"},
        %{model_profile: "fast", provider_key: "openai", model_key: "gpt-5-mini"},
        %{model_profile: "deep", provider_key: "anthropic", model_key: "claude-3-7-sonnet"}
      ],
      adapter_default_model_profiles: %{strategy: %{"adaptive" => "balanced"}}
    ]
  end

  defp seed_default_policies(instance_id, context) do
    Enum.each(@default_allowed_actions, fn action ->
      _ =
        PolicyRuntime.set_policy(
          instance_id,
          "instance",
          %{
            effect: "allow",
            action: action,
            resource: "*",
            reason_code: "jido_code_default_allow_#{action}"
          },
          context
        )
    end)
  end

  defp seed_default_capabilities(instance_id, context) do
    Enum.each(@default_coding_capabilities, fn capability ->
      _ =
        ScopeRegistry.register_asset(
          instance_id,
          "skill",
          %{
            canonical_name: capability,
            version: "1.0.0",
            scope_kind: "instance",
            scope_id: instance_id,
            source: "jido_code.seed.#{capability}"
          },
          context
        )
    end)
  end

  defp seed_defaults_enabled? do
    @seed_defaults_enabled
  end

  defp bootstrap_context(instance_id) do
    %{
      instance_id: instance_id,
      actor_id: "system:jido_code",
      request_id: unique_id("req"),
      correlation_id: unique_id("corr")
    }
  end

  defp resolve_runtime_service_key(service_ref) when is_binary(service_ref) and service_ref != "" do
    {:ok, service_ref}
  end

  defp resolve_runtime_service_key(service_ref) when is_atom(service_ref) do
    if match?({:module, _module}, Code.ensure_compiled(service_ref)) and
         function_exported?(service_ref, :runtime_service_key, 0) do
      service_key = service_ref.runtime_service_key()

      if is_binary(service_key) and service_key != "" do
        {:ok, service_key}
      else
        {:error, {:runtime_service_key_invalid, service_ref}}
      end
    else
      {:error, {:runtime_service_key_unsupported, service_ref}}
    end
  end

  defp resolve_runtime_service_key(service_ref),
    do: {:error, {:runtime_service_key_unsupported, service_ref}}

  defp resolve_runtime_service(service_ref) do
    with {:ok, service_key} <- resolve_runtime_service_key(service_ref) do
      case resolve_runtime_service_module(service_ref, service_key) do
        {:ok, service_module} ->
          {:ok,
           %{
             service_key: service_key,
             service_module: service_module,
             admitted?: true
           }}

        :error ->
          {:error, {:runtime_service_unknown, service_key}}
      end
    end
  end

  defp resolve_runtime_service_module(service_ref, _service_key) when is_atom(service_ref) do
    cond do
      match?({:module, _module}, Code.ensure_compiled(service_ref)) and
          function_exported?(service_ref, :runtime_service_module, 0) ->
        {:ok, service_ref.runtime_service_module()}

      match?({:module, _module}, Code.ensure_compiled(service_ref)) and
          function_exported?(service_ref, :runtime_service_key, 0) ->
        {:ok, service_ref}

      true ->
        :error
    end
  end

  defp resolve_runtime_service_module(_service_ref, service_key) do
    case Map.fetch(@known_runtime_services, service_key) do
      {:ok, service_module} -> {:ok, service_module}
      :error -> :error
    end
  end

  defp normalize_service_status(service, instance_status) do
    child_spec_ready = runtime_service_module_ready?(service.service_module)
    available? = child_spec_ready and instance_status.ready?
    ready? = available?
    runtime_status = runtime_service_runtime_status(instance_status, child_spec_ready)
    dependency_status = runtime_service_dependency_status(child_spec_ready)
    extension_admission = %{enabled: service.admitted?, reason_code: nil}

    %{
      service_key: service.service_key,
      status: runtime_service_status(instance_status.status, available?),
      admitted?: service.admitted?,
      available?: available?,
      ready?: ready?,
      child_spec_ready: child_spec_ready,
      runtime_status: runtime_status,
      dependency_status: dependency_status,
      extension_admission: extension_admission,
      registration_epoch: nil,
      reason_code: nil
    }
  end

  defp unavailable_service_status(service_key, reason_code) do
    %{
      service_key: service_key,
      status: "unavailable",
      admitted?: false,
      available?: false,
      ready?: false,
      child_spec_ready: false,
      runtime_status: "missing",
      dependency_status: "unknown",
      extension_admission: %{enabled: false, reason_code: reason_code},
      registration_epoch: nil,
      reason_code: reason_code
    }
  end

  defp apply_test_service_status_override(%{service_key: service_key} = status) do
    case runtime_service_status_override(service_key) do
      %{} = override when @seed_defaults_enabled ->
        merge_service_status_override(status, override)

      _other ->
        status
    end
  end

  defp merge_service_status_override(status, override) do
    normalized_override = normalize_override_map(override)

    extension_admission =
      Map.merge(
        status.extension_admission || %{},
        Map.get(normalized_override, :extension_admission, %{})
      )

    status
    |> Map.merge(Map.drop(normalized_override, [:extension_admission]))
    |> Map.put(:extension_admission, extension_admission)
  end

  defp normalize_override_map(%{} = override) do
    Enum.reduce(override, %{}, fn {key, value}, acc ->
      case normalize_override_key(key, @service_status_override_keys) do
        nil ->
          acc

        normalized_key ->
          normalized_value =
            cond do
              normalized_key == :extension_admission and is_map(value) ->
                normalize_extension_admission_override(value)

              true ->
                value
            end

          Map.put(acc, normalized_key, normalized_value)
      end
    end)
  end

  defp runtime_service_status_override(service_key) when is_binary(service_key) do
    overrides =
      Application.get_env(:jido_code, :runtime_service_status_overrides, %{})
      |> normalize_runtime_service_status_overrides()

    Map.get(overrides, service_key)
  end

  defp normalize_runtime_service_status_overrides(overrides) when is_map(overrides) do
    Enum.reduce(overrides, %{}, fn {key, value}, acc ->
      case normalize_override_lookup_key(key) do
        nil -> acc
        normalized_key -> Map.put(acc, normalized_key, value)
      end
    end)
  end

  defp normalize_runtime_service_status_overrides(_overrides), do: %{}

  defp normalize_extension_admission_override(override) when is_map(override) do
    Enum.reduce(override, %{}, fn {key, value}, acc ->
      case normalize_override_key(key, @extension_admission_override_keys) do
        nil -> acc
        normalized_key -> Map.put(acc, normalized_key, value)
      end
    end)
  end

  defp normalize_override_key(key, lookup) when is_atom(key) do
    key
    |> Atom.to_string()
    |> then(&Map.get(lookup, &1))
  end

  defp normalize_override_key(key, lookup) when is_binary(key), do: Map.get(lookup, key)
  defp normalize_override_key(_key, _lookup), do: nil

  defp normalize_override_lookup_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_override_lookup_key(key) when is_binary(key) and key != "", do: key
  defp normalize_override_lookup_key(_key), do: nil

  defp runtime_service_module_ready?(service_module) do
    match?({:module, _module}, Code.ensure_compiled(service_module)) and
      function_exported?(service_module, :assist, 3) and
      function_exported?(service_module, :start_turn, 3) and
      function_exported?(service_module, :subscribe_turn_events, 3) and
      function_exported?(service_module, :unsubscribe_turn_events, 3)
  end

  defp runtime_service_runtime_status(%{status: "ready"}, true), do: "running"
  defp runtime_service_runtime_status(%{status: "starting"}, true), do: "starting"
  defp runtime_service_runtime_status(_instance_status, true), do: "stopped"
  defp runtime_service_runtime_status(_instance_status, false), do: "missing"

  defp runtime_service_dependency_status(true), do: "satisfied"
  defp runtime_service_dependency_status(false), do: "unknown"

  defp runtime_service_status("ready", true), do: "available"
  defp runtime_service_status("starting", false), do: "starting"
  defp runtime_service_status(_instance_status, _available), do: "unavailable"

  defp instance_runtime_status(true, true), do: "ready"
  defp instance_runtime_status(true, false), do: "starting"
  defp instance_runtime_status(false, _ready), do: "stopped"

  defp wait_until(fun, attempts_left \\ @wait_attempts)

  defp wait_until(_fun, 0), do: false

  defp wait_until(fun, attempts_left) do
    if fun.() do
      true
    else
      Process.sleep(@wait_interval_ms)
      wait_until(fun, attempts_left - 1)
    end
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp get_string(map, key) when is_map(map) do
    value = Map.get(map, key) || Map.get(map, Atom.to_string(key))

    if is_binary(value) and value != "", do: value, else: nil
  end

  defp get_string(_map, _key), do: nil
end
