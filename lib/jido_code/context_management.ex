defmodule JidoCode.ContextManagement do
  # covers: architecture.context_management_pod.coding_pod_owns_context_management
  # covers: architecture.context_management_pod.compaction_store_is_product_owned
  # covers: architecture.context_management_pod.request_time_budgeting_remains_hard_guard
  @moduledoc """
  Product-owned context-management boundary for work-item CodingPods.

  This module keeps pod identity, policy normalization, and metadata shaping out
  of `AgentWorkspace` so monitoring and compaction can evolve without exposing
  internal agent details to product callers.
  """

  alias JidoCode.ContextBudget

  @default_policy_id "context-management:v1"
  @default_high_water_mark 0.80
  @default_repeated_trim_threshold 2
  @default_debounce_window_ms 300_000
  @default_max_summary_tokens 1_000
  @default_max_candidate_tokens 4_000

  defmodule BudgetObservation do
    @moduledoc "Metadata-only budget observation accepted by the BudgetMonitor."
    @enforce_keys [:managed_repo_id, :work_item_id, :workflow, :specialist_role]
    defstruct [
      :managed_repo_id,
      :work_item_id,
      :workflow,
      :specialist_role,
      :conversation_id,
      :turn_id,
      :source,
      :context_budget,
      :tool_budget,
      :observed_at,
      diagnostics: %{}
    ]
  end

  defmodule Recommendation do
    @moduledoc "Deterministic monitor decision for proactive compaction."
    @enforce_keys [:id, :state, :managed_repo_id, :work_item_id, :workflow, :specialist_role]
    defstruct [
      :id,
      :state,
      :managed_repo_id,
      :work_item_id,
      :workflow,
      :specialist_role,
      :reason,
      :debounce_key,
      :policy_id,
      :created_at,
      diagnostics: %{}
    ]
  end

  defmodule CompactionSummary do
    @moduledoc "Bounded prompt-context summary produced by the context compactor."
    @enforce_keys [
      :id,
      :managed_repo_id,
      :work_item_id,
      :workflow,
      :specialist_role,
      :summary_text,
      :source_span_ids,
      :created_at,
      :policy_id
    ]
    defstruct [
      :id,
      :managed_repo_id,
      :work_item_id,
      :workflow,
      :specialist_role,
      :conversation_id,
      :turn_id,
      :summary_text,
      :source_span_ids,
      :retention,
      :policy_id,
      :created_at,
      :superseded_at,
      original_estimate: %{},
      summary_estimate: %{},
      replacement: %{},
      diagnostics: %{}
    ]
  end

  @type policy :: map()
  @type metadata :: map()
  @type budget_observation :: %BudgetObservation{}
  @type recommendation :: %Recommendation{}
  @type compaction_summary :: %CompactionSummary{}
  @type compaction_candidate :: map()

  @doc "Returns the stable context-management pod id for a work item."
  @spec pod_id(String.t()) :: String.t()
  def pod_id(work_item_id) when is_binary(work_item_id), do: "context-management-pod-#{work_item_id}"

  @doc "Returns whether context management is enabled for this request."
  @spec enabled?(keyword() | map()) :: boolean()
  def enabled?(opts \\ []) do
    opts = normalize_opts(opts)
    config = config()

    case Map.get(opts, :enabled?, Map.get(config, :enabled?, true)) do
      false -> false
      "false" -> false
      "0" -> false
      _other -> true
    end
  end

  @doc "Normalizes context-management policy from app config and request overrides."
  @spec policy(keyword() | map()) :: policy()
  def policy(opts \\ []) do
    opts = normalize_opts(opts)
    config = config()

    %{
      id: normalize_optional_string(Map.get(opts, :id, Map.get(config, :id))) || @default_policy_id,
      enabled?: enabled?(opts),
      compaction_enabled?:
        boolean_value(Map.get(opts, :compaction_enabled?, Map.get(config, :compaction_enabled?, true)), true),
      high_water_mark:
        ratio_value(Map.get(opts, :high_water_mark, Map.get(config, :high_water_mark)), @default_high_water_mark),
      repeated_trim_threshold:
        positive_integer(
          Map.get(opts, :repeated_trim_threshold, Map.get(config, :repeated_trim_threshold)),
          @default_repeated_trim_threshold
        ),
      debounce_window_ms:
        positive_integer(
          Map.get(opts, :debounce_window_ms, Map.get(config, :debounce_window_ms)),
          @default_debounce_window_ms
        ),
      max_summary_tokens:
        positive_integer(
          Map.get(opts, :max_summary_tokens, Map.get(config, :max_summary_tokens)),
          @default_max_summary_tokens
        ),
      max_candidate_tokens:
        positive_integer(
          Map.get(opts, :max_candidate_tokens, Map.get(config, :max_candidate_tokens)),
          @default_max_candidate_tokens
        ),
      diagnostics: config_diagnostics(opts, config)
    }
  end

  @doc "Builds initial pod metadata for a work-item-scoped context-management pod."
  @spec initial_metadata(String.t(), String.t(), String.t(), String.t(), keyword() | map()) :: metadata()
  def initial_metadata(managed_repo_id, work_item_id, workspace_path, parent_pod_id, opts \\ []) do
    now = DateTime.utc_now()
    policy = policy(opts)

    %{
      scope: :work_item,
      managed_repo_id: managed_repo_id,
      work_item_id: work_item_id,
      workspace_path: workspace_path,
      parent_pod_id: parent_pod_id,
      runtime_status: :running,
      context_management_status: if(policy.enabled?, do: :healthy, else: :disabled),
      policy: public_policy(policy),
      observations: [],
      recommendations: [],
      summaries: [],
      latest_monitor_decision: nil,
      latest_compaction: nil,
      diagnostics: policy.diagnostics,
      updated_at: now
    }
  end

  @doc "Returns a concise public summary for pod metadata."
  @spec status_summary(metadata() | nil) :: map()
  def status_summary(nil) do
    %{
      "enabled?" => false,
      "state" => "unavailable",
      "observation_count" => 0,
      "recommendation_count" => 0,
      "summary_count" => 0,
      "latest_monitor_decision" => nil,
      "latest_compaction" => nil,
      "diagnostics" => [%{"kind" => "context_management_unavailable", "state" => "degraded"}]
    }
  end

  def status_summary(metadata) when is_map(metadata) do
    policy = normalize_map(Map.get(metadata, :policy, Map.get(metadata, "policy", %{})))

    %{
      "enabled?" => Map.get(policy, "enabled?", Map.get(policy, :enabled?, true)),
      "state" =>
        metadata
        |> Map.get(:context_management_status, Map.get(metadata, "context_management_status", :healthy))
        |> Atom.to_string(),
      "policy_id" => Map.get(policy, "id", Map.get(policy, :id)),
      "observation_count" => metadata |> Map.get(:observations, Map.get(metadata, "observations", [])) |> length(),
      "recommendation_count" =>
        metadata |> Map.get(:recommendations, Map.get(metadata, "recommendations", [])) |> length(),
      "summary_count" => metadata |> Map.get(:summaries, Map.get(metadata, "summaries", [])) |> length(),
      "latest_monitor_decision" =>
        stringify_keys(Map.get(metadata, :latest_monitor_decision, Map.get(metadata, "latest_monitor_decision"))),
      "latest_compaction" => stringify_keys(Map.get(metadata, :latest_compaction, Map.get(metadata, "latest_compaction"))),
      "diagnostics" =>
        metadata
        |> Map.get(:diagnostics, Map.get(metadata, "diagnostics", []))
        |> Enum.map(&stringify_keys/1)
    }
  end

  @doc "Builds a disabled status update without affecting request-time budget packing."
  @spec disabled_metadata(String.t()) :: metadata()
  def disabled_metadata(reason \\ "Context management is disabled for this request.") do
    %{
      context_management_status: :disabled,
      policy: %{id: @default_policy_id, enabled?: false, compaction_enabled?: false},
      latest_monitor_decision: %{
        state: :skipped,
        reason: reason,
        diagnostics: %{kind: :context_management_disabled, state: :skipped}
      },
      diagnostics: [%{kind: :context_management_disabled, state: :skipped, detail: reason}],
      updated_at: DateTime.utc_now()
    }
  end

  @doc "Returns a metadata-only observation struct."
  @spec observation(map()) :: {:ok, budget_observation()} | {:error, term()}
  def observation(attrs) when is_map(attrs) do
    with {:ok, managed_repo_id} <- required_string(attrs, :managed_repo_id),
         {:ok, work_item_id} <- required_string(attrs, :work_item_id),
         {:ok, workflow} <- required_string(attrs, :workflow),
         {:ok, specialist_role} <- required_string(attrs, :specialist_role) do
      {:ok,
       %BudgetObservation{
         managed_repo_id: managed_repo_id,
         work_item_id: work_item_id,
         workflow: workflow,
         specialist_role: specialist_role,
         conversation_id: optional_string(attrs, :conversation_id),
         turn_id: optional_string(attrs, :turn_id),
         source: optional_string(attrs, :source) || "agent_workspace",
         context_budget: ContextBudget.summary(Map.get(attrs, :context_budget, Map.get(attrs, "context_budget"))),
         tool_budget: ContextBudget.summary(Map.get(attrs, :tool_budget, Map.get(attrs, "tool_budget"))),
         diagnostics: redact_diagnostics(Map.get(attrs, :diagnostics, Map.get(attrs, "diagnostics", %{}))),
         observed_at: Map.get(attrs, :observed_at, DateTime.utc_now())
       }}
    end
  end

  def observation(_attrs), do: {:error, :invalid_observation}

  @doc "Adds a metadata-only budget observation to pod metadata."
  @spec add_observation(metadata(), map() | budget_observation(), keyword() | map()) ::
          {:ok, metadata()} | {:error, term()}
  def add_observation(metadata, observation_attrs, opts \\ [])

  def add_observation(metadata, %BudgetObservation{} = observation, opts) when is_map(metadata) do
    add_observation(metadata, Map.from_struct(observation), opts)
  end

  def add_observation(metadata, observation_attrs, _opts) when is_map(metadata) and is_map(observation_attrs) do
    with :ok <- reject_raw_context_metadata(observation_attrs),
         {:ok, observation} <- observation(observation_attrs) do
      observation_payload = public_payload(observation)
      observations = Map.get(metadata, :observations, Map.get(metadata, "observations", []))
      next_observations = observations ++ [observation_payload]
      policy = policy_from_metadata(metadata)
      existing_recommendations = Map.get(metadata, :recommendations, Map.get(metadata, "recommendations", []))
      decision = evaluate_observations(next_observations, policy)
      {recommendations, decision} = maybe_append_recommendation(existing_recommendations, decision)

      {:ok,
       metadata
       |> Map.put(:observations, next_observations)
       |> Map.put(:recommendations, recommendations)
       |> Map.put(:latest_monitor_decision, decision)
       |> Map.put(:context_management_status, monitor_status(decision))
       |> Map.put(:updated_at, DateTime.utc_now())}
    end
  end

  def add_observation(_metadata, _observation_attrs, _opts), do: {:error, :invalid_budget_observation_store}

  @doc "Evaluates budget observations into a deterministic monitor decision."
  @spec evaluate_observations([map()], policy()) :: map()
  def evaluate_observations(observations, policy \\ policy()) when is_list(observations) and is_map(policy) do
    latest = List.last(observations) || %{}
    context_budget = Map.get(latest, "context_budget", %{})
    diagnostics = Map.get(context_budget, "diagnostics", [])

    cond do
      unresolved_tool_group?(latest) ->
        monitor_decision(latest, policy, :blocked, :unresolved_tool_call_group)

      required_context_overflow?(context_budget, diagnostics) ->
        monitor_decision(latest, policy, :blocked, :required_context_overflow)

      high_water_exceeded?(context_budget, policy) ->
        monitor_decision(latest, policy, :recommend, :history_high_water_mark)

      repeated_trim?(observations, policy) ->
        monitor_decision(latest, policy, :recommend, :repeated_context_trimming)

      true ->
        monitor_decision(latest, policy, :healthy, :within_budget)
    end
  end

  @doc "Normalizes and validates a compaction summary record."
  @spec compaction_summary(map() | compaction_summary(), keyword() | map()) ::
          {:ok, compaction_summary()} | {:error, term()}
  def compaction_summary(attrs, opts \\ [])

  def compaction_summary(%CompactionSummary{} = summary, opts) do
    compaction_summary(Map.from_struct(summary), opts)
  end

  def compaction_summary(attrs, opts) when is_map(attrs) do
    policy = policy(opts)

    with :ok <- reject_raw_context_metadata(attrs),
         {:ok, managed_repo_id} <- required_string(attrs, :managed_repo_id),
         {:ok, work_item_id} <- required_string(attrs, :work_item_id),
         {:ok, workflow} <- required_string(attrs, :workflow),
         {:ok, specialist_role} <- required_string(attrs, :specialist_role),
         {:ok, summary_text} <- required_string(attrs, :summary_text),
         {:ok, source_span_ids} <- source_span_ids(attrs),
         :ok <- validate_summary_size(summary_text, policy) do
      summary_estimate = ContextBudget.estimate(summary_text)
      original_estimate = estimate_from_attrs(attrs, :original_estimate)
      now = DateTime.utc_now()

      {:ok,
       %CompactionSummary{
         id: optional_string(attrs, :id) || summary_id(work_item_id, workflow, specialist_role, source_span_ids),
         managed_repo_id: managed_repo_id,
         work_item_id: work_item_id,
         workflow: workflow,
         specialist_role: specialist_role,
         conversation_id: optional_string(attrs, :conversation_id),
         turn_id: optional_string(attrs, :turn_id),
         summary_text: summary_text,
         source_span_ids: source_span_ids,
         retention: normalize_retention(Map.get(attrs, :retention, Map.get(attrs, "retention", :important))),
         policy_id: optional_string(attrs, :policy_id) || policy.id,
         created_at: Map.get(attrs, :created_at, Map.get(attrs, "created_at", now)),
         superseded_at: Map.get(attrs, :superseded_at, Map.get(attrs, "superseded_at")),
         original_estimate: original_estimate,
         summary_estimate: summary_estimate,
         replacement:
           attrs
           |> Map.get(:replacement, Map.get(attrs, "replacement", %{}))
           |> normalize_replacement(source_span_ids),
         diagnostics:
           attrs
           |> Map.get(:diagnostics, Map.get(attrs, "diagnostics", %{}))
           |> redact_diagnostics()
       }}
    end
  end

  def compaction_summary(_attrs, _opts), do: {:error, :invalid_compaction_summary}

  @doc """
  Adds a compaction summary to pod metadata and marks prior same-span summaries
  as superseded.
  """
  @spec add_summary(metadata(), map() | compaction_summary(), keyword() | map()) ::
          {:ok, metadata()} | {:error, term()}
  def add_summary(metadata, summary_attrs, opts \\ [])

  def add_summary(metadata, summary_attrs, opts) when is_map(metadata) do
    with {:ok, summary} <- compaction_summary(summary_attrs, opts) do
      existing =
        metadata
        |> Map.get(:summaries, Map.get(metadata, "summaries", []))
        |> Enum.map(&public_payload/1)

      summary_payload = public_payload(summary)
      superseded = supersede_replaced_summaries(existing, summary_payload, DateTime.utc_now())

      {:ok,
       metadata
       |> Map.put(:summaries, superseded ++ [summary_payload])
       |> Map.put(:latest_compaction, compaction_event(summary_payload, :stored))
       |> Map.put(:context_management_status, :healthy)
       |> Map.put(:updated_at, DateTime.utc_now())}
    end
  end

  def add_summary(_metadata, _summary_attrs, _opts), do: {:error, :invalid_compaction_store}

  @doc "Returns active prompt-eligible summaries from pod metadata."
  @spec active_summaries(metadata() | nil, keyword() | map()) :: [map()]
  def active_summaries(metadata, opts \\ [])

  def active_summaries(nil, _opts), do: []

  def active_summaries(metadata, opts) when is_map(metadata) do
    opts = normalize_opts(opts)
    workflow = normalize_optional_string(Map.get(opts, :workflow))
    specialist_role = normalize_optional_string(Map.get(opts, :specialist_role))
    limit = positive_integer(Map.get(opts, :limit), 8)

    metadata
    |> Map.get(:summaries, Map.get(metadata, "summaries", []))
    |> Enum.map(&public_payload/1)
    |> Enum.filter(&(Map.get(&1, "superseded_at") in [nil, ""]))
    |> Enum.filter(fn summary ->
      (is_nil(workflow) or Map.get(summary, "workflow") == workflow) and
        (is_nil(specialist_role) or Map.get(summary, "specialist_role") == specialist_role)
    end)
    |> Enum.sort_by(&normalize_sort_datetime(Map.get(&1, "created_at")), {:desc, DateTime})
    |> Enum.take(limit)
  end

  def active_summaries(_metadata, _opts), do: []

  @doc """
  Builds a protocol-safe compaction candidate from older specialist messages.

  The latest non-system group is treated as active and excluded. Assistant
  tool-call messages must stay paired with following tool-result messages; an
  unresolved tool-call group is rejected as ineligible.
  """
  @spec compaction_candidate([map()], map() | keyword(), keyword() | map()) ::
          {:ok, compaction_candidate()} | {:error, term()}
  def compaction_candidate(messages, attrs, opts \\ [])

  def compaction_candidate(messages, attrs, opts) when is_list(messages) do
    policy = policy(opts)
    attrs = normalize_opts(attrs)
    body_messages = Enum.reject(messages, &(message_role(&1) == :system))
    groups = message_groups(body_messages)

    cond do
      Enum.any?(groups, &unresolved_message_tool_group?/1) ->
        {:ok, ineligible_candidate(attrs, policy, :unresolved_tool_call_group)}

      length(groups) <= 1 ->
        {:ok, ineligible_candidate(attrs, policy, :no_eligible_history)}

      true ->
        eligible_groups = Enum.drop(groups, -1)
        source_span_ids = Enum.map(eligible_groups, &group_span_id/1)
        source_text = render_candidate_source(eligible_groups)
        estimate = ContextBudget.estimate(source_text)

        if estimate.approximate_tokens > policy.max_candidate_tokens do
          {:ok,
           attrs
           |> ineligible_candidate(policy, :candidate_exceeds_policy)
           |> Map.put(:source_span_ids, source_span_ids)
           |> Map.put(:original_estimate, estimate)}
        else
          {:ok,
           %{
             eligible?: true,
             workflow: normalize_optional_string(Map.get(attrs, :workflow)),
             specialist_role: normalize_optional_string(Map.get(attrs, :specialist_role)),
             managed_repo_id: normalize_optional_string(Map.get(attrs, :managed_repo_id)),
             work_item_id: normalize_optional_string(Map.get(attrs, :work_item_id)),
             conversation_id: normalize_optional_string(Map.get(attrs, :conversation_id)),
             turn_id: normalize_optional_string(Map.get(attrs, :turn_id)),
             policy_id: policy.id,
             source_span_ids: source_span_ids,
             source_text: source_text,
             original_estimate: estimate,
             diagnostics: %{
               kind: :compaction_candidate,
               state: :eligible,
               original_message_count: length(messages),
               eligible_group_count: length(eligible_groups),
               excluded_active_group_count: 1
             }
           }}
        end
    end
  end

  def compaction_candidate(_messages, _attrs, _opts), do: {:error, :invalid_compaction_candidate}

  @doc "Converts a struct or map to metadata-safe public data."
  @spec public_payload(map() | struct() | nil) :: map() | nil
  def public_payload(nil), do: nil

  def public_payload(%module{} = struct)
      when module in [BudgetObservation, Recommendation, CompactionSummary] do
    struct
    |> Map.from_struct()
    |> public_payload()
  end

  def public_payload(%{} = map), do: map |> redact_diagnostics() |> stringify_keys()

  @doc "Returns the public policy shape stored in pod metadata."
  @spec public_policy(policy()) :: map()
  def public_policy(policy) when is_map(policy) do
    policy
    |> Map.take([
      :id,
      :enabled?,
      :compaction_enabled?,
      :high_water_mark,
      :repeated_trim_threshold,
      :debounce_window_ms,
      :max_summary_tokens,
      :max_candidate_tokens
    ])
  end

  @doc "Returns true when a metadata payload contains disallowed raw context keys."
  @spec raw_context_metadata?(term()) :: boolean()
  def raw_context_metadata?(value), do: contains_raw_key?(value)

  @doc "Returns :ok when metadata avoids raw prompt and raw tool-output keys."
  @spec reject_raw_context_metadata(term()) :: :ok | {:error, term()}
  def reject_raw_context_metadata(value) do
    if raw_context_metadata?(value) do
      {:error, :raw_context_metadata_rejected}
    else
      :ok
    end
  end

  @doc "Redacts diagnostics and rejects raw prompt/tool-output keys."
  @spec redact_diagnostics(term()) :: term()
  def redact_diagnostics(%_module{} = struct), do: struct

  def redact_diagnostics(%{} = map) do
    map
    |> Enum.reject(fn {key, _value} -> raw_key?(key) end)
    |> Enum.map(fn {key, value} -> {key, redact_diagnostics(value)} end)
    |> Map.new()
  end

  def redact_diagnostics(list) when is_list(list), do: Enum.map(list, &redact_diagnostics/1)
  def redact_diagnostics(value), do: value

  defp config do
    Application.get_env(:jido_code, :context_management, [])
    |> normalize_opts()
  end

  defp config_diagnostics(opts, config) do
    [:high_water_mark, :repeated_trim_threshold, :debounce_window_ms, :max_summary_tokens, :max_candidate_tokens]
    |> Enum.flat_map(fn key ->
      value = Map.get(opts, key, Map.get(config, key))

      cond do
        is_nil(value) ->
          []

        key == :high_water_mark and ratio_value(value, nil) == nil ->
          [%{kind: :invalid_context_management_config, state: :degraded, key: key, value: inspect(value)}]

        key != :high_water_mark and positive_integer(value, nil) == nil ->
          [%{kind: :invalid_context_management_config, state: :degraded, key: key, value: inspect(value)}]

        true ->
          []
      end
    end)
  end

  defp policy_from_metadata(metadata) do
    metadata
    |> Map.get(:policy, Map.get(metadata, "policy", %{}))
    |> case do
      %{} = stored_policy ->
        policy(Map.merge(config(), normalize_map(stored_policy)))

      _other ->
        policy()
    end
  end

  defp unresolved_tool_group?(observation) do
    observation
    |> Map.get("diagnostics", %{})
    |> get_in_any([["unresolved_tool_call_group?"], [:unresolved_tool_call_group?]])
    |> case do
      true -> true
      "true" -> true
      _other -> false
    end
  end

  defp required_context_overflow?(context_budget, diagnostics) do
    degraded? =
      Map.get(context_budget, "degraded?", Map.get(context_budget, :degraded?, false)) in [true, "true"]

    required_degraded? =
      Enum.any?(diagnostics, fn diagnostic ->
        diagnostic_state(diagnostic) == "degraded" and diagnostic_retention(diagnostic) == "required"
      end)

    degraded? or required_degraded?
  end

  defp high_water_exceeded?(context_budget, policy) do
    budget = numeric_value(Map.get(context_budget, "model_budget", Map.get(context_budget, :model_budget)), 0)
    estimated =
      numeric_value(Map.get(context_budget, "estimated_input_tokens", Map.get(context_budget, :estimated_input_tokens)), 0)

    budget > 0 and estimated / budget >= policy.high_water_mark
  end

  defp repeated_trim?(observations, policy) do
    trim_count =
      observations
      |> Enum.take(-policy.repeated_trim_threshold)
      |> Enum.count(&trimmed_observation?/1)

    trim_count >= policy.repeated_trim_threshold
  end

  defp trimmed_observation?(observation) do
    context_budget = Map.get(observation, "context_budget", %{})

    Map.get(context_budget, "state") in ["trimmed", :trimmed] or
      Enum.any?(Map.get(context_budget, "diagnostics", []), fn diagnostic ->
        diagnostic_state(diagnostic) in ["trimmed", "dropped", "truncated"]
      end)
  end

  defp monitor_decision(observation, policy, state, reason) do
    workflow = Map.get(observation, "workflow")
    specialist_role = Map.get(observation, "specialist_role")
    debounce_key = monitor_debounce_key(observation, reason)

    %{
      id: observation_decision_id(observation),
      state: state,
      reason: reason,
      managed_repo_id: Map.get(observation, "managed_repo_id"),
      work_item_id: Map.get(observation, "work_item_id"),
      workflow: workflow,
      specialist_role: specialist_role,
      source: Map.get(observation, "source"),
      debounce_key: debounce_key,
      policy_id: policy.id,
      created_at: DateTime.utc_now(),
      diagnostics: %{
        kind: :budget_monitor_decision,
        state: state,
        reason: reason,
        observation_count: 1,
        high_water_mark: policy.high_water_mark,
        repeated_trim_threshold: policy.repeated_trim_threshold
      }
    }
  end

  defp monitor_debounce_key(observation, reason) do
    [
      Map.get(observation, "work_item_id"),
      Map.get(observation, "workflow"),
      Map.get(observation, "specialist_role"),
      reason,
      observation_span_key(observation)
    ]
    |> Enum.map(&to_string/1)
    |> Enum.join(":")
  end

  defp observation_span_key(observation) do
    observation
    |> Map.get("diagnostics", %{})
    |> get_in_any([["source_span_ids"], [:source_span_ids]])
    |> normalize_string_list()
    |> case do
      [] -> Map.get(observation, "turn_id") || Map.get(observation, "source") || "latest"
      span_ids -> span_key(span_ids)
    end
  end

  defp maybe_append_recommendation(recommendations, %{state: state} = decision)
       when state in [:recommend, "recommend", :blocked, "blocked", :degraded, "degraded"] do
    public_decision = public_payload(decision)
    debounce_key = Map.get(public_decision, "debounce_key")

    if Enum.any?(recommendations, &(Map.get(&1, "debounce_key") == debounce_key)) do
      {recommendations, Map.put(public_decision, "debounced?", true)}
    else
      {recommendations ++ [public_decision], public_decision}
    end
  end

  defp maybe_append_recommendation(recommendations, decision), do: {recommendations, public_payload(decision)}

  defp monitor_status(%{"state" => "healthy"}), do: :healthy
  defp monitor_status(%{"state" => "recommend"}), do: :recommend_compaction
  defp monitor_status(%{"state" => "blocked"}), do: :blocked
  defp monitor_status(%{"state" => "degraded"}), do: :degraded
  defp monitor_status(%{state: :healthy}), do: :healthy
  defp monitor_status(%{state: :recommend}), do: :recommend_compaction
  defp monitor_status(%{state: :blocked}), do: :blocked
  defp monitor_status(%{state: :degraded}), do: :degraded
  defp monitor_status(_decision), do: :healthy

  defp diagnostic_state(diagnostic) do
    diagnostic
    |> Map.get("state", Map.get(diagnostic, :state))
    |> normalize_optional_string()
  end

  defp diagnostic_retention(diagnostic) do
    diagnostic
    |> Map.get("retention", Map.get(diagnostic, :retention))
    |> normalize_optional_string()
  end

  defp get_in_any(map, paths) do
    Enum.find_value(paths, fn path -> get_in(map, path) end)
  end

  defp required_string(attrs, key) do
    case optional_string(attrs, key) do
      nil -> {:error, {:missing_required_context_management_field, key}}
      value -> {:ok, value}
    end
  end

  defp optional_string(attrs, key) do
    attrs
    |> Map.get(key, Map.get(attrs, Atom.to_string(key)))
    |> normalize_optional_string()
  end

  defp source_span_ids(attrs) do
    attrs
    |> Map.get(:source_span_ids, Map.get(attrs, "source_span_ids", []))
    |> normalize_string_list()
    |> case do
      [] -> {:error, :missing_source_span_ids}
      span_ids -> {:ok, span_ids}
    end
  end

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_string_list(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil -> []
      string -> [string]
    end
  end

  defp validate_summary_size(summary_text, policy) do
    estimate = ContextBudget.estimate(summary_text)

    if estimate.approximate_tokens <= policy.max_summary_tokens do
      :ok
    else
      {:error,
       {:summary_exceeds_policy,
        %{max_summary_tokens: policy.max_summary_tokens, approximate_tokens: estimate.approximate_tokens}}}
    end
  end

  defp estimate_from_attrs(attrs, key) do
    attrs
    |> Map.get(key, Map.get(attrs, Atom.to_string(key), %{}))
    |> normalize_map()
    |> case do
      estimate when map_size(estimate) > 0 ->
        estimate

      _estimate ->
        source_text = Map.get(attrs, :source_text, Map.get(attrs, "source_text", ""))
        ContextBudget.estimate(source_text)
    end
  end

  defp normalize_replacement(replacement, source_span_ids) do
    replacement
    |> normalize_map()
    |> Map.put(:source_span_ids, source_span_ids)
    |> Map.put_new(:mode, :summary)
    |> redact_diagnostics()
  end

  defp normalize_retention(retention) when retention in [:required, :important, :useful, :optional], do: retention

  defp normalize_retention(retention) when is_binary(retention) do
    retention
    |> String.trim()
    |> String.downcase()
    |> String.to_existing_atom()
    |> normalize_retention()
  rescue
    ArgumentError -> :important
  end

  defp normalize_retention(_retention), do: :important

  defp summary_id(work_item_id, workflow, specialist_role, source_span_ids) do
    digest =
      :crypto.hash(:sha256, Enum.join([work_item_id, workflow, specialist_role | source_span_ids], "|"))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 16)

    "summary_#{digest}"
  end

  defp observation_decision_id(observation_payload) do
    digest =
      :crypto.hash(
        :sha256,
        Enum.join(
          [
            Map.get(observation_payload, "managed_repo_id"),
            Map.get(observation_payload, "work_item_id"),
            Map.get(observation_payload, "workflow"),
            Map.get(observation_payload, "specialist_role"),
            Map.get(observation_payload, "observed_at") |> inspect()
          ],
          "|"
        )
      )
      |> Base.encode16(case: :lower)
      |> binary_part(0, 16)

    "context_observation_#{digest}"
  end

  defp supersede_replaced_summaries(existing, summary_payload, superseded_at) do
    replacement_key = span_key(Map.get(summary_payload, "source_span_ids", []))

    Enum.map(existing, fn existing_summary ->
      if span_key(Map.get(existing_summary, "source_span_ids", [])) == replacement_key do
        Map.put(existing_summary, "superseded_at", superseded_at)
      else
        existing_summary
      end
    end)
  end

  defp span_key(source_span_ids) do
    source_span_ids
    |> normalize_string_list()
    |> Enum.sort()
    |> Enum.join("|")
  end

  defp compaction_event(summary_payload, state) do
    %{
      id: Map.get(summary_payload, "id"),
      state: state,
      workflow: Map.get(summary_payload, "workflow"),
      specialist_role: Map.get(summary_payload, "specialist_role"),
      source_span_count: summary_payload |> Map.get("source_span_ids", []) |> length(),
      summary_estimate: Map.get(summary_payload, "summary_estimate", %{}),
      policy_id: Map.get(summary_payload, "policy_id"),
      updated_at: DateTime.utc_now()
    }
  end

  defp normalize_sort_datetime(%DateTime{} = datetime), do: datetime

  defp normalize_sort_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _other -> DateTime.from_unix!(0)
    end
  end

  defp normalize_sort_datetime(_value), do: DateTime.from_unix!(0)

  defp ineligible_candidate(attrs, policy, reason) do
    %{
      eligible?: false,
      workflow: normalize_optional_string(Map.get(attrs, :workflow)),
      specialist_role: normalize_optional_string(Map.get(attrs, :specialist_role)),
      managed_repo_id: normalize_optional_string(Map.get(attrs, :managed_repo_id)),
      work_item_id: normalize_optional_string(Map.get(attrs, :work_item_id)),
      conversation_id: normalize_optional_string(Map.get(attrs, :conversation_id)),
      turn_id: normalize_optional_string(Map.get(attrs, :turn_id)),
      policy_id: policy.id,
      source_span_ids: [],
      source_text: "",
      original_estimate: %{bytes: 0, approximate_tokens: 0},
      diagnostics: %{kind: :compaction_candidate, state: :blocked, reason: reason}
    }
  end

  defp message_groups(messages) do
    messages
    |> Enum.with_index()
    |> Enum.reduce([], fn {message, index}, groups ->
      indexed_message = Map.put(message, :__context_index__, index)

      if message_role(indexed_message) == :tool and groups != [] and assistant_tool_group?(List.last(groups)) do
        List.update_at(groups, -1, &(&1 ++ [indexed_message]))
      else
        groups ++ [[indexed_message]]
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
    message_role(message) == :assistant and message_tool_calls(message) != []
  end

  defp unresolved_message_tool_group?(group) do
    assistant_tool_group?(group) and not Enum.any?(group, &(message_role(&1) == :tool))
  end

  defp group_span_id(group) do
    group
    |> Enum.map(fn message ->
      normalize_optional_string(Map.get(message, :id, Map.get(message, "id"))) ||
        "message-#{Map.fetch!(message, :__context_index__)}"
    end)
    |> Enum.join("..")
  end

  defp render_candidate_source(groups) do
    groups
    |> List.flatten()
    |> Enum.map_join("\n", fn message ->
      role = message_role(message)
      content = normalize_optional_string(Map.get(message, :content, Map.get(message, "content"))) || ""
      "#{role}: #{content}"
    end)
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

  defp message_tool_calls(%{} = message) do
    message
    |> Map.get(:tool_calls, Map.get(message, "tool_calls", []))
    |> case do
      calls when is_list(calls) -> calls
      _other -> []
    end
  end

  defp message_tool_calls(_message), do: []

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(value), do: inspect(value)

  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(opts) when is_map(opts), do: normalize_map(opts)
  defp normalize_opts(_opts), do: %{}

  defp normalize_map(%{} = map) do
    map
    |> Enum.map(fn {key, value} -> {normalize_key(key), value} end)
    |> Map.new()
  end

  defp normalize_map(_map), do: %{}

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    key
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> key
  end

  defp normalize_key(key), do: key

  defp boolean_value(value, _default) when value in [true, "true", "1"], do: true
  defp boolean_value(value, _default) when value in [false, "false", "0"], do: false
  defp boolean_value(_value, default), do: default

  defp ratio_value(value, _default) when is_float(value) and value > 0 and value <= 1, do: value
  defp ratio_value(value, _default) when is_integer(value) and value > 0 and value <= 100, do: value / 100

  defp ratio_value(value, default) when is_binary(value) do
    case Float.parse(value) do
      {parsed, ""} -> ratio_value(parsed, default)
      _other -> default
    end
  end

  defp ratio_value(_value, default), do: default

  defp positive_integer(nil, default), do: default
  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _other -> default
    end
  end

  defp positive_integer(_value, default), do: default

  defp numeric_value(value, _default) when is_integer(value), do: value
  defp numeric_value(value, _default) when is_float(value), do: value

  defp numeric_value(value, default) when is_binary(value) do
    case Float.parse(value) do
      {parsed, ""} -> parsed
      _other -> default
    end
  end

  defp numeric_value(_value, default), do: default

  defp raw_key?(key) when is_atom(key), do: raw_key?(Atom.to_string(key))

  defp raw_key?(key) when is_binary(key) do
    key
    |> String.downcase()
    |> String.replace("-", "_")
    |> then(&(&1 in ["prompt", "raw_prompt", "raw_tool_output", "tool_output", "messages", "transcript"]))
  end

  defp raw_key?(_key), do: false

  defp contains_raw_key?(%_module{}), do: false

  defp contains_raw_key?(%{} = map) do
    Enum.any?(map, fn {key, value} -> raw_key?(key) or contains_raw_key?(value) end)
  end

  defp contains_raw_key?(list) when is_list(list), do: Enum.any?(list, &contains_raw_key?/1)
  defp contains_raw_key?(_value), do: false

  defp stringify_keys(%_module{} = struct), do: struct

  defp stringify_keys(%{} = map) do
    Map.new(map, fn {key, value} -> {stringify_key(key), stringify_keys(value)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(nil), do: nil
  defp stringify_keys(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_keys(value), do: value

  defp stringify_key(key) when is_atom(key), do: Atom.to_string(key)
  defp stringify_key(key), do: key
end
