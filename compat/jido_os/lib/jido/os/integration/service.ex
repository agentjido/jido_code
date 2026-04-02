defmodule Jido.Os.Integration.Service do
  @moduledoc false
  @runtime_service_key "integration_service"

  alias Jido.Os.Integration.Model
  alias Jido.Os.State

  @supported_operation_ids MapSet.new(
                             Enum.flat_map(Model.supported_providers(), fn provider ->
                               provider
                               |> Model.provider_operation_descriptors()
                               |> Enum.map(&Map.get(&1, "operation_id"))
                             end)
                           )

  def runtime_service_key, do: @runtime_service_key

  def supported_providers, do: Model.supported_providers()
  def supported_binding_statuses, do: Model.supported_binding_statuses()
  def supported_install_states, do: Model.supported_install_states()
  def supported_operation_runtime_classes, do: Model.supported_operation_runtime_classes()

  def begin_install(instance_id, payload, context)
      when is_binary(instance_id) and is_map(payload) and is_map(context) do
    with {:ok, service_context} <- normalize_service_context(payload, context),
         provider when is_binary(provider) <- normalize_provider(payload),
         project_id <- service_context.project_id do
      install_id = unique_id("install")

      install_session =
        %{
          install_id: install_id,
          project_id: project_id,
          provider: provider,
          binding_alias: binding_alias(payload, provider),
          authorization_url: authorization_url(provider, install_id),
          redirect_uri: get_string(payload, :redirect_uri),
          expires_at: timestamp_in(15 * 60),
          metadata: sanitize_metadata(Map.get(payload, :metadata) || Map.get(payload, "metadata")),
          actor_id: service_context.actor_id
        }
        |> compact_nil_values()

      State.put_integration_install_session(instance_id, install_id, install_session)
      {:ok, Model.normalize_install_session(install_session)}
    else
      {:error, _reason} = error -> error
      nil -> {:error, :unsupported_provider}
    end
  end

  def complete_install(instance_id, payload, context)
      when is_binary(instance_id) and is_map(payload) and is_map(context) do
    with {:ok, service_context} <- normalize_service_context(payload, context),
         install_id when is_binary(install_id) <- get_string(payload, :install_id),
         %{} = install_session <- State.get_integration_install_session(instance_id, install_id),
         :ok <- validate_install_completion(payload, install_session, service_context.project_id) do
      binding_id = unique_id("binding")
      existing_bindings = State.list_integration_project_bindings(instance_id, service_context.project_id)
      provider = Map.get(install_session, :provider)

      binding =
        %{
          binding_id: binding_id,
          project_id: service_context.project_id,
          provider: provider,
          binding_alias: Map.get(install_session, :binding_alias),
          status: "connected",
          is_default: no_default_binding?(existing_bindings, provider),
          install_state: "authorization_completed",
          metadata:
            payload
            |> Map.get(:metadata, Map.get(payload, "metadata", %{}))
            |> sanitize_metadata()
            |> Map.put_new("install_id", install_id)
        }

      State.put_integration_project_binding(
        instance_id,
        service_context.project_id,
        binding_id,
        binding
      )

      {:ok, Model.normalize_project_binding(binding)}
    else
      {:error, _reason} = error -> error
      nil -> {:error, :missing_install_id}
      _other -> {:error, :install_session_not_found}
    end
  end

  def list_project_bindings(instance_id, payload, context)
      when is_binary(instance_id) and is_map(payload) and is_map(context) do
    with {:ok, service_context} <- normalize_service_context(payload, context) do
      bindings =
        instance_id
        |> State.list_integration_project_bindings(service_context.project_id)
        |> filter_provider(normalize_optional_provider(payload))
        |> Enum.map(&Model.normalize_project_binding/1)

      {:ok, bindings}
    end
  end

  def get_project_binding(instance_id, payload, context)
      when is_binary(instance_id) and is_map(payload) and is_map(context) do
    with {:ok, service_context} <- normalize_service_context(payload, context),
         {:ok, binding} <- resolve_binding(instance_id, payload, service_context.project_id, :read) do
      {:ok, Model.normalize_project_binding(binding)}
    end
  end

  def set_default_project_binding(instance_id, payload, context)
      when is_binary(instance_id) and is_map(payload) and is_map(context) do
    with {:ok, service_context} <- normalize_service_context(payload, context),
         {:ok, binding} <- resolve_binding(instance_id, payload, service_context.project_id, :write),
         "connected" <- Map.get(binding, :status) || Map.get(binding, "status") || {:error, :binding_not_connected},
         :ok <- clear_provider_defaults(instance_id, service_context.project_id, Map.get(binding, :provider)),
         {:ok, updated_binding} <-
           State.update_integration_project_binding(
             instance_id,
             service_context.project_id,
             Map.get(binding, :binding_id),
             &Map.put(&1, :is_default, true)
           ) do
      {:ok, Model.normalize_project_binding(updated_binding)}
    else
      {:error, _reason} = error -> error
      "revoked" -> {:error, :binding_not_connected}
      "error" -> {:error, :binding_not_connected}
      "pending_install" -> {:error, :binding_not_connected}
    end
  end

  def revoke_project_binding(instance_id, payload, context)
      when is_binary(instance_id) and is_map(payload) and is_map(context) do
    with {:ok, service_context} <- normalize_service_context(payload, context),
         {:ok, binding} <- resolve_binding(instance_id, payload, service_context.project_id, :write),
         {:ok, updated_binding} <-
           State.update_integration_project_binding(
             instance_id,
             service_context.project_id,
             Map.get(binding, :binding_id),
             fn stored ->
               stored
               |> Map.put(:status, "revoked")
               |> Map.put(:is_default, false)
             end
           ) do
      {:ok, Model.normalize_project_binding(updated_binding)}
    end
  end

  def list_provider_operations(instance_id, payload, context)
      when is_binary(instance_id) and is_map(payload) and is_map(context) do
    with {:ok, service_context} <- normalize_service_context(payload, context),
         _project_id <- service_context.project_id do
      provider = normalize_optional_provider(payload)

      operations =
        case provider do
          nil ->
            Model.supported_providers()
            |> Enum.flat_map(&Model.provider_operation_descriptors/1)

          normalized_provider ->
            Model.provider_operation_descriptors(normalized_provider)
        end

      {:ok, operations}
    end
  end

  def invoke_operation(instance_id, payload, context)
      when is_binary(instance_id) and is_map(payload) and is_map(context) do
    with {:ok, service_context} <- normalize_service_context(payload, context),
         {:ok, operation_ref} <- normalize_operation_ref(payload),
         :ok <- validate_operation(operation_ref),
         {:ok, binding} <-
           resolve_binding(
             instance_id,
             %{
               "project_id" => service_context.project_id,
               "provider" => operation_ref.provider,
               "binding" => operation_ref.binding
             },
             service_context.project_id,
             :invoke
           ),
         "connected" <- Map.get(binding, :status) || {:error, :binding_not_connected} do
      result =
        Model.normalize_invocation_result(%{
          project_binding: binding,
          operation: %{
            provider: operation_ref.provider,
            operation_id: operation_ref.operation_id,
            version: operation_ref.version,
            binding: operation_ref.binding
          },
          output: operation_output(operation_ref, payload),
          auth_state: %{status: "ok", reason_code: nil, metadata: %{}},
          evidence_ref: %{
            evidence_id: unique_id("evidence"),
            event_ref: "runtime.integration.#{unique_id("event")}",
            correlation_id: service_context.correlation_id
          },
          metadata:
            payload
            |> Map.get(:metadata, Map.get(payload, "metadata", %{}))
            |> sanitize_metadata()
        })

      {:ok, result}
    else
      {:error, _reason} = error -> error
      "revoked" -> {:error, :binding_not_connected}
      "error" -> {:error, :binding_not_connected}
      "pending_install" -> {:error, :binding_not_connected}
    end
  end

  defp normalize_service_context(payload, context) do
    actor_id = get_string(context, :actor_id)
    project_id = get_string(payload, :project_id) || get_string(context, :project_id)

    cond do
      not is_binary(actor_id) ->
        {:error, :missing_actor_id}

      not is_binary(project_id) ->
        {:error, :missing_project_id}

      true ->
        {:ok,
         %{
           actor_id: actor_id,
           project_id: project_id,
           request_id: get_string(context, :request_id),
           correlation_id: get_string(context, :correlation_id),
           workspace_id: get_string(context, :workspace_id)
         }}
    end
  end

  defp normalize_provider(payload) do
    payload
    |> normalize_optional_provider()
    |> case do
      nil -> nil
      provider -> provider
    end
  end

  defp normalize_optional_provider(payload) when is_map(payload) do
    payload
    |> Map.get(:provider, Map.get(payload, "provider"))
    |> Model.normalize_provider()
  end

  defp normalize_optional_provider(_payload), do: nil

  defp normalize_operation_ref(payload) do
    operation =
      payload
      |> Map.get(:operation, Map.get(payload, "operation", %{}))
      |> normalize_map()

    provider =
      operation
      |> Map.get("provider")
      |> Model.normalize_provider()

    operation_ref =
      Model.normalize_operation_ref(%{
        provider: provider,
        operation_id: Map.get(operation, "operation_id"),
        version: Map.get(operation, "version"),
        binding: Map.get(operation, "binding")
      })

    if is_binary(operation_ref.provider) and is_binary(operation_ref.operation_id) do
      {:ok, operation_ref}
    else
      {:error, :unsupported_operation}
    end
  end

  defp validate_operation(operation_ref) do
    cond do
      not is_binary(operation_ref.provider) ->
        {:error, :unsupported_provider}

      not MapSet.member?(@supported_operation_ids, operation_ref.operation_id) ->
        {:error, :unsupported_operation}

      true ->
        :ok
    end
  end

  defp validate_install_completion(payload, install_session, project_id) do
    payload_provider = normalize_optional_provider(payload)
    install_provider = Map.get(install_session, :provider)
    payload_project_id = get_string(payload, :project_id)

    cond do
      payload_project_id && payload_project_id != project_id ->
        {:error, :project_mismatch}

      payload_provider && payload_provider != install_provider ->
        {:error, :provider_mismatch}

      true ->
        :ok
    end
  end

  defp resolve_binding(instance_id, payload, project_id, mode) do
    selector =
      payload
      |> Map.get(:binding, Map.get(payload, "binding"))
      |> Model.normalize_binding_selector()

    provider = normalize_optional_provider(payload)

    bindings =
      instance_id
      |> State.list_integration_project_bindings(project_id)
      |> filter_provider(provider)

    cond do
      is_binary(selector.binding_id) ->
        find_single_binding(bindings, fn binding ->
          Map.get(binding, :binding_id) == selector.binding_id
        end)

      is_binary(selector.binding_alias) ->
        find_single_binding(bindings, fn binding ->
          Map.get(binding, :binding_alias) == selector.binding_alias
        end)

      selector.use_default or mode in [:invoke, :write] ->
        resolve_default_or_single_binding(bindings)

      true ->
        resolve_default_or_single_binding(bindings)
    end
  end

  defp find_single_binding(bindings, matcher) when is_list(bindings) and is_function(matcher, 1) do
    case Enum.filter(bindings, matcher) do
      [binding] -> {:ok, binding}
      [] -> {:error, :binding_not_found}
      _many -> {:error, :ambiguous_binding}
    end
  end

  defp resolve_default_or_single_binding(bindings) when is_list(bindings) do
    defaults = Enum.filter(bindings, &truthy?(Map.get(&1, :is_default)))

    cond do
      length(defaults) == 1 ->
        {:ok, hd(defaults)}

      bindings == [] ->
        {:error, :binding_not_found}

      length(bindings) == 1 ->
        {:ok, hd(bindings)}

      true ->
        {:error, :ambiguous_binding}
    end
  end

  defp clear_provider_defaults(instance_id, project_id, provider) do
    instance_id
    |> State.list_integration_project_bindings(project_id)
    |> filter_provider(provider)
    |> Enum.reduce_while(:ok, fn binding, :ok ->
      case State.update_integration_project_binding(
             instance_id,
             project_id,
             Map.get(binding, :binding_id),
             &Map.put(&1, :is_default, false)
           ) do
        {:ok, _updated} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp filter_provider(bindings, nil), do: bindings

  defp filter_provider(bindings, provider) do
    Enum.filter(bindings, fn binding ->
      Map.get(binding, :provider) == provider || Map.get(binding, "provider") == provider
    end)
  end

  defp operation_output(%{provider: "github", operation_id: "github.repositories.list"}, payload) do
    owner =
      get_string(payload, :owner) ||
        get_in(normalize_map(Map.get(payload, :input) || Map.get(payload, "input")), ["owner"])

    %{
      repositories: [
        compact_nil_values(%{
          owner: owner || "owner",
          name: "example-repo",
          full_name: "#{owner || "owner"}/example-repo"
        })
      ]
    }
  end

  defp operation_output(%{provider: "github", operation_id: "github.issues.create"}, payload) do
    input = normalize_map(Map.get(payload, :input) || Map.get(payload, "input"))

    %{
      issue: %{
        repository: Map.get(input, "repository"),
        title: Map.get(input, "title"),
        body: Map.get(input, "body"),
        issue_number: 1
      }
    }
  end

  defp operation_output(%{provider: "notion", operation_id: "notion.pages.create"}, payload) do
    input = normalize_map(Map.get(payload, :input) || Map.get(payload, "input"))

    %{
      page: %{
        parent_id: Map.get(input, "parent_id"),
        title: Map.get(input, "title"),
        page_id: unique_id("page")
      }
    }
  end

  defp operation_output(_operation_ref, payload) do
    %{
      result: normalize_map(Map.get(payload, :input) || Map.get(payload, "input"))
    }
  end

  defp binding_alias(payload, provider) do
    get_string(payload, :binding_alias) || "#{provider}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp authorization_url(provider, install_id) do
    "https://example.test/#{provider}/authorize?install_id=#{install_id}"
  end

  defp no_default_binding?(bindings, provider) do
    bindings
    |> filter_provider(provider)
    |> Enum.any?(&truthy?(Map.get(&1, :is_default) || Map.get(&1, "is_default")))
    |> Kernel.not()
  end

  defp sanitize_metadata(value) when is_map(value) do
    value
    |> normalize_map()
    |> Map.drop(["connection_id", "connector_id", "credential_lease_handle", "lease_handle"])
  end

  defp sanitize_metadata(_value), do: %{}

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
          is_map(nested_value) -> normalize_map(nested_value)
          is_list(nested_value) -> Enum.map(nested_value, &normalize_nested/1)
          true -> nested_value
        end

      Map.put(acc, normalized_key, normalized_value)
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested(value), do: value

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

  defp compact_nil_values(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp truthy?(value) when value in [true, "true", 1, "1"], do: true
  defp truthy?(_value), do: false

  defp timestamp_in(seconds) when is_integer(seconds) do
    DateTime.utc_now()
    |> DateTime.add(seconds, :second)
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
