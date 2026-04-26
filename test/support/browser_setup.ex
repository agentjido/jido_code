defmodule JidoCodeWeb.BrowserSetup do
  # covers: architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
  # covers: architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
  # covers: architecture.conversation_orchestration.llm_readiness_and_failure_states_are_explicit
  @moduledoc false

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts.User
  alias JidoCode.Repo
  alias JidoCode.Control.Actor
  alias JidoCode.Projects.Project

  @checked_at ~U[2026-02-13 12:34:56Z]
  @owner_email "owner@example.com"
  @owner_password "owner-password-123"
  @setup_modes ~w(normal fallback)
  @conversation_modes ~w(conversation_ready conversation_runtime_blocked conversation_degraded)
  @scenario_modes @setup_modes ++ @conversation_modes

  def valid_scenario?(mode) when mode in @scenario_modes, do: true
  def valid_scenario?(_mode), do: false

  def owner_email, do: @owner_email
  def owner_password, do: @owner_password

  def apply_scenario!(mode) when mode in @scenario_modes do
    reset_browser_state!()
    seed_owner!()

    case mode do
      setup_mode when setup_mode in @setup_modes ->
        configure_frontend_delivery!(setup_mode)
        configure_project_importer!()
        seed_setup_system_config!()

      conversation_mode when conversation_mode in @conversation_modes ->
        configure_conversation_delivery!(conversation_mode)
        seed_conversation_system_config!()
        seed_conversation_project!(conversation_mode)
    end

    :ok
  end

  defp reset_browser_state! do
    Ecto.Adapters.SQL.query!(Repo, "TRUNCATE TABLE users RESTART IDENTITY CASCADE", [])

    Application.delete_env(:jido_code, :setup_github_credential_checker)
    Application.delete_env(:jido_code, :setup_github_http_client)
    Application.delete_env(:jido_code, :setup_github_http_client_options)
    Application.delete_env(:jido_code, :setup_project_importer)
    Application.delete_env(:jido_code, :frontend_assets_override)
    Application.delete_env(:jido_code, :conversation_pubsub_subscriber)
    Application.delete_env(:jido_code, :system_config)

    System.delete_env("BURRITO_TARGET")
  end

  defp configure_frontend_delivery!("normal"), do: :ok

  defp configure_frontend_delivery!("fallback") do
    Application.put_env(:jido_code, :frontend_assets_override, %{
      mode: :fallback,
      reason: :asset_manifest_unavailable
    })
  end

  defp configure_conversation_delivery!("conversation_ready"), do: :ok
  defp configure_conversation_delivery!("conversation_runtime_blocked"), do: :ok

  defp configure_conversation_delivery!("conversation_degraded") do
    Application.put_env(
      :jido_code,
      :conversation_pubsub_subscriber,
      JidoCodeWeb.FailingConversationSubscriber
    )
  end

  defp configure_project_importer! do
    Application.put_env(:jido_code, :setup_project_importer, &browser_project_importer/1)
  end

  defp seed_owner! do
    strategy = Info.strategy!(User, :password)

    case Strategy.action(
           strategy,
           :register,
           %{
             "email" => @owner_email,
             "password" => @owner_password,
             "password_confirmation" => @owner_password
           },
           context: %{token_type: :sign_in}
         ) do
      {:ok, _owner} ->
        :ok

      {:error, reason} ->
        if owner_already_registered?(reason) do
          :ok
        else
          raise "browser scenario owner seed failed: #{inspect(reason)}"
        end
    end
  end

  defp seed_setup_system_config! do
    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{
        "1" => %{"validated_note" => "System prerequisites verified (browser harness)."},
        "2" => %{
          "owner_email" => @owner_email,
          "owner_mode" => "created",
          "registration_actions_disabled" => true,
          "validated_note" => "Owner account bootstrapped."
        },
        "4" => %{
          "github_credentials" => %{
            "status" => "ready",
            "paths" => [
              %{
                "path" => "github_app",
                "status" => "ready",
                "repository_access" => "confirmed",
                "repositories" => [
                  %{"id" => "repo_100", "full_name" => "owner/repo-one"},
                  %{"id" => "repo_200", "full_name" => "owner/repo-two"},
                  %{"id" => "repo_300", "full_name" => "agentjido/repo-three"}
                ]
              }
            ]
          }
        }
      },
      default_environment: :sprite,
      workspace_root: nil
    })
  end

  defp seed_conversation_system_config! do
    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: true,
      onboarding_step: 7,
      onboarding_state: %{},
      default_environment: :sprite,
      workspace_root: nil
    })
  end

  defp seed_conversation_project!("conversation_ready") do
    workspace_path = create_browser_workspace!("conversation-ready")

    upsert_conversation_project!(%{
      name: "browser-conversation-ready",
      github_full_name: "owner/browser-conversation-ready",
      default_branch: "main",
      settings: %{
        "workspace" => ready_workspace_settings(workspace_path),
        "execution" => %{
          "llm" => %{"provider" => "openai", "model" => "gpt-5-mini"}
        }
      }
    })
  end

  defp seed_conversation_project!("conversation_runtime_blocked") do
    upsert_conversation_project!(%{
      name: "browser-conversation-blocked",
      github_full_name: "owner/browser-conversation-blocked",
      default_branch: "main",
      settings: %{
        "workspace" => %{
          "clone_status" => "ready",
          "workspace_initialized" => true,
          "baseline_synced" => true
        },
        "execution" => %{
          "llm" => %{"provider" => "openai", "model" => "gpt-5-mini"}
        }
      }
    })
  end

  defp seed_conversation_project!("conversation_degraded") do
    workspace_path = create_browser_workspace!("conversation-degraded")

    upsert_conversation_project!(%{
      name: "browser-conversation-degraded",
      github_full_name: "owner/browser-conversation-degraded",
      default_branch: "main",
      settings: %{
        "workspace" => ready_workspace_settings(workspace_path),
        "execution" => %{
          "llm" => %{"provider" => "openai", "model" => "gpt-5-mini"}
        }
      }
    })
  end

  defp browser_project_importer(%{selected_repository: selected_repository})
       when is_binary(selected_repository) do
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
  end

  defp ready_workspace_settings(workspace_path) when is_binary(workspace_path) do
    %{
      "workspace_path" => workspace_path,
      "clone_status" => "ready",
      "workspace_initialized" => true,
      "baseline_synced" => true
    }
  end

  defp create_browser_workspace!(slug) when is_binary(slug) do
    workspace_path =
      Path.join(System.tmp_dir!(), "jido-code-browser-#{slug}")
      |> Path.expand()

    File.rm_rf!(workspace_path)
    File.mkdir_p!(workspace_path)

    File.write!(
      Path.join(workspace_path, "README.md"),
      """
      # Browser scenario workspace

      Scenario: #{slug}
      """
    )

    workspace_path
  end

  defp upsert_conversation_project!(attrs) when is_map(attrs) do
    actor = Actor.operator_actor()
    github_full_name = Map.fetch!(attrs, :github_full_name)

    case Project.get_by_github_full_name(github_full_name, actor: actor) do
      {:ok, project} ->
        {:ok, _project} = Project.update(project, attrs, actor: actor)

      {:error, reason} ->
        if project_not_found?(reason) do
          {:ok, _project} = Project.create(attrs, actor: actor)
        else
          raise "browser scenario project upsert failed: #{inspect(reason)}"
        end
    end
  end

  defp project_not_found?(%Ash.Error.Query.NotFound{}), do: true

  defp project_not_found?(%Ash.Error.Invalid{errors: errors}) when is_list(errors) do
    Enum.any?(errors, &project_not_found?/1)
  end

  defp project_not_found?(%{errors: errors}) when is_list(errors) do
    Enum.any?(errors, &project_not_found?/1)
  end

  defp project_not_found?(_reason), do: false

  defp owner_already_registered?(%Ash.Error.Changes.InvalidAttribute{
         field: :email,
         message: message
       })
       when is_binary(message) do
    String.contains?(message, "already been taken")
  end

  defp owner_already_registered?(%Ash.Error.Invalid{errors: errors}) when is_list(errors) do
    Enum.any?(errors, &owner_already_registered?/1)
  end

  defp owner_already_registered?(%{errors: errors}) when is_list(errors) do
    Enum.any?(errors, &owner_already_registered?/1)
  end

  defp owner_already_registered?(_reason), do: false
end
