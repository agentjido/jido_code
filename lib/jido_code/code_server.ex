defmodule JidoCode.CodeServer do
  @moduledoc """
  Internal facade for project-scoped conversation runtime operations.
  """

  require Logger

  alias Jido.Code.Server, as: Runtime
  alias Jido.Code.Server.Engine
  alias JidoCode.CodeServer.Error
  alias JidoCode.CodeServer.ProjectScope

  @runtime_start_remediation """
  Retry runtime startup. If this persists, verify workspace readiness and runtime configuration.
  """

  @conversation_start_remediation """
  Retry conversation startup after confirming the project runtime is healthy.
  """

  @message_send_remediation """
  Retry message send after starting a conversation for this project.
  """

  @subscription_remediation """
  Retry conversation subscription after confirming the conversation is active.
  """

  @conversation_control_remediation """
  Retry the conversation control action. If this persists, restart the project runtime.
  """

  @runtime_optional_config_keys [
    :llm_adapter,
    :llm_model,
    :llm_system_prompt,
    :llm_temperature,
    :llm_max_tokens,
    :tool_timeout_ms,
    :tool_timeout_alert_threshold,
    :tool_max_output_bytes,
    :tool_max_artifact_bytes,
    :tool_max_concurrency,
    :tool_max_concurrency_per_conversation,
    :llm_timeout_ms,
    :watcher,
    :watcher_debounce_ms,
    :strict_asset_loading,
    :allow_tools,
    :deny_tools,
    :network_egress_policy,
    :network_allowlist,
    :network_allowed_schemes,
    :sensitive_path_denylist,
    :sensitive_path_allowlist,
    :outside_root_allowlist,
    :tool_env_allowlist,
    :protocol_allowlist,
    :command_executor
  ]

  @type runtime_status :: :started | :reused

  @type runtime_handle :: %{
          project_id: String.t(),
          root_path: String.t(),
          project: map(),
          runtime_status: runtime_status(),
          runtime_pid: pid() | nil
        }

  @spec ensure_project_runtime(term()) :: {:ok, runtime_handle()} | {:error, Error.typed_error()}
  def ensure_project_runtime(project_id) do
    normalized_project_id = normalize_optional_string(project_id)
    log_info("code_server.runtime.ensure.start", project_id: normalized_project_id)

    with {:ok, scope} <- scope_module().resolve(project_id),
         {:ok, runtime_handle} <- ensure_runtime(scope) do
      log_info("code_server.runtime.ensure.success",
        project_id: runtime_handle.project_id,
        runtime_status: runtime_handle.runtime_status
      )

      {:ok, runtime_handle}
    else
      {:error, typed_error} ->
        log_typed_error("code_server.runtime.ensure.failure", typed_error, project_id: normalized_project_id)

        {:error, typed_error}
    end
  end

  @spec start_conversation(term(), keyword()) :: {:ok, String.t()} | {:error, Error.typed_error()}
  def start_conversation(project_id, opts \\ [])

  def start_conversation(project_id, opts) when is_list(opts) do
    requested_conversation_id =
      normalize_optional_string(Keyword.get(opts, :conversation_id)) || generated_conversation_id()

    normalized_opts = Keyword.put(opts, :conversation_id, requested_conversation_id)

    with {:ok, runtime} <- ensure_project_runtime(project_id) do
      case runtime_module().start_conversation(runtime.project_id, normalized_opts) do
        {:ok, conversation_id} ->
          case conversation_driver_module().prepare_conversation(
                 conversation_driver_attrs(runtime, conversation_id, nil, opts)
               ) do
            {:ok, _context} ->
              log_info("code_server.conversation.start.success",
                project_id: runtime.project_id,
                conversation_id: normalize_optional_string(conversation_id) || requested_conversation_id
              )

              {:ok, conversation_id}

            {:error, reason} ->
              _ = runtime_module().stop_conversation(runtime.project_id, conversation_id)

              typed_error =
                Error.build(
                  "code_server_conversation_start_failed",
                  "Conversation startup failed (#{format_reason(reason)}).",
                  @conversation_start_remediation,
                  project_id: runtime.project_id,
                  conversation_id: requested_conversation_id
                )

              log_typed_error("code_server.conversation.start.failure", typed_error)

              {:error, typed_error}
          end

        {:error, reason} ->
          typed_error =
            Error.build(
              "code_server_conversation_start_failed",
              "Conversation startup failed (#{format_reason(reason)}).",
              @conversation_start_remediation,
              project_id: runtime.project_id,
              conversation_id: requested_conversation_id
            )

          log_typed_error("code_server.conversation.start.failure", typed_error)

          {:error, typed_error}
      end
    end
  end

  def start_conversation(project_id, _opts) do
    typed_error =
      Error.build(
        "code_server_conversation_start_failed",
        "Conversation startup options must be a keyword list.",
        @conversation_start_remediation,
        project_id: normalize_optional_string(project_id)
      )

    log_typed_error("code_server.conversation.start.failure", typed_error)

    {:error, typed_error}
  end

  @spec send_user_message(term(), term(), term(), keyword()) :: :ok | {:error, Error.typed_error()}
  def send_user_message(project_id, conversation_id, content, opts \\ [])

  def send_user_message(project_id, conversation_id, content, opts) when is_list(opts) do
    with {:ok, runtime} <- ensure_project_runtime(project_id),
         {:ok, normalized_conversation_id} <-
           normalize_conversation_id(
             conversation_id,
             runtime.project_id,
             "code_server_message_send_failed",
             @message_send_remediation
           ),
         {:ok, normalized_content} <-
           normalize_message_content(content, runtime.project_id, normalized_conversation_id),
         driver_attrs <- conversation_driver_attrs(runtime, normalized_conversation_id, normalized_content, opts),
         {:ok, user_event} <-
           build_user_message_event(normalized_content, conversation_message_opts(opts, driver_attrs)) do
      case conversation_driver_module().handle_turn(driver_attrs) do
        {:ok, %{events: driver_events}} ->
          dispatch_conversation_events(runtime.project_id, normalized_conversation_id, [user_event | driver_events])

        {:error, reason, driver_context, failure_event} ->
          _ =
            dispatch_conversation_events(runtime.project_id, normalized_conversation_id, [
              user_event,
              failure_event
            ])

          {:error,
           Error.build(
             "code_server_message_send_failed",
             "Conversation driver failed (#{format_reason(reason)}).",
             @message_send_remediation,
             project_id: runtime.project_id,
             conversation_id: normalized_conversation_id,
             request_id: map_get(driver_context, :request_id, "request_id", nil),
             correlation_id: map_get(driver_context, :correlation_id, "correlation_id", nil)
           )}
      end
    end
  end

  def send_user_message(project_id, conversation_id, _content, _opts) do
    {:error,
     Error.build(
       "code_server_message_send_failed",
       "Message options must be a keyword list.",
       @message_send_remediation,
       project_id: normalize_optional_string(project_id),
       conversation_id: normalize_optional_string(conversation_id)
     )}
  end

  @spec subscribe(term(), term(), pid()) :: :ok | {:error, Error.typed_error()}
  def subscribe(project_id, conversation_id, pid \\ self())

  def subscribe(project_id, conversation_id, pid) when is_pid(pid) do
    with {:ok, runtime} <- ensure_project_runtime(project_id),
         {:ok, normalized_conversation_id} <-
           normalize_conversation_id(
             conversation_id,
             runtime.project_id,
             "code_server_subscription_failed",
             @subscription_remediation
           ),
         :ok <- do_subscribe(runtime.project_id, normalized_conversation_id, pid) do
      :ok
    end
  end

  def subscribe(project_id, conversation_id, _pid) do
    {:error,
     Error.build(
       "code_server_subscription_failed",
       "Conversation subscriber must be a live process identifier.",
       @subscription_remediation,
       project_id: normalize_optional_string(project_id),
       conversation_id: normalize_optional_string(conversation_id)
     )}
  end

  @spec unsubscribe(term(), term(), pid()) :: :ok | {:error, Error.typed_error()}
  def unsubscribe(project_id, conversation_id, pid \\ self())

  def unsubscribe(project_id, conversation_id, pid) when is_pid(pid) do
    with {:ok, runtime} <- ensure_project_runtime(project_id),
         {:ok, normalized_conversation_id} <-
           normalize_conversation_id(
             conversation_id,
             runtime.project_id,
             "code_server_subscription_failed",
             @subscription_remediation
           ),
         :ok <- do_unsubscribe(runtime.project_id, normalized_conversation_id, pid) do
      :ok
    end
  end

  def unsubscribe(project_id, conversation_id, _pid) do
    {:error,
     Error.build(
       "code_server_subscription_failed",
       "Conversation subscriber must be a live process identifier.",
       @subscription_remediation,
       project_id: normalize_optional_string(project_id),
       conversation_id: normalize_optional_string(conversation_id)
     )}
  end

  @spec stop_conversation(term(), term()) :: :ok | {:error, Error.typed_error()}
  def stop_conversation(project_id, conversation_id) do
    with {:ok, runtime} <- ensure_project_runtime(project_id),
         {:ok, normalized_conversation_id} <-
           normalize_conversation_id(
             conversation_id,
             runtime.project_id,
             "code_server_unexpected_error",
             @conversation_control_remediation
           ),
         :ok <- do_stop_conversation(runtime.project_id, normalized_conversation_id) do
      log_info("code_server.conversation.stop.success",
        project_id: runtime.project_id,
        conversation_id: normalized_conversation_id
      )

      :ok
    else
      {:error, typed_error} ->
        log_typed_error("code_server.conversation.stop.failure", typed_error,
          project_id: normalize_optional_string(project_id),
          conversation_id: normalize_optional_string(conversation_id)
        )

        {:error, typed_error}
    end
  end

  defp ensure_runtime(%{project_id: project_id} = scope) do
    case engine_module().whereis_project(project_id) do
      {:ok, project_pid} ->
        {:ok, runtime_handle(scope, :reused, project_pid)}

      {:error, {:project_not_found, ^project_id}} ->
        start_runtime(scope)

      {:error, reason} ->
        {:error,
         Error.build(
           "code_server_runtime_start_failed",
           "Project runtime lookup failed (#{format_reason(reason)}).",
           @runtime_start_remediation,
           project_id: project_id
         )}
    end
  end

  defp start_runtime(%{project_id: project_id, root_path: root_path} = scope) do
    case runtime_module().start_project(root_path, start_project_opts(project_id)) do
      {:ok, _started_project_id} ->
        {:ok, runtime_handle(scope, :started, lookup_runtime_pid(project_id))}

      {:error, {:already_started, _already_started_project_id}} ->
        {:ok, runtime_handle(scope, :reused, lookup_runtime_pid(project_id))}

      {:error, reason} ->
        {:error,
         Error.build(
           "code_server_runtime_start_failed",
           "Project runtime startup failed (#{format_reason(reason)}).",
           @runtime_start_remediation,
           project_id: project_id
         )}
    end
  end

  defp dispatch_conversation_event(project_id, conversation_id, event) do
    case runtime_module().send_event(project_id, conversation_id, event) do
      :ok ->
        :ok

      {:error, reason} ->
        typed_error =
          Error.build(
            "code_server_message_send_failed",
            "Conversation message send failed (#{format_reason(reason)}).",
            @message_send_remediation,
            project_id: project_id,
            conversation_id: conversation_id
          )

        log_typed_error("code_server.message.send.failure", typed_error)

        {:error, typed_error}
    end
  end

  defp dispatch_conversation_events(project_id, conversation_id, events) when is_list(events) do
    Enum.reduce_while(events, :ok, fn event, :ok ->
      case dispatch_conversation_event(project_id, conversation_id, event) do
        :ok -> {:cont, :ok}
        {:error, typed_error} -> {:halt, {:error, typed_error}}
      end
    end)
  end

  defp do_subscribe(project_id, conversation_id, pid) do
    case runtime_module().subscribe_conversation(project_id, conversation_id, pid) do
      :ok ->
        :ok

      {:error, reason} ->
        typed_error =
          Error.build(
            "code_server_subscription_failed",
            "Conversation subscription failed (#{format_reason(reason)}).",
            @subscription_remediation,
            project_id: project_id,
            conversation_id: conversation_id
          )

        log_typed_error("code_server.subscription.failure", typed_error)

        {:error, typed_error}
    end
  end

  defp do_unsubscribe(project_id, conversation_id, pid) do
    case runtime_module().unsubscribe_conversation(project_id, conversation_id, pid) do
      :ok ->
        :ok

      {:error, reason} ->
        typed_error =
          Error.build(
            "code_server_subscription_failed",
            "Conversation unsubscription failed (#{format_reason(reason)}).",
            @subscription_remediation,
            project_id: project_id,
            conversation_id: conversation_id
          )

        log_typed_error("code_server.subscription.failure", typed_error)

        {:error, typed_error}
    end
  end

  defp do_stop_conversation(project_id, conversation_id) do
    case runtime_module().stop_conversation(project_id, conversation_id) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         Error.build(
           "code_server_unexpected_error",
           "Conversation stop failed (#{format_reason(reason)}).",
           @conversation_control_remediation,
           project_id: project_id,
           conversation_id: conversation_id
         )}
    end
  end

  defp build_user_message_event(content, opts) do
    metadata =
      opts
      |> Keyword.get(:meta, %{})
      |> normalize_map()

    event =
      %{
        "type" => "user.message",
        "data" => %{"content" => content}
      }
      |> maybe_put_meta(metadata)

    {:ok, event}
  end

  defp start_project_opts(project_id) do
    config = code_server_config()

    base_opts = [
      project_id: project_id,
      data_dir: map_get(config, :data_dir, "data_dir", ".jido"),
      conversation_orchestration: map_get(config, :conversation_orchestration, "conversation_orchestration", false)
    ]

    Enum.reduce(@runtime_optional_config_keys, base_opts, fn key, acc ->
      case config_fetch(config, key) do
        {:ok, value} -> Keyword.put(acc, key, value)
        :error -> acc
      end
    end)
  end

  defp code_server_config do
    :jido_code
    |> Application.get_env(:code_server, %{})
    |> normalize_map()
  end

  defp config_fetch(config, key) when is_map(config) and is_atom(key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(config, key) -> {:ok, Map.get(config, key)}
      Map.has_key?(config, string_key) -> {:ok, Map.get(config, string_key)}
      true -> :error
    end
  end

  defp config_fetch(_config, _key), do: :error

  defp maybe_put_meta(event, metadata) when map_size(metadata) == 0, do: event
  defp maybe_put_meta(event, metadata), do: Map.put(event, "meta", metadata)

  defp conversation_message_opts(opts, driver_attrs) do
    metadata =
      opts
      |> Keyword.get(:meta, %{})
      |> normalize_map()
      |> Map.merge(
        %{
          "actor_id" => map_get(driver_attrs, :actor_id, "actor_id", nil),
          "managed_repo_id" => map_get(driver_attrs, :managed_repo_id, "managed_repo_id", nil),
          "request_id" => map_get(driver_attrs, :request_id, "request_id", nil),
          "correlation_id" => map_get(driver_attrs, :correlation_id, "correlation_id", nil)
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()
      )

    Keyword.put(opts, :meta, metadata)
  end

  defp conversation_driver_attrs(runtime, conversation_id, content, opts) when is_map(runtime) and is_list(opts) do
    actor =
      opts
      |> Keyword.get(:actor, %{})
      |> normalize_map()

    %{
      project_id: runtime.project_id,
      managed_repo_id: resolve_managed_repo_id(runtime.project_id),
      conversation_id: conversation_id,
      session_id: conversation_id,
      content: content,
      actor_id:
        actor
        |> map_get(:id, "id", nil)
        |> normalize_optional_string(),
      actor_email:
        actor
        |> map_get(:email, "email", nil)
        |> normalize_optional_string(),
      work_item_id:
        opts
        |> Keyword.get(:work_item_id)
        |> normalize_optional_string(),
      operation:
        opts
        |> Keyword.get(:operation)
        |> normalize_optional_string(),
      request_id:
        opts
        |> Keyword.get(:request_id)
        |> normalize_optional_string() || generated_request_id("req"),
      correlation_id:
        opts
        |> Keyword.get(:correlation_id)
        |> normalize_optional_string() || generated_request_id("corr"),
      workspace_id: runtime.root_path
    }
  end

  defp conversation_driver_attrs(runtime, conversation_id, content, _opts)
       when is_map(runtime) and is_binary(conversation_id) do
    conversation_driver_attrs(runtime, conversation_id, content, [])
  end

  defp resolve_managed_repo_id(project_id) do
    case repo_bridge_module().managed_repo_for_project(project_id) do
      {:ok, managed_repo} ->
        managed_repo
        |> map_get(:id, "id", nil)
        |> normalize_optional_string()

      _other ->
        nil
    end
  end

  defp generated_conversation_id do
    "conversation-" <> generated_request_id("session")
  end

  defp generated_request_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp normalize_conversation_id(conversation_id, project_id, error_type, remediation) do
    case normalize_optional_string(conversation_id) do
      nil ->
        {:error,
         Error.build(
           error_type,
           "Conversation identifier is missing.",
           remediation,
           project_id: project_id
         )}

      normalized_conversation_id ->
        {:ok, normalized_conversation_id}
    end
  end

  defp normalize_message_content(content, project_id, conversation_id) do
    case normalize_optional_string(content) do
      nil ->
        {:error,
         Error.build(
           "code_server_message_send_failed",
           "Message content is missing.",
           @message_send_remediation,
           project_id: project_id,
           conversation_id: conversation_id
         )}

      normalized_content ->
        {:ok, normalized_content}
    end
  end

  defp lookup_runtime_pid(project_id) do
    case engine_module().whereis_project(project_id) do
      {:ok, project_pid} -> project_pid
      {:error, _reason} -> nil
    end
  end

  defp scope_module do
    Application.get_env(:jido_code, :code_server_project_scope_module, ProjectScope)
  end

  defp runtime_module do
    Application.get_env(:jido_code, :code_server_runtime_module, Runtime)
  end

  defp engine_module do
    Application.get_env(:jido_code, :code_server_engine_module, Engine)
  end

  defp conversation_driver_module do
    Application.get_env(:jido_code, :code_server_conversation_driver_module, JidoCode.Conversations.Driver)
  end

  defp repo_bridge_module do
    Application.get_env(:jido_code, :code_server_repo_bridge_module, JidoCode.Control.RepoBridge)
  end

  defp runtime_handle(scope, runtime_status, runtime_pid) do
    %{
      project_id: scope.project_id,
      root_path: scope.root_path,
      project: scope.project,
      runtime_status: runtime_status,
      runtime_pid: runtime_pid
    }
  end

  defp format_reason(reason) do
    Exception.message(reason)
  rescue
    _exception -> inspect(reason)
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_boolean(value), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(value) when is_float(value), do: :erlang.float_to_binary(value)
  defp normalize_optional_string(_value), do: nil

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp log_info(event, metadata) do
    normalized_metadata = normalize_log_metadata(metadata)
    Logger.info(format_log_message(event, normalized_metadata), normalized_metadata)
  end

  defp log_error(event, metadata) do
    normalized_metadata = normalize_log_metadata(metadata)
    Logger.error(format_log_message(event, normalized_metadata), normalized_metadata)
  end

  defp log_typed_error(event, typed_error, fallback_metadata \\ []) do
    base_metadata = [
      project_id: map_get(typed_error, :project_id, "project_id", nil),
      conversation_id: map_get(typed_error, :conversation_id, "conversation_id", nil),
      error_type: map_get(typed_error, :error_type, "error_type", "code_server_unexpected_error")
    ]

    merged_metadata = Keyword.merge(base_metadata, normalize_log_metadata(fallback_metadata))
    log_error(event, merged_metadata)
  end

  defp normalize_log_metadata(metadata) when is_list(metadata) do
    metadata
    |> Enum.reduce([], fn
      {key, value}, acc when is_atom(key) and not is_nil(value) -> [{key, value} | acc]
      _entry, acc -> acc
    end)
    |> Enum.reverse()
  end

  defp normalize_log_metadata(_metadata), do: []

  defp format_log_message(event, metadata) do
    case format_log_metadata(metadata) do
      "" -> event
      rendered_metadata -> event <> " " <> rendered_metadata
    end
  end

  defp format_log_metadata(metadata) do
    metadata
    |> Enum.map(fn {key, value} -> "#{key}=#{inspect(value)}" end)
    |> Enum.join(" ")
  end
end
