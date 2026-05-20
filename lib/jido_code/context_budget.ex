defmodule JidoCode.ContextBudget do
  # covers: architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary
  # covers: architecture.conversation_orchestration.llm_readiness_and_failure_states_are_explicit
  @moduledoc """
  Product-owned context budget policy and prompt section vocabulary.

  The first implementation uses byte and approximate-token accounting. This
  keeps the budget boundary deterministic and provider independent while still
  producing diagnostics that make the approximation explicit.
  """

  @default_policy_id "context-budget:v1"
  @default_context_window_tokens 16_000
  @default_output_token_reserve 2_000
  @minimum_input_token_budget 512
  @approx_bytes_per_token 4
  @default_tool_max_bytes 10_000
  @default_tool_max_lines 500
  @default_tool_max_results 1_000
  @default_history_max_messages 24
  @default_history_token_budget 8_000

  @section_kinds [
    :system_prompt,
    :current_request,
    :repository_scope,
    :conversation_history,
    :prompt_memory,
    :semantic_context,
    :memory_context,
    :accepted_tool_results,
    :referenced_files,
    :tool_output,
    :clarification_context,
    :workflow,
    :guidance
  ]

  @retention_classes [:required, :important, :useful, :optional]

  @default_section_order [
    :system_prompt,
    :current_request,
    :repository_scope,
    :workflow,
    :clarification_context,
    :referenced_files,
    :accepted_tool_results,
    :prompt_memory,
    :memory_context,
    :semantic_context,
    :conversation_history,
    :tool_output,
    :guidance
  ]

  @default_section_ratios %{
    system_prompt: 0.12,
    current_request: 0.20,
    repository_scope: 0.08,
    workflow: 0.04,
    clarification_context: 0.08,
    referenced_files: 0.08,
    accepted_tool_results: 0.12,
    prompt_memory: 0.10,
    memory_context: 0.14,
    semantic_context: 0.14,
    conversation_history: 0.24,
    tool_output: 0.14,
    guidance: 0.06
  }

  @model_defaults %{
    {"deterministic", "deterministic"} => %{context_window_tokens: 4_096, output_token_reserve: 512},
    {"openai", "gpt-5"} => %{context_window_tokens: 128_000, output_token_reserve: 8_000},
    {"openai", "gpt-4.1"} => %{context_window_tokens: 128_000, output_token_reserve: 8_000},
    {"anthropic", "claude-sonnet-4"} => %{context_window_tokens: 128_000, output_token_reserve: 8_000}
  }

  @type section_kind :: atom()
  @type retention_class :: :required | :important | :useful | :optional
  @type estimate :: %{bytes: non_neg_integer(), approximate_tokens: non_neg_integer()}
  @type section :: %{
          kind: section_kind(),
          label: String.t(),
          retention: retention_class(),
          text: String.t(),
          entries: [String.t()],
          metadata: map()
        }
  @type policy :: %{
          id: String.t(),
          provider: String.t() | nil,
          model: String.t() | nil,
          model_spec: String.t() | nil,
          source: atom(),
          context_window_tokens: pos_integer(),
          output_token_reserve: non_neg_integer(),
          input_token_budget: pos_integer(),
          section_order: [section_kind()],
          section_ratios: %{optional(section_kind()) => float()},
          history: map(),
          tool_output: map(),
          diagnostics: [map()]
        }

  @doc "Returns the canonical prompt section kinds understood by the budget layer."
  @spec section_kinds() :: [section_kind()]
  def section_kinds, do: @section_kinds

  @doc "Returns retention classes in decreasing preservation priority."
  @spec retention_classes() :: [retention_class()]
  def retention_classes, do: @retention_classes

  @doc "Returns the default section packing order."
  @spec section_order() :: [section_kind()]
  def section_order, do: @default_section_order

  @doc "Returns default section budget ratios keyed by section kind."
  @spec section_ratios() :: %{section_kind() => float()}
  def section_ratios, do: @default_section_ratios

  @doc """
  Builds a normalized context budget policy from config, LLM selection, and overrides.
  """
  @spec policy(keyword() | map()) :: policy()
  def policy(opts \\ []) do
    opts = normalize_opts(opts)
    config = normalize_opts(Application.get_env(:jido_code, :context_budget, []))
    llm_selection = normalize_map(Map.get(opts, :llm_selection) || Map.get(config, :llm_selection) || %{})
    {provider, model, model_spec} = model_identity(llm_selection)
    model_defaults = model_defaults(provider, model)
    diagnostics = model_diagnostics(provider, model, model_defaults)

    context_window_tokens =
      positive_integer(
        Map.get(opts, :context_window_tokens, Map.get(config, :context_window_tokens)),
        model_defaults.context_window_tokens
      )

    output_token_reserve =
      non_negative_integer(
        Map.get(opts, :output_token_reserve, Map.get(config, :output_token_reserve)),
        model_defaults.output_token_reserve
      )

    input_token_budget =
      positive_integer(
        Map.get(opts, :input_token_budget, Map.get(config, :input_token_budget)),
        max(context_window_tokens - output_token_reserve, @minimum_input_token_budget)
      )

    %{
      id: normalize_optional_string(Map.get(opts, :id, Map.get(config, :id))) || @default_policy_id,
      provider: provider,
      model: model,
      model_spec: model_spec,
      source: policy_source(model_defaults, opts, config),
      context_window_tokens: context_window_tokens,
      output_token_reserve: output_token_reserve,
      input_token_budget: max(input_token_budget, @minimum_input_token_budget),
      section_order: section_order(Map.get(opts, :section_order, Map.get(config, :section_order))),
      section_ratios: section_ratios(Map.get(opts, :section_ratios, Map.get(config, :section_ratios))),
      history: history_policy(opts, config),
      tool_output: tool_output_policy(opts, config),
      diagnostics: diagnostics
    }
  end

  @doc """
  Builds a normalized prompt section.
  """
  @spec section(section_kind(), String.t() | [String.t()] | nil, keyword() | map()) :: section()
  def section(kind, content, opts \\ []) when is_atom(kind) do
    opts = normalize_opts(opts)
    label = normalize_optional_string(Map.get(opts, :label)) || humanize_kind(kind)
    retention = retention_class(Map.get(opts, :retention, default_retention(kind)))
    entries = normalize_entries(content)

    %{
      kind: kind,
      label: label,
      retention: retention,
      text: Enum.join(entries, "\n"),
      entries: entries,
      metadata: normalize_map(Map.get(opts, :metadata, %{}))
    }
  end

  @doc """
  Estimates prompt size using bytes and a conservative approximate-token count.
  """
  @spec estimate(String.t() | [String.t()] | map() | nil) :: estimate()
  def estimate(value) do
    text = render_estimate_text(value)
    bytes = byte_size(text)

    %{
      bytes: bytes,
      approximate_tokens: ceil(bytes / @approx_bytes_per_token)
    }
  end

  @doc "Builds a compact public summary from a policy or packed result."
  @spec summary(map() | nil) :: map() | nil
  def summary(nil), do: nil

  def summary(%{summary: %{} = summary}), do: stringify_keys(summary)

  def summary(%{id: id, input_token_budget: input_token_budget} = policy) do
    %{
      "policy_id" => id,
      "state" => "ready",
      "model_budget" => input_token_budget,
      "estimated_input_tokens" => 0,
      "trimmed_section_count" => 0,
      "degraded?" => false,
      "diagnostics" => Enum.map(Map.get(policy, :diagnostics, []), &stringify_keys/1)
    }
  end

  def summary(%{} = map), do: stringify_keys(map)
  def summary(_other), do: nil

  defp model_defaults(provider, model) when is_binary(provider) and is_binary(model) do
    key = {String.downcase(provider), String.downcase(model)}

    case Map.get(@model_defaults, key) do
      nil ->
        %{
          context_window_tokens: @default_context_window_tokens,
          output_token_reserve: @default_output_token_reserve,
          fallback?: true
        }

      defaults ->
        Map.put(defaults, :fallback?, false)
    end
  end

  defp model_defaults(_provider, _model) do
    %{
      context_window_tokens: @default_context_window_tokens,
      output_token_reserve: @default_output_token_reserve,
      fallback?: true
    }
  end

  defp model_diagnostics(provider, model, %{fallback?: true}) do
    [
      %{
        kind: :missing_model_metadata,
        state: :degraded,
        detail: "Using conservative fallback context budget because model metadata is unavailable.",
        provider: provider,
        model: model
      }
    ]
  end

  defp model_diagnostics(_provider, _model, _defaults), do: []

  defp policy_source(_model_defaults, opts, config)
       when is_map_key(opts, :input_token_budget) or is_map_key(config, :input_token_budget),
       do: :override

  defp policy_source(%{fallback?: true}, _opts, _config), do: :fallback
  defp policy_source(_model_defaults, _opts, _config), do: :model_default

  defp history_policy(opts, config) do
    history_opts =
      normalize_opts(Map.get(config, :history, [])) |> Map.merge(normalize_opts(Map.get(opts, :history, [])))

    %{
      max_messages: positive_integer(Map.get(history_opts, :max_messages), @default_history_max_messages),
      token_budget: positive_integer(Map.get(history_opts, :token_budget), @default_history_token_budget)
    }
  end

  defp tool_output_policy(opts, config) do
    tool_opts =
      normalize_opts(Map.get(config, :tool_output, []))
      |> Map.merge(normalize_opts(Map.get(opts, :tool_output, [])))

    %{
      max_bytes: positive_integer(Map.get(tool_opts, :max_bytes), @default_tool_max_bytes),
      max_lines: positive_integer(Map.get(tool_opts, :max_lines), @default_tool_max_lines),
      max_results: positive_integer(Map.get(tool_opts, :max_results), @default_tool_max_results)
    }
  end

  defp section_order(nil), do: @default_section_order

  defp section_order(order) when is_list(order) do
    normalized =
      order
      |> Enum.map(&normalize_kind/1)
      |> Enum.filter(&(&1 in @section_kinds))

    if normalized == [], do: @default_section_order, else: Enum.uniq(normalized)
  end

  defp section_order(_other), do: @default_section_order

  defp section_ratios(nil), do: @default_section_ratios

  defp section_ratios(ratios) when is_map(ratios) or is_list(ratios) do
    ratios
    |> normalize_opts()
    |> Enum.reduce(@default_section_ratios, fn {key, value}, acc ->
      kind = normalize_kind(key)

      if kind in @section_kinds and is_number(value) and value > 0 do
        Map.put(acc, kind, value / 1)
      else
        acc
      end
    end)
  end

  defp section_ratios(_other), do: @default_section_ratios

  defp default_retention(kind) when kind in [:system_prompt, :current_request, :repository_scope], do: :required
  defp default_retention(kind) when kind in [:workflow, :clarification_context], do: :important
  defp default_retention(kind) when kind in [:guidance, :tool_output], do: :optional
  defp default_retention(_kind), do: :useful

  defp retention_class(value) when value in @retention_classes, do: value

  defp retention_class(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.to_existing_atom()
    |> retention_class()
  rescue
    ArgumentError -> :useful
  end

  defp retention_class(_value), do: :useful

  defp model_identity(selection) do
    provider = normalize_optional_string(Map.get(selection, "provider"))
    model = normalize_optional_string(Map.get(selection, "model"))
    model_spec = normalize_optional_string(Map.get(selection, "model_spec"))

    cond do
      provider && model ->
        {provider, model, model_spec || "#{provider}:#{model}"}

      model_spec && String.contains?(model_spec, ":") ->
        [provider, model] = String.split(model_spec, ":", parts: 2)
        {provider, model, model_spec}

      true ->
        {provider, model, model_spec}
    end
  end

  defp normalize_entries(nil), do: []

  defp normalize_entries(entries) when is_list(entries) do
    entries
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_entries(value) do
    case normalize_optional_string(value) do
      nil -> []
      text -> [text]
    end
  end

  defp render_estimate_text(nil), do: ""
  defp render_estimate_text(value) when is_binary(value), do: value
  defp render_estimate_text(value) when is_list(value), do: value |> normalize_entries() |> Enum.join("\n")
  defp render_estimate_text(value) when is_map(value), do: inspect(value, pretty: true)
  defp render_estimate_text(value), do: to_string(value)

  defp normalize_opts(nil), do: %{}
  defp normalize_opts(opts) when is_list(opts), do: opts |> Enum.into(%{}) |> normalize_opts()

  defp normalize_opts(%{} = opts) do
    Enum.reduce(opts, %{}, fn {key, value}, acc ->
      case normalize_opt_key(key) do
        nil -> acc
        normalized_key -> Map.put(acc, normalized_key, value)
      end
    end)
  end

  defp normalize_opts(_opts), do: %{}

  defp normalize_opt_key(key) when is_atom(key), do: key

  defp normalize_opt_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp normalize_opt_key(key), do: key

  defp normalize_map(%{} = map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      Map.put(acc, normalized_key, value)
    end)
  end

  defp normalize_map(_map), do: %{}

  defp normalize_kind(value) when is_atom(value), do: value

  defp normalize_kind(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> nil
  end

  defp normalize_kind(_value), do: nil

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_atom(value) do
    value |> Atom.to_string() |> normalize_optional_string()
  end

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp normalize_optional_string(value), do: value |> inspect() |> normalize_optional_string()

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value
  defp non_negative_integer(_value, default), do: default

  defp humanize_kind(kind) do
    kind
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp stringify_keys(%{} = map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      Map.put(acc, stringify_key(key), stringify_value(value))
    end)
  end

  defp stringify_value(%{} = value), do: stringify_keys(value)
  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value), do: value

  defp stringify_key(key) when is_atom(key), do: Atom.to_string(key)
  defp stringify_key(key) when is_binary(key), do: key
  defp stringify_key(key), do: to_string(key)
end
