defmodule JidoCode.Conversations.ContextMemory do
  @moduledoc """
  Product-owned boundary for short-term prompt context memory.

  This module is the only conversation runtime surface that should call
  `Jido.Memory.Runtime` directly. It keeps provider configuration, namespace
  policy, failure handling, and prompt-facing projection shape inside
  `jido_code` instead of leaking `jido_memory` structs into LiveViews or
  conversation runtime callers.
  """

  alias Jido.Memory.{Record, RetrieveResult, Runtime, Store}

  @default_config [
    enabled?: false,
    provider: :basic,
    store: {Jido.Memory.Store.ETS, [table: :jido_code_prompt_memory]},
    store_opts: [],
    timeout_ms: 250,
    retrieval_limit: 6,
    max_instruction_lines: 6,
    max_instruction_bytes: 2_000,
    ttl_ms: 86_400_000
  ]

  @record_policies %{
    active_constraint: %{class: :working, tags: ["prompt-memory", "constraint"]},
    accepted_tool_result: %{class: :episodic, tags: ["prompt-memory", "tool-result"]},
    clarification_answer: %{class: :episodic, tags: ["prompt-memory", "clarification"]},
    plan_summary: %{class: :working, tags: ["prompt-memory", "plan"]},
    next_step: %{class: :working, tags: ["prompt-memory", "next-step"]},
    stable_preference: %{class: :semantic, tags: ["prompt-memory", "preference"]},
    workflow_preference: %{class: :procedural, tags: ["prompt-memory", "workflow"]}
  }

  @default_kind :next_step

  @type scope :: map()
  @type state :: :ready | :disabled | :degraded
  @type prompt_kind ::
          :active_constraint
          | :accepted_tool_result
          | :clarification_answer
          | :plan_summary
          | :next_step
          | :stable_preference
          | :workflow_preference
  @type item :: %{
          id: String.t() | nil,
          class: atom() | nil,
          kind: atom() | String.t() | nil,
          text: String.t() | nil,
          tags: [String.t()],
          source: String.t() | nil,
          metadata: map()
        }
  @type projection :: %{
          state: state(),
          namespace: String.t() | nil,
          items: [item()],
          instruction_lines: [String.t()],
          diagnostics: map(),
          metadata: map()
        }

  @doc """
  Retrieves bounded prompt memory for a product conversation scope.

  The function is intentionally non-fatal for runtime callers. Disabled config,
  invalid scope, missing providers, and provider errors all return a normalized
  projection with `:disabled` or `:degraded` state.
  """
  @spec retrieve(scope(), keyword()) :: {:ok, projection()}
  def retrieve(scope, opts \\ [])

  def retrieve(scope, opts) when is_map(scope) and is_list(opts) do
    config = config(opts)

    with :ok <- ensure_enabled(config),
         {:ok, namespace} <- namespace(scope),
         :ok <- ensure_store_ready(config),
         query <- retrieval_query(namespace, config, opts),
         {:ok, %RetrieveResult{} = result} <-
           Runtime.retrieve(target(scope), query, runtime_opts(namespace, config)) do
      {:ok, ready_projection(namespace, result, config)}
    else
      :disabled ->
        {:ok, disabled_projection(scope)}

      {:error, reason} ->
        {:ok, degraded_projection(scope, reason)}
    end
  end

  def retrieve(_scope, _opts), do: {:ok, degraded_projection(%{}, :invalid_scope)}

  @doc """
  Stores one reduced prompt-memory record for a product conversation scope.

  This write path is for compact reusable summaries only. It should not be used
  for raw transcript mirroring, raw tool output, or durable-memory promotion.
  """
  @spec remember(scope(), map() | keyword(), keyword()) ::
          {:ok, %{state: state(), namespace: String.t() | nil, record_id: String.t() | nil, diagnostics: map()}}
  def remember(scope, attrs, opts \\ [])

  def remember(scope, attrs, opts) when is_map(scope) and is_list(opts) do
    config = config(opts)

    with :ok <- ensure_enabled(config),
         {:ok, namespace} <- namespace(scope),
         :ok <- ensure_store_ready(config),
         {:ok, memory_attrs} <- record_attrs(namespace, scope, attrs, config),
         {:ok, %Record{} = record} <-
           Runtime.remember(target(scope), memory_attrs, runtime_opts(namespace, config)) do
      {:ok, %{state: :ready, namespace: namespace, record_id: record.id, diagnostics: %{}}}
    else
      :disabled ->
        {:ok, %{state: :disabled, namespace: nil, record_id: nil, diagnostics: %{}}}

      {:error, reason} ->
        {:ok, %{state: :degraded, namespace: nil, record_id: nil, diagnostics: %{reason: inspect(reason)}}}
    end
  end

  def remember(_scope, _attrs, _opts),
    do: {:ok, %{state: :degraded, namespace: nil, record_id: nil, diagnostics: %{reason: "invalid_scope"}}}

  @doc """
  Resolves the product-owned prompt-memory namespace for a conversation scope.
  """
  @spec namespace(scope()) :: {:ok, String.t()} | {:error, term()}
  def namespace(scope) when is_map(scope) do
    managed_repo_id = optional_string(map_get(scope, :managed_repo_id))
    work_item_id = optional_string(map_get(scope, :work_item_id))

    cond do
      is_binary(managed_repo_id) and is_binary(work_item_id) ->
        {:ok, "repo:#{managed_repo_id}:work_item:#{work_item_id}"}

      is_binary(managed_repo_id) ->
        {:ok, "repo:#{managed_repo_id}:intake"}

      true ->
        {:error, :managed_repo_scope_required}
    end
  end

  def namespace(_scope), do: {:error, :invalid_scope}

  @doc """
  Returns namespace projection metadata for a conversation scope.

  Work-item scoped conversations keep the work item as the primary namespace
  while retaining repo-intake as a previous namespace for transition-aware
  adoption in later runtime phases.
  """
  @spec namespaces(scope()) ::
          {:ok, %{primary: String.t(), previous: [String.t()], metadata: map()}} | {:error, term()}
  def namespaces(scope) when is_map(scope) do
    managed_repo_id = optional_string(map_get(scope, :managed_repo_id))
    work_item_id = optional_string(map_get(scope, :work_item_id))

    cond do
      is_binary(managed_repo_id) and is_binary(work_item_id) ->
        {:ok,
         %{
           primary: "repo:#{managed_repo_id}:work_item:#{work_item_id}",
           previous: ["repo:#{managed_repo_id}:intake"],
           metadata: scope_metadata(scope)
         }}

      is_binary(managed_repo_id) ->
        {:ok,
         %{
           primary: "repo:#{managed_repo_id}:intake",
           previous: [],
           metadata: scope_metadata(scope)
         }}

      true ->
        {:error, :managed_repo_scope_required}
    end
  end

  def namespaces(_scope), do: {:error, :invalid_scope}

  @doc """
  Returns the bounded prompt-memory record policy for a supported kind.
  """
  @spec record_policy(prompt_kind() | String.t() | nil) :: {:ok, map()} | {:error, term()}
  def record_policy(kind) do
    with {:ok, normalized_kind} <- normalize_prompt_kind(kind) do
      {:ok, Map.put(@record_policies[normalized_kind], :kind, normalized_kind)}
    end
  end

  @doc """
  Returns all prompt-memory kinds supported by the product adapter.
  """
  @spec supported_kinds() :: [prompt_kind()]
  def supported_kinds, do: Map.keys(@record_policies)

  @doc """
  Returns prompt-facing instruction lines from a normalized projection.
  """
  @spec instruction_lines(projection() | term()) :: [String.t()]
  def instruction_lines(%{instruction_lines: lines}) when is_list(lines), do: lines
  def instruction_lines(_projection), do: []

  @doc """
  Returns true when prompt memory is enabled in the current application config.
  """
  @spec enabled?(keyword()) :: boolean()
  def enabled?(opts \\ []) when is_list(opts), do: config(opts)[:enabled?] == true

  defp config(opts) do
    @default_config
    |> Keyword.merge(List.wrap(Application.get_env(:jido_code, :conversation_context_memory, [])))
    |> Keyword.merge(opts)
    |> normalize_config()
  end

  defp normalize_config(config) do
    config
    |> Keyword.put(:enabled?, config[:enabled?] == true)
    |> Keyword.put(:provider, normalize_provider(config[:provider]))
    |> Keyword.put(:store_opts, normalize_keyword(config[:store_opts]))
    |> Keyword.put(:timeout_ms, positive_integer(config[:timeout_ms], @default_config[:timeout_ms]))
    |> Keyword.put(:retrieval_limit, positive_integer(config[:retrieval_limit], @default_config[:retrieval_limit]))
    |> Keyword.put(
      :max_instruction_lines,
      positive_integer(config[:max_instruction_lines], @default_config[:max_instruction_lines])
    )
    |> Keyword.put(
      :max_instruction_bytes,
      positive_integer(config[:max_instruction_bytes], @default_config[:max_instruction_bytes])
    )
    |> Keyword.put(:ttl_ms, positive_integer(config[:ttl_ms], @default_config[:ttl_ms]))
  end

  defp normalize_provider(provider) when provider in [:basic, :redis], do: provider
  defp normalize_provider("basic"), do: :basic
  defp normalize_provider("redis"), do: :redis
  defp normalize_provider(_provider), do: :basic

  defp ensure_enabled(config) do
    if config[:enabled?], do: :ok, else: :disabled
  end

  defp ensure_store_ready(config) do
    store = config[:store] || @default_config[:store]
    store_opts = config[:store_opts] || []

    with {:ok, {store_mod, base_opts}} <- Store.normalize_store(store),
         :ok <- Store.validate_options(store_mod, Keyword.merge(base_opts, store_opts)) do
      store_mod.ensure_ready(Keyword.merge(base_opts, store_opts))
    end
  end

  defp retrieval_query(namespace, config, opts) do
    opts
    |> Keyword.get(:query, %{})
    |> normalize_map()
    |> Map.put(:namespace, namespace)
    |> Map.put_new(:kinds, supported_kinds())
    |> Map.put_new(:limit, config[:retrieval_limit])
    |> Map.put_new(:order, :desc)
  end

  defp runtime_opts(namespace, config) do
    [
      provider: config[:provider],
      namespace: namespace,
      store: config[:store],
      store_opts: config[:store_opts]
    ]
  end

  defp target(scope) do
    %{
      id:
        optional_string(map_get(scope, :conversation_id)) || optional_string(map_get(scope, :managed_repo_id)) ||
          "conversation-context-memory"
    }
  end

  defp record_attrs(namespace, scope, attrs, config) do
    attrs = normalize_map(attrs)
    now = System.system_time(:millisecond)
    text = optional_string(map_get(attrs, :text))
    kind_input = map_get(attrs, :kind) || @default_kind

    with :ok <- ensure_text(text),
         {:ok, policy} <- record_policy(kind_input) do
      metadata =
        attrs
        |> Map.get(:metadata, Map.get(attrs, "metadata", %{}))
        |> normalize_map()
        |> Map.merge(scope_metadata(scope))

      tags =
        attrs
        |> map_get(:tags)
        |> normalize_string_list()
        |> Kernel.++(policy.tags)
        |> Enum.uniq()

      {:ok,
       attrs
       |> Map.put(:namespace, namespace)
       |> Map.put(:class, policy.class)
       |> Map.put(:kind, policy.kind)
       |> Map.put(:text, text)
       |> Map.put(:tags, tags)
       |> Map.put_new(:source, "conversation_context_memory")
       |> Map.put(:metadata, metadata)
       |> Map.put_new(:observed_at, now)
       |> Map.put_new(:expires_at, now + config[:ttl_ms])}
    end
  end

  defp scope_metadata(scope) do
    %{
      "managed_repo_id" => optional_string(map_get(scope, :managed_repo_id)),
      "work_item_id" => optional_string(map_get(scope, :work_item_id)),
      "conversation_id" => optional_string(map_get(scope, :conversation_id)),
      "turn_id" => optional_string(map_get(scope, :turn_id)),
      "workflow" => optional_string(map_get(scope, :workflow)),
      "source" => optional_string(map_get(scope, :source))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp ready_projection(namespace, %RetrieveResult{} = result, config) do
    items =
      result
      |> RetrieveResult.records()
      |> Enum.map(&project_record/1)

    %{
      state: :ready,
      namespace: namespace,
      items: items,
      instruction_lines: instruction_lines_for_items(items, config),
      diagnostics: %{},
      metadata: %{total_count: result.total_count, provider: provider_name(result.provider)}
    }
  end

  defp disabled_projection(scope) do
    %{
      state: :disabled,
      namespace: scope_namespace(scope),
      items: [],
      instruction_lines: [],
      diagnostics: %{},
      metadata: %{enabled?: false}
    }
  end

  defp degraded_projection(scope, reason) do
    %{
      state: :degraded,
      namespace: scope_namespace(scope),
      items: [],
      instruction_lines: [],
      diagnostics: %{reason: inspect(reason)},
      metadata: %{}
    }
  end

  defp scope_namespace(scope) do
    case namespace(scope) do
      {:ok, namespace} -> namespace
      {:error, _reason} -> nil
    end
  end

  defp project_record(%Record{} = record) do
    %{
      id: record.id,
      class: record.class,
      kind: record.kind,
      text: record.text,
      tags: record.tags || [],
      source: record.source,
      metadata: record.metadata || %{}
    }
  end

  defp instruction_lines_for_items(items, config) do
    items
    |> Enum.map(&instruction_line/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(config[:max_instruction_lines])
    |> cap_instruction_bytes(config[:max_instruction_bytes])
  end

  defp instruction_line(%{kind: kind, text: text}) do
    with normalized_text when is_binary(normalized_text) <- optional_string(text),
         normalized_kind when is_binary(normalized_kind) <- optional_string(kind) do
      "- #{normalized_kind}: #{normalized_text}"
    else
      _other -> nil
    end
  end

  defp cap_instruction_bytes(lines, max_bytes) do
    lines
    |> Enum.reduce_while({[], 0}, fn line, {acc, bytes} ->
      line_bytes = byte_size(line)

      if bytes + line_bytes <= max_bytes do
        {:cont, {[line | acc], bytes + line_bytes}}
      else
        {:halt, {acc, bytes}}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp provider_name(nil), do: nil
  defp provider_name(%{name: name}) when is_binary(name), do: name
  defp provider_name(%{key: key}) when is_atom(key), do: Atom.to_string(key)
  defp provider_name(_provider), do: nil

  defp normalize_map(value) when is_list(value), do: Map.new(value)
  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp normalize_keyword(value) when is_list(value), do: value
  defp normalize_keyword(_value), do: []

  defp normalize_prompt_kind(nil), do: {:ok, @default_kind}
  defp normalize_prompt_kind(kind) when is_atom(kind) and is_map_key(@record_policies, kind), do: {:ok, kind}

  defp normalize_prompt_kind(kind) when is_binary(kind) do
    case String.trim(kind) do
      "active_constraint" -> {:ok, :active_constraint}
      "accepted_tool_result" -> {:ok, :accepted_tool_result}
      "clarification_answer" -> {:ok, :clarification_answer}
      "plan_summary" -> {:ok, :plan_summary}
      "next_step" -> {:ok, :next_step}
      "stable_preference" -> {:ok, :stable_preference}
      "workflow_preference" -> {:ok, :workflow_preference}
      _other -> {:error, {:unsupported_prompt_memory_kind, kind}}
    end
  end

  defp normalize_prompt_kind(kind), do: {:error, {:unsupported_prompt_memory_kind, kind}}

  defp ensure_text(text) when is_binary(text), do: :ok
  defp ensure_text(_text), do: {:error, :prompt_memory_text_required}

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.map(&optional_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_string_list(_values), do: []

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp optional_string(_value), do: nil

  defp map_get(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
