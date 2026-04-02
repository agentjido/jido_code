defmodule Jido.Os.Integration.Model do
  @moduledoc false

  @providers ["github", "notion"]
  @binding_statuses ["pending_install", "connected", "revoked", "error"]
  @install_states ["authorization_pending", "authorization_completed", "expired"]
  @operation_runtime_classes ["direct"]
  @provider_operations %{
    "github" => [
      %{
        provider: "github",
        operation_id: "github.repositories.list",
        display_name: "List repositories",
        runtime_class: "direct",
        required_scopes: ["repo:read"],
        input_schema: %{"type" => "object", "properties" => %{"owner" => %{"type" => "string"}}},
        output_schema: %{"type" => "object", "properties" => %{"repositories" => %{"type" => "array"}}},
        metadata: %{}
      },
      %{
        provider: "github",
        operation_id: "github.issues.create",
        display_name: "Create issue",
        runtime_class: "direct",
        required_scopes: ["repo:write", "issues:write"],
        input_schema: %{
          "type" => "object",
          "properties" => %{
            "repository" => %{"type" => "string"},
            "title" => %{"type" => "string"},
            "body" => %{"type" => "string"}
          }
        },
        output_schema: %{"type" => "object", "properties" => %{"issue" => %{"type" => "object"}}},
        metadata: %{}
      }
    ],
    "notion" => [
      %{
        provider: "notion",
        operation_id: "notion.pages.create",
        display_name: "Create page",
        runtime_class: "direct",
        required_scopes: ["pages:write"],
        input_schema: %{
          "type" => "object",
          "properties" => %{
            "parent_id" => %{"type" => "string"},
            "title" => %{"type" => "string"}
          }
        },
        output_schema: %{"type" => "object", "properties" => %{"page" => %{"type" => "object"}}},
        metadata: %{}
      }
    ]
  }

  def supported_providers, do: @providers
  def supported_binding_statuses, do: @binding_statuses
  def supported_install_states, do: @install_states
  def supported_operation_runtime_classes, do: @operation_runtime_classes

  def provider_operation_descriptors(nil) do
    @provider_operations
    |> Map.values()
    |> List.flatten()
    |> Enum.map(&normalize_map/1)
  end

  def provider_operation_descriptors(provider) when is_binary(provider) do
    provider
    |> normalize_provider()
    |> case do
      nil -> []
      normalized_provider -> @provider_operations |> Map.get(normalized_provider, []) |> Enum.map(&normalize_map/1)
    end
  end

  def normalize_provider(provider) when is_binary(provider) do
    provider
    |> String.trim()
    |> String.downcase()
    |> case do
      value when value in @providers -> value
      _other -> nil
    end
  end

  def normalize_provider(provider) when is_atom(provider), do: provider |> Atom.to_string() |> normalize_provider()
  def normalize_provider(_provider), do: nil

  def normalize_binding_selector(selector) when is_map(selector) do
    %{
      binding_id: get_string(selector, :binding_id),
      binding_alias: get_string(selector, :binding_alias),
      use_default: truthy?(Map.get(selector, :use_default) || Map.get(selector, "use_default"))
    }
  end

  def normalize_binding_selector(_selector), do: %{binding_id: nil, binding_alias: nil, use_default: false}

  def normalize_project_binding(binding) when is_map(binding) do
    %{
      binding_id: get_string(binding, :binding_id) || "binding-unknown",
      project_id: get_string(binding, :project_id),
      provider: normalize_provider(Map.get(binding, :provider) || Map.get(binding, "provider")),
      binding_alias: get_string(binding, :binding_alias),
      status: normalize_binding_status(Map.get(binding, :status) || Map.get(binding, "status")),
      is_default: truthy?(Map.get(binding, :is_default) || Map.get(binding, "is_default")),
      install_state: normalize_install_state(Map.get(binding, :install_state) || Map.get(binding, "install_state")),
      metadata: normalize_map(Map.get(binding, :metadata) || Map.get(binding, "metadata"))
    }
  end

  def normalize_install_session(session) when is_map(session) do
    %{
      install_id: get_string(session, :install_id) || "install-unknown",
      project_id: get_string(session, :project_id),
      provider: normalize_provider(Map.get(session, :provider) || Map.get(session, "provider")),
      binding_alias: get_string(session, :binding_alias),
      authorization_url: get_string(session, :authorization_url),
      redirect_uri: get_string(session, :redirect_uri),
      expires_at: get_string(session, :expires_at),
      metadata: normalize_map(Map.get(session, :metadata) || Map.get(session, "metadata"))
    }
  end

  def normalize_operation_ref(operation) when is_map(operation) do
    %{
      provider: normalize_provider(Map.get(operation, :provider) || Map.get(operation, "provider")),
      operation_id: get_string(operation, :operation_id),
      version: get_string(operation, :version),
      binding: normalize_binding_selector(Map.get(operation, :binding) || Map.get(operation, "binding"))
    }
  end

  def normalize_auth_state(auth_state) when is_map(auth_state) do
    %{
      status:
        auth_state
        |> Map.get(:status, Map.get(auth_state, "status"))
        |> normalize_auth_status(),
      reason_code: get_string(auth_state, :reason_code),
      metadata: normalize_map(Map.get(auth_state, :metadata) || Map.get(auth_state, "metadata"))
    }
  end

  def normalize_auth_state(_auth_state), do: %{status: "unknown", reason_code: nil, metadata: %{}}

  def normalize_invocation_result(result) when is_map(result) do
    %{
      project_binding:
        result
        |> Map.get(:project_binding, Map.get(result, "project_binding", %{}))
        |> normalize_project_binding(),
      operation:
        result
        |> Map.get(:operation, Map.get(result, "operation", %{}))
        |> normalize_operation_ref(),
      output: normalize_map(Map.get(result, :output) || Map.get(result, "output")),
      auth_state:
        result
        |> Map.get(:auth_state, Map.get(result, "auth_state", %{}))
        |> normalize_auth_state(),
      evidence_ref: normalize_map(Map.get(result, :evidence_ref) || Map.get(result, "evidence_ref")),
      metadata: normalize_map(Map.get(result, :metadata) || Map.get(result, "metadata"))
    }
  end

  def normalize_invocation_result(_result) do
    %{
      project_binding: normalize_project_binding(%{}),
      operation: normalize_operation_ref(%{}),
      output: %{},
      auth_state: normalize_auth_state(%{}),
      evidence_ref: %{},
      metadata: %{}
    }
  end

  defp normalize_binding_status(status) when status in @binding_statuses, do: status

  defp normalize_binding_status(status) when is_binary(status) and status != "",
    do: if(status in @binding_statuses, do: status, else: "error")

  defp normalize_binding_status(_status), do: "error"

  defp normalize_install_state(status) when status in @install_states, do: status

  defp normalize_install_state(status) when is_binary(status) and status != "",
    do: if(status in @install_states, do: status, else: nil)

  defp normalize_install_state(_status), do: nil

  defp normalize_auth_status(status) when status in ["ok", "reauthorization_required", "revoked", "expired", "unknown"],
    do: status

  defp normalize_auth_status(status) when is_binary(status) and status != "",
    do: if(status in ["ok", "reauthorization_required", "revoked", "expired", "unknown"], do: status, else: "unknown")

  defp normalize_auth_status(_status), do: "unknown"

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

  defp truthy?(value) when value in [true, "true", 1, "1"], do: true
  defp truthy?(_value), do: false
end
