defmodule JidoCodeWeb.AgentsLiveTest do
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Projects.Project

  setup do
    original_project_loader =
      Application.get_env(:jido_code, :support_agent_config_project_loader, :__missing__)

    original_project_updater =
      Application.get_env(:jido_code, :support_agent_config_project_updater, :__missing__)

    on_exit(fn ->
      restore_env(:support_agent_config_project_loader, original_project_loader)
      restore_env(:support_agent_config_project_updater, original_project_updater)
    end)

    :ok
  end

  test "agents page exposes enable and disable controls and persists issue bot enabled state per project",
       %{
         conn: _conn
       } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project_enabled} =
      Project.create(%{
        name: "repo-enabled",
        github_full_name: "owner/repo-enabled",
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{"enabled" => true}
          }
        }
      })

    {:ok, project_disabled} =
      Project.create(%{
        name: "repo-disabled",
        github_full_name: "owner/repo-disabled",
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{"enabled" => false}
          }
        }
      })

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/agents", on_error: :warn)

    assert has_element?(view, "#agents-project-table")

    assert has_element?(
             view,
             "#agents-project-github-full-name-#{project_enabled.id}",
             "owner/repo-enabled"
           )

    assert has_element?(
             view,
             "#agents-project-github-full-name-#{project_disabled.id}",
             "owner/repo-disabled"
           )

    assert has_element?(view, "#agents-issue-bot-enable-#{project_enabled.id}")
    assert has_element?(view, "#agents-issue-bot-disable-#{project_enabled.id}")
    assert has_element?(view, "#agents-issue-bot-enable-#{project_disabled.id}")
    assert has_element?(view, "#agents-issue-bot-disable-#{project_disabled.id}")

    assert has_element?(view, "#agents-issue-bot-status-#{project_enabled.id}", "Enabled")
    assert has_element?(view, "#agents-issue-bot-status-#{project_disabled.id}", "Disabled")

    view
    |> element("#agents-issue-bot-disable-#{project_enabled.id}")
    |> render_click()

    assert has_element?(view, "#agents-issue-bot-status-#{project_enabled.id}", "Disabled")

    refreshed_project_enabled = read_project!(project_enabled.id)
    assert issue_bot_enabled(refreshed_project_enabled.settings) == false

    view
    |> element("#agents-issue-bot-enable-#{project_disabled.id}")
    |> render_click()

    assert has_element?(view, "#agents-issue-bot-status-#{project_disabled.id}", "Enabled")

    refreshed_project_disabled = read_project!(project_disabled.id)
    assert issue_bot_enabled(refreshed_project_disabled.settings) == true
  end

  test "persistence failure leaves enabled state unchanged and renders typed error feedback", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-failure",
        github_full_name: "owner/repo-failure",
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{"enabled" => true}
          }
        }
      })

    Application.put_env(:jido_code, :support_agent_config_project_updater, fn _project, _update_attributes ->
      {:error, :forced_support_agent_config_failure}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/agents", on_error: :warn)

    assert has_element?(view, "#agents-issue-bot-status-#{project.id}", "Enabled")

    view
    |> element("#agents-issue-bot-disable-#{project.id}")
    |> render_click()

    assert has_element?(
             view,
             "#agents-issue-bot-error-type",
             "support_agent_config_persistence_failed"
           )

    assert has_element?(view, "#agents-issue-bot-status-#{project.id}", "Enabled")

    refreshed_project = read_project!(project.id)
    assert issue_bot_enabled(refreshed_project.settings) == true
  end

  test "agents page persists explicit per-project webhook event list updates", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-events",
        github_full_name: "owner/repo-events",
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{
              "enabled" => true,
              "webhook_events" => ["issues.opened"]
            }
          }
        }
      })

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/agents", on_error: :warn)

    assert has_element?(
             view,
             "#agents-issue-bot-event-checkbox-#{project.id}-issues-opened"
           )

    assert has_element?(
             view,
             "#agents-issue-bot-event-checkbox-#{project.id}-issues-edited"
           )

    assert has_element?(
             view,
             "#agents-issue-bot-event-checkbox-#{project.id}-issue-comment-created"
           )

    view
    |> element("#agents-issue-bot-events-form-#{project.id}")
    |> render_submit(%{
      "project_id" => project.id,
      "webhook_events" => ["issues.edited", "issue_comment.created"]
    })

    refreshed_project = read_project!(project.id)

    assert issue_bot_webhook_events(refreshed_project.settings) == [
             "issues.edited",
             "issue_comment.created"
           ]
  end

  test "agents page rejects unsupported webhook event values with typed validation errors", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-event-validation",
        github_full_name: "owner/repo-event-validation",
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{
              "enabled" => true,
              "webhook_events" => ["issues.opened"]
            }
          }
        }
      })

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/agents", on_error: :warn)

    view
    |> element("#agents-issue-bot-events-form-#{project.id}")
    |> render_submit(%{
      "project_id" => project.id,
      "webhook_events" => ["issues.opened", "issues.invalid_action"]
    })

    assert has_element?(
             view,
             "#agents-issue-bot-error-type",
             "support_agent_config_validation_failed"
           )

    assert has_element?(
             view,
             "#agents-issue-bot-error-detail",
             "issues.invalid_action"
           )

    refreshed_project = read_project!(project.id)
    assert issue_bot_webhook_events(refreshed_project.settings) == ["issues.opened"]
  end

  test "agents page supports per-project approval mode selection and persists issue bot policy",
       %{
         conn: _conn
       } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-approval-mode",
        github_full_name: "owner/repo-approval-mode",
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{
              "enabled" => true,
              "approval_mode" => "manual"
            }
          }
        }
      })

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/agents", on_error: :warn)

    assert has_element?(
             view,
             "#agents-issue-bot-approval-select-#{project.id} option[value='auto_post']",
             "Auto-post"
           )

    assert has_element?(
             view,
             "#agents-issue-bot-approval-select-#{project.id} option[value='approval_required']",
             "Approval required"
           )

    assert has_element?(
             view,
             "#agents-issue-bot-approval-mode-#{project.id}",
             "Approval required"
           )

    assert has_element?(view, "#agents-issue-bot-last-updated-#{project.id}", "Last updated:")

    view
    |> element("#agents-issue-bot-approval-form-#{project.id}")
    |> render_submit(%{
      "project_id" => project.id,
      "approval_mode" => "auto_post"
    })

    assert has_element?(
             view,
             "#agents-issue-bot-approval-mode-#{project.id}",
             "Auto-post"
           )

    refreshed_project = read_project!(project.id)
    assert issue_bot_approval_mode(refreshed_project.settings) == "auto_post"
  end

  test "approval mode persistence failure keeps prior policy and renders typed failure context",
       %{
         conn: _conn
       } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-approval-mode-failure",
        github_full_name: "owner/repo-approval-mode-failure",
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{
              "enabled" => true,
              "approval_mode" => "approval_required"
            }
          }
        }
      })

    Application.put_env(:jido_code, :support_agent_config_project_updater, fn _project, _update_attributes ->
      {:error, :forced_support_agent_config_failure}
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/agents", on_error: :warn)

    assert has_element?(
             view,
             "#agents-issue-bot-approval-mode-#{project.id}",
             "Approval required"
           )

    view
    |> element("#agents-issue-bot-approval-form-#{project.id}")
    |> render_submit(%{
      "project_id" => project.id,
      "approval_mode" => "auto_post"
    })

    assert has_element?(
             view,
             "#agents-issue-bot-error-type",
             "support_agent_config_persistence_failed"
           )

    assert has_element?(
             view,
             "#agents-issue-bot-approval-mode-#{project.id}",
             "Approval required"
           )

    refreshed_project = read_project!(project.id)
    assert issue_bot_approval_mode(refreshed_project.settings) == "approval_required"
  end

  defp read_project!(project_id) do
    {:ok, [project]} = Project.read(query: [filter: [id: project_id], limit: 1])
    project
  end

  defp issue_bot_enabled(settings) when is_map(settings) do
    settings
    |> map_get(:support_agent_config, "support_agent_config", %{})
    |> normalize_map()
    |> map_get(:github_issue_bot, "github_issue_bot", %{})
    |> normalize_map()
    |> map_get(:enabled, "enabled", true)
    |> case do
      true -> true
      "true" -> true
      false -> false
      "false" -> false
      _other -> true
    end
  end

  defp issue_bot_enabled(_settings), do: true

  defp issue_bot_webhook_events(settings) when is_map(settings) do
    settings
    |> map_get(:support_agent_config, "support_agent_config", %{})
    |> normalize_map()
    |> map_get(:github_issue_bot, "github_issue_bot", %{})
    |> normalize_map()
    |> map_get(:webhook_events, "webhook_events", [])
    |> case do
      webhook_events when is_list(webhook_events) -> webhook_events
      _other -> []
    end
  end

  defp issue_bot_webhook_events(_settings), do: []

  defp issue_bot_approval_mode(settings) when is_map(settings) do
    settings
    |> map_get(:support_agent_config, "support_agent_config", %{})
    |> normalize_map()
    |> map_get(:github_issue_bot, "github_issue_bot", %{})
    |> normalize_map()
    |> map_get(:approval_mode, "approval_mode", "approval_required")
    |> case do
      approval_mode when is_binary(approval_mode) ->
        String.trim(approval_mode)

      approval_mode when is_atom(approval_mode) ->
        approval_mode |> Atom.to_string() |> String.trim()

      _other ->
        "approval_required"
    end
    |> case do
      "auto_post" -> "auto_post"
      "auto-post" -> "auto_post"
      "auto" -> "auto_post"
      "approval_required" -> "approval_required"
      "approval-required" -> "approval_required"
      "manual" -> "approval_required"
      "manual_gate" -> "approval_required"
      "manual-gate" -> "approval_required"
      _other -> "approval_required"
    end
  end

  defp issue_bot_approval_mode(_settings), do: "approval_required"

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp map_get(map, atom_key, string_key, default)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default
end
