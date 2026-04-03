defmodule JidoCodeWeb.SetupLiveTest do
  # covers: baseline.surface.public_entry_routes
  # covers: users.admin_system.bootstrap_admin
  # covers: users.admin_system.admin_role_assignment
  # covers: users.admin_system.registration_guardrails
  # covers: setup.onboarding.post_bootstrap_start_surface
  # covers: setup.onboarding.deployment_mode_auto_detected
  # covers: setup.onboarding.deferred_integrations
  # covers: setup.onboarding.start_path_preference_persisted
  use JidoCodeWeb.ConnCase, async: false

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts
  alias JidoCode.Accounts.User
  alias JidoCode.Repo

  import Phoenix.LiveViewTest

  @checked_at ~U[2026-02-13 12:34:56Z]
  @owner_recovery_audit_event [:jido_code, :auth, :owner_recovery, :completed]

  setup do
    original_config = Application.get_env(:jido_code, :system_config, :__missing__)
    original_prerequisite_checker = Application.get_env(:jido_code, :setup_prerequisite_checker, :__missing__)
    original_target = fetch_system_env("BURRITO_TARGET")

    on_exit(fn ->
      restore_env(:system_config, original_config)
      restore_env(:setup_prerequisite_checker, original_prerequisite_checker)
      restore_system_env("BURRITO_TARGET", original_target)
    end)

    Application.delete_env(:jido_code, :setup_prerequisite_checker)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 1,
      onboarding_state: %{}
    })

    Application.put_env(:jido_code, :setup_prerequisite_checker, fn _timeout_ms ->
      passing_prerequisite_report()
    end)

    System.delete_env("BURRITO_TARGET")
    reset_owner_state!()

    :ok
  end

  test "zero-user bootstrap on /welcome persists prerequisite and admin state, then enters the setup start surface",
       %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/welcome"}}} =
             live(conn, ~p"/setup", on_error: :warn)

    {:ok, view, _html} = live(conn, ~p"/welcome", on_error: :warn)

    view
    |> form("#welcome-owner-form", %{
      "owner" => %{
        "email" => "owner@example.com",
        "password" => "owner-password-123",
        "password_confirmation" => "owner-password-123"
      }
    })
    |> render_submit()

    auth_redirect_path =
      view
      |> assert_redirect()
      |> redirect_path()

    auth_response = build_conn() |> get(auth_redirect_path)
    assert redirected_to(auth_response, 302) == "/setup"

    {:ok, setup_view, _html} = live(recycle(auth_response), ~p"/setup", on_error: :warn)

    assert_setup_start_surface(setup_view)
    assert has_element?(setup_view, "#setup-selected-start-path", "Not chosen yet")
    assert_owner_count(1)
    assert_single_owner_admin!(true)

    assert %{
             onboarding_completed: false,
             onboarding_step: 3,
             onboarding_state: %{
               "1" => %{
                 "validated_note" => "System prerequisites verified (welcome flow).",
                 "prerequisite_checks" => %{"status" => "pass"}
               },
               "2" => %{
                 "owner_email" => "owner@example.com",
                 "owner_mode" => "created",
                 "registration_actions_disabled" => true,
                 "validated_note" => "Owner account bootstrapped."
               }
             }
           } = Application.get_env(:jido_code, :system_config)
  end

  test "continue setup sign-in from /welcome enters the setup start surface without advancing onboarding state",
       %{conn: conn} do
    register_owner("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{
        "1" => %{"validated_note" => "System prerequisites verified (welcome flow)."},
        "2" => %{
          "owner_email" => "owner@example.com",
          "owner_mode" => "created",
          "registration_actions_disabled" => true,
          "validated_note" => "Owner account bootstrapped."
        }
      }
    })

    {:ok, view, _html} = live(conn, ~p"/welcome", on_error: :warn)

    view
    |> form("#continue-setup-owner-form", %{
      "owner" => %{
        "email" => "owner@example.com",
        "password" => "owner-password-123"
      }
    })
    |> render_submit()

    auth_redirect_path =
      view
      |> assert_redirect()
      |> redirect_path()

    auth_response = build_conn() |> get(auth_redirect_path)
    assert redirected_to(auth_response, 302) == "/setup"

    {:ok, setup_view, _html} = live(recycle(auth_response), ~p"/setup", on_error: :warn)

    assert_setup_start_surface(setup_view)

    assert %{
             onboarding_completed: false,
             onboarding_step: 3,
             onboarding_state: %{
               "1" => %{"validated_note" => "System prerequisites verified (welcome flow)."},
               "2" => %{"validated_note" => "Owner account bootstrapped."}
             }
           } = Application.get_env(:jido_code, :system_config)
  end

  test "continue setup recovery on /welcome requires explicit verification, resets credentials, and keeps the bootstrap admin role",
       %{conn: conn} do
    attach_owner_recovery_audit_handler()
    register_owner("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 2,
      onboarding_state: %{"1" => %{"validated_note" => "Prerequisite checks passed"}}
    })

    {:ok, view, _html} = live(conn, ~p"/welcome", on_error: :warn)

    view
    |> form("#continue-setup-recovery-form", %{
      "owner_recovery" => %{
        "email" => "owner@example.com",
        "password" => "owner-recovered-password-789",
        "password_confirmation" => "owner-recovered-password-789",
        "verification_phrase" => "RECOVER OWNER ACCESS",
        "verification_ack" => "true"
      }
    })
    |> render_submit()

    auth_redirect_path =
      view
      |> assert_redirect()
      |> redirect_path()

    auth_response = build_conn() |> get(auth_redirect_path)
    assert redirected_to(auth_response, 302) == "/setup"

    {:ok, setup_view, _html} = live(recycle(auth_response), ~p"/setup", on_error: :warn)
    assert_setup_start_surface(setup_view)

    strategy = Info.strategy!(User, :password)

    assert {:error, _reason} =
             Strategy.action(
               strategy,
               :sign_in,
               %{"email" => "owner@example.com", "password" => "owner-password-123"},
               context: %{token_type: :sign_in}
             )

    assert {:ok, _owner} =
             Strategy.action(
               strategy,
               :sign_in,
               %{"email" => "owner@example.com", "password" => "owner-recovered-password-789"},
               context: %{token_type: :sign_in}
             )

    assert_receive {:owner_recovery_audit, event_name, measurements, metadata}
    assert event_name == @owner_recovery_audit_event
    assert measurements.count == 1
    assert metadata.owner_email == "owner@example.com"
    assert metadata.recovery_mode == "bootstrap"

    assert_owner_count(1)
    assert_single_owner_admin!(true)

    assert %{
             onboarding_completed: false,
             onboarding_step: 3,
             onboarding_state: %{
               "2" => %{
                 "owner_email" => "owner@example.com",
                 "owner_mode" => "recovered",
                 "registration_actions_disabled" => true,
                 "validated_note" => "Owner account recovered."
               }
             }
           } = Application.get_env(:jido_code, :system_config)
  end

  test "setup redirects unsigned sessions back to /welcome once bootstrap is complete", %{conn: conn} do
    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{"2" => %{"owner_email" => "owner@example.com"}}
    })

    assert {:error, {:live_redirect, %{to: "/welcome"}}} =
             live(conn, ~p"/setup", on_error: :warn)
  end

  test "desktop setup start surface emphasizes adding a local repo first", %{conn: conn} do
    System.put_env("BURRITO_TARGET", "darwin-aarch64")
    register_owner("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{
        "2" => %{
          "owner_email" => "owner@example.com",
          "owner_mode" => "created",
          "registration_actions_disabled" => true
        }
      }
    })

    {:ok, view, _html} =
      conn
      |> authenticate_owner_conn("owner@example.com", "owner-password-123")
      |> live(~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-deployment-mode", "Desktop")
    assert has_element?(view, "#setup-start-choice-local_repo-badge", "Recommended")
    assert has_element?(view, "#setup-start-choice-local_repo-save", "Add local repo")
    assert has_element?(view, "#setup-start-choice-github-save", "Connect GitHub")
    assert has_element?(view, "#setup-start-choice-later-save", "Do this later")
  end

  test "cloud setup start surface keeps GitHub and later as the only start choices", %{conn: conn} do
    register_owner("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{
        "2" => %{
          "owner_email" => "owner@example.com",
          "owner_mode" => "created",
          "registration_actions_disabled" => true
        }
      }
    })

    {:ok, view, _html} =
      conn
      |> authenticate_owner_conn("owner@example.com", "owner-password-123")
      |> live(~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-deployment-mode", "Cloud")
    refute has_element?(view, "#setup-start-choice-local_repo")
    assert has_element?(view, "#setup-start-choice-github-badge", "Recommended")
    assert has_element?(view, "#setup-start-choice-github-save", "Connect GitHub")
    assert has_element?(view, "#setup-start-choice-later-save", "Do this later")
  end

  test "choosing a start path persists the saved choice without advancing onboarding progress", %{
    conn: conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{
        "1" => %{"validated_note" => "System prerequisites verified (welcome flow)."},
        "2" => %{
          "owner_email" => "owner@example.com",
          "owner_mode" => "created",
          "registration_actions_disabled" => true,
          "validated_note" => "Owner account bootstrapped."
        }
      }
    })

    {:ok, view, _html} =
      conn
      |> authenticate_owner_conn("owner@example.com", "owner-password-123")
      |> live(~p"/setup", on_error: :warn)

    view
    |> element("#setup-start-choice-github-save")
    |> render_click()

    assert has_element?(view, "#setup-selected-start-path", "Connect GitHub")
    assert has_element?(view, "#setup-start-choice-github-badge", "Saved")
    assert has_element?(view, "#setup-start-choice-github-save[disabled]", "Saved")

    assert %{
             onboarding_completed: false,
             onboarding_step: 3,
             onboarding_state: %{
               "1" => %{"validated_note" => "System prerequisites verified (welcome flow)."},
               "2" => %{"validated_note" => "Owner account bootstrapped."},
               "3" => %{
                 "start_path" => "github",
                 "deployment_mode" => "cloud",
                 "validated_note" => "GitHub path selected."
               }
             }
           } = Application.get_env(:jido_code, :system_config)
  end

  test "later onboarding states still render the simplified setup start surface instead of the old wizard",
       %{conn: conn} do
    register_owner("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 7,
      onboarding_state: %{
        "2" => %{
          "owner_email" => "owner@example.com",
          "owner_mode" => "created",
          "registration_actions_disabled" => true
        },
        "3" => %{
          "start_path" => "later",
          "deployment_mode" => "cloud",
          "validated_note" => "Repo setup deferred for now."
        },
        "7" => %{"validated_note" => "Legacy import state retained for migration coverage."}
      }
    })

    {:ok, view, _html} =
      conn
      |> authenticate_owner_conn("owner@example.com", "owner-password-123")
      |> live(~p"/setup", on_error: :warn)

    assert_setup_start_surface(view)
    assert has_element?(view, "#setup-selected-start-path", "Do this later")
    refute render(view) =~ "System checks"
    refute render(view) =~ "First project import readiness"
  end

  test "completed onboarding redirects signed-in sessions away from /setup to /dashboard", %{conn: conn} do
    register_owner("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: true,
      onboarding_step: 8,
      onboarding_state: %{
        "2" => %{
          "owner_email" => "owner@example.com",
          "owner_mode" => "created",
          "registration_actions_disabled" => true
        }
      }
    })

    assert {:error, {:live_redirect, %{to: "/dashboard"}}} =
             conn
             |> authenticate_owner_conn("owner@example.com", "owner-password-123")
             |> live(~p"/setup", on_error: :warn)
  end

  defp attach_owner_recovery_audit_handler do
    test_pid = self()
    handler_id = "setup-owner-recovery-audit-handler-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        @owner_recovery_audit_event,
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:owner_recovery_audit, event_name, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp fetch_system_env(key) do
    case System.get_env(key) do
      nil -> :__missing__
      value -> value
    end
  end

  defp assert_setup_start_surface(view) do
    assert has_element?(view, "#setup-start-surface")
    assert has_element?(view, "#setup-title", "Choose how to start")
    assert has_element?(view, "#setup-description")
    assert has_element?(view, "#setup-owner-email", "owner@example.com")
  end

  defp assert_owner_count(expected_count) do
    {:ok, owners} = Ash.read(User, domain: Accounts, authorize?: false)
    assert length(owners) == expected_count
  end

  defp assert_single_owner_admin!(expected_admin?) do
    {:ok, [owner]} = Ash.read(User, domain: Accounts, authorize?: false)
    assert owner.is_admin == expected_admin?
    owner
  end

  defp passing_prerequisite_report do
    %{
      checked_at: @checked_at,
      status: :pass,
      checks: [
        %{
          id: "database_connectivity",
          name: "Database connectivity",
          status: :pass,
          detail: "Successfully connected to Postgres.",
          remediation: "Confirm Postgres is reachable and verify `DATABASE_URL` or Repo runtime config.",
          checked_at: @checked_at
        },
        %{
          id: "runtime_token_signing_secret",
          name: "Runtime configuration: TOKEN_SIGNING_SECRET",
          status: :pass,
          detail: "Runtime configuration: TOKEN_SIGNING_SECRET is configured.",
          remediation: "Set `TOKEN_SIGNING_SECRET` in runtime config (or env) and restart JidoCode.",
          checked_at: @checked_at
        }
      ]
    }
  end

  defp redirect_path({path, _flash}) when is_binary(path), do: path
  defp redirect_path(path) when is_binary(path), do: path

  defp reset_owner_state! do
    Ecto.Adapters.SQL.query!(Repo, "TRUNCATE TABLE users RESTART IDENTITY CASCADE", [])
  end
end
