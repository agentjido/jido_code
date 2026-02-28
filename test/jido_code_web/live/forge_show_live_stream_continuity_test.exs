defmodule JidoCodeWeb.ForgeShowLiveStreamContinuityTest do
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Forge
  alias JidoCode.Forge.Persistence
  alias JidoCode.Forge.PubSub, as: ForgePubSub

  defmodule FailingSubscriber do
    def subscribe(_pubsub, _topic), do: {:error, :forced_subscription_failure}
    def unsubscribe(_pubsub, _topic), do: :ok
  end

  setup do
    original_subscriber = Application.get_env(:jido_code, :forge_pubsub_subscriber)

    on_exit(fn ->
      if original_subscriber do
        Application.put_env(:jido_code, :forge_pubsub_subscriber, original_subscriber)
      else
        Application.delete_env(:jido_code, :forge_pubsub_subscriber)
      end
    end)

    :ok
  end

  test "subscribes to forge session topic and renders streamed output", %{conn: conn} do
    session_id = start_session!()

    {:ok, view, _html} =
      live_isolated(conn, JidoCodeWeb.Forge.ShowLive, session: %{"session_id" => session_id})

    assert :ok =
             ForgePubSub.broadcast_session(
               session_id,
               {:output, %{chunk: "topic-stream-line", seq: 1}}
             )

    assert_eventually(fn ->
      has_element?(view, "#terminal", "topic-stream-line")
    end)
  end

  test "preserves output ordering and labels discontinuities when a sequence gap appears", %{
    conn: conn
  } do
    session_id = start_session!()

    {:ok, view, _html} =
      live_isolated(conn, JidoCodeWeb.Forge.ShowLive, session: %{"session_id" => session_id})

    send(view.pid, {:output, %{chunk: "first-sequence-line", seq: 1}})
    send(view.pid, {:output, %{chunk: "third-sequence-line", seq: 3}})
    send(view.pid, {:output, %{chunk: "late-second-sequence-line", seq: 2}})

    assert_eventually(fn ->
      has_element?(
        view,
        "#terminal",
        "[stream discontinuity] missing output sequence 2..2; resumed at 3."
      )
    end)

    html = render(view)

    assert has_element?(view, "#forge-stream-discontinuity-count", "discontinuities: 1")
    refute html =~ "late-second-sequence-line"

    {first_index, _} = :binary.match(html, "first-sequence-line")

    {gap_index, _} =
      :binary.match(html, "[stream discontinuity] missing output sequence 2..2; resumed at 3.")

    {third_index, _} = :binary.match(html, "third-sequence-line")

    assert first_index < gap_index
    assert gap_index < third_index
  end

  test "surfaces degraded mode and keeps persisted logs when stream subscription fails", %{
    conn: conn
  } do
    session_id = start_session!()

    assert {:ok, _session} =
             Persistence.record_execution_complete(session_id, %{
               status: :done,
               output: "persisted-output-line"
             })

    Application.put_env(:jido_code, :forge_pubsub_subscriber, FailingSubscriber)

    {:ok, view, _html} =
      live_isolated(conn, JidoCodeWeb.Forge.ShowLive, session: %{"session_id" => session_id})

    assert has_element?(view, "#forge-stream-degraded-alert", "Stream degraded mode")
    assert has_element?(view, "#forge-stream-degraded-alert", "Showing persisted logs only")
    assert has_element?(view, "#terminal", "persisted-output-line")
  end

  defp start_session! do
    session_id = "forge-stream-#{System.unique_integer([:positive])}"

    spec = %{
      infra_client: :fake,
      runner: :shell,
      runner_config: %{command: "echo stream-ready"},
      env: %{},
      bootstrap: []
    }

    assert {:ok, _handle} = Forge.start_session(session_id, spec)

    on_exit(fn ->
      case Forge.stop_session(session_id) do
        :ok -> :ok
        {:error, :not_found} -> :ok
      end
    end)

    session_id
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
