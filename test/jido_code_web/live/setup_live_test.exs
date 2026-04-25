defmodule JidoCodeWeb.SetupLiveTest do
  # covers: baseline.surface.public_entry_routes
  # covers: architecture.frontend_stack.product_owned_mounting_boundary
  # covers: architecture.frontend_stack.server_authored_props_streams_and_events
  # covers: architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
  # covers: users.admin_system.bootstrap_admin
  # covers: users.admin_system.admin_role_assignment
  # covers: users.admin_system.registration_guardrails
  # covers: setup.onboarding.post_bootstrap_start_surface
  # covers: setup.onboarding.deployment_mode_auto_detected
  # covers: setup.onboarding.runtime_environment_selection_distinct_from_install_flavor
  # covers: setup.onboarding.runtime_environment_selection_persisted_metadata
  # covers: setup.onboarding.explicit_completion_path_to_dashboard
  # covers: setup.onboarding.deferred_integrations
  # covers: setup.onboarding.github_repository_selection_persisted_metadata
  # covers: setup.onboarding.github_pat_capture_persisted_secret_ref
  # covers: setup.onboarding.github_pat_capture_requires_encryption_ready_secret_storage
  # covers: setup.onboarding.start_path_preference_persisted
  use JidoCodeWeb.ConnCase, async: false

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts
  alias JidoCode.Accounts.User
  alias JidoCode.Security.SecretRefs
  alias JidoCode.Repo

  import Phoenix.LiveViewTest

  @checked_at ~U[2026-02-13 12:34:56Z]
  @owner_recovery_audit_event [:jido_code, :auth, :owner_recovery, :completed]

  setup do
    original_config = Application.get_env(:jido_code, :system_config, :__missing__)
    original_prerequisite_checker = Application.get_env(:jido_code, :setup_prerequisite_checker, :__missing__)
    original_github_credential_checker = Application.get_env(:jido_code, :setup_github_credential_checker, :__missing__)
    original_github_http_client = Application.get_env(:jido_code, :setup_github_http_client, :__missing__)

    original_github_http_client_options =
      Application.get_env(:jido_code, :setup_github_http_client_options, :__missing__)

    original_project_importer = Application.get_env(:jido_code, :setup_project_importer, :__missing__)
    original_frontend_override = Application.get_env(:jido_code, :frontend_assets_override, :__missing__)
    original_target = fetch_system_env("BURRITO_TARGET")

    on_exit(fn ->
      restore_env(:system_config, original_config)
      restore_env(:setup_prerequisite_checker, original_prerequisite_checker)
      restore_env(:setup_github_credential_checker, original_github_credential_checker)
      restore_env(:setup_github_http_client, original_github_http_client)
      restore_env(:setup_github_http_client_options, original_github_http_client_options)
      restore_env(:setup_project_importer, original_project_importer)
      restore_env(:frontend_assets_override, original_frontend_override)
      restore_system_env("BURRITO_TARGET", original_target)
    end)

    Application.delete_env(:jido_code, :setup_prerequisite_checker)
    Application.delete_env(:jido_code, :setup_github_credential_checker)
    Application.delete_env(:jido_code, :setup_github_http_client)
    Application.delete_env(:jido_code, :setup_github_http_client_options)
    Application.delete_env(:jido_code, :setup_project_importer)
    Application.delete_env(:jido_code, :frontend_assets_override)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 1,
      onboarding_state: %{},
      default_environment: :sprite,
      workspace_root: nil
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
    assert runtime_defaults_widget(setup_view).props["selectedStartPathLabel"] == "Not chosen yet"
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

    runtime_widget = runtime_defaults_widget(view)
    start_widget = start_path_widget(view)

    assert has_element?(view, "#setup-complete-continue", "Continue to dashboard")

    assert runtime_widget.props["installFlavor"] == "Desktop"
    assert runtime_widget.props["savedRuntimeLabel"] == "Cloud"

    assert_vue_handler(view, "changeRuntimeEnvironment", "change_runtime_environment",
      id: "setup-runtime-defaults-widget"
    )

    assert_vue_handler(view, "saveRuntimeEnvironment", "save_runtime_environment",
      id: "setup-runtime-defaults-widget"
    )

    assert Enum.map(start_widget.props["options"], & &1["id"]) == ["local_repo", "github", "later"]
    assert start_option(start_widget, "local_repo")["badgeLabel"] == "Recommended"
    assert start_option(start_widget, "local_repo")["buttonLabel"] == "Add local repo"
    assert start_option(start_widget, "github")["buttonLabel"] == "Connect GitHub"
    assert start_option(start_widget, "later")["buttonLabel"] == "Do this later"

    assert_vue_handler(view, "chooseStartPath", "choose_start_path", id: "setup-start-path-selector")
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

    runtime_widget = runtime_defaults_widget(view)
    start_widget = start_path_widget(view)

    assert has_element?(view, "#setup-complete-continue", "Continue to dashboard")

    assert runtime_widget.props["installFlavor"] == "Cloud"
    assert runtime_widget.props["savedRuntimeLabel"] == "Cloud"

    assert Enum.map(start_widget.props["options"], & &1["id"]) == ["github", "later"]
    assert start_option(start_widget, "github")["badgeLabel"] == "Recommended"
    assert start_option(start_widget, "github")["buttonLabel"] == "Connect GitHub"
    assert start_option(start_widget, "later")["buttonLabel"] == "Do this later"
  end

  test "saving a local runtime environment persists validated local defaults without advancing onboarding progress",
       %{conn: conn} do
    workspace_root = tmp_workspace_path!()
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
      },
      default_environment: :sprite,
      workspace_root: nil
    })

    {:ok, view, _html} =
      conn
      |> authenticate_owner_conn("owner@example.com", "owner-password-123")
      |> live(~p"/setup", on_error: :warn)

    render_change(view, "change_runtime_environment", %{
      "runtime_environment" => %{
        "mode" => "local"
      }
    })

    assert runtime_defaults_widget(view).props["form"]["mode"] == "local"

    render_submit(view, "save_runtime_environment", %{
      "runtime_environment" => %{
        "mode" => "local",
        "workspace_root" => workspace_root
      }
    })

    runtime_widget = runtime_defaults_widget(view)
    assert runtime_widget.props["savedRuntimeLabel"] == "Local"
    assert runtime_widget.props["savedRuntimeNote"] ==
             "Local execution will use #{workspace_root} as the default workspace root."

    assert %{
             onboarding_completed: false,
             onboarding_step: 3,
             default_environment: :local,
             workspace_root: ^workspace_root,
             onboarding_state: %{
               "3" => %{
                 "runtime_environment" => %{
                   "mode" => "local",
                   "default_environment" => "local",
                   "workspace_root" => ^workspace_root,
                   "status" => "ready"
                 },
                 "runtime_environment_note" => runtime_note
               }
             }
           } = Application.get_env(:jido_code, :system_config)

    assert runtime_note =~ workspace_root
  end

  test "saving a local runtime environment rejects an invalid workspace root", %{conn: conn} do
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
      },
      default_environment: :sprite,
      workspace_root: nil
    })

    {:ok, view, _html} =
      conn
      |> authenticate_owner_conn("owner@example.com", "owner-password-123")
      |> live(~p"/setup", on_error: :warn)

    render_change(view, "change_runtime_environment", %{
      "runtime_environment" => %{
        "mode" => "local"
      }
    })

    render_submit(view, "save_runtime_environment", %{
      "runtime_environment" => %{
        "mode" => "local",
        "workspace_root" => "relative/workspaces"
      }
    })

    assert runtime_defaults_widget(view).props["saveError"] =~
             "Workspace root must be an absolute path."

    assert %{
             onboarding_completed: false,
             onboarding_step: 3,
             default_environment: :sprite,
             workspace_root: nil,
             onboarding_state: onboarding_state
           } = Application.get_env(:jido_code, :system_config)

    refute get_in(onboarding_state, ["3", "runtime_environment"])
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

    choose_start_path(view, "github")

    assert runtime_defaults_widget(view).props["selectedStartPathLabel"] == "Connect GitHub"
    assert start_option(start_path_widget(view), "github")["badgeLabel"] == "Saved"
    assert start_option(start_path_widget(view), "github")["buttonLabel"] == "Saved"
    assert start_option(start_path_widget(view), "github")["disabled"] == true

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

  test "choosing GitHub surfaces the bounded LiveVue repository selector with linked repository options",
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
        },
        "4" => %{
          "github_credentials" => %{
            "paths" => [
              %{
                "path" => "github_app",
                "status" => "ready",
                "repository_access" => "confirmed",
                "repositories" => [
                  %{"id" => "repo_100", "full_name" => "owner/repo-one"},
                  %{"id" => "repo_200", "full_name" => "owner/repo-two"}
                ]
              }
            ]
          }
        }
      }
    })

    {:ok, view, _html} =
      conn
      |> authenticate_owner_conn("owner@example.com", "owner-password-123")
      |> live(~p"/setup", on_error: :warn)

    refute has_element?(view, "#setup-github-repository-panel")

    choose_start_path(view, "github")

    assert has_element?(view, "#setup-github-repository-panel")
    refute has_element?(view, "#setup-github-repository-summary")

    assert_vue_component(view, "SetupGitHubRepositorySelectorWidget", id: "setup-github-repository-selector")

    assert_vue_handler(view, "selectRepository", "select_github_repository", id: "setup-github-repository-selector")

    assert_vue_handler(view, "refreshRepositories", "refresh_github_repository_listing",
      id: "setup-github-repository-selector"
    )

    assert_vue_handler(view, "importRepository", "import_selected_github_repository",
      id: "setup-github-repository-selector"
    )

    selector = vue(view, id: "setup-github-repository-selector")

    assert selector.props["panelTitle"] == "Choose GitHub repositories"
    assert selector.props["panelBadgeLabel"] == "Optional follow-up"
    assert selector.props["panelSummary"] ==
             "Pick one or more linked GitHub repositories and import them into the control plane."

    assert selector.props["panelDetail"] ==
             "Pick one or more linked GitHub repositories to import into the control plane now, or finish onboarding and come back later."

    assert selector.props["boundaryNote"] ==
             "LiveView still owns PAT capture, persistence, and completion; this widget only makes repository follow-up easier to scan and resume."

    assert selector.props["selectedRepositories"] == []
    assert selector.props["importSelectedRepositories"] == []
    assert selector.props["listingStatus"] == "ready"
    assert selector.props["repositoryCountLabel"] == "2 linked repositories available for import."

    assert Enum.map(selector.props["repositoryOptions"], & &1["fullName"]) == [
             "owner/repo-one",
             "owner/repo-two"
           ]
  end

  test "GitHub repository selector persists multi-selection toggles through the LiveView event contract",
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
        },
        "4" => %{
          "github_credentials" => %{
            "paths" => [
              %{
                "path" => "github_app",
                "status" => "ready",
                "repository_access" => "confirmed",
                "repositories" => [
                  %{"id" => "repo_100", "full_name" => "owner/repo-one"},
                  %{"id" => "repo_200", "full_name" => "owner/repo-two"}
                ]
              }
            ]
          }
        }
      }
    })

    {:ok, view, _html} =
      conn
      |> authenticate_owner_conn("owner@example.com", "owner-password-123")
      |> live(~p"/setup", on_error: :warn)

    choose_start_path(view, "github")

    render_click(view, "select_github_repository", %{"repository_full_name" => "owner/repo-one"})

    assert %{
             onboarding_state: %{
               "7" => %{
                 "selected_repository" => "owner/repo-one",
                 "selected_repositories" => ["owner/repo-one"]
               }
             }
           } = Application.get_env(:jido_code, :system_config)

    assert vue(view, id: "setup-github-repository-selector").props["selectedRepositories"] == [
             "owner/repo-one"
           ]

    render_click(view, "select_github_repository", %{"repository_full_name" => "owner/repo-two"})

    assert %{
             onboarding_state: %{
               "7" => %{
                 "selected_repository" => "owner/repo-one",
                 "selected_repositories" => ["owner/repo-one", "owner/repo-two"]
               }
             }
           } = Application.get_env(:jido_code, :system_config)

    assert vue(view, id: "setup-github-repository-selector").props["selectedRepositories"] == [
             "owner/repo-one",
             "owner/repo-two"
           ]

    render_click(view, "select_github_repository", %{"repository_full_name" => "owner/repo-one"})

    assert %{
             onboarding_state: %{
               "7" => %{
                 "selected_repository" => "owner/repo-two",
                 "selected_repositories" => ["owner/repo-two"]
               }
             }
           } = Application.get_env(:jido_code, :system_config)

    assert vue(view, id: "setup-github-repository-selector").props["selectedRepositories"] == [
             "owner/repo-two"
           ]

    render_click(view, "select_github_repository", %{"repository_full_name" => "owner/repo-two"})

    assert %{
             onboarding_state: %{
               "7" => step_state
             }
           } = Application.get_env(:jido_code, :system_config)

    refute Map.has_key?(step_state, "selected_repository")
    refute Map.has_key?(step_state, "selected_repositories")
    assert vue(view, id: "setup-github-repository-selector").props["selectedRepositories"] == []
  end

  test "GitHub repository selector does not preselect previously imported repositories on reload",
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
        },
        "4" => %{
          "github_credentials" => %{
            "paths" => [
              %{
                "path" => "github_app",
                "status" => "ready",
                "repository_access" => "confirmed",
                "repositories" => [
                  %{"id" => "repo_100", "full_name" => "owner/repo-one"},
                  %{"id" => "repo_200", "full_name" => "owner/repo-two"}
                ]
              }
            ]
          }
        },
        "7" => %{
          "project_import_batch" => %{
            "checked_at" => DateTime.to_iso8601(@checked_at),
            "status" => "ready",
            "selected_repositories" => ["owner/repo-one"],
            "imported_repositories" => ["owner/repo-one"],
            "project_paths" => [
              %{
                "repository_full_name" => "owner/repo-one",
                "managed_repo_id" => "managed-repo-repo-one",
                "path" => "/repos/managed-repo-repo-one"
              }
            ],
            "detail" => "Imported owner/repo-one into the managed-repository control plane.",
            "remediation" => "Import complete.",
            "error_type" => nil
          }
        }
      }
    })

    {:ok, view, _html} =
      conn
      |> authenticate_owner_conn("owner@example.com", "owner-password-123")
      |> live(~p"/setup", on_error: :warn)

    choose_start_path(view, "github")

    selector = vue(view, id: "setup-github-repository-selector")

    assert selector.props["selectedRepositories"] == []
    assert selector.props["repositoryCountLabel"] == "2 linked repositories available for import."
    assert selector.props["importProjectDisplayName"] == "repo-one"
  end

  test "choosing GitHub requires PAT capture when deployment-local repository access is not configured",
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

    {:ok, view, _html} =
      conn
      |> authenticate_owner_conn("owner@example.com", "owner-password-123")
      |> live(~p"/setup", on_error: :warn)

    choose_start_path(view, "github")

    assert has_element?(view, "#setup-github-pat-panel")
    assert has_element?(
             view,
             "#setup-github-repository-summary",
             "Save a deployment-local GitHub PAT first, then repository selection will unlock automatically."
           )

    assert has_element?(view, "#setup-github-pat-form")
    assert has_element?(view, "#setup-github-repository-selector-deferred")
    refute has_element?(view, "#setup-github-repository-selector")

    assert has_element?(
             view,
             "#setup-github-pat-summary",
             "No GitHub personal access token fallback is configured"
           )

    assert has_element?(view, "#setup-github-pat-note", "vcs/github/pat")
  end

  test "saving a GitHub PAT persists encrypted secret storage and refreshes linked repositories",
       %{conn: conn} do
    register_owner("owner@example.com", "owner-password-123")

    managed_app_env_keys = [
      :github_app_id,
      :github_app_private_key,
      :github_app_installation_token,
      :github_app_accessible_repos,
      :github_app_expected_repos,
      :github_pat,
      :github_pat_accessible_repos
    ]

    managed_system_env_keys = [
      "GITHUB_APP_ID",
      "GITHUB_APP_PRIVATE_KEY",
      "GITHUB_APP_INSTALLATION_TOKEN",
      "GITHUB_APP_ACCESSIBLE_REPOS",
      "GITHUB_APP_EXPECTED_REPOS",
      "GITHUB_PAT",
      "GITHUB_PAT_ACCESSIBLE_REPOS"
    ]

    original_app_env =
      Enum.map(managed_app_env_keys, fn key ->
        {key, Application.get_env(:jido_code, key, :__missing__)}
      end)

    original_system_env =
      Enum.map(managed_system_env_keys, fn key ->
        {key, fetch_system_env(key)}
      end)

    on_exit(fn ->
      Enum.each(original_app_env, fn {key, value} ->
        restore_env(key, value)
      end)

      Enum.each(original_system_env, fn {key, value} ->
        restore_system_env(key, value)
      end)
    end)

    Enum.each(managed_app_env_keys, &Application.delete_env(:jido_code, &1))
    Enum.each(managed_system_env_keys, &System.delete_env/1)

    test_pid = self()

    Application.put_env(:jido_code, :setup_github_http_client, fn :pat, "ghp_test_token", _opts ->
      send(test_pid, :github_pat_repository_listing_requested)

      {:ok,
       [
         %{id: "repo_100", full_name: "owner/repo-one"},
         %{id: "repo_200", full_name: "owner/repo-two"}
       ]}
    end)

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

    choose_start_path(view, "github")

    render_submit(view, "save_github_pat", %{"github_pat" => %{"value" => "ghp_test_token"}})

    assert_receive :github_pat_repository_listing_requested
    refute has_element?(view, "#setup-github-pat-panel")

    selector = vue(view, id: "setup-github-repository-selector")

    assert selector.props["listingStatus"] == "ready"

    assert Enum.map(selector.props["repositoryOptions"], & &1["fullName"]) == [
             "owner/repo-one",
             "owner/repo-two"
           ]

    assert {:ok, pat_secret} =
             SecretRefs.operational_secret_value(:integration, "vcs/github/pat")

    assert pat_secret.value == "ghp_test_token"
    assert pat_secret.source == :onboarding

    assert %{
             onboarding_state: %{
               "4" => %{
                 "github_credentials" => %{
                   "paths" => [
                     %{
                       "path" => "github_app",
                       "status" => "not_configured"
                     },
                     %{
                       "path" => "pat",
                       "repository_access" => "confirmed",
                       "repositories" => ["owner/repo-one", "owner/repo-two"],
                       "status" => "ready"
                     }
                   ],
                   "status" => "ready"
                 }
               },
               "7" => %{
                 "repository_listing" => %{
                   "status" => "ready"
                 }
               }
             }
           } = Application.get_env(:jido_code, :system_config)
  end

  test "choosing GitHub surfaces encryption preflight before PAT save when secret storage is unavailable",
       %{conn: conn} do
    register_owner("owner@example.com", "owner-password-123")

    original_encryption_key = Application.get_env(:jido_code, :secret_ref_encryption_key, :__missing__)

    on_exit(fn ->
      restore_env(:secret_ref_encryption_key, original_encryption_key)
    end)

    Application.delete_env(:jido_code, :secret_ref_encryption_key)

    test_pid = self()

    Application.put_env(:jido_code, :setup_github_http_client, fn _path, _token, _opts ->
      send(test_pid, :github_pat_repository_listing_requested_unexpectedly)
      {:ok, []}
    end)

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

    choose_start_path(view, "github")

    assert has_element?(view, "#setup-github-pat-encryption-preflight")
    assert has_element?(view, "#setup-github-repository-selector-deferred")
    refute has_element?(view, "#setup-github-repository-selector")
    assert render(view) =~ "Encrypted secret storage is unavailable in this running JidoCode process."
    assert render(view) =~ "JIDO_CODE_SECRET_REF_ENCRYPTION_KEY"

    render_submit(view, "save_github_pat", %{"github_pat" => %{"value" => "ghp_test_token"}})

    refute_received :github_pat_repository_listing_requested_unexpectedly

    assert has_element?(
             view,
             "#setup-github-pat-save-error",
             "Encrypted secret storage is unavailable in this running JidoCode process."
           )
  end

  test "choosing GitHub hydrates deployment-local credential checks when step 4 state is missing",
       %{conn: conn} do
    register_owner("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :setup_github_credential_checker, fn _context ->
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
            transition: "activated",
            owner_context: "owner@example.com",
            repository_access: :confirmed,
            repositories: ["owner/repo-one", "owner/repo-two"],
            expected_repositories: [],
            missing_repositories: [],
            detail: "GitHub App credentials resolved with confirmed repository access.",
            remediation: "Credential path is ready.",
            error_type: nil,
            validated_at: @checked_at,
            checked_at: @checked_at
          }
        ]
      }
    end)

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

    choose_start_path(view, "github")

    selector = vue(view, id: "setup-github-repository-selector")

    assert selector.props["listingStatus"] == "ready"

    assert Enum.map(selector.props["repositoryOptions"], & &1["fullName"]) == [
             "owner/repo-one",
             "owner/repo-two"
           ]

    assert %{
             onboarding_state: %{
               "4" => %{
                 "github_credentials" => %{
                   "owner_context" => "owner@example.com",
                   "status" => "ready",
                   "paths" => [
                     %{
                       "path" => "github_app",
                       "repository_access" => "confirmed",
                       "repositories" => ["owner/repo-one", "owner/repo-two"],
                       "status" => "ready"
                     }
                   ]
                 }
               }
             }
           } = Application.get_env(:jido_code, :system_config)
  end

  test "fallback GitHub repository selector persists selection and import metadata when richer delivery degrades",
       %{conn: conn} do
    register_owner("owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :frontend_assets_override, %{
      mode: :fallback,
      reason: :asset_manifest_unavailable
    })

    Application.put_env(:jido_code, :setup_project_importer, fn context ->
      selected_repository = context.selected_repository
      repo_name = selected_repository |> String.split("/") |> List.last()
      managed_repo_id = "managed-repo-#{repo_name}"

      %{
        checked_at: @checked_at,
        status: :ready,
        selected_repository: selected_repository,
        project_record: %{
          id: managed_repo_id,
          name: repo_name,
          source_kind: :github,
          source_identifier: selected_repository,
          github_full_name: selected_repository,
          local_path: nil,
          default_branch: "main",
          import_mode: :created,
          imported_at: @checked_at,
          clone_status: :ready,
          clone_status_history: [
            %{status: :pending},
            %{status: :cloning},
            %{status: :ready}
          ],
          last_synced_at: @checked_at
        },
        baseline_metadata: %{
          workspace_initialized: true,
          baseline_synced: true,
          default_workflow_registered: true,
          agent_configuration_registered: true,
          status: :ready,
          initialized_at: @checked_at,
          synced_branch: "main",
          last_synced_at: @checked_at,
          workspace_environment: :sprite,
          workspace_path: nil
        },
        detail: "Imported #{selected_repository} into the managed-repository control plane.",
        remediation: "Import complete.",
        error_type: nil
      }
    end)

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
        },
        "4" => %{
          "github_credentials" => %{
            "paths" => [
              %{
                "path" => "github_app",
                "status" => "ready",
                "repository_access" => "confirmed",
                "repositories" => [
                  %{"id" => "repo_100", "full_name" => "owner/repo-one"},
                  %{"id" => "repo_200", "full_name" => "owner/repo-two"}
                ]
              }
            ]
          }
        }
      }
    })

    {:ok, view, _html} =
      conn
      |> authenticate_owner_conn("owner@example.com", "owner-password-123")
      |> live(~p"/setup", on_error: :warn)

    choose_start_path(view, "github")

    assert has_element?(view, "#setup-github-repository-selector-fallback")
    assert has_element?(view, "#setup-github-repository-selector-fallback-body")
    assert has_element?(view, "#setup-github-repository-fallback-title", "Choose GitHub repositories")
    assert has_element?(view, "#setup-github-repository-fallback-badge", "Optional follow-up")

    assert has_element?(
             view,
             "#setup-github-repository-fallback-summary",
             "Pick one or more linked GitHub repositories and import them into the control plane."
           )

    assert has_element?(
             view,
             "#setup-github-repository-fallback-boundary-note",
             "LiveView still owns PAT capture, persistence, and completion; this widget only makes repository follow-up easier to scan and resume."
           )

    assert has_element?(view, "#setup-github-repository-fallback-list")

    assert has_element?(
             view,
             "#setup-github-repository-fallback-count",
             "2 linked repositories available for import."
           )

    view
    |> element("#setup-github-repository-fallback-option-repo_100")
    |> render_click()

    assert %{
             onboarding_state: %{
               "7" => %{
                 "selected_repository" => "owner/repo-one",
                 "selected_repositories" => ["owner/repo-one"]
               }
             }
           } = Application.get_env(:jido_code, :system_config)

    view
    |> element("#setup-github-repository-fallback-option-repo_200")
    |> render_click()

    assert %{
             onboarding_state: %{
               "7" => %{
                 "selected_repository" => "owner/repo-one",
                 "selected_repositories" => ["owner/repo-one", "owner/repo-two"]
               }
             }
           } = Application.get_env(:jido_code, :system_config)

    view
    |> form("#setup-github-repository-selector-fallback-form", %{
      "repository_selection" => %{"repository_full_names" => ["owner/repo-one", "owner/repo-two"]}
    })
    |> render_submit()

    assert %{
             onboarding_state: %{
               "7" => step_state
             }
           } = Application.get_env(:jido_code, :system_config)

    assert step_state["project_import"]["selected_repository"] == "owner/repo-two"
    assert step_state["project_import"]["project_record"]["id"] == "managed-repo-repo-two"
    assert step_state["project_import"]["status"] == "ready"
    assert step_state["project_import_batch"]["selected_repositories"] == ["owner/repo-one", "owner/repo-two"]
    assert step_state["project_import_batch"]["imported_repositories"] == ["owner/repo-one", "owner/repo-two"]
    assert step_state["project_import_batch"]["status"] == "ready"
    assert step_state["repository_selection_note"] == "GitHub repository selection cleared."
    refute Map.has_key?(step_state, "selected_repository")
    refute Map.has_key?(step_state, "selected_repositories")

    assert has_element?(view, "#setup-github-import-fallback-success")
    assert has_element?(
             view,
             "#setup-github-import-fallback-success",
             "Imported 2 GitHub repositories into the managed-repository control plane."
           )

    refute has_element?(view, "#setup-github-import-fallback-open-repo")
    assert has_element?(view, "#setup-github-repository-fallback-selection", "Not selected")
  end

  test "completing setup after choosing GitHub marks onboarding complete and enters the dashboard", %{
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

    authed_conn =
      conn
      |> authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, view, _html} = live(authed_conn, ~p"/setup", on_error: :warn)

    choose_start_path(view, "github")

    view
    |> element("#setup-complete-continue")
    |> render_click()

    assert_redirect(view, "/dashboard?onboarding=completed")

    assert %{
             onboarding_completed: true,
             onboarding_step: 4,
             onboarding_state: %{
               "1" => %{"validated_note" => "System prerequisites verified (welcome flow)."},
               "2" => %{"validated_note" => "Owner account bootstrapped."},
               "3" => %{
                 "start_path" => "github",
                 "deployment_mode" => "cloud",
                 "validated_note" => "GitHub path selected.",
                 "completion_note" => completion_note
               }
             }
           } = Application.get_env(:jido_code, :system_config)

    assert completion_note =~ "Setup completed."

    {:ok, dashboard_view, _html} =
      live(recycle(authed_conn), ~p"/dashboard?onboarding=completed", on_error: :warn)

    assert has_element?(dashboard_view, "#dashboard-run-summaries")
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
    assert runtime_defaults_widget(view).props["selectedStartPathLabel"] == "Do this later"
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
    assert_vue_component(view, "SetupRuntimeDefaultsWidget", id: "setup-runtime-defaults-widget")
    assert_vue_component(view, "SetupStartPathSelectorWidget", id: "setup-start-path-selector")
    assert_vue_handler(view, "changeRuntimeEnvironment", "change_runtime_environment",
      id: "setup-runtime-defaults-widget"
    )

    assert_vue_handler(view, "saveRuntimeEnvironment", "save_runtime_environment",
      id: "setup-runtime-defaults-widget"
    )

    assert_vue_handler(view, "chooseStartPath", "choose_start_path", id: "setup-start-path-selector")
    assert has_element?(view, "#setup-complete-continue", "Continue to dashboard")
    assert runtime_defaults_widget(view).props["ownerEmail"] == "owner@example.com"
  end

  defp runtime_defaults_widget(view), do: vue(view, id: "setup-runtime-defaults-widget")

  defp start_path_widget(view), do: vue(view, id: "setup-start-path-selector")

  defp start_option(widget, id) do
    Enum.find(widget.props["options"], &(&1["id"] == id))
  end

  defp choose_start_path(view, choice) do
    render_click(view, "choose_start_path", %{"choice" => choice})
  end

  defp tmp_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "setup-live-runtime-workspace-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
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
