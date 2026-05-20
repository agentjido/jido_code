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
  @type packed_section :: %{
          kind: section_kind(),
          label: String.t(),
          retention: retention_class(),
          text: String.t(),
          entries: [String.t()],
          metadata: map(),
          diagnostics: map()
        }
  @type packed_result :: %{
          text: String.t(),
          sections: [packed_section()],
          diagnostics: [map()],
          summary: map(),
          policy: policy()
        }
  @type packed_messages :: %{
          messages: [map()],
          diagnostics: map(),
          summary: map(),
          policy: policy()
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

  @doc """
  Packs structured prompt sections according to the resolved context budget.

  Required sections are preserved first. Remaining sections are packed by
  retention class and section order, with per-section ratios limiting how much
  any optional context source can consume.
  """
  @spec pack([section() | map()], keyword() | map()) :: packed_result()
  def pack(sections, opts \\ []) when is_list(sections) do
    opts = normalize_opts(opts)
    policy = normalize_policy(Map.get(opts, :policy), opts)
    initial_budget = positive_integer(Map.get(opts, :input_token_budget), policy.input_token_budget)

    sections =
      sections
      |> Enum.map(&normalize_section/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(&section_sort_key(&1, policy))

    {packed_sections, remaining_budget} =
      Enum.reduce(sections, {[], initial_budget}, fn section, {acc, remaining} ->
        {packed_section, spent} = pack_section(section, remaining, policy)
        {[packed_section | acc], remaining - spent}
      end)

    packed_sections = Enum.reverse(packed_sections)
    diagnostics = Enum.map(packed_sections, & &1.diagnostics)
    text = render_sections(packed_sections)
    summary = pack_summary(policy, diagnostics, text, initial_budget, remaining_budget)

    %{
      text: text,
      sections: packed_sections,
      diagnostics: diagnostics,
      summary: summary,
      policy: policy
    }
  end

  @doc "Renders a packed result or packed sections to prompt text."
  @spec render(packed_result() | [packed_section()] | nil) :: String.t()
  def render(%{text: text}) when is_binary(text), do: text
  def render(sections) when is_list(sections), do: render_sections(sections)
  def render(_other), do: ""

  @doc """
  Packs ReAct message history at request time.

  Messages are packed at protocol-safe group boundaries. Assistant messages with
  tool calls stay paired with following tool-result messages when either side is
  retained.
  """
  @spec pack_messages([map()], keyword() | map()) :: packed_messages()
  def pack_messages(messages, opts \\ []) when is_list(messages) do
    opts = normalize_opts(opts)
    policy = normalize_policy(Map.get(opts, :policy), opts)
    history_policy = Map.get(policy, :history, %{})
    max_messages = positive_integer(Map.get(opts, :max_messages), Map.get(history_policy, :max_messages, 24))
    token_budget = positive_integer(Map.get(opts, :token_budget), Map.get(history_policy, :token_budget, 8_000))

    {system_messages, body_messages} = Enum.split_with(messages, &(message_role(&1) == :system))
    groups = message_groups(body_messages)

    {selected_groups, dropped_groups, dropped_messages, forced_groups} =
      pack_message_groups(groups, token_budget, max_messages)

    packed_messages = system_messages ++ List.flatten(selected_groups)

    diagnostics = %{
      kind: :conversation_history,
      state: if(dropped_messages > 0, do: :trimmed, else: :packed),
      original_messages: length(messages),
      packed_messages: length(packed_messages),
      dropped_messages: dropped_messages,
      original_groups: length(groups),
      packed_groups: length(selected_groups),
      dropped_groups: dropped_groups,
      forced_groups: forced_groups,
      token_budget: token_budget,
      max_messages: max_messages,
      packed_approximate_tokens: estimate_messages(packed_messages).approximate_tokens,
      original_approximate_tokens: estimate_messages(messages).approximate_tokens
    }

    %{
      messages: packed_messages,
      diagnostics: diagnostics,
      summary: stringify_keys(diagnostics),
      policy: policy
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

  defp normalize_policy(%{input_token_budget: _input_token_budget} = policy, _opts), do: policy
  defp normalize_policy(_policy, opts), do: policy(opts)

  defp normalize_section(%{kind: kind, text: text} = section) when is_atom(kind) do
    entries =
      section
      |> Map.get(:entries, normalize_entries(text))
      |> normalize_entries()

    %{
      kind: kind,
      label: normalize_optional_string(Map.get(section, :label)) || humanize_kind(kind),
      retention: retention_class(Map.get(section, :retention, default_retention(kind))),
      text: Enum.join(entries, "\n"),
      entries: entries,
      metadata: normalize_map(Map.get(section, :metadata, %{}))
    }
  end

  defp normalize_section(%{"kind" => kind} = section) do
    kind = normalize_kind(kind)

    if kind do
      normalize_section(%{
        kind: kind,
        label: Map.get(section, "label"),
        retention: Map.get(section, "retention"),
        text: Map.get(section, "text"),
        entries: Map.get(section, "entries"),
        metadata: Map.get(section, "metadata", %{})
      })
    end
  end

  defp normalize_section(_section), do: nil

  defp section_sort_key(section, policy) do
    {retention_rank(section.retention), order_index(policy.section_order, section.kind)}
  end

  defp retention_rank(:required), do: 0
  defp retention_rank(:important), do: 1
  defp retention_rank(:useful), do: 2
  defp retention_rank(:optional), do: 3
  defp retention_rank(_retention), do: 4

  defp order_index(order, kind) do
    Enum.find_index(order, &(&1 == kind)) || length(order)
  end

  defp pack_section(%{retention: :required} = section, remaining_budget, _policy) do
    original = estimate(section.text)

    diagnostics =
      section_diagnostics(section, original, original, 0,
        state: if(original.approximate_tokens > max(remaining_budget, 0), do: :degraded, else: :packed),
        reason:
          if(original.approximate_tokens > max(remaining_budget, 0),
            do: :required_section_exceeds_remaining_budget,
            else: nil
          )
      )

    {Map.put(section, :diagnostics, diagnostics), original.approximate_tokens}
  end

  defp pack_section(section, remaining_budget, policy) do
    original = estimate(section.text)
    section_budget = section_budget(section, remaining_budget, policy)

    cond do
      section.entries == [] ->
        {Map.put(section, :diagnostics, section_diagnostics(section, original, original, 0, state: :empty)), 0}

      section_budget <= 0 ->
        diagnostics =
          section_diagnostics(section, original, %{bytes: 0, approximate_tokens: 0}, length(section.entries),
            state: :dropped,
            reason: :budget_exhausted
          )

        {section |> Map.put(:text, "") |> Map.put(:entries, []) |> Map.put(:diagnostics, diagnostics), 0}

      true ->
        {packed_entries, dropped_entries, reason} = pack_entries(section.entries, section_budget)
        packed_text = Enum.join(packed_entries, "\n")
        packed = estimate(packed_text)

        diagnostics =
          section_diagnostics(section, original, packed, dropped_entries,
            state: section_state(original, packed, dropped_entries),
            reason: reason
          )

        {section
         |> Map.put(:text, packed_text)
         |> Map.put(:entries, packed_entries)
         |> Map.put(:diagnostics, diagnostics), packed.approximate_tokens}
    end
  end

  defp section_budget(section, remaining_budget, policy) do
    ratio = Map.get(policy.section_ratios, section.kind, 1.0)
    ratio_budget = ceil(policy.input_token_budget * ratio)

    remaining_budget
    |> max(0)
    |> min(ratio_budget)
  end

  defp pack_entries(entries, token_budget) do
    Enum.reduce_while(entries, {[], token_budget, 0, nil}, fn entry, {packed, remaining, dropped, reason} ->
      entry_estimate = estimate(entry)

      cond do
        entry_estimate.approximate_tokens <= remaining ->
          {:cont, {[entry | packed], remaining - entry_estimate.approximate_tokens, dropped, reason}}

        packed == [] and remaining > 0 ->
          truncated = trim_to_token_budget(entry, remaining)

          {:halt,
           {
             [truncated | packed],
             0,
             dropped + length(entries) - 1,
             :section_entry_truncated
           }}

        true ->
          {:halt, {packed, remaining, dropped + 1 + trailing_count(entries, entry), reason || :section_budget_exceeded}}
      end
    end)
    |> case do
      {packed, _remaining, dropped, reason} ->
        {Enum.reverse(packed), dropped, reason}
    end
  end

  defp trailing_count(entries, entry) do
    case Enum.find_index(entries, &(&1 == entry)) do
      nil -> 0
      index -> max(length(entries) - index - 1, 0)
    end
  end

  defp trim_to_token_budget(text, token_budget) when token_budget > 0 do
    max_chars = max(token_budget * @approx_bytes_per_token, 1)

    if String.length(text) > max_chars do
      String.slice(text, 0, max_chars) <> "\n... (context section truncated)"
    else
      text
    end
  end

  defp trim_to_token_budget(_text, _token_budget), do: ""

  defp section_state(_original, %{approximate_tokens: 0}, dropped_entries) when dropped_entries > 0, do: :dropped

  defp section_state(original, packed, dropped_entries)
       when dropped_entries > 0 or original.approximate_tokens > packed.approximate_tokens,
       do: :trimmed

  defp section_state(_original, _packed, _dropped_entries), do: :packed

  defp section_diagnostics(section, original, packed, dropped_entries, opts) do
    opts = normalize_opts(opts)

    %{
      kind: section.kind,
      label: section.label,
      retention: section.retention,
      state: Map.get(opts, :state, :packed),
      original_bytes: original.bytes,
      original_approximate_tokens: original.approximate_tokens,
      packed_bytes: packed.bytes,
      packed_approximate_tokens: packed.approximate_tokens,
      original_entries: length(section.entries),
      packed_entries: max(length(section.entries) - dropped_entries, 0),
      dropped_entries: dropped_entries,
      reason: Map.get(opts, :reason),
      metadata: section.metadata
    }
    |> Enum.reject(fn
      {_key, nil} -> true
      {_key, %{} = value} -> map_size(value) == 0
      _other -> false
    end)
    |> Map.new()
  end

  defp pack_summary(policy, diagnostics, text, initial_budget, remaining_budget) do
    estimated = estimate(text)
    trimmed_count = Enum.count(diagnostics, &(Map.get(&1, :state) in [:trimmed, :dropped]))
    degraded? = Enum.any?(diagnostics, &(Map.get(&1, :state) == :degraded))

    %{
      policy_id: policy.id,
      state: pack_state(degraded?, trimmed_count),
      model_budget: initial_budget,
      estimated_input_tokens: estimated.approximate_tokens,
      estimated_input_bytes: estimated.bytes,
      remaining_budget: remaining_budget,
      section_count: length(diagnostics),
      trimmed_section_count: trimmed_count,
      dropped_entry_count: Enum.reduce(diagnostics, 0, &(&2 + Map.get(&1, :dropped_entries, 0))),
      degraded?: degraded?,
      diagnostics: diagnostics
    }
  end

  defp pack_state(true, _trimmed_count), do: "degraded"
  defp pack_state(false, trimmed_count) when trimmed_count > 0, do: "trimmed"
  defp pack_state(false, _trimmed_count), do: "packed"

  defp render_sections(sections) do
    sections
    |> Enum.reject(&(normalize_optional_string(Map.get(&1, :text)) == nil))
    |> Enum.map_join("\n\n", fn section ->
      "#{section.label}:\n#{section.text}"
    end)
  end

  defp pack_message_groups(groups, token_budget, max_messages) do
    groups
    |> Enum.reverse()
    |> Enum.reduce_while({[], 0, 0, 0}, fn group, {selected, spent_tokens, selected_count, forced_groups} ->
      group_tokens = estimate_messages(group).approximate_tokens
      group_count = length(group)
      required_tail? = selected == []

      fits? =
        spent_tokens + group_tokens <= token_budget and selected_count + group_count <= max_messages

      cond do
        fits? ->
          {:cont, {[group | selected], spent_tokens + group_tokens, selected_count + group_count, forced_groups}}

        required_tail? ->
          {:cont, {[group | selected], spent_tokens + group_tokens, selected_count + group_count, forced_groups + 1}}

        true ->
          {:halt, {selected, spent_tokens, selected_count, forced_groups}}
      end
    end)
    |> case do
      {selected, _spent_tokens, _selected_count, forced_groups} ->
        dropped_groups = max(length(groups) - length(selected), 0)
        dropped_messages = groups |> Enum.take(dropped_groups) |> List.flatten() |> length()
        {selected, dropped_groups, dropped_messages, forced_groups}
    end
  end

  defp message_groups(messages) do
    messages
    |> Enum.reduce([], fn message, groups ->
      role = message_role(message)

      cond do
        role == :tool and groups != [] and assistant_tool_group?(List.last(groups)) ->
          List.update_at(groups, -1, &(&1 ++ [message]))

        true ->
          groups ++ [[message]]
      end
    end)
  end

  defp assistant_tool_group?([]), do: false

  defp assistant_tool_group?(group) when is_list(group) do
    group
    |> List.first()
    |> assistant_tool_message?()
  end

  defp assistant_tool_message?(message) do
    message_role(message) == :assistant and
      message
      |> message_tool_calls()
      |> case do
        calls when is_list(calls) -> calls != []
        _other -> false
      end
  end

  defp estimate_messages(messages) when is_list(messages) do
    messages
    |> Enum.map(&message_content_text/1)
    |> Enum.join("\n")
    |> estimate()
  end

  defp message_role(%{} = message) do
    message
    |> Map.get(:role, Map.get(message, "role"))
    |> normalize_role()
  end

  defp message_role(_message), do: :unknown

  defp normalize_role(role) when is_atom(role), do: role

  defp normalize_role(role) when is_binary(role) do
    role
    |> String.downcase()
    |> String.to_existing_atom()
  rescue
    ArgumentError -> :unknown
  end

  defp normalize_role(_role), do: :unknown

  defp message_tool_calls(%{} = message), do: Map.get(message, :tool_calls, Map.get(message, "tool_calls"))
  defp message_tool_calls(_message), do: nil

  defp message_content_text(%{} = message) do
    message
    |> Map.get(:content, Map.get(message, "content", ""))
    |> render_estimate_text()
  end

  defp message_content_text(message), do: render_estimate_text(message)

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
