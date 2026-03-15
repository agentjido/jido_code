defmodule JidoCode.CodeServerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  require Logger

  alias JidoCode.CodeServer
  alias JidoCode.TestSupport.CodeServer.EngineFake
  alias JidoCode.TestSupport.CodeServer.RuntimeFake
  alias JidoCode.TestSupport.CodeServer.ScopeFake

  setup do
    original_scope_module = Application.get_env(:jido_code, :code_server_project_scope_module, :__missing__)
    original_runtime_module = Application.get_env(:jido_code, :code_server_runtime_module, :__missing__)
    original_engine_module = Application.get_env(:jido_code, :code_server_engine_module, :__missing__)

    Application.put_env(:jido_code, :code_server_project_scope_module, ScopeFake)
    Application.put_env(:jido_code, :code_server_runtime_module, RuntimeFake)
    Application.put_env(:jido_code, :code_server_engine_module, EngineFake)

    ScopeFake.clear()
    RuntimeFake.clear()
    EngineFake.clear()

    on_exit(fn ->
      ScopeFake.clear()
      RuntimeFake.clear()
      EngineFake.clear()

      restore_env(:code_server_project_scope_module, original_scope_module)
      restore_env(:code_server_runtime_module, original_runtime_module)
      restore_env(:code_server_engine_module, original_engine_module)
    end)

    :ok
  end

  test "ensure_project_runtime lazily starts project runtime when missing" do
    ScopeFake.put_resolve_result(
      {:ok,
       %{
         project_id: "project-lazy-start",
         root_path: "/tmp/project-lazy-start",
         project: %{id: "project-lazy-start"}
       }}
    )

    EngineFake.put_whereis_responses("project-lazy-start", [
      {:error, {:project_not_found, "project-lazy-start"}},
      {:ok, self()}
    ])

    assert {:ok, runtime_handle} = CodeServer.ensure_project_runtime("project-lazy-start")
    assert runtime_handle.runtime_status == :started
    assert runtime_handle.runtime_pid == self()

    assert [{"/tmp/project-lazy-start", opts}] = RuntimeFake.calls(:start_project)
    assert Keyword.get(opts, :project_id) == "project-lazy-start"
    assert Keyword.get(opts, :conversation_orchestration) == true
    assert EngineFake.whereis_calls() == ["project-lazy-start", "project-lazy-start"]
  end

  test "ensure_project_runtime logs start and success with project metadata" do
    ScopeFake.put_resolve_result(
      {:ok,
       %{
         project_id: "project-log-runtime",
         root_path: "/tmp/project-log-runtime",
         project: %{id: "project-log-runtime"}
       }}
    )

    EngineFake.put_default_whereis_response({:ok, self()})

    log =
      capture_info_log(fn ->
        assert {:ok, runtime_handle} = CodeServer.ensure_project_runtime("project-log-runtime")
        assert runtime_handle.runtime_status == :reused
      end)

    assert log =~ "code_server.runtime.ensure.start"
    assert log =~ "project_id=\"project-log-runtime\""
    assert log =~ "code_server.runtime.ensure.success"
    assert log =~ "runtime_status=:reused"
  end

  test "ensure_project_runtime reuses existing runtime when already registered" do
    ScopeFake.put_resolve_result(
      {:ok,
       %{
         project_id: "project-runtime-ready",
         root_path: "/tmp/project-runtime-ready",
         project: %{id: "project-runtime-ready"}
       }}
    )

    EngineFake.put_whereis_responses("project-runtime-ready", [{:ok, self()}])

    assert {:ok, runtime_handle} = CodeServer.ensure_project_runtime("project-runtime-ready")
    assert runtime_handle.runtime_status == :reused
    assert runtime_handle.runtime_pid == self()
    assert RuntimeFake.calls(:start_project) == []
  end

  test "start_conversation and send_user_message delegate to runtime modules" do
    ScopeFake.put_resolve_result(
      {:ok,
       %{
         project_id: "project-chat",
         root_path: "/tmp/project-chat",
         project: %{id: "project-chat"}
       }}
    )

    EngineFake.put_default_whereis_response({:ok, self()})
    RuntimeFake.put_result(:start_conversation, {:ok, "conversation-42"})

    assert {:ok, "conversation-42"} = CodeServer.start_conversation("project-chat")

    assert :ok =
             CodeServer.send_user_message(
               "project-chat",
               "conversation-42",
               "Generate a summary",
               meta: %{"source" => "unit-test"}
             )

    assert [{"project-chat", "conversation-42", event}] = RuntimeFake.calls(:send_event)
    assert event["type"] == "user.message"
    assert get_in(event, ["data", "content"]) == "Generate a summary"
    assert get_in(event, ["meta", "source"]) == "unit-test"
  end

  test "start_conversation and stop_conversation emit observability logs" do
    ScopeFake.put_resolve_result(
      {:ok,
       %{
         project_id: "project-log-conversation",
         root_path: "/tmp/project-log-conversation",
         project: %{id: "project-log-conversation"}
       }}
    )

    EngineFake.put_default_whereis_response({:ok, self()})
    RuntimeFake.put_result(:start_conversation, {:ok, "conversation-log-1"})

    log =
      capture_info_log(fn ->
        assert {:ok, "conversation-log-1"} = CodeServer.start_conversation("project-log-conversation")
        assert :ok = CodeServer.stop_conversation("project-log-conversation", "conversation-log-1")
      end)

    assert log =~ "code_server.conversation.start.success"
    assert log =~ "code_server.conversation.stop.success"
    assert log =~ "project_id=\"project-log-conversation\""
    assert log =~ "conversation_id=\"conversation-log-1\""
  end

  test "send_user_message returns typed error when content is empty" do
    ScopeFake.put_resolve_result(
      {:ok,
       %{
         project_id: "project-empty-message",
         root_path: "/tmp/project-empty-message",
         project: %{id: "project-empty-message"}
       }}
    )

    EngineFake.put_default_whereis_response({:ok, self()})

    assert {:error, typed_error} =
             CodeServer.send_user_message("project-empty-message", "conversation-1", "   ")

    assert typed_error.error_type == "code_server_message_send_failed"
    assert typed_error.detail =~ "Message content is missing"
    assert RuntimeFake.calls(:send_event) == []
  end

  test "stop_conversation returns typed error when runtime stop fails" do
    ScopeFake.put_resolve_result(
      {:ok,
       %{
         project_id: "project-stop-failure",
         root_path: "/tmp/project-stop-failure",
         project: %{id: "project-stop-failure"}
       }}
    )

    EngineFake.put_default_whereis_response({:ok, self()})
    RuntimeFake.put_result(:stop_conversation, {:error, :boom})

    assert {:error, typed_error} = CodeServer.stop_conversation("project-stop-failure", "conversation-1")
    assert typed_error.error_type == "code_server_unexpected_error"
    assert typed_error.detail =~ "Conversation stop failed"
    assert typed_error.detail =~ "boom"
  end

  test "send_user_message logs failure with typed error metadata and no payload content" do
    ScopeFake.put_resolve_result(
      {:ok,
       %{
         project_id: "project-log-send-failure",
         root_path: "/tmp/project-log-send-failure",
         project: %{id: "project-log-send-failure"}
       }}
    )

    EngineFake.put_default_whereis_response({:ok, self()})
    RuntimeFake.put_result(:send_event, {:error, :boom})

    log =
      capture_log(fn ->
        assert {:error, typed_error} =
                 CodeServer.send_user_message(
                   "project-log-send-failure",
                   "conversation-log-2",
                   "do not log this content"
                 )

        assert typed_error.error_type == "code_server_message_send_failed"
      end)

    assert log =~ "code_server.message.send.failure"
    assert log =~ "project_id=\"project-log-send-failure\""
    assert log =~ "conversation_id=\"conversation-log-2\""
    assert log =~ "error_type=\"code_server_message_send_failed\""
    refute log =~ "do not log this content"
  end

  test "subscribe returns typed error when pid is invalid" do
    assert {:error, typed_error} = CodeServer.subscribe("project-invalid-pid", "conversation-1", :not_a_pid)
    assert typed_error.error_type == "code_server_subscription_failed"
    assert typed_error.detail =~ "subscriber must be a live process identifier"
  end

  test "subscribe logs failure with error_type metadata" do
    ScopeFake.put_resolve_result(
      {:ok,
       %{
         project_id: "project-log-subscribe",
         root_path: "/tmp/project-log-subscribe",
         project: %{id: "project-log-subscribe"}
       }}
    )

    EngineFake.put_default_whereis_response({:ok, self()})
    RuntimeFake.put_result(:subscribe_conversation, {:error, :boom})

    log =
      capture_log(fn ->
        assert {:error, typed_error} =
                 CodeServer.subscribe("project-log-subscribe", "conversation-log-3", self())

        assert typed_error.error_type == "code_server_subscription_failed"
      end)

    assert log =~ "code_server.subscription.failure"
    assert log =~ "project_id=\"project-log-subscribe\""
    assert log =~ "conversation_id=\"conversation-log-3\""
    assert log =~ "error_type=\"code_server_subscription_failed\""
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)

  defp capture_info_log(fun) when is_function(fun, 0) do
    original_level = Logger.level()

    Logger.configure(level: :info)

    try do
      capture_log(fun)
    after
      Logger.configure(level: original_level)
    end
  end
end
