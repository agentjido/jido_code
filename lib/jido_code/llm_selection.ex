defmodule JidoCode.LLMSelection do
  @moduledoc false

  alias JidoCode.Control.RepoBridge

  @canonical_selection_keys ["llm", "llm_selection"]
  @llm_opt_key_map %{
    "api_key" => :api_key,
    "base_url" => :base_url,
    "temperature" => :temperature,
    "max_tokens" => :max_tokens,
    "max_retries" => :max_retries,
    "seed" => :seed,
    "top_p" => :top_p,
    "top_k" => :top_k,
    "frequency_penalty" => :frequency_penalty,
    "presence_penalty" => :presence_penalty,
    "headers" => :headers
  }
  @req_http_option_key_map %{
    "receive_timeout" => :receive_timeout,
    "connect_options" => :connect_options,
    "pool_timeout" => :pool_timeout,
    "headers" => :headers
  }

  @type selection_source :: :explicit | :conversation | :repo_default | :system_default

  @type selection :: %{
          provider: String.t(),
          model: String.t(),
          model_spec: String.t(),
          source: selection_source(),
          llm_opts: keyword(),
          req_http_options: keyword()
        }

  @spec resolve(String.t(), keyword()) :: {:ok, selection()} | {:error, map()}
  def resolve(managed_repo_id, opts \\ [])

  def resolve(managed_repo_id, opts) when is_binary(managed_repo_id) and is_list(opts) do
    repo_execution_settings =
      managed_repo_id
      |> repo_execution_settings()
      |> normalize_map()

    resolve_from_execution_settings(repo_execution_settings, opts)
  end

  def resolve(_managed_repo_id, _opts), do: {:error, missing_selection_error()}

  @spec resolve_from_project_detail(map(), keyword()) :: {:ok, selection()} | {:error, map()}
  def resolve_from_project_detail(project_detail, opts \\ [])

  def resolve_from_project_detail(project_detail, opts)
      when is_map(project_detail) and is_list(opts) do
    execution_settings =
      project_detail
      |> map_get(:settings, "settings", %{})
      |> normalize_map()
      |> Map.get("execution", %{})
      |> normalize_map()

    resolve_from_execution_settings(execution_settings, opts)
  end

  def resolve_from_project_detail(_project_detail, _opts), do: {:error, missing_selection_error()}

  @spec resolve_from_execution_settings(map(), keyword()) :: {:ok, selection()} | {:error, map()}
  def resolve_from_execution_settings(execution_settings, opts \\ [])

  def resolve_from_execution_settings(execution_settings, opts)
      when is_map(execution_settings) and is_list(opts) do
    explicit_selection =
      opts
      |> Keyword.get(:llm_selection, Keyword.get(opts, :llm))
      |> normalize_selection_config()

    conversation_selection =
      opts
      |> Keyword.get(:conversation_metadata, %{})
      |> normalize_map()
      |> extract_selection_config()

    repo_selection =
      execution_settings
      |> normalize_map()
      |> extract_selection_config()

    system_selection =
      Application.get_env(:jido_code, :llm_selection, %{})
      |> normalize_map()
      |> extract_system_default()

    case first_selection([
           {:explicit, explicit_selection},
           {:conversation, conversation_selection},
           {:repo_default, repo_selection},
           {:system_default, system_selection}
         ]) do
      {:ok, selection} -> {:ok, selection}
      :error -> {:error, missing_selection_error()}
    end
  end

  def resolve_from_execution_settings(_execution_settings, _opts), do: {:error, missing_selection_error()}

  @spec summary(selection() | map() | nil) :: map() | nil
  def summary(%{provider: provider, model: model, model_spec: model_spec, source: source}) do
    %{
      provider: provider,
      model: model,
      model_spec: model_spec,
      source: source
    }
  end

  def summary(_selection), do: nil

  @spec apply_to_agent(module(), pid(), selection() | map() | nil) :: :ok | {:error, map()}
  def apply_to_agent(_agent_module, _pid, nil), do: {:error, missing_selection_error()}

  def apply_to_agent(agent_module, pid, %{model_spec: model_spec})
      when is_atom(agent_module) and is_pid(pid) and is_binary(model_spec) do
    case agent_module.set(pid, %{model: model_spec}) do
      {:ok, _agent} ->
        :ok

      {:error, reason} ->
        {:error,
         %{
           "error_type" => "conversation_runtime_llm_selection_invalid",
           "detail" => "Failed to apply the selected LLM provider and model to the specialist runtime.",
           "remediation" => "Verify the selected provider/model pair and retry the conversation turn.",
           "reason" => inspect(reason)
         }}
    end
  end

  def apply_to_agent(_agent_module, _pid, _selection), do: {:error, missing_selection_error()}

  @spec missing_selection_error() :: map()
  def missing_selection_error do
    %{
      "error_type" => "conversation_runtime_llm_selection_missing",
      "detail" =>
        "LLM provider and model selection is missing for real coding execution.",
      "remediation" =>
        "Set a concrete provider and model in conversation metadata, managed-repo execution settings, or system configuration and retry."
    }
  end

  defp repo_execution_settings(managed_repo_id) when is_binary(managed_repo_id) do
    case RepoBridge.repo_scope(managed_repo_id) do
      {:ok, scope} ->
        scope
        |> map_get(:managed_repo, "managed_repo", %{})
        |> map_get(:execution_settings, "execution_settings", %{})
        |> normalize_map()

      _other ->
        %{}
    end
  end

  defp extract_system_default(config) when is_map(config) do
    cond do
      has_provider_and_model?(config) ->
        normalize_selection_config(config)

      true ->
        config
        |> Map.get("default", %{})
        |> normalize_selection_config()
    end
  end

  defp extract_selection_config(config) when is_map(config) do
    cond do
      has_provider_and_model?(config) ->
        normalize_selection_config(config)

      true ->
        config
        |> selection_container()
        |> normalize_selection_config()
    end
  end

  defp extract_selection_config(_config), do: nil

  defp selection_submap(config) when is_map(config) do
    Enum.find_value(@canonical_selection_keys, %{}, fn key ->
      case Map.get(config, key) do
        %{} = selection -> normalize_map(selection)
        _other -> nil
      end
    end)
  end

  defp selection_container(config) when is_map(config) do
    case selection_submap(config) do
      %{} = selection when map_size(selection) > 0 ->
        selection

      _other ->
        execution_config =
          config
          |> Map.get("execution", %{})
          |> normalize_map()

        cond do
          has_provider_and_model?(execution_config) ->
            execution_config

          true ->
            selection_submap(execution_config)
        end
    end
  end

  defp normalize_selection_config(config) when is_map(config) do
    config = normalize_map(config)

    model_spec =
      config
      |> Map.get("model_spec", Map.get(config, "spec"))
      |> normalize_optional_string()

    {provider_from_spec, model_from_spec} = parse_model_spec(model_spec)

    provider =
      config
      |> Map.get("provider")
      |> normalize_optional_string()
      |> fallback_optional_string(provider_from_spec)

    model =
      config
      |> Map.get("model")
      |> normalize_optional_string()
      |> fallback_optional_string(model_from_spec)

    if provider && model do
      %{
        provider: provider,
        model: model,
        model_spec: "#{provider}:#{model}",
        llm_opts: normalize_keyword_options(Map.get(config, "llm_opts"), @llm_opt_key_map),
        req_http_options:
          normalize_keyword_options(Map.get(config, "req_http_options"), @req_http_option_key_map)
      }
    else
      nil
    end
  end

  defp normalize_selection_config(_config), do: nil

  defp first_selection(candidates) when is_list(candidates) do
    Enum.find_value(candidates, :error, fn
      {source, %{} = selection} ->
        {:ok, Map.put(selection, :source, source)}

      _other ->
        nil
    end)
  end

  defp normalize_keyword_options(nil, _allowed_keys), do: []

  defp normalize_keyword_options(options, allowed_keys) when is_map(options) do
    options
    |> normalize_map()
    |> Enum.reduce([], fn {key, value}, acc ->
      case Map.get(allowed_keys, key) do
        nil -> acc
        normalized_key -> acc ++ [{normalized_key, normalize_nested_value(value)}]
      end
    end)
  end

  defp normalize_keyword_options(options, allowed_keys) when is_list(options) do
    options
    |> Enum.reduce(%{}, fn
      {key, value}, acc -> Map.put(acc, to_string(key), value)
      _other, acc -> acc
    end)
    |> normalize_keyword_options(allowed_keys)
  end

  defp normalize_keyword_options(_options, _allowed_keys), do: []

  defp has_provider_and_model?(config) when is_map(config) do
    not is_nil(normalize_optional_string(Map.get(config, "provider"))) and
      (not is_nil(normalize_optional_string(Map.get(config, "model"))) or
         not is_nil(normalize_optional_string(Map.get(config, "model_spec"))) or
         not is_nil(normalize_optional_string(Map.get(config, "spec"))))
  end

  defp has_provider_and_model?(_config), do: false

  defp parse_model_spec(nil), do: {nil, nil}

  defp parse_model_spec(model_spec) when is_binary(model_spec) do
    case String.split(String.trim(model_spec), ":", parts: 2) do
      [provider, model] when provider != "" and model != "" -> {provider, model}
      _other -> {nil, nil}
    end
  end

  defp parse_model_spec(_model_spec), do: {nil, nil}

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      Map.put(acc, normalized_key, normalize_nested_value(nested_value))
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_optional_string()
  end

  defp normalize_optional_string(_value), do: nil

  defp fallback_optional_string(primary, _fallback) when is_binary(primary), do: primary
  defp fallback_optional_string(nil, fallback), do: fallback
  defp fallback_optional_string(_primary, fallback), do: fallback
end
