defmodule JidoCode.JidoOsRuntime do
  # covers: coding_assistance.boundary.runtime_bootstrap_defaults
  @moduledoc """
  Helpers for bootstrapping and accessing the embedded `jido_os` runtime.

  The helper keeps `jido_os` instance startup, runtime context construction,
  and development/test-only default seeding behind one product-local boundary.
  """

  alias Jido.Os.AI.Runtime, as: AIRuntime
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
