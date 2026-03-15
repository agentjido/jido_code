defmodule JidoCodeWeb.SetupLiveTest do
  use JidoCodeWeb.ConnCase, async: false

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts
  alias JidoCode.Accounts.User
  alias JidoCode.Projects.Project
  alias JidoCode.Repo
  alias JidoCode.Security.SecretRefs

  import Phoenix.LiveViewTest

  @checked_at ~U[2026-02-13 12:34:56Z]
  @previous_checked_at ~U[2026-02-12 08:00:00Z]
  @owner_recovery_audit_event [:jido_code, :auth, :owner_recovery, :completed]

  setup do
    original_loader = Application.get_env(:jido_code, :system_config_loader, :__missing__)
    original_saver = Application.get_env(:jido_code, :system_config_saver, :__missing__)
    original_config = Application.get_env(:jido_code, :system_config, :__missing__)
    original_checker = Application.get_env(:jido_code, :setup_prerequisite_checker, :__missing__)

    original_provider_checker =
      Application.get_env(:jido_code, :setup_provider_credential_checker, :__missing__)

    original_github_checker =
      Application.get_env(:jido_code, :setup_github_credential_checker, :__missing__)

    original_webhook_simulation_checker =
      Application.get_env(:jido_code, :setup_webhook_simulation_checker, :__missing__)

    original_project_importer =
      Application.get_env(:jido_code, :setup_project_importer, :__missing__)

    original_clone_provisioner =
      Application.get_env(:jido_code, :setup_project_clone_provisioner, :__missing__)

    original_baseline_syncer =
      Application.get_env(:jido_code, :setup_project_baseline_syncer, :__missing__)

    original_repository_fetcher =
      Application.get_env(:jido_code, :setup_github_repository_fetcher, :__missing__)

    original_runtime_mode = Application.get_env(:jido_code, :runtime_mode, :__missing__)

    original_timeout =
      Application.get_env(:jido_code, :setup_prerequisite_timeout_ms, :__missing__)

    on_exit(fn ->
      restore_env(:system_config_loader, original_loader)
      restore_env(:system_config_saver, original_saver)
      restore_env(:system_config, original_config)
      restore_env(:setup_prerequisite_checker, original_checker)
      restore_env(:setup_provider_credential_checker, original_provider_checker)
      restore_env(:setup_github_credential_checker, original_github_checker)
      restore_env(:setup_webhook_simulation_checker, original_webhook_simulation_checker)
      restore_env(:setup_project_importer, original_project_importer)
      restore_env(:setup_project_clone_provisioner, original_clone_provisioner)
      restore_env(:setup_project_baseline_syncer, original_baseline_syncer)
      restore_env(:setup_github_repository_fetcher, original_repository_fetcher)
      restore_env(:setup_prerequisite_timeout_ms, original_timeout)
      restore_env(:runtime_mode, original_runtime_mode)
    end)

    Application.delete_env(:jido_code, :system_config_loader)
    Application.delete_env(:jido_code, :system_config_saver)
    Application.delete_env(:jido_code, :setup_prerequisite_timeout_ms)
    Application.delete_env(:jido_code, :setup_provider_credential_checker)
    Application.delete_env(:jido_code, :setup_github_credential_checker)
    Application.delete_env(:jido_code, :setup_webhook_simulation_checker)
    Application.delete_env(:jido_code, :setup_project_importer)
    Application.delete_env(:jido_code, :setup_project_clone_provisioner)
    Application.delete_env(:jido_code, :setup_project_baseline_syncer)
    Application.delete_env(:jido_code, :setup_github_repository_fetcher)
    Application.put_env(:jido_code, :runtime_mode, :test)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 1,
      onboarding_state: %{}
    })

    Application.put_env(:jido_code, :setup_prerequisite_checker, fn _timeout_ms ->
      passing_prerequisite_report()
    end)

    Application.put_env(:jido_code, :setup_provider_credential_checker, fn _context ->
      passing_provider_credential_report()
    end)

    Application.put_env(:jido_code, :setup_github_credential_checker, fn _context ->
      passing_github_credential_report()
    end)

    Application.put_env(:jido_code, :setup_webhook_simulation_checker, fn _context ->
      passing_webhook_simulation_report()
    end)

    reset_owner_state!()

    :ok
  end

  test "step 1 shows timestamped prerequisite checks and persists progression on success", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-prerequisite-status")
    assert has_element?(view, "#setup-prerequisite-checked-at", "2026-02-13T12:34:56Z")
    assert has_element?(view, "#setup-prerequisite-database_connectivity-status", "Pass")

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "Prerequisite checks passed"}
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 2")

    assert %{
             onboarding_step: 2,
             onboarding_state: %{
               "1" => %{
                 "validated_note" => "Prerequisite checks passed",
                 "prerequisite_checks" => %{"status" => "pass"}
               }
             }
           } = Application.get_env(:jido_code, :system_config)

    {:ok, resumed_view, _html} = live(build_conn(), ~p"/setup", on_error: :warn)

    assert has_element?(resumed_view, "#resolved-onboarding-step", "Step 2")
    assert has_element?(resumed_view, "#validated-state-step-1", "Prerequisite checks passed")
    assert has_element?(resumed_view, "#setup-owner-bootstrap-form")
  end

  test "step 1 validation failure shows remediation and blocks persistence", %{conn: conn} do
    test_pid = self()

    Application.put_env(:jido_code, :setup_prerequisite_checker, fn _timeout_ms ->
      failing_prerequisite_report()
    end)

    Application.put_env(:jido_code, :system_config_saver, fn _config ->
      send(test_pid, :unexpected_save)
      {:ok, %{onboarding_completed: false, onboarding_step: 2, onboarding_state: %{}}}
    end)

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(
             view,
             "#setup-prerequisite-remediation-runtime_token_signing_secret",
             "TOKEN_SIGNING_SECRET"
           )

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "Attempting to bypass failing prerequisites"}
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 1")
    assert has_element?(view, "#setup-save-error", "System prerequisite checks failed")
    assert has_element?(view, "#setup-save-error", "TOKEN_SIGNING_SECRET")
    refute_received :unexpected_save

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 1
    assert Map.fetch!(persisted_config, :onboarding_state) == %{}
  end

  test "step 2 creates owner when none exists and grants immediate protected-route session access",
       %{conn: conn} do
    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 2,
      onboarding_state: %{"1" => %{"validated_note" => "Prerequisite checks passed"}}
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-owner-bootstrap-mode", "No owner account exists yet")

    view
    |> form("#setup-owner-bootstrap-form", %{
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

    assert auth_redirect_path =~ "/auth/"
    assert auth_redirect_path =~ "sign_in_with_token"

    authed_response = build_conn() |> get(auth_redirect_path)
    assert redirected_to(authed_response, 302) == "/"

    {:ok, dashboard_view, _html} = live(recycle(authed_response), ~p"/dashboard", on_error: :warn)
    assert has_element?(dashboard_view, "p", "owner@example.com")

    assert_owner_count(1)

    assert %{
             onboarding_step: 3,
             onboarding_state: %{
               "2" => %{
                 "owner_email" => "owner@example.com",
                 "owner_mode" => "created",
                 "validated_note" => "Owner account bootstrapped."
               }
             }
           } = Application.get_env(:jido_code, :system_config)
  end

  test "step 2 rejects malformed owner email addresses with a validation error", %{conn: conn} do
    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 2,
      onboarding_state: %{"1" => %{"validated_note" => "Prerequisite checks passed"}}
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    view
    |> form("#setup-owner-bootstrap-form", %{
      "owner" => %{
        "email" => "not-an-email",
        "password" => "owner-password-123",
        "password_confirmation" => "owner-password-123"
      }
    })
    |> render_submit()

    html = render(view)
    assert has_element?(view, "#setup-save-error", "valid email address")
    refute html =~ "Bread Crumbs"
    assert_owner_count(0)
    assert %{onboarding_step: 2} = Application.get_env(:jido_code, :system_config)
  end

  test "step 2 rejects short owner passwords with a friendly validation message", %{conn: conn} do
    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 2,
      onboarding_state: %{"1" => %{"validated_note" => "Prerequisite checks passed"}}
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    view
    |> form("#setup-owner-bootstrap-form", %{
      "owner" => %{
        "email" => "owner@example.com",
        "password" => "short",
        "password_confirmation" => "short"
      }
    })
    |> render_submit()

    html = render(view)
    assert has_element?(view, "#setup-save-error", "at least 8 characters")
    refute html =~ "Bread Crumbs"

    assert_owner_count(0)
    assert %{onboarding_step: 2} = Application.get_env(:jido_code, :system_config)
  end

  test "step 2 confirms existing owner and grants immediate protected-route session access", %{
    conn: conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 2,
      onboarding_state: %{"1" => %{"validated_note" => "Prerequisite checks passed"}}
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-owner-bootstrap-mode", "owner account already exists")
    assert has_element?(view, "#setup-owner-bootstrap-owner-email", "owner@example.com")

    view
    |> form("#setup-owner-bootstrap-form", %{
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

    authed_response = build_conn() |> get(auth_redirect_path)
    assert redirected_to(authed_response, 302) == "/"

    {:ok, dashboard_view, _html} = live(recycle(authed_response), ~p"/dashboard", on_error: :warn)
    assert has_element?(dashboard_view, "p", "owner@example.com")

    assert_owner_count(1)

    assert %{
             onboarding_step: 3,
             onboarding_state: %{
               "2" => %{
                 "owner_email" => "owner@example.com",
                 "owner_mode" => "confirmed",
                 "validated_note" => "Owner account confirmed."
               }
             }
           } = Application.get_env(:jido_code, :system_config)
  end

  test "step 2 recovery requires explicit verification, resets credentials, and records recovery audit metadata",
       %{conn: conn} do
    attach_owner_recovery_audit_handler()
    register_owner("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 2,
      onboarding_state: %{"1" => %{"validated_note" => "Prerequisite checks passed"}}
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-owner-recovery-form")

    assert has_element?(
             view,
             "#setup-owner-recovery-verification-target",
             "RECOVER OWNER ACCESS"
           )

    view
    |> form("#setup-owner-recovery-form", %{
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

    authed_response = build_conn() |> get(auth_redirect_path)
    assert redirected_to(authed_response, 302) == "/"

    {:ok, dashboard_view, _html} = live(recycle(authed_response), ~p"/dashboard", on_error: :warn)
    assert has_element?(dashboard_view, "p", "owner@example.com")

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
    assert is_integer(measurements.recovery_timestamp)
    assert metadata.route == "/setup"
    assert metadata.owner_email == "owner@example.com"
    assert metadata.recovery_mode == "bootstrap"

    assert metadata.verification_steps == [
             "owner_email_match",
             "verification_phrase",
             "manual_acknowledgement"
           ]

    assert is_binary(metadata.verified_at)
    assert_owner_count(1)

    assert %{
             onboarding_step: 3,
             onboarding_state: %{
               "2" => %{
                 "owner_email" => "owner@example.com",
                 "owner_mode" => "recovered",
                 "validated_note" => "Owner account recovered.",
                 "owner_recovery_audit" => %{
                   "route" => "/setup",
                   "owner_email" => "owner@example.com",
                   "recovery_mode" => "bootstrap",
                   "verification_steps" => [
                     "owner_email_match",
                     "verification_phrase",
                     "manual_acknowledgement"
                   ]
                 }
               }
             }
           } = Application.get_env(:jido_code, :system_config)

    verified_at =
      Application.get_env(:jido_code, :system_config)
      |> Map.fetch!(:onboarding_state)
      |> Map.fetch!("2")
      |> Map.fetch!("owner_recovery_audit")
      |> Map.fetch!("verified_at")

    assert is_binary(verified_at)
  end

  test "step 2 recovery denies credential reset when verification fails and leaves owner state unchanged",
       %{conn: conn} do
    attach_owner_recovery_audit_handler()
    register_owner("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 2,
      onboarding_state: %{"1" => %{"validated_note" => "Prerequisite checks passed"}}
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    view
    |> form("#setup-owner-recovery-form", %{
      "owner_recovery" => %{
        "email" => "owner@example.com",
        "password" => "owner-recovered-password-789",
        "password_confirmation" => "owner-recovered-password-789",
        "verification_phrase" => "INVALID PHRASE",
        "verification_ack" => "true"
      }
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 2")
    assert has_element?(view, "#setup-save-error", "verification failed")
    assert has_element?(view, "#setup-save-error", "state is unchanged")

    strategy = Info.strategy!(User, :password)

    assert {:ok, _owner} =
             Strategy.action(
               strategy,
               :sign_in,
               %{"email" => "owner@example.com", "password" => "owner-password-123"},
               context: %{token_type: :sign_in}
             )

    assert {:error, _reason} =
             Strategy.action(
               strategy,
               :sign_in,
               %{"email" => "owner@example.com", "password" => "owner-recovered-password-789"},
               context: %{token_type: :sign_in}
             )

    refute_receive {:owner_recovery_audit, _event_name, _measurements, _metadata}
    assert_owner_count(1)

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 2
    refute Map.has_key?(Map.fetch!(persisted_config, :onboarding_state), "2")
  end

  test "step 2 recovery rejects short passwords with a friendly validation message", %{conn: conn} do
    register_owner("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 2,
      onboarding_state: %{"1" => %{"validated_note" => "Prerequisite checks passed"}}
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    view
    |> form("#setup-owner-recovery-form", %{
      "owner_recovery" => %{
        "email" => "owner@example.com",
        "password" => "short",
        "password_confirmation" => "short",
        "verification_phrase" => "RECOVER OWNER ACCESS",
        "verification_ack" => "true"
      }
    })
    |> render_submit()

    html = render(view)
    assert has_element?(view, "#setup-save-error", "at least 8 characters")
    refute html =~ "Bread Crumbs"

    assert_owner_count(1)
    assert %{onboarding_step: 2} = Application.get_env(:jido_code, :system_config)
  end

  test "step 2 recovery requires a verification phrase before credential reset", %{conn: conn} do
    register_owner("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 2,
      onboarding_state: %{"1" => %{"validated_note" => "Prerequisite checks passed"}}
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    view
    |> form("#setup-owner-recovery-form", %{
      "owner_recovery" => %{
        "email" => "owner@example.com",
        "password" => "owner-recovered-password-789",
        "password_confirmation" => "owner-recovered-password-789",
        "verification_phrase" => "",
        "verification_ack" => "true"
      }
    })
    |> render_submit()

    html = render(view)
    assert has_element?(view, "#setup-save-error", "verification phrase")
    refute html =~ "Bread Crumbs"

    assert_owner_count(1)
    assert %{onboarding_step: 2} = Application.get_env(:jido_code, :system_config)
  end

  test "step 2 recovery requires explicit acknowledgement before credential reset", %{conn: conn} do
    register_owner("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 2,
      onboarding_state: %{"1" => %{"validated_note" => "Prerequisite checks passed"}}
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    view
    |> form("#setup-owner-recovery-form", %{
      "owner_recovery" => %{
        "email" => "owner@example.com",
        "password" => "owner-recovered-password-789",
        "password_confirmation" => "owner-recovered-password-789",
        "verification_phrase" => "RECOVER OWNER ACCESS",
        "verification_ack" => "false"
      }
    })
    |> render_submit()

    html = render(view)
    assert has_element?(view, "#setup-save-error", "explicit recovery acknowledgement")
    refute html =~ "Bread Crumbs"

    assert_owner_count(1)
    assert %{onboarding_step: 2} = Application.get_env(:jido_code, :system_config)
  end

  test "owner bootstrap and recovery events are rejected outside step 2", %{conn: conn} do
    register_owner("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{
        "1" => %{"validated_note" => "Prerequisite checks passed"},
        "2" => %{"validated_note" => "Owner account confirmed"}
      }
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    view
    |> render_submit("bootstrap_owner", %{
      "owner" => %{
        "email" => "owner@example.com",
        "password" => "owner-password-123"
      }
    })

    assert has_element?(view, "#setup-save-error", "Complete owner account bootstrap before continuing.")

    view
    |> render_submit("recover_owner", %{
      "owner_recovery" => %{
        "email" => "owner@example.com",
        "password" => "owner-password-123",
        "password_confirmation" => "owner-password-123",
        "verification_phrase" => "RECOVER OWNER ACCESS",
        "verification_ack" => "true"
      }
    })

    assert has_element?(
             view,
             "#setup-save-error",
             "Complete owner recovery verification before attempting credential reset."
           )

    assert %{onboarding_step: 3} = Application.get_env(:jido_code, :system_config)
    assert_owner_count(1)
  end

  test "step 2 blocks additional owner creation attempts with a single-user policy error", %{
    conn: conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 2,
      onboarding_state: %{"1" => %{"validated_note" => "Prerequisite checks passed"}}
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    view
    |> form("#setup-owner-bootstrap-form", %{
      "owner" => %{
        "email" => "second-owner@example.com",
        "password" => "another-password-123"
      }
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 2")
    assert has_element?(view, "#setup-save-error", "Single-user policy error")

    assert_owner_count(1)

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 2
  end

  test "production step 2 marks registration actions disabled and keeps owner login available while blocking registration",
       %{conn: conn} do
    Application.put_env(:jido_code, :runtime_mode, :prod)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 2,
      onboarding_state: %{"1" => %{"validated_note" => "Prerequisite checks passed"}}
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    view
    |> form("#setup-owner-bootstrap-form", %{
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

    authed_response = build_conn() |> get(auth_redirect_path)
    assert redirected_to(authed_response, 302) == "/"

    strategy = Info.strategy!(User, :password)

    assert {:ok, _owner} =
             Strategy.action(
               strategy,
               :sign_in,
               %{"email" => "owner@example.com", "password" => "owner-password-123"},
               context: %{token_type: :sign_in}
             )

    assert {:error, %Ash.Error.Forbidden{} = error} =
             Strategy.action(
               strategy,
               :register,
               %{
                 "email" => "another-user@example.com",
                 "password" => "owner-password-123",
                 "password_confirmation" => "owner-password-123"
               },
               context: %{token_type: :sign_in}
             )

    assert Enum.any?(error.errors, &match?(%Ash.Error.Forbidden.Policy{}, &1))
    assert_owner_count(1)

    assert %{
             onboarding_step: 3,
             onboarding_state: %{
               "2" => %{
                 "owner_email" => "owner@example.com",
                 "owner_mode" => "created",
                 "registration_actions_disabled" => true,
                 "validated_note" => "Owner account bootstrapped."
               }
             }
           } = Application.get_env(:jido_code, :system_config)
  end

  test "production registration request fails with a typed authorization error once owner exists" do
    Application.put_env(:jido_code, :runtime_mode, :prod)
    register_owner("owner@example.com", "owner-password-123")

    strategy = Info.strategy!(User, :password)

    assert {:error, %Ash.Error.Forbidden{} = error} =
             Strategy.action(
               strategy,
               :register,
               %{
                 "email" => "blocked-user@example.com",
                 "password" => "owner-password-123",
                 "password_confirmation" => "owner-password-123"
               },
               context: %{token_type: :sign_in}
             )

    assert Enum.any?(error.errors, &match?(%Ash.Error.Forbidden.Policy{}, &1))
  end

  test "step 1 timeout keeps onboarding blocked and does not persist downstream data", %{
    conn: conn
  } do
    test_pid = self()

    Application.put_env(:jido_code, :setup_prerequisite_checker, fn _timeout_ms ->
      timeout_prerequisite_report()
    end)

    Application.put_env(:jido_code, :system_config_saver, fn _config ->
      send(test_pid, :unexpected_save)
      {:ok, %{onboarding_completed: false, onboarding_step: 2, onboarding_state: %{}}}
    end)

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)
    assert has_element?(view, "#setup-prerequisite-runtime_phx_host-status", "Timeout")

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "Attempting to continue after timeout"}
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 1")
    assert has_element?(view, "#setup-save-error", "timed out")
    assert has_element?(view, "#setup-save-error", "no setup progress was saved")
    refute_received :unexpected_save

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 1
    assert Map.fetch!(persisted_config, :onboarding_state) == %{}
  end

  test "step 3 requires one active provider and persists verified provider status before GitHub setup",
       %{conn: conn} do
    Application.put_env(:jido_code, :setup_provider_credential_checker, fn _context ->
      mixed_provider_credential_report()
    end)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{
        "1" => %{"validated_note" => "Prerequisite checks passed"},
        "2" => %{"validated_note" => "Owner account confirmed"}
      }
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-provider-anthropic-status", "Active")
    assert has_element?(view, "#setup-provider-transition-anthropic", "Not set -> Active")
    assert has_element?(view, "#setup-provider-openai-status", "Invalid")
    assert has_element?(view, "#setup-provider-remediation-openai", "OPENAI_API_KEY")

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "Provider setup confirmed"}
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 4")

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 4

    provider_state =
      persisted_config
      |> Map.fetch!(:onboarding_state)
      |> Map.fetch!("3")
      |> Map.fetch!("provider_credentials")

    assert provider_state["status"] == "active"

    credentials_by_provider =
      provider_state["credentials"]
      |> Enum.map(fn credential -> {credential["provider"], credential} end)
      |> Map.new()

    assert credentials_by_provider["anthropic"]["status"] == "active"
    assert is_binary(credentials_by_provider["anthropic"]["verified_at"])
    assert credentials_by_provider["openai"]["status"] == "invalid"
    assert is_nil(credentials_by_provider["openai"]["verified_at"])
  end

  test "step 3 exposes source resolution diagnostics without rendering secret material", %{
    conn: conn
  } do
    original_anthropic_env = fetch_system_env("ANTHROPIC_API_KEY")
    original_anthropic_app_env = Application.get_env(:jido_code, :anthropic_api_key, :__missing__)

    on_exit(fn ->
      restore_system_env("ANTHROPIC_API_KEY", original_anthropic_env)
      restore_env(:anthropic_api_key, original_anthropic_app_env)
    end)

    env_secret = "sk-ant-env-#{System.unique_integer([:positive])}"
    db_secret = "sk-ant-db-#{System.unique_integer([:positive])}"

    System.put_env("ANTHROPIC_API_KEY", env_secret)
    Application.delete_env(:jido_code, :anthropic_api_key)
    Application.delete_env(:jido_code, :setup_provider_credential_checker)

    assert {:ok, _metadata} =
             SecretRefs.persist_operational_secret(%{
               scope: :integration,
               name: SecretRefs.provider_secret_ref_name(:anthropic),
               value: db_secret,
               source: :onboarding
             })

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{
        "1" => %{"validated_note" => "Prerequisite checks passed"},
        "2" => %{"validated_note" => "Owner account confirmed"}
      }
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-provider-anthropic", "source=env")
    assert has_element?(view, "#setup-provider-anthropic", "outcome=resolved")

    assert has_element?(
             view,
             "#setup-provider-anthropic",
             "secret_ref_name=providers/anthropic_api_key"
           )

    refute has_element?(view, "#setup-provider-anthropic", env_secret)
    refute has_element?(view, "#setup-provider-anthropic", db_secret)
  end

  test "step 3 blocks progression when all provider checks fail and does not save false success",
       %{conn: conn} do
    test_pid = self()

    Application.put_env(:jido_code, :setup_provider_credential_checker, fn _context ->
      failing_provider_credential_report()
    end)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{
        "1" => %{"validated_note" => "Prerequisite checks passed"},
        "2" => %{"validated_note" => "Owner account confirmed"}
      }
    })

    Application.put_env(:jido_code, :system_config_saver, fn _config ->
      send(test_pid, :unexpected_save)
      {:ok, %{onboarding_completed: false, onboarding_step: 4, onboarding_state: %{}}}
    end)

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-provider-anthropic-status", "Not set")
    assert has_element?(view, "#setup-provider-openai-status", "Invalid")
    assert has_element?(view, "#setup-provider-transition-openai", "Not set -> Invalid")
    assert has_element?(view, "#setup-provider-remediation-openai", "OPENAI_API_KEY")

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "Attempting provider bypass"}
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 3")
    assert has_element?(view, "#setup-save-error", "must verify as Active")
    assert has_element?(view, "#setup-save-error", "No setup progress was saved")
    refute_received :unexpected_save

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 3
    refute Map.has_key?(Map.fetch!(persisted_config, :onboarding_state), "3")
  end

  test "step 3 preserves prior verification timestamp and exposes typed provider errors when checker fails",
       %{conn: conn} do
    test_pid = self()

    Application.put_env(:jido_code, :setup_provider_credential_checker, fn _context ->
      {:error, :provider_timeout}
    end)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{
        "1" => %{"validated_note" => "Prerequisite checks passed"},
        "2" => %{"validated_note" => "Owner account confirmed"},
        "3" => %{
          "validated_note" => "Provider setup previously confirmed",
          "provider_credentials" => prior_active_provider_credential_state()
        }
      }
    })

    Application.put_env(:jido_code, :system_config_saver, fn _config ->
      send(test_pid, :unexpected_save)
      {:ok, %{onboarding_completed: false, onboarding_step: 4, onboarding_state: %{}}}
    end)

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-provider-anthropic-status", "Invalid")
    assert has_element?(view, "#setup-provider-transition-anthropic", "Active -> Invalid")

    assert has_element?(
             view,
             "#setup-provider-error-type-anthropic",
             "anthropic_provider_check_failed"
           )

    assert has_element?(view, "#setup-provider-verified-at-anthropic", "2026-02-12T08:00:00Z")

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "Retry after provider endpoint timeout"}
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 3")
    assert has_element?(view, "#setup-save-error", "anthropic_provider_check_failed")
    refute_received :unexpected_save
  end

  test "step 4 validates GitHub App or PAT fallback and persists owner-context repository access",
       %{conn: conn} do
    Application.put_env(:jido_code, :setup_github_credential_checker, fn _context ->
      mixed_github_credential_report()
    end)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 4,
      onboarding_state: %{
        "1" => %{"validated_note" => "Prerequisite checks passed"},
        "2" => %{
          "validated_note" => "Owner account confirmed",
          "owner_email" => "owner@example.com"
        },
        "3" => %{"validated_note" => "Provider setup confirmed"}
      }
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-github-checked-at", "2026-02-13T12:34:56Z")
    assert has_element?(view, "#setup-github-owner-context", "owner@example.com")
    assert has_element?(view, "#setup-github-readiness-status", "Ready")
    assert has_element?(view, "#setup-github-app-readiness-status", "Invalid")
    assert has_element?(view, "#setup-github-github_app-status", "Invalid")

    assert has_element?(
             view,
             "#setup-github-error-type-github_app",
             "github_app_repository_access_unverified"
           )

    assert has_element?(view, "#setup-github-pat-status", "Ready")
    assert has_element?(view, "#setup-github-repository-access-pat", "Confirmed")
    assert has_element?(view, "#setup-github-repositories-pat", "owner/repo-one")

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "GitHub credentials validated"}
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 5")

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 5

    github_state =
      persisted_config
      |> Map.fetch!(:onboarding_state)
      |> Map.fetch!("4")
      |> Map.fetch!("github_credentials")

    assert github_state["status"] == "ready"
    assert github_state["owner_context"] == "owner@example.com"
    assert github_state["integration_health"]["readiness_status"] == "ready"
    assert github_state["integration_health"]["github_app_status"] == "invalid"
    assert github_state["integration_health"]["missing_repositories"] == []
    assert github_state["integration_health"]["last_checked_at"] == "2026-02-13T12:34:56Z"

    paths_by_type =
      github_state["paths"]
      |> Enum.map(fn path_result -> {path_result["path"], path_result} end)
      |> Map.new()

    assert paths_by_type["pat"]["status"] == "ready"
    assert paths_by_type["pat"]["repository_access"] == "confirmed"
    assert is_binary(paths_by_type["pat"]["validated_at"])
    assert paths_by_type["github_app"]["status"] == "invalid"
    assert paths_by_type["github_app"]["error_type"] == "github_app_repository_access_unverified"
  end

  test "step 4 blocks progression with typed integration errors when GitHub App and PAT fail",
       %{conn: conn} do
    test_pid = self()

    Application.put_env(:jido_code, :setup_github_credential_checker, fn _context ->
      failing_github_credential_report()
    end)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 4,
      onboarding_state: %{
        "1" => %{"validated_note" => "Prerequisite checks passed"},
        "2" => %{
          "validated_note" => "Owner account confirmed",
          "owner_email" => "owner@example.com"
        },
        "3" => %{"validated_note" => "Provider setup confirmed"}
      }
    })

    Application.put_env(:jido_code, :system_config_saver, fn _config ->
      send(test_pid, :unexpected_save)
      {:ok, %{onboarding_completed: false, onboarding_step: 5, onboarding_state: %{}}}
    end)

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-github-readiness-status", "Blocked")
    assert has_element?(view, "#setup-github-app-readiness-status", "Invalid")
    assert has_element?(view, "#setup-github-github_app-status", "Invalid")
    assert has_element?(view, "#setup-github-pat-status", "Invalid")

    assert has_element?(
             view,
             "#setup-github-error-type-github_app",
             "github_app_credentials_invalid"
           )

    assert has_element?(view, "#setup-github-error-type-pat", "github_pat_credentials_invalid")

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "Attempting GitHub setup bypass"}
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 4")
    assert has_element?(view, "#setup-save-error", "typed integration errors")
    assert has_element?(view, "#setup-save-error", "github_app_credentials_invalid")
    assert has_element?(view, "#setup-save-error", "github_pat_credentials_invalid")
    refute_received :unexpected_save

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 4
    refute Map.has_key?(Map.fetch!(persisted_config, :onboarding_state), "4")
  end

  test "step 4 blocks progression when GitHub App installation access misses expected repositories",
       %{conn: conn} do
    test_pid = self()

    Application.put_env(:jido_code, :setup_github_credential_checker, fn _context ->
      github_app_installation_gap_report()
    end)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 4,
      onboarding_state: %{
        "1" => %{"validated_note" => "Prerequisite checks passed"},
        "2" => %{
          "validated_note" => "Owner account confirmed",
          "owner_email" => "owner@example.com"
        },
        "3" => %{"validated_note" => "Provider setup confirmed"}
      }
    })

    Application.put_env(:jido_code, :system_config_saver, fn _config ->
      send(test_pid, :unexpected_save)
      {:ok, %{onboarding_completed: false, onboarding_step: 5, onboarding_state: %{}}}
    end)

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-github-readiness-status", "Blocked")
    assert has_element?(view, "#setup-github-app-readiness-status", "Invalid")

    assert has_element?(
             view,
             "#setup-github-expected-repositories",
             "owner/repo-one, owner/repo-two"
           )

    assert has_element?(view, "#setup-github-missing-repositories", "owner/repo-two")

    assert has_element?(
             view,
             "#setup-github-error-type-github_app",
             "github_app_installation_access_missing_repositories"
           )

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "Attempting GitHub setup with missing installation access"}
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 4")
    assert has_element?(view, "#setup-save-error", "typed integration errors")

    assert has_element?(
             view,
             "#setup-save-error",
             "github_app_installation_access_missing_repositories"
           )

    refute_received :unexpected_save
  end

  test "step 5 persists local environment defaults with workspace validation results", %{
    conn: conn
  } do
    workspace_root = unique_workspace_root()

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 5,
      onboarding_state: %{
        "1" => %{"validated_note" => "Prerequisite checks passed"},
        "2" => %{
          "validated_note" => "Owner account confirmed",
          "owner_email" => "owner@example.com"
        },
        "3" => %{"validated_note" => "Provider setup confirmed"},
        "4" => %{"validated_note" => "GitHub credentials validated"}
      }
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-environment-mode", "Cloud")
    assert has_element?(view, "#setup-default-environment", "sprite")

    view
    |> form("#onboarding-step-form", %{
      "step" => %{
        "execution_mode" => "local",
        "workspace_root" => workspace_root,
        "validated_note" => "Environment defaults confirmed"
      }
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 6")

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 6
    assert Map.fetch!(persisted_config, :default_environment) == :local
    assert Map.fetch!(persisted_config, :workspace_root) == Path.expand(workspace_root)

    environment_state =
      persisted_config
      |> Map.fetch!(:onboarding_state)
      |> Map.fetch!("5")
      |> Map.fetch!("environment_defaults")

    assert environment_state["status"] == "ready"
    assert environment_state["mode"] == "local"
    assert environment_state["default_environment"] == "local"
    assert environment_state["workspace_root"] == Path.expand(workspace_root)

    check_by_id =
      environment_state["checks"]
      |> Enum.map(fn check -> {check["id"], check} end)
      |> Map.new()

    assert check_by_id["local_workspace_root"]["status"] == "ready"
  end

  test "step 5 enforces sprite defaults when cloud mode is selected", %{conn: conn} do
    prior_workspace_root = unique_workspace_root()

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 5,
      default_environment: :local,
      workspace_root: prior_workspace_root,
      onboarding_state: %{
        "1" => %{"validated_note" => "Prerequisite checks passed"},
        "2" => %{
          "validated_note" => "Owner account confirmed",
          "owner_email" => "owner@example.com"
        },
        "3" => %{"validated_note" => "Provider setup confirmed"},
        "4" => %{"validated_note" => "GitHub credentials validated"}
      }
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-environment-mode", "Local")
    assert has_element?(view, "#setup-default-environment", "local")

    view
    |> form("#onboarding-step-form", %{
      "step" => %{
        "execution_mode" => "cloud",
        "workspace_root" => "/tmp/ignored-by-cloud-mode",
        "validated_note" => "Switching to cloud defaults"
      }
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 6")

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 6
    assert Map.fetch!(persisted_config, :default_environment) == :sprite
    assert is_nil(Map.fetch!(persisted_config, :workspace_root))

    environment_state =
      persisted_config
      |> Map.fetch!(:onboarding_state)
      |> Map.fetch!("5")
      |> Map.fetch!("environment_defaults")

    assert environment_state["mode"] == "cloud"
    assert environment_state["default_environment"] == "sprite"
    assert is_nil(environment_state["workspace_root"])

    check_by_id =
      environment_state["checks"]
      |> Enum.map(fn check -> {check["id"], check} end)
      |> Map.new()

    assert check_by_id["cloud_sprite_default"]["status"] == "ready"
  end

  test "step 5 blocks invalid local workspace roots and preserves existing defaults", %{
    conn: conn
  } do
    test_pid = self()
    persisted_workspace_root = unique_workspace_root()

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 5,
      default_environment: :local,
      workspace_root: persisted_workspace_root,
      onboarding_state: %{
        "1" => %{"validated_note" => "Prerequisite checks passed"},
        "2" => %{
          "validated_note" => "Owner account confirmed",
          "owner_email" => "owner@example.com"
        },
        "3" => %{"validated_note" => "Provider setup confirmed"},
        "4" => %{"validated_note" => "GitHub credentials validated"}
      }
    })

    Application.put_env(:jido_code, :system_config_saver, fn _config ->
      send(test_pid, :unexpected_save)
      {:ok, %{onboarding_completed: false, onboarding_step: 6, onboarding_state: %{}}}
    end)

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    view
    |> form("#onboarding-step-form", %{
      "step" => %{
        "execution_mode" => "local",
        "workspace_root" => "relative/workspace-root",
        "validated_note" => "Attempting invalid local mode save"
      }
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 5")
    assert has_element?(view, "#setup-save-error", "Environment defaults validation failed")
    assert has_element?(view, "#setup-save-error", "workspace root")
    refute_received :unexpected_save

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 5
    assert Map.fetch!(persisted_config, :default_environment) == :local
    assert Map.fetch!(persisted_config, :workspace_root) == Path.expand(persisted_workspace_root)
    refute Map.has_key?(Map.fetch!(persisted_config, :onboarding_state), "5")
  end

  test "step 6 runs webhook simulation before enabling Issue Bot defaults and persists readiness output",
       %{conn: conn} do
    Application.put_env(:jido_code, :setup_webhook_simulation_checker, fn _context ->
      passing_webhook_simulation_report()
    end)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 6,
      onboarding_state: %{
        "1" => %{"validated_note" => "Prerequisite checks passed"},
        "2" => %{
          "validated_note" => "Owner account confirmed",
          "owner_email" => "owner@example.com"
        },
        "3" => %{"validated_note" => "Provider setup confirmed"},
        "4" => %{"validated_note" => "GitHub credentials validated"},
        "5" => %{"validated_note" => "Environment defaults confirmed"}
      }
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-webhook-simulated-at", "2026-02-13T12:34:56Z")
    assert has_element?(view, "#setup-webhook-simulation-status", "Ready")
    assert has_element?(view, "#setup-webhook-signature-status", "Ready")
    assert has_element?(view, "#setup-webhook-event-issues-opened-status", "Ready")

    assert has_element?(
             view,
             "#setup-webhook-event-issues-opened-route",
             "Issue Bot triage workflow"
           )

    assert has_element?(view, "#setup-webhook-event-issue-comment-created-status", "Ready")
    assert has_element?(view, "#setup-issue-bot-default-enabled", "true")
    assert has_element?(view, "#setup-issue-bot-default-approval-mode", "manual")

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "Webhook simulation confirmed"}
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 7")

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 7

    step_state =
      persisted_config
      |> Map.fetch!(:onboarding_state)
      |> Map.fetch!("6")

    webhook_simulation_state = Map.fetch!(step_state, "webhook_simulation")
    assert webhook_simulation_state["status"] == "ready"
    assert webhook_simulation_state["signature"]["status"] == "ready"

    events_by_name =
      webhook_simulation_state["events"]
      |> Enum.map(fn event_result -> {event_result["event"], event_result} end)
      |> Map.new()

    assert events_by_name["issues.opened"]["status"] == "ready"
    assert events_by_name["issues.edited"]["status"] == "ready"
    assert events_by_name["issue_comment.created"]["status"] == "ready"

    assert Map.fetch!(step_state, "issue_bot_defaults") == %{
             "approval_mode" => "manual",
             "enabled" => true
           }
  end

  test "step 6 blocks Issue Bot enablement when webhook simulation fails and retains the failure reason for retry",
       %{conn: conn} do
    test_pid = self()

    Application.put_env(:jido_code, :setup_webhook_simulation_checker, fn _context ->
      failing_webhook_simulation_report()
    end)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 6,
      onboarding_state: %{
        "1" => %{"validated_note" => "Prerequisite checks passed"},
        "2" => %{
          "validated_note" => "Owner account confirmed",
          "owner_email" => "owner@example.com"
        },
        "3" => %{"validated_note" => "Provider setup confirmed"},
        "4" => %{"validated_note" => "GitHub credentials validated"},
        "5" => %{"validated_note" => "Environment defaults confirmed"}
      }
    })

    Application.put_env(:jido_code, :system_config_saver, fn _config ->
      send(test_pid, :unexpected_save)
      {:ok, %{onboarding_completed: false, onboarding_step: 7, onboarding_state: %{}}}
    end)

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-webhook-simulation-status", "Blocked")
    assert has_element?(view, "#setup-webhook-signature-status", "Failed")
    assert has_element?(view, "#setup-webhook-event-issue-comment-created-status", "Failed")
    assert has_element?(view, "#setup-webhook-failure-reason", "Webhook secret is missing")

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "Attempting to bypass webhook simulation failure"}
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 6")
    assert has_element?(view, "#setup-save-error", "Webhook simulation failed")
    assert has_element?(view, "#setup-save-error", "retained for retry")
    assert has_element?(view, "#setup-save-error", "Webhook secret is missing")
    assert has_element?(view, "#setup-webhook-failure-reason", "Webhook secret is missing")
    refute_received :unexpected_save

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 6
    refute Map.has_key?(Map.fetch!(persisted_config, :onboarding_state), "6")
  end

  test "step 7 lists only accessible repositories and renders stable identifiers for import selection",
       %{conn: conn} do
    onboarding_state =
      onboarding_state_through_step_6()
      |> put_in(["4", "github_credentials", "paths"], [
        %{
          "path" => "github_app",
          "status" => "ready",
          "repository_access" => "confirmed",
          "repositories" => [
            %{"id" => "repo_200", "full_name" => "owner/repo-two"},
            "owner/repo-one"
          ]
        },
        %{
          "path" => "pat",
          "status" => "invalid",
          "repository_access" => "unconfirmed",
          "repositories" => ["owner/private-repo"]
        }
      ])

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 7,
      onboarding_state: onboarding_state
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-project-repository-listing-status", "Ready")
    assert has_element?(view, "#setup-project-repository-option-owner-repo-one", "owner/repo-one")
    assert has_element?(view, "#setup-project-repository-option-owner-repo-two", "owner/repo-two")
    refute has_element?(view, "#setup-project-repository-option-owner-private-repo")

    assert has_element?(
             view,
             "#setup-project-repository-stable-id-owner-repo-one",
             "repo:owner/repo-one"
           )

    assert has_element?(view, "#setup-project-repository-stable-id-owner-repo-two", "repo_200")
    assert has_element?(view, "#setup-project-repository-select option[value=\"owner/repo-one\"]")
    assert has_element?(view, "#setup-project-repository-select option[value=\"owner/repo-two\"]")
  end

  test "step 7 repository refresh surfaces typed GitHub fetch errors and preserves prior listing state",
       %{conn: conn} do
    test_pid = self()

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 7,
      onboarding_state: onboarding_state_through_step_6()
    })

    Application.put_env(:jido_code, :system_config_saver, fn _config ->
      send(test_pid, :unexpected_save)
      {:ok, %{onboarding_completed: false, onboarding_step: 8, onboarding_state: %{}}}
    end)

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-project-repository-listing-status", "Ready")
    assert has_element?(view, "#setup-project-repository-option-owner-repo-one", "owner/repo-one")

    Application.put_env(:jido_code, :setup_github_repository_fetcher, fn _context ->
      {:error, {"github_repository_fetch_timeout", "GitHub API request timed out while listing repositories."}}
    end)

    view
    |> element("#setup-project-repository-refresh")
    |> render_click()

    assert has_element?(view, "#resolved-onboarding-step", "Step 7")
    assert has_element?(view, "#setup-project-repository-listing-status", "Blocked")

    assert has_element?(
             view,
             "#setup-project-repository-listing-error-type",
             "github_repository_fetch_timeout"
           )

    assert has_element?(view, "#setup-save-error", "github_repository_fetch_timeout")
    assert has_element?(view, "#setup-save-error", "state was preserved for retry")
    assert has_element?(view, "#setup-project-repository-option-owner-repo-one", "owner/repo-one")
    refute_received :unexpected_save

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 7
    refute Map.has_key?(Map.fetch!(persisted_config, :onboarding_state), "7")
  end

  test "step 7 shows stale installation sync warning with retry guidance on repository listing",
       %{conn: conn} do
    onboarding_state =
      onboarding_state_through_step_6()
      |> Map.put("7", %{
        "installation_sync" => %{
          "status" => "stale",
          "event" => "installation",
          "action" => "created",
          "error_type" => "github_installation_sync_stale",
          "detail" =>
            "Installation sync failed while processing `installation.created`. Repository availability may be stale.",
          "remediation" => "Retry repository refresh in step 7 after confirming GitHub App installation access.",
          "accessible_repositories" => ["owner/repo-one"]
        }
      })

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 7,
      onboarding_state: onboarding_state
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-project-repository-listing-status", "Blocked")

    assert has_element?(
             view,
             "#setup-project-repository-listing-detail",
             "Repository availability may be stale"
           )

    assert has_element?(
             view,
             "#setup-project-repository-listing-remediation",
             "Retry repository refresh in step 7"
           )

    assert has_element?(view, "#setup-project-repository-option-owner-repo-one", "owner/repo-one")
  end

  test "step 7 imports the selected repository and step 8 completes onboarding with dashboard next actions",
       %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")
    authed_conn = authenticate_owner_conn("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 7,
      onboarding_state: onboarding_state_through_step_6()
    })

    {:ok, view, _html} = live(authed_conn, ~p"/setup", on_error: :warn)

    assert has_element?(view, "#setup-project-repository-select")
    assert has_element?(view, "#setup-project-repository-option-owner-repo-one", "owner/repo-one")

    view
    |> form("#onboarding-step-form", %{
      "step" => %{
        "repository_full_name" => "owner/repo-one",
        "validated_note" => "Imported first project"
      }
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 8")
    assert has_element?(view, "#setup-project-import-clone-status", "Ready")
    assert has_element?(view, "#setup-project-import-clone-transition", "Pending -> Cloning -> Ready")
    assert has_element?(view, "#setup-project-import-baseline-branch", "main")
    assert has_element?(view, "#setup-project-import-last-sync-at")

    post_import_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(post_import_config, :onboarding_step) == 8
    assert Map.fetch!(post_import_config, :onboarding_completed) == false

    project_import_state =
      post_import_config
      |> Map.fetch!(:onboarding_state)
      |> Map.fetch!("7")
      |> Map.fetch!("project_import")

    assert project_import_state["status"] == "ready"
    assert project_import_state["selected_repository"] == "owner/repo-one"
    assert project_import_state["baseline_metadata"]["status"] == "ready"
    assert project_import_state["project_record"]["clone_status"] == "ready"
    assert project_import_state["baseline_metadata"]["synced_branch"] == "main"
    assert is_binary(project_import_state["baseline_metadata"]["last_synced_at"])

    {:ok, [imported_project]} =
      Project.read(query: [filter: [github_full_name: "owner/repo-one"], limit: 1])

    assert imported_project.github_full_name == "owner/repo-one"
    assert imported_project.default_branch == "main"
    assert imported_project.settings["workspace"]["clone_status"] == "ready"
    assert is_binary(imported_project.settings["workspace"]["last_synced_at"])

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "Onboarding completed and ready for dashboard"}
    })
    |> render_submit()

    redirect_to =
      view
      |> assert_redirect()
      |> redirect_path()

    uri = URI.parse(redirect_to)
    assert uri.path == "/dashboard"
    assert uri.query =~ "onboarding=completed"

    {:ok, dashboard_view, _html} = live(recycle(authed_conn), redirect_to, on_error: :warn)
    assert has_element?(dashboard_view, "#dashboard-onboarding-next-actions")
    assert has_element?(dashboard_view, "#dashboard-next-action-1", "Run your first workflow")

    assert has_element?(
             dashboard_view,
             "#dashboard-next-action-2",
             "Review the security playbook"
           )

    assert has_element?(dashboard_view, "#dashboard-next-action-3", "Test the RPC client")

    completed_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(completed_config, :onboarding_completed) == true
    assert Map.fetch!(completed_config, :onboarding_step) == 9

    completion_state =
      completed_config
      |> Map.fetch!(:onboarding_state)
      |> Map.fetch!("8")

    assert completion_state["imported_repository"] == "owner/repo-one"

    assert completion_state["next_actions"] == [
             "Run your first workflow",
             "Review the security playbook",
             "Test the RPC client"
           ]
  end

  test "step 7 duplicate imports keep a single project record for the selected repository", %{
    conn: conn
  } do
    {:ok, _project} =
      Project.create(%{
        name: "repo-one",
        github_full_name: "owner/repo-one",
        default_branch: "main"
      })

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 7,
      onboarding_state: onboarding_state_through_step_6()
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    view
    |> form("#onboarding-step-form", %{
      "step" => %{
        "repository_full_name" => "owner/repo-one",
        "validated_note" => "Re-importing existing project"
      }
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 8")

    project_import_state =
      Application.get_env(:jido_code, :system_config)
      |> Map.fetch!(:onboarding_state)
      |> Map.fetch!("7")
      |> Map.fetch!("project_import")

    assert project_import_state["status"] == "ready"

    {:ok, projects} = Project.read(query: [filter: [github_full_name: "owner/repo-one"]])
    assert length(projects) == 1
  end

  test "step 7 baseline sync failure marks clone status as error with retry guidance", %{
    conn: conn
  } do
    Application.put_env(:jido_code, :setup_project_baseline_syncer, fn _context ->
      {:error, {"baseline_sync_unavailable", "Baseline sync worker timed out before checkout."}}
    end)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 7,
      onboarding_state: onboarding_state_through_step_6()
    })

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    view
    |> form("#onboarding-step-form", %{
      "step" => %{
        "repository_full_name" => "owner/repo-one",
        "validated_note" => "Import project with baseline sync failure"
      }
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 7")
    assert has_element?(view, "#setup-project-import-status", "Blocked")
    assert has_element?(view, "#setup-project-import-error-type", "baseline_sync_unavailable")
    assert has_element?(view, "#setup-project-import-clone-status", "Error")
    assert has_element?(view, "#setup-project-import-remediation", "Retry step 7")
    assert has_element?(view, "#setup-save-error", "baseline_sync_unavailable")

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 7
    assert Map.fetch!(persisted_config, :onboarding_completed) == false
    refute Map.has_key?(Map.fetch!(persisted_config, :onboarding_state), "7")

    {:ok, [project]} =
      Project.read(query: [filter: [github_full_name: "owner/repo-one"], limit: 1])

    assert project.settings["workspace"]["clone_status"] == "error"
    assert project.settings["workspace"]["last_error_type"] == "baseline_sync_unavailable"
    assert project.settings["workspace"]["retry_instructions"] =~ "Retry step 7"
  end

  test "step 7 import failure blocks onboarding completion and leaves completion flag unset", %{
    conn: conn
  } do
    test_pid = self()

    Application.put_env(:jido_code, :setup_project_importer, fn _context ->
      failing_project_import_report()
    end)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 7,
      onboarding_state: onboarding_state_through_step_6()
    })

    Application.put_env(:jido_code, :system_config_saver, fn _config ->
      send(test_pid, :unexpected_save)
      {:ok, %{onboarding_completed: true, onboarding_step: 8, onboarding_state: %{}}}
    end)

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)

    view
    |> form("#onboarding-step-form", %{
      "step" => %{
        "repository_full_name" => "owner/repo-one",
        "validated_note" => "Attempting to bypass failing project import"
      }
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 7")
    assert has_element?(view, "#setup-project-import-status", "Blocked")
    assert has_element?(view, "#setup-project-import-error-type", "repository_import_failed")
    assert has_element?(view, "#setup-save-error", "Onboarding completion is blocked")
    refute_received :unexpected_save

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 7
    assert Map.fetch!(persisted_config, :onboarding_completed) == false
    refute Map.has_key?(Map.fetch!(persisted_config, :onboarding_state), "7")

    {:ok, projects} = Project.read(query: [filter: [github_full_name: "owner/repo-one"]])
    assert projects == []
  end

  test "save failure keeps the same step and shows a retry-safe error", %{conn: conn} do
    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{
        "1" => %{"validated_note" => "Prerequisite checks passed"},
        "2" => %{"validated_note" => "Owner account confirmed"}
      }
    })

    Application.put_env(:jido_code, :system_config_saver, fn _config ->
      {:error, :database_unreachable}
    end)

    {:ok, view, _html} = live(conn, ~p"/setup", on_error: :warn)
    assert has_element?(view, "#resolved-onboarding-step", "Step 3")

    view
    |> form("#onboarding-step-form", %{
      "step" => %{"validated_note" => "Provider setup confirmed"}
    })
    |> render_submit()

    assert has_element?(view, "#resolved-onboarding-step", "Step 3")
    assert has_element?(view, "#setup-save-error", "safely retry this step")
    assert has_element?(view, "#validated-state-step-1", "Prerequisite checks passed")
    assert has_element?(view, "#validated-state-step-2", "Owner account confirmed")

    persisted_config = Application.get_env(:jido_code, :system_config)
    assert Map.fetch!(persisted_config, :onboarding_step) == 3
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

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)

  defp fetch_system_env(key) do
    case System.get_env(key) do
      nil -> :__missing__
      value -> value
    end
  end

  defp restore_system_env(key, :__missing__), do: System.delete_env(key)
  defp restore_system_env(key, value), do: System.put_env(key, value)

  defp register_owner(email, password) do
    strategy = Info.strategy!(User, :password)

    {:ok, owner} =
      Strategy.action(
        strategy,
        :register,
        %{
          "email" => email,
          "password" => password,
          "password_confirmation" => password
        },
        context: %{token_type: :sign_in}
      )

    owner
  end

  defp authenticate_owner_conn(email, password) do
    strategy = Info.strategy!(User, :password)

    {:ok, owner} =
      Strategy.action(
        strategy,
        :sign_in,
        %{"email" => email, "password" => password},
        context: %{token_type: :sign_in}
      )

    token =
      owner
      |> Map.get(:__metadata__, %{})
      |> Map.fetch!(:token)

    auth_response = build_conn() |> get(owner_sign_in_with_token_path(strategy, token))
    assert redirected_to(auth_response, 302) == "/"
    recycle(auth_response)
  end

  defp owner_sign_in_with_token_path(strategy, token) do
    strategy_path =
      strategy
      |> Strategy.routes()
      |> Enum.find_value(fn
        {path, :sign_in_with_token} -> path
        _other -> nil
      end)

    path =
      Path.join(
        "/auth",
        String.trim_leading(strategy_path || "/user/password/sign_in_with_token", "/")
      )

    query = URI.encode_query(%{"token" => token})
    "#{path}?#{query}"
  end

  defp assert_owner_count(expected_count) do
    {:ok, owners} = Ash.read(User, domain: Accounts, authorize?: false)
    assert length(owners) == expected_count
  end

  defp onboarding_state_through_step_6 do
    %{
      "1" => %{"validated_note" => "Prerequisite checks passed"},
      "2" => %{
        "validated_note" => "Owner account confirmed",
        "owner_email" => "owner@example.com"
      },
      "3" => %{"validated_note" => "Provider setup confirmed"},
      "4" => %{
        "validated_note" => "GitHub credentials validated",
        "github_credentials" => %{
          "status" => "ready",
          "paths" => [
            %{
              "path" => "github_app",
              "status" => "ready",
              "repositories" => ["owner/repo-one"]
            }
          ]
        }
      },
      "5" => %{"validated_note" => "Environment defaults confirmed"},
      "6" => %{"validated_note" => "Webhook simulation confirmed"}
    }
  end

  defp unique_workspace_root do
    workspace_root =
      Path.join(
        System.tmp_dir!(),
        "jido_code_setup_workspace_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(workspace_root)
    File.mkdir_p!(workspace_root)
    Path.expand(workspace_root)
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
        },
        %{
          id: "runtime_secret_key_base",
          name: "Runtime configuration: SECRET_KEY_BASE",
          status: :pass,
          detail: "Runtime configuration: SECRET_KEY_BASE is configured.",
          remediation: "Set endpoint `secret_key_base` (or env `SECRET_KEY_BASE`) and restart JidoCode.",
          checked_at: @checked_at
        },
        %{
          id: "runtime_phx_host",
          name: "Runtime configuration: PHX_HOST",
          status: :pass,
          detail: "Runtime configuration: PHX_HOST is configured.",
          remediation: "Set endpoint URL host (or env `PHX_HOST`) and restart JidoCode.",
          checked_at: @checked_at
        }
      ]
    }
  end

  defp failing_prerequisite_report do
    %{
      checked_at: @checked_at,
      status: :fail,
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
          status: :fail,
          detail: "Required runtime value `TOKEN_SIGNING_SECRET` is missing.",
          remediation: "Set `TOKEN_SIGNING_SECRET` in runtime config (or env) and restart JidoCode.",
          checked_at: @checked_at
        }
      ]
    }
  end

  defp timeout_prerequisite_report do
    %{
      checked_at: @checked_at,
      status: :timeout,
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
          id: "runtime_phx_host",
          name: "Runtime configuration: PHX_HOST",
          status: :timeout,
          detail: "Check timed out after 3000ms.",
          remediation: "Set endpoint URL host (or env `PHX_HOST`) and restart JidoCode.",
          checked_at: @checked_at
        }
      ]
    }
  end

  defp passing_provider_credential_report do
    %{
      checked_at: @checked_at,
      status: :active,
      credentials: [
        %{
          provider: :anthropic,
          name: "Anthropic",
          status: :active,
          detail: "ANTHROPIC_API_KEY is configured and passed verification checks.",
          remediation: "Credential is active.",
          verified_at: @checked_at,
          checked_at: @checked_at
        },
        %{
          provider: :openai,
          name: "OpenAI",
          status: :not_set,
          detail: "No OPENAI_API_KEY credential is configured.",
          remediation: "Set `OPENAI_API_KEY` and retry verification.",
          checked_at: @checked_at
        }
      ]
    }
  end

  defp mixed_provider_credential_report do
    %{
      checked_at: @checked_at,
      status: :active,
      credentials: [
        %{
          provider: :anthropic,
          name: "Anthropic",
          status: :active,
          detail: "ANTHROPIC_API_KEY is configured and passed verification checks.",
          remediation: "Credential is active.",
          verified_at: @checked_at,
          checked_at: @checked_at
        },
        %{
          provider: :openai,
          name: "OpenAI",
          status: :invalid,
          detail: "Configured OPENAI_API_KEY failed verification checks.",
          remediation: "Set a valid `OPENAI_API_KEY` (typically prefixed with `sk-`) and retry verification.",
          checked_at: @checked_at
        }
      ]
    }
  end

  defp failing_provider_credential_report do
    %{
      checked_at: @checked_at,
      status: :invalid,
      credentials: [
        %{
          provider: :anthropic,
          name: "Anthropic",
          status: :not_set,
          detail: "No ANTHROPIC_API_KEY credential is configured.",
          remediation: "Set `ANTHROPIC_API_KEY` and retry verification.",
          checked_at: @checked_at
        },
        %{
          provider: :openai,
          name: "OpenAI",
          status: :invalid,
          detail: "Configured OPENAI_API_KEY failed verification checks.",
          remediation: "Set a valid `OPENAI_API_KEY` (typically prefixed with `sk-`) and retry verification.",
          checked_at: @checked_at
        }
      ]
    }
  end

  defp prior_active_provider_credential_state do
    %{
      "checked_at" => DateTime.to_iso8601(@previous_checked_at),
      "status" => "active",
      "credentials" => [
        %{
          "provider" => "anthropic",
          "status" => "active",
          "verified_at" => DateTime.to_iso8601(@previous_checked_at),
          "checked_at" => DateTime.to_iso8601(@previous_checked_at)
        },
        %{
          "provider" => "openai",
          "status" => "active",
          "verified_at" => DateTime.to_iso8601(@previous_checked_at),
          "checked_at" => DateTime.to_iso8601(@previous_checked_at)
        }
      ]
    }
  end

  defp passing_github_credential_report do
    %{
      checked_at: @checked_at,
      status: :ready,
      owner_context: "owner@example.com",
      paths: [
        %{
          path: :github_app,
          name: "GitHub App",
          status: :ready,
          previous_status: :not_configured,
          transition: "Not configured -> Ready",
          owner_context: "owner@example.com",
          repository_access: :confirmed,
          repositories: ["owner/repo-one"],
          detail: "GitHub App credentials are valid and repository access is confirmed.",
          remediation: "Credential path is ready.",
          validated_at: @checked_at,
          checked_at: @checked_at
        },
        %{
          path: :pat,
          name: "Personal Access Token (PAT)",
          status: :not_configured,
          previous_status: :not_configured,
          transition: "Not configured -> Not configured",
          owner_context: "owner@example.com",
          repository_access: :unconfirmed,
          repositories: [],
          detail: "No GitHub personal access token fallback is configured (`GITHUB_PAT`).",
          remediation: "Set `GITHUB_PAT` and retry validation.",
          error_type: "github_pat_not_configured",
          checked_at: @checked_at
        }
      ]
    }
  end

  defp mixed_github_credential_report do
    %{
      checked_at: @checked_at,
      status: :ready,
      owner_context: "owner@example.com",
      paths: [
        %{
          path: :github_app,
          name: "GitHub App",
          status: :invalid,
          previous_status: :not_configured,
          transition: "Not configured -> Invalid",
          owner_context: "owner@example.com",
          repository_access: :unconfirmed,
          repositories: [],
          detail: "GitHub App credentials are configured but repository access could not be confirmed.",
          remediation: "Grant repository access for this owner context and retry validation.",
          error_type: "github_app_repository_access_unverified",
          checked_at: @checked_at
        },
        %{
          path: :pat,
          name: "Personal Access Token (PAT)",
          status: :ready,
          previous_status: :not_configured,
          transition: "Not configured -> Ready",
          owner_context: "owner@example.com",
          repository_access: :confirmed,
          repositories: ["owner/repo-one", "owner/repo-two"],
          detail: "GitHub PAT fallback is valid and confirms repository access.",
          remediation: "Credential path is ready.",
          validated_at: @checked_at,
          checked_at: @checked_at
        }
      ]
    }
  end

  defp failing_github_credential_report do
    %{
      checked_at: @checked_at,
      status: :blocked,
      owner_context: "owner@example.com",
      paths: [
        %{
          path: :github_app,
          name: "GitHub App",
          status: :invalid,
          previous_status: :not_configured,
          transition: "Not configured -> Invalid",
          owner_context: "owner@example.com",
          repository_access: :unconfirmed,
          repositories: [],
          detail: "Configured GitHub App credentials failed validation.",
          remediation: "Set valid GitHub App credentials and retry validation.",
          error_type: "github_app_credentials_invalid",
          checked_at: @checked_at
        },
        %{
          path: :pat,
          name: "Personal Access Token (PAT)",
          status: :invalid,
          previous_status: :not_configured,
          transition: "Not configured -> Invalid",
          owner_context: "owner@example.com",
          repository_access: :unconfirmed,
          repositories: [],
          detail: "Configured GitHub PAT failed validation.",
          remediation: "Set a valid `GITHUB_PAT` and retry validation.",
          error_type: "github_pat_credentials_invalid",
          checked_at: @checked_at
        }
      ]
    }
  end

  defp github_app_installation_gap_report do
    %{
      checked_at: @checked_at,
      status: :blocked,
      owner_context: "owner@example.com",
      paths: [
        %{
          path: :github_app,
          name: "GitHub App",
          status: :invalid,
          previous_status: :not_configured,
          transition: "Not configured -> Invalid",
          owner_context: "owner@example.com",
          repository_access: :unconfirmed,
          repositories: ["owner/repo-one"],
          expected_repositories: ["owner/repo-one", "owner/repo-two"],
          missing_repositories: ["owner/repo-two"],
          detail:
            "Credential path is configured but GitHub App installation access is missing expected repositories: owner/repo-two.",
          remediation: "Grant GitHub App installation access to expected repositories and retry validation.",
          error_type: "github_app_installation_access_missing_repositories",
          checked_at: @checked_at
        },
        %{
          path: :pat,
          name: "Personal Access Token (PAT)",
          status: :not_configured,
          previous_status: :not_configured,
          transition: "Not configured -> Not configured",
          owner_context: "owner@example.com",
          repository_access: :unconfirmed,
          repositories: [],
          detail: "No GitHub personal access token fallback is configured (`GITHUB_PAT`).",
          remediation: "Set `GITHUB_PAT` and retry validation.",
          error_type: "github_pat_not_configured",
          checked_at: @checked_at
        }
      ]
    }
  end

  defp passing_webhook_simulation_report do
    %{
      checked_at: @checked_at,
      status: :ready,
      signature: %{
        status: :ready,
        previous_status: :failed,
        transition: "Failed -> Ready",
        detail: "Webhook signature verification is ready for simulated deliveries.",
        remediation: "Signature readiness confirmed.",
        checked_at: @checked_at
      },
      events: [
        %{
          event: "issues.opened",
          route: "Issue Bot triage workflow",
          status: :ready,
          previous_status: :failed,
          transition: "Failed -> Ready",
          detail: "Webhook routing is ready for `issues.opened`.",
          remediation: "Routing readiness confirmed.",
          checked_at: @checked_at
        },
        %{
          event: "issues.edited",
          route: "Issue Bot re-triage workflow",
          status: :ready,
          previous_status: :failed,
          transition: "Failed -> Ready",
          detail: "Webhook routing is ready for `issues.edited`.",
          remediation: "Routing readiness confirmed.",
          checked_at: @checked_at
        },
        %{
          event: "issue_comment.created",
          route: "Issue Bot follow-up context workflow",
          status: :ready,
          previous_status: :failed,
          transition: "Failed -> Ready",
          detail: "Webhook routing is ready for `issue_comment.created`.",
          remediation: "Routing readiness confirmed.",
          checked_at: @checked_at
        }
      ],
      issue_bot_defaults: %{"enabled" => true, "approval_mode" => "manual"}
    }
  end

  defp failing_webhook_simulation_report do
    %{
      checked_at: @checked_at,
      status: :blocked,
      signature: %{
        status: :failed,
        previous_status: :failed,
        transition: "Failed -> Failed",
        detail: "Webhook secret is missing for signature verification.",
        remediation: "Configure `GITHUB_WEBHOOK_SECRET` and retry webhook simulation.",
        checked_at: @checked_at
      },
      events: [
        %{
          event: "issues.opened",
          route: "Issue Bot triage workflow",
          status: :ready,
          previous_status: :failed,
          transition: "Failed -> Ready",
          detail: "Webhook routing is ready for `issues.opened`.",
          remediation: "Routing readiness confirmed.",
          checked_at: @checked_at
        },
        %{
          event: "issues.edited",
          route: "Issue Bot re-triage workflow",
          status: :ready,
          previous_status: :failed,
          transition: "Failed -> Ready",
          detail: "Webhook routing is ready for `issues.edited`.",
          remediation: "Routing readiness confirmed.",
          checked_at: @checked_at
        },
        %{
          event: "issue_comment.created",
          route: "Issue Bot follow-up context workflow",
          status: :failed,
          previous_status: :failed,
          transition: "Failed -> Failed",
          detail: "Webhook routing is not configured for `issue_comment.created`.",
          remediation: "Configure Issue Bot webhook routing for this event and retry simulation.",
          checked_at: @checked_at
        }
      ],
      failure_reason: "Webhook secret is missing for signature verification."
    }
  end

  defp failing_project_import_report do
    %{
      checked_at: @checked_at,
      status: :blocked,
      selected_repository: "owner/repo-one",
      detail: "Repository import failed while initializing baseline metadata.",
      remediation: "Fix repository import configuration and retry step 7.",
      error_type: "repository_import_failed"
    }
  end

  defp redirect_path({path, _flash}) when is_binary(path), do: path
  defp redirect_path(path) when is_binary(path), do: path

  defp reset_owner_state! do
    Ecto.Adapters.SQL.query!(Repo, "TRUNCATE TABLE users RESTART IDENTITY CASCADE", [])
  end
end
