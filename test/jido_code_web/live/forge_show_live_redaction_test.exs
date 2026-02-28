defmodule JidoCodeWeb.ForgeShowLiveRedactionTest do
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Forge

  test "run details render masked placeholders for redacted output", %{conn: conn} do
    session_id = start_session!()

    {:ok, view, _html} =
      live_isolated(conn, JidoCodeWeb.Forge.ShowLive, session: %{"session_id" => session_id})

    secret = "sk-test-0123456789abcdef"
    send(view.pid, {:output, %{chunk: "Authorization: Bearer #{secret}", seq: 1}})
    render(view)

    assert has_element?(view, "#terminal", "Authorization: Bearer [REDACTED")
    refute has_element?(view, "#terminal", secret)
    refute has_element?(view, "#forge-run-security-alert")
  end

  test "run details flag security alert and suppress unsafe post-render output", %{conn: conn} do
    session_id = start_session!()

    {:ok, view, _html} =
      live_isolated(conn, JidoCodeWeb.Forge.ShowLive, session: %{"session_id" => session_id})

    leaked_token = "xoxb-12345678901234567890"
    send(view.pid, {:output, %{chunk: "unexpected credential #{leaked_token}", seq: 2}})
    render(view)

    assert has_element?(view, "#forge-run-security-alert", "Security alert")
    assert has_element?(view, "#terminal", "[SENSITIVE CONTENT SUPPRESSED]")
    refute has_element?(view, "#terminal", leaked_token)
  end

  defp start_session! do
    session_id = "forge-redaction-#{System.unique_integer([:positive])}"

    spec = %{
      infra_client: :fake,
      runner: :shell,
      runner_config: %{command: "echo redaction-ready"},
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
end
