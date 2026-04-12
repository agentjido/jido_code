defmodule JidoCodeWeb.Demos.ChatLiveTest do
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Conversations.Driver
  alias JidoCode.Projects.Project

  defmodule FailingSubscriber do
    def subscribe(_pubsub, _topic), do: {:error, :forced_subscription_failure}
    def unsubscribe(_pubsub, _topic), do: :ok
  end

  setup do
    original_subscriber =
      Application.get_env(:jido_code, :conversation_pubsub_subscriber, Phoenix.PubSub)

    on_exit(fn ->
      Application.put_env(:jido_code, :conversation_pubsub_subscriber, original_subscriber)
    end)

    :ok
  end

  test "renders live conversation events after the browser attaches the stream", %{conn: conn} do
    managed_repo = managed_repo_fixture!("live-updates")

    {:ok, view, _html} =
      live_isolated(conn, JidoCodeWeb.Demos.ChatLive, session: %{"managed_repo_id" => managed_repo.id})

    render_hook(view, "client_ready", %{"after_sequence" => "0"})
    conversation_id = capture_data_attr(render(view), "conversation-id")

    on_exit(fn ->
      :ok = Driver.stop(conversation_id)
    end)

    view
    |> form("#chat-form", input: "Inspect the event-driven conversation demo.")
    |> render_submit()

    assert_eventually(fn ->
      has_element?(view, "#conversation-events", "turn.started")
    end)

    assert_eventually(fn ->
      has_element?(view, "#conversation-events", "tool.completed")
    end)

    assert has_element?(view, "#conversation-stream-discontinuity-count", "discontinuities: 0")
  end

  test "reconnect resumes from the next available event sequence when continuity is available", %{conn: conn} do
    managed_repo = managed_repo_fixture!("reconnect")

    {:ok, first_view, _html} =
      live_isolated(conn, JidoCodeWeb.Demos.ChatLive, session: %{"managed_repo_id" => managed_repo.id})

    render_hook(first_view, "client_ready", %{"after_sequence" => "0"})
    conversation_id = capture_data_attr(render(first_view), "conversation-id")

    on_exit(fn ->
      :ok = Driver.stop(conversation_id)
    end)

    first_view
    |> form("#chat-form", input: "Prepare reconnect continuity coverage.")
    |> render_submit()

    assert_eventually(fn ->
      html = render(first_view)
      html =~ "tool.completed"
    end)

    first_html = render(first_view)
    last_sequence = capture_data_attr(first_html, "last-event-sequence") |> String.to_integer()
    after_sequence = max(last_sequence - 2, 0)

    {:ok, resumed_view, _html} =
      live_isolated(conn, JidoCodeWeb.Demos.ChatLive, session: %{"managed_repo_id" => managed_repo.id})

    render_hook(resumed_view, "client_ready", %{
      "conversation_id" => conversation_id,
      "after_sequence" => Integer.to_string(after_sequence)
    })

    assert has_element?(
             resumed_view,
             "#conversation-demo",
             "Conversation stream resumed from event sequence #{after_sequence + 1}."
           )
  end

  test "surfaces degraded-mode messaging when the conversation stream subscription fails", %{conn: conn} do
    managed_repo = managed_repo_fixture!("degraded")

    Application.put_env(:jido_code, :conversation_pubsub_subscriber, FailingSubscriber)

    {:ok, view, _html} =
      live_isolated(conn, JidoCodeWeb.Demos.ChatLive, session: %{"managed_repo_id" => managed_repo.id})

    render_hook(view, "client_ready", %{"after_sequence" => "0"})
    conversation_id = capture_data_attr(render(view), "conversation-id")

    on_exit(fn ->
      :ok = Driver.stop(conversation_id)
    end)

    assert has_element?(view, "#conversation-stream-degraded-alert", "Stream degraded mode")
    assert has_element?(view, "#conversation-stream-degraded-alert", "Showing the latest conversation snapshot only")
  end

  defp managed_repo_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "chat-live-#{suffix}",
        github_full_name: "owner/chat-live-#{suffix}",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    managed_repo
  end

  defp capture_data_attr(html, attr_name) do
    Regex.run(~r/data-#{attr_name}="([^"]+)"/, html, capture: :all_but_first)
    |> List.first()
  end

  defp assert_eventually(assertion_fun, timeout_ms \\ 1_500) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_assert_eventually(assertion_fun, deadline)
  end

  defp do_assert_eventually(assertion_fun, deadline) do
    if assertion_fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        flunk("expected assertion to pass before timeout")
      else
        receive do
        after
          25 -> do_assert_eventually(assertion_fun, deadline)
        end
      end
    end
  end
end
