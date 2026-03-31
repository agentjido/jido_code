defmodule JidoCodeWeb.GitHubWebhookControllerTest do
  # covers: architecture.demand_ingress.trusted_ingress_uses_explicit_actor_classes
  use JidoCodeWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias JidoCode.GitHub.Repo, as: GitHubRepo
  alias JidoCode.GitHub.WebhookDelivery
  alias JidoCode.Orchestration.WorkflowRun
  alias JidoCode.Projects.Project

  require Logger

  @webhook_path "/api/github/webhooks"

  setup do
    original_log_level = Logger.level()
    Logger.configure(level: :info)

    original_secret = Application.get_env(:jido_code, :github_webhook_secret, :__missing__)

    original_dispatcher =
      Application.get_env(:jido_code, :github_webhook_verified_dispatcher, :__missing__)

    original_system_config = Application.get_env(:jido_code, :system_config, :__missing__)

    original_issue_triage_artifact_persister =
      Application.get_env(:jido_code, :issue_triage_artifact_persister, :__missing__)

    original_issue_triage_response_poster =
      Application.get_env(:jido_code, :issue_triage_response_poster, :__missing__)

    on_exit(fn ->
      Logger.configure(level: original_log_level)
      restore_env(:github_webhook_secret, original_secret)
      restore_env(:github_webhook_verified_dispatcher, original_dispatcher)
      restore_env(:system_config, original_system_config)
      restore_env(:issue_triage_artifact_persister, original_issue_triage_artifact_persister)
      restore_env(:issue_triage_response_poster, original_issue_triage_response_poster)
    end)

    :ok
  end

  test "accepts verified deliveries, persists delivery ID before dispatch, and forwards handoff",
       %{
         conn: conn
       } do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)
    repo = create_repo!()

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      persisted_delivery =
        WebhookDelivery.get_by_github_delivery_id(delivery.delivery_id, authorize?: false)

      send(test_pid, {:verified_delivery_handoff, delivery, persisted_delivery})
      :ok
    end)

    payload =
      Jason.encode!(%{
        "action" => "opened",
        "issue" => %{"number" => 42},
        "repository" => %{"full_name" => repo.full_name}
      })

    delivery_id = "delivery-#{System.unique_integer([:positive])}"
    event = "issues"

    log_output =
      capture_log([level: :info], fn ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-hub-signature-256", sign(payload, secret))
          |> put_req_header("x-github-delivery", delivery_id)
          |> put_req_header("x-github-event", event)
          |> post(@webhook_path, payload)
          |> json_response(202)

        assert response["status"] == "accepted"
      end)

    assert_receive {:verified_delivery_handoff, handoff, {:ok, %WebhookDelivery{} = persisted_delivery}}

    assert handoff.delivery_id == delivery_id
    assert handoff.event == event
    assert handoff.payload["action"] == "opened"
    assert handoff.payload["repository"]["full_name"] == repo.full_name
    assert handoff.raw_payload == payload
    assert persisted_delivery.github_delivery_id == delivery_id
    assert persisted_delivery.event_type == event
    assert persisted_delivery.repo_id == repo.id

    assert log_output =~ "security_audit=github_webhook_signature_verified"
    assert log_output =~ "delivery_id=#{delivery_id}"
    assert log_output =~ "event=#{event}"
  end

  test "acknowledges duplicate deliveries safely without duplicate dispatch", %{conn: conn} do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)
    repo = create_repo!()

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(test_pid, {:verified_delivery_handoff, delivery.delivery_id})
      :ok
    end)

    payload =
      Jason.encode!(%{
        "action" => "opened",
        "issue" => %{"number" => 44},
        "repository" => %{"full_name" => repo.full_name}
      })

    delivery_id = "delivery-#{System.unique_integer([:positive])}"
    event = "issues"

    first_response =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-hub-signature-256", sign(payload, secret))
      |> put_req_header("x-github-delivery", delivery_id)
      |> put_req_header("x-github-event", event)
      |> post(@webhook_path, payload)
      |> json_response(202)

    assert first_response["status"] == "accepted"
    assert_receive {:verified_delivery_handoff, ^delivery_id}

    duplicate_log =
      capture_log([level: :info], fn ->
        second_response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-hub-signature-256", sign(payload, secret))
          |> put_req_header("x-github-delivery", delivery_id)
          |> put_req_header("x-github-event", event)
          |> post(@webhook_path, payload)
          |> json_response(202)

        assert second_response["status"] == "accepted"
      end)

    refute_receive {:verified_delivery_handoff, ^delivery_id}
    assert duplicate_log =~ "outcome=duplicate_acknowledged"

    assert {:ok, %WebhookDelivery{} = persisted_delivery} =
             WebhookDelivery.get_by_github_delivery_id(delivery_id, authorize?: false)

    assert persisted_delivery.repo_id == repo.id
    assert persisted_delivery.event_type == event
  end

  test "uses stored project Issue Bot webhook event list when evaluating deliveries", %{
    conn: conn
  } do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    unique_suffix = System.unique_integer([:positive])
    owner = "event-owner-#{unique_suffix}"
    name = "event-repo-#{unique_suffix}"
    repo_full_name = "#{owner}/#{name}"

    _repo = create_repo!(%{owner: owner, name: name})

    {:ok, _project} =
      Project.create(%{
        name: name,
        github_full_name: repo_full_name,
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{
              "enabled" => true,
              "webhook_events" => ["issues.edited"]
            }
          }
        }
      })

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(
        test_pid,
        {:verified_delivery_handoff, delivery.delivery_id, delivery.event, delivery.payload["action"]}
      )

      :ok
    end)

    blocked_payload =
      Jason.encode!(%{
        "action" => "opened",
        "issue" => %{"number" => 55},
        "repository" => %{"full_name" => repo_full_name}
      })

    blocked_delivery_id = "delivery-blocked-#{System.unique_integer([:positive])}"

    blocked_log =
      capture_log([level: :info], fn ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-hub-signature-256", sign(blocked_payload, secret))
          |> put_req_header("x-github-delivery", blocked_delivery_id)
          |> put_req_header("x-github-event", "issues")
          |> post(@webhook_path, blocked_payload)
          |> json_response(202)

        assert response["status"] == "accepted"
      end)

    refute_receive {:verified_delivery_handoff, ^blocked_delivery_id, _, _}
    assert blocked_log =~ "github_webhook_trigger_filtered"

    assert {:ok, %WebhookDelivery{} = blocked_delivery} =
             WebhookDelivery.get_by_github_delivery_id(blocked_delivery_id, authorize?: false)

    assert blocked_delivery.event_type == "issues"
    assert blocked_delivery.action == "opened"

    allowed_payload =
      Jason.encode!(%{
        "action" => "edited",
        "issue" => %{"number" => 56},
        "repository" => %{"full_name" => repo_full_name}
      })

    allowed_delivery_id = "delivery-allowed-#{System.unique_integer([:positive])}"

    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-hub-signature-256", sign(allowed_payload, secret))
      |> put_req_header("x-github-delivery", allowed_delivery_id)
      |> put_req_header("x-github-event", "issues")
      |> post(@webhook_path, allowed_payload)
      |> json_response(202)

    assert response["status"] == "accepted"

    assert_receive {:verified_delivery_handoff, ^allowed_delivery_id, "issues", "edited"}
  end

  test "creates tracked issue_triage runs with webhook context and issue identifiers for issues.opened",
       %{
         conn: conn
       } do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    unique_suffix = System.unique_integer([:positive])
    owner = "triage-owner-#{unique_suffix}"
    name = "triage-repo-#{unique_suffix}"
    repo_full_name = "#{owner}/#{name}"

    _repo = create_repo!(%{owner: owner, name: name})

    {:ok, %Project{} = project} =
      Project.create(%{
        name: name,
        github_full_name: repo_full_name,
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

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(
        test_pid,
        {:verified_delivery_handoff, delivery.delivery_id, delivery.event, delivery.payload["action"]}
      )

      :ok
    end)

    payload =
      Jason.encode!(%{
        "action" => "opened",
        "issue" => %{
          "id" => 90_001,
          "number" => 77,
          "node_id" => "I_kwDOABC1234",
          "url" => "https://api.github.com/repos/#{repo_full_name}/issues/77",
          "html_url" => "https://github.com/#{repo_full_name}/issues/77"
        },
        "repository" => %{"full_name" => repo_full_name}
      })

    delivery_id = "delivery-triage-#{System.unique_integer([:positive])}"

    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-hub-signature-256", sign(payload, secret))
      |> put_req_header("x-github-delivery", delivery_id)
      |> put_req_header("x-github-event", "issues")
      |> post(@webhook_path, payload)
      |> json_response(202)

    assert response["status"] == "accepted"
    assert_receive {:verified_delivery_handoff, ^delivery_id, "issues", "opened"}

    assert {:ok, [%WorkflowRun{} = run]} = workflow_runs_for_project(project.id)
    assert run.workflow_name == "issue_triage"
    assert map_get(run.initiating_actor, :actor_class, "actor_class") == "external_ingress"
    assert map_get(run.initiating_actor, :id, "id") == "system:github-webhook"

    source_row = map_get(run.trigger, :source_row, "source_row", %{})
    webhook_context = map_get(run.trigger, :webhook, "webhook", %{})
    source_issue = map_get(run.trigger, :source_issue, "source_issue", %{})

    assert map_get(run.trigger, :source, "source") == "github_webhook"
    assert map_get(run.trigger, :mode, "mode") == "webhook"
    assert map_get(source_row, :route, "route") == "/api/github/webhooks"
    assert map_get(source_row, :delivery_id, "delivery_id") == delivery_id
    assert map_get(webhook_context, :event, "event") == "issues"
    assert map_get(webhook_context, :action, "action") == "opened"
    assert map_get(source_issue, :number, "number") == 77
    assert map_get(source_issue, :id, "id") == 90_001
    assert map_get(run.inputs, :issue_reference, "issue_reference") == "#{repo_full_name}#77"
  end

  test "persists triage, research, and response draft artifacts linked to workflow run and source issue metadata",
       %{
         conn: conn
       } do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    unique_suffix = System.unique_integer([:positive])
    owner = "artifact-owner-#{unique_suffix}"
    name = "artifact-repo-#{unique_suffix}"
    repo_full_name = "#{owner}/#{name}"

    _repo = create_repo!(%{owner: owner, name: name})

    {:ok, %Project{} = project} =
      Project.create(%{
        name: name,
        github_full_name: repo_full_name,
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

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(test_pid, {:verified_delivery_handoff, delivery.delivery_id})
      :ok
    end)

    payload =
      Jason.encode!(%{
        "action" => "opened",
        "issue" => %{
          "id" => 90_101,
          "number" => 88,
          "title" => "Bug: state persistence fails on retry",
          "body" => "When retries run, the state update fails with an exception.",
          "url" => "https://api.github.com/repos/#{repo_full_name}/issues/88",
          "html_url" => "https://github.com/#{repo_full_name}/issues/88"
        },
        "repository" => %{"full_name" => repo_full_name}
      })

    delivery_id = "delivery-artifacts-#{System.unique_integer([:positive])}"

    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-hub-signature-256", sign(payload, secret))
      |> put_req_header("x-github-delivery", delivery_id)
      |> put_req_header("x-github-event", "issues")
      |> post(@webhook_path, payload)
      |> json_response(202)

    assert response["status"] == "accepted"
    assert_receive {:verified_delivery_handoff, ^delivery_id}

    assert {:ok, [%WorkflowRun{} = run]} = workflow_runs_for_project(project.id)
    assert run.workflow_name == "issue_triage"

    triage_artifact = map_get(run.step_results, :run_issue_triage, "run_issue_triage", %{})
    research_artifact = map_get(run.step_results, :run_issue_research, "run_issue_research", %{})

    response_artifact =
      map_get(run.step_results, :compose_issue_response, "compose_issue_response", %{})

    artifact_lineage =
      map_get(run.step_results, :issue_bot_artifact_lineage, "issue_bot_artifact_lineage", %{})

    triage_linked_run = map_get(triage_artifact, :linked_run, "linked_run", %{})
    linked_source_issue = map_get(triage_linked_run, :source_issue, "source_issue", %{})

    assert map_get(triage_artifact, :classification, "classification") == "bug"

    assert map_get(research_artifact, :summary, "summary") =~
             "Initial research for Bug: state persistence fails on retry focused on bug signals"

    assert map_get(response_artifact, :proposed_response, "proposed_response") =~
             "We triaged this as bug"

    assert map_get(artifact_lineage, :status, "status") == "persisted"

    assert Enum.sort(map_get(artifact_lineage, :artifact_keys, "artifact_keys", [])) == [
             "compose_issue_response",
             "run_issue_research",
             "run_issue_triage"
           ]

    assert map_get(triage_linked_run, :run_id, "run_id") == run.run_id
    assert map_get(triage_linked_run, :issue_reference, "issue_reference") == "#{repo_full_name}#88"
    assert map_get(linked_source_issue, :number, "number") == 88
    assert map_get(linked_source_issue, :id, "id") == 90_101
  end

  test "marks run failed with typed persistence error and preserves partial issue triage artifacts when artifact persistence fails",
       %{
         conn: conn
       } do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    unique_suffix = System.unique_integer([:positive])
    owner = "artifact-failure-owner-#{unique_suffix}"
    name = "artifact-failure-repo-#{unique_suffix}"
    repo_full_name = "#{owner}/#{name}"

    _repo = create_repo!(%{owner: owner, name: name})

    {:ok, %Project{} = project} =
      Project.create(%{
        name: name,
        github_full_name: repo_full_name,
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

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(test_pid, {:verified_delivery_handoff, delivery.delivery_id})
      :ok
    end)

    Application.put_env(:jido_code, :issue_triage_artifact_persister, fn _context ->
      {:error,
       %{
         reason_type: "artifact_store_unavailable",
         detail: "Issue triage artifact store is unavailable for this webhook delivery.",
         remediation: "Restore artifact storage health and retry issue triage."
       }}
    end)

    payload =
      Jason.encode!(%{
        "action" => "opened",
        "issue" => %{
          "id" => 90_201,
          "number" => 89,
          "title" => "Bug: webhook triage artifact persistence fails",
          "body" => "Persistence errors prevent issue artifacts from being stored.",
          "url" => "https://api.github.com/repos/#{repo_full_name}/issues/89",
          "html_url" => "https://github.com/#{repo_full_name}/issues/89"
        },
        "repository" => %{"full_name" => repo_full_name}
      })

    delivery_id = "delivery-artifacts-failed-#{System.unique_integer([:positive])}"

    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-hub-signature-256", sign(payload, secret))
      |> put_req_header("x-github-delivery", delivery_id)
      |> put_req_header("x-github-event", "issues")
      |> post(@webhook_path, payload)
      |> json_response(202)

    assert response["status"] == "accepted"
    assert_receive {:verified_delivery_handoff, ^delivery_id}

    assert {:ok, [%WorkflowRun{} = run]} = workflow_runs_for_project(project.id)
    assert run.workflow_name == "issue_triage"
    assert run.status == :failed
    assert run.current_step == "persist_issue_triage_artifacts"
    assert get_in(run.error, ["error_type"]) == "issue_triage_artifact_persistence_failed"
    assert get_in(run.error, ["reason_type"]) == "artifact_store_unavailable"
    assert get_in(run.error, ["failed_step"]) == "persist_issue_triage_artifacts"
    assert get_in(run.error, ["last_successful_step"]) == "run_issue_triage"

    triage_artifact = map_get(run.step_results, :run_issue_triage, "run_issue_triage", %{})
    research_artifact = map_get(run.step_results, :run_issue_research, "run_issue_research")
    response_artifact = map_get(run.step_results, :compose_issue_response, "compose_issue_response")

    artifact_lineage =
      map_get(run.step_results, :issue_bot_artifact_lineage, "issue_bot_artifact_lineage", %{})

    typed_failure = map_get(artifact_lineage, :typed_failure, "typed_failure", %{})

    assert map_get(triage_artifact, :classification, "classification") == "bug"
    assert is_nil(research_artifact)
    assert is_nil(response_artifact)
    assert map_get(artifact_lineage, :status, "status") == "partial_persistence_failed"

    assert map_get(typed_failure, :error_type, "error_type") ==
             "issue_triage_artifact_persistence_failed"
  end

  test "creates retriage runs for issues.edited with prior issue analysis artifact linkage", %{
    conn: conn
  } do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    unique_suffix = System.unique_integer([:positive])
    owner = "retriage-owner-#{unique_suffix}"
    name = "retriage-repo-#{unique_suffix}"
    repo_full_name = "#{owner}/#{name}"
    issue_reference = "#{repo_full_name}#78"

    _repo = create_repo!(%{owner: owner, name: name})

    {:ok, %Project{} = project} =
      Project.create(%{
        name: name,
        github_full_name: repo_full_name,
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{
              "enabled" => true,
              "webhook_events" => ["issues.opened", "issues.edited"]
            }
          }
        }
      })

    {:ok, %WorkflowRun{} = prior_run} =
      WorkflowRun.create(
        %{
          run_id: "run-prior-#{System.unique_integer([:positive])}",
          project_id: project.id,
          workflow_name: "issue_triage",
          workflow_version: 1,
          trigger: %{
            "source" => "github_webhook",
            "mode" => "webhook",
            "source_row" => %{
              "route" => "/api/github/webhooks",
              "delivery_id" => "delivery-prior-#{System.unique_integer([:positive])}",
              "event" => "issues",
              "action" => "opened"
            },
            "source_issue" => %{
              "id" => 90_003,
              "number" => 78
            }
          },
          inputs: %{"issue_reference" => issue_reference},
          input_metadata: %{
            "issue_reference" => %{"required" => true, "source" => "github_webhook"}
          },
          initiating_actor: %{"id" => "github_webhook", "email" => nil},
          current_step: "run_issue_research",
          step_results: %{
            "run_issue_triage" => %{"classification" => "bug"},
            "run_issue_research" => %{"summary" => "Prior issue analysis artifact"}
          },
          started_at: ~U[2026-02-14 20:00:00Z]
        },
        authorize?: false
      )

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(
        test_pid,
        {:verified_delivery_handoff, delivery.delivery_id, delivery.event, delivery.payload["action"]}
      )

      :ok
    end)

    payload =
      Jason.encode!(%{
        "action" => "edited",
        "issue" => %{
          "id" => 90_003,
          "number" => 78,
          "node_id" => "I_kwDOXYZ5678",
          "url" => "https://api.github.com/repos/#{repo_full_name}/issues/78",
          "html_url" => "https://github.com/#{repo_full_name}/issues/78"
        },
        "repository" => %{"full_name" => repo_full_name}
      })

    delivery_id = "delivery-retriage-#{System.unique_integer([:positive])}"

    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-hub-signature-256", sign(payload, secret))
      |> put_req_header("x-github-delivery", delivery_id)
      |> put_req_header("x-github-event", "issues")
      |> post(@webhook_path, payload)
      |> json_response(202)

    assert response["status"] == "accepted"
    assert_receive {:verified_delivery_handoff, ^delivery_id, "issues", "edited"}

    assert {:ok, [_prior_run, %WorkflowRun{} = retriage_run]} =
             workflow_runs_for_project(project.id)

    assert retriage_run.workflow_name == "issue_triage"

    policy = map_get(retriage_run.trigger, :policy, "policy", %{})
    retriage = map_get(retriage_run.trigger, :retriage, "retriage", %{})
    comparison_context = map_get(retriage, :comparison_context, "comparison_context", %{})

    prior_artifacts =
      map_get(
        comparison_context,
        :prior_issue_analysis_artifacts,
        "prior_issue_analysis_artifacts",
        []
      )

    assert map_get(policy, :name, "name") == "issue_triage_webhook_retriage"
    assert map_get(retriage, :event, "event") == "issues.edited"
    assert map_get(comparison_context, :issue_reference, "issue_reference") == issue_reference

    assert map_get(
             comparison_context,
             :prior_issue_analysis_artifact_count,
             "prior_issue_analysis_artifact_count"
           ) ==
             1

    assert [%{} = prior_artifact] = prior_artifacts
    assert map_get(prior_artifact, :run_id, "run_id") == prior_run.run_id
    assert map_get(prior_artifact, :issue_reference, "issue_reference") == issue_reference

    assert Enum.sort(map_get(prior_artifact, :artifact_keys, "artifact_keys", [])) == [
             "run_issue_research",
             "run_issue_triage"
           ]
  end

  test "creates follow-up issue_triage runs for issue_comment.created with approval policy context",
       %{conn: conn} do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    unique_suffix = System.unique_integer([:positive])
    owner = "follow-up-owner-#{unique_suffix}"
    name = "follow-up-repo-#{unique_suffix}"
    repo_full_name = "#{owner}/#{name}"

    _repo = create_repo!(%{owner: owner, name: name})

    {:ok, %Project{} = project} =
      Project.create(%{
        name: name,
        github_full_name: repo_full_name,
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{
              "enabled" => true,
              "webhook_events" => ["issue_comment.created"],
              "approval_mode" => "auto_post"
            }
          }
        }
      })

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(
        test_pid,
        {:verified_delivery_handoff, delivery.delivery_id, delivery.event, delivery.payload["action"]}
      )

      :ok
    end)

    payload =
      Jason.encode!(%{
        "action" => "created",
        "issue" => %{
          "id" => 90_005,
          "number" => 80,
          "node_id" => "I_kwDOABC5678",
          "url" => "https://api.github.com/repos/#{repo_full_name}/issues/80",
          "html_url" => "https://github.com/#{repo_full_name}/issues/80"
        },
        "comment" => %{
          "id" => 92_001,
          "node_id" => "IC_kwDOABC5678",
          "body" => "/jido follow-up please investigate regression behavior",
          "html_url" => "https://github.com/#{repo_full_name}/issues/80#issuecomment-92001",
          "author_association" => "MEMBER",
          "user" => %{"login" => "maintainer-user"}
        },
        "repository" => %{"full_name" => repo_full_name}
      })

    delivery_id = "delivery-follow-up-#{System.unique_integer([:positive])}"

    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-hub-signature-256", sign(payload, secret))
      |> put_req_header("x-github-delivery", delivery_id)
      |> put_req_header("x-github-event", "issue_comment")
      |> post(@webhook_path, payload)
      |> json_response(202)

    assert response["status"] == "accepted"
    assert_receive {:verified_delivery_handoff, ^delivery_id, "issue_comment", "created"}

    assert {:ok, [%WorkflowRun{} = follow_up_run]} = workflow_runs_for_project(project.id)
    assert follow_up_run.workflow_name == "issue_triage"

    source_row = map_get(follow_up_run.trigger, :source_row, "source_row", %{})
    webhook_context = map_get(follow_up_run.trigger, :webhook, "webhook", %{})
    policy = map_get(follow_up_run.trigger, :policy, "policy", %{})
    approval_policy = map_get(follow_up_run.trigger, :approval_policy, "approval_policy", %{})
    policy_approval_policy = map_get(policy, :approval_policy, "approval_policy", %{})
    follow_up = map_get(follow_up_run.trigger, :follow_up, "follow_up", %{})
    follow_up_comment = map_get(follow_up, :comment, "comment", %{})

    assert map_get(source_row, :route, "route") == "/api/github/webhooks"
    assert map_get(source_row, :delivery_id, "delivery_id") == delivery_id
    assert map_get(webhook_context, :event, "event") == "issue_comment"
    assert map_get(webhook_context, :action, "action") == "created"
    assert map_get(policy, :name, "name") == "issue_triage_webhook_follow_up"
    assert map_get(approval_policy, :mode, "mode") == "auto_post"
    assert map_get(approval_policy, :post_behavior, "post_behavior") == "auto_post"
    assert map_get(approval_policy, :auto_post, "auto_post") == true
    assert map_get(approval_policy, :requires_approval, "requires_approval") == false

    assert map_get(approval_policy, :source, "source") ==
             "support_agent_config.github_issue_bot.approval_mode"

    assert policy_approval_policy == approval_policy
    assert map_get(follow_up, :event, "event") == "issue_comment.created"
    assert map_get(follow_up_comment, :id, "id") == 92_001
    assert map_get(follow_up_comment, :author_login, "author_login") == "maintainer-user"
    assert map_get(follow_up_comment, :author_association, "author_association") == "MEMBER"
    assert map_get(follow_up_comment, :body, "body") =~ "follow-up"
    assert map_get(follow_up_comment, :html_url, "html_url") =~ "#issuecomment-92001"
    assert map_get(follow_up_run.inputs, :issue_reference, "issue_reference") == "#{repo_full_name}#80"
  end

  test "auto-post policy posts approved response and persists GitHub comment URL artifact", %{
    conn: conn
  } do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    unique_suffix = System.unique_integer([:positive])
    owner = "auto-post-owner-#{unique_suffix}"
    name = "auto-post-repo-#{unique_suffix}"
    repo_full_name = "#{owner}/#{name}"

    _repo = create_repo!(%{owner: owner, name: name})

    {:ok, %Project{} = project} =
      Project.create(%{
        name: name,
        github_full_name: repo_full_name,
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{
              "enabled" => true,
              "webhook_events" => ["issues.opened"],
              "approval_mode" => "auto_post"
            }
          }
        }
      })

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(test_pid, {:verified_delivery_handoff, delivery.delivery_id})
      :ok
    end)

    Application.put_env(:jido_code, :issue_triage_response_poster, fn post_request ->
      send(test_pid, {:issue_triage_post_request, post_request})

      {:ok,
       %{
         status: "posted",
         provider: "github",
         comment_url: "https://github.com/#{repo_full_name}/issues/96#issuecomment-96001",
         comment_api_url: "https://api.github.com/repos/#{repo_full_name}/issues/comments/96001",
         comment_id: 96_001,
         posted_at: "2026-02-15T09:00:00Z"
       }}
    end)

    payload =
      Jason.encode!(%{
        "action" => "opened",
        "issue" => %{
          "id" => 90_601,
          "number" => 96,
          "title" => "Bug: auto-post should persist comment URL",
          "body" => "Issue bot should post and persist URL.",
          "url" => "https://api.github.com/repos/#{repo_full_name}/issues/96",
          "html_url" => "https://github.com/#{repo_full_name}/issues/96"
        },
        "repository" => %{"full_name" => repo_full_name}
      })

    delivery_id = "delivery-auto-post-#{System.unique_integer([:positive])}"

    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-hub-signature-256", sign(payload, secret))
      |> put_req_header("x-github-delivery", delivery_id)
      |> put_req_header("x-github-event", "issues")
      |> post(@webhook_path, payload)
      |> json_response(202)

    assert response["status"] == "accepted"
    assert_receive {:verified_delivery_handoff, ^delivery_id}

    assert_receive {:issue_triage_post_request, post_request}
    assert map_get(post_request, :repo_full_name, "repo_full_name") == repo_full_name
    assert map_get(post_request, :issue_number, "issue_number") == 96
    assert map_get(post_request, :body, "body") =~ "We triaged this as"

    assert {:ok, [%WorkflowRun{} = run]} = workflow_runs_for_project(project.id)
    assert run.status == :completed
    assert run.current_step == "post_github_comment"

    post_artifact = map_get(run.step_results, :post_issue_response, "post_issue_response", %{})

    assert map_get(post_artifact, :status, "status") == "posted"
    assert map_get(post_artifact, :posted, "posted") == true

    assert map_get(post_artifact, :comment_url, "comment_url") ==
             "https://github.com/#{repo_full_name}/issues/96#issuecomment-96001"

    assert map_get(post_artifact, :comment_id, "comment_id") == 96_001
    assert map_get(post_artifact, :approval_mode, "approval_mode") == "auto_post"
    assert map_get(post_artifact, :approval_decision, "approval_decision") == "auto_approved"
  end

  test "auto-post failure captures typed auth error artifact and does not mark response posted", %{
    conn: conn
  } do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    unique_suffix = System.unique_integer([:positive])
    owner = "auto-post-failure-owner-#{unique_suffix}"
    name = "auto-post-failure-repo-#{unique_suffix}"
    repo_full_name = "#{owner}/#{name}"

    _repo = create_repo!(%{owner: owner, name: name})

    {:ok, %Project{} = project} =
      Project.create(%{
        name: name,
        github_full_name: repo_full_name,
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{
              "enabled" => true,
              "webhook_events" => ["issues.opened"],
              "approval_mode" => "auto_post"
            }
          }
        }
      })

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(test_pid, {:verified_delivery_handoff, delivery.delivery_id})
      :ok
    end)

    Application.put_env(:jido_code, :issue_triage_response_poster, fn _post_request ->
      {:error,
       %{
         error_type: "github_issue_comment_authentication_failed",
         reason_type: "authentication",
         detail: "Bad credentials for Issue Bot posting token.",
         remediation: "Rotate token and retry."
       }}
    end)

    payload =
      Jason.encode!(%{
        "action" => "opened",
        "issue" => %{
          "id" => 90_701,
          "number" => 97,
          "title" => "Bug: posting auth fails",
          "body" => "Issue bot posting should capture auth failure.",
          "url" => "https://api.github.com/repos/#{repo_full_name}/issues/97",
          "html_url" => "https://github.com/#{repo_full_name}/issues/97"
        },
        "repository" => %{"full_name" => repo_full_name}
      })

    delivery_id = "delivery-auto-post-failed-#{System.unique_integer([:positive])}"

    response =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-hub-signature-256", sign(payload, secret))
      |> put_req_header("x-github-delivery", delivery_id)
      |> put_req_header("x-github-event", "issues")
      |> post(@webhook_path, payload)
      |> json_response(202)

    assert response["status"] == "accepted"
    assert_receive {:verified_delivery_handoff, ^delivery_id}

    assert {:ok, [%WorkflowRun{} = run]} = workflow_runs_for_project(project.id)
    assert run.status == :failed
    assert run.current_step == "post_github_comment"
    assert get_in(run.error, ["error_type"]) == "github_issue_comment_authentication_failed"
    assert get_in(run.error, ["reason_type"]) == "auth_error"
    assert get_in(run.error, ["failed_step"]) == "post_github_comment"
    assert get_in(run.error, ["last_successful_step"]) == "compose_issue_response"

    post_artifact = map_get(run.step_results, :post_issue_response, "post_issue_response", %{})
    post_typed_failure = map_get(post_artifact, :typed_failure, "typed_failure", %{})

    assert map_get(post_artifact, :status, "status") == "failed"
    assert map_get(post_artifact, :posted, "posted") == false
    assert is_nil(map_get(post_artifact, :comment_url, "comment_url"))
    assert map_get(post_typed_failure, :reason_type, "reason_type") == "auth_error"
  end

  test "records issue_comment.created deliveries as no-op when project Issue Bot is disabled", %{
    conn: conn
  } do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    unique_suffix = System.unique_integer([:positive])
    owner = "comment-disabled-owner-#{unique_suffix}"
    name = "comment-disabled-repo-#{unique_suffix}"
    repo_full_name = "#{owner}/#{name}"

    _repo = create_repo!(%{owner: owner, name: name})

    {:ok, %Project{} = project} =
      Project.create(%{
        name: name,
        github_full_name: repo_full_name,
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{
              "enabled" => false,
              "webhook_events" => ["issue_comment.created"],
              "approval_mode" => "auto_post"
            }
          }
        }
      })

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(
        test_pid,
        {:verified_delivery_handoff, delivery.delivery_id, delivery.event, delivery.payload["action"]}
      )

      :ok
    end)

    payload =
      Jason.encode!(%{
        "action" => "created",
        "issue" => %{
          "id" => 90_006,
          "number" => 81,
          "url" => "https://api.github.com/repos/#{repo_full_name}/issues/81",
          "html_url" => "https://github.com/#{repo_full_name}/issues/81"
        },
        "comment" => %{
          "id" => 92_002,
          "body" => "/jido follow-up",
          "author_association" => "MEMBER"
        },
        "repository" => %{"full_name" => repo_full_name}
      })

    delivery_id = "delivery-comment-disabled-#{System.unique_integer([:positive])}"

    log_output =
      capture_log([level: :info], fn ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-hub-signature-256", sign(payload, secret))
          |> put_req_header("x-github-delivery", delivery_id)
          |> put_req_header("x-github-event", "issue_comment")
          |> post(@webhook_path, payload)
          |> json_response(202)

        assert response["status"] == "accepted"
      end)

    refute_receive {:verified_delivery_handoff, ^delivery_id, _, _}
    assert log_output =~ "github_webhook_trigger_filtered outcome=noop"
    assert log_output =~ "policy=support_agent_config.github_issue_bot.enabled"
    assert log_output =~ "event=issue_comment.created"
    assert {:ok, []} = workflow_runs_for_project(project.id)

    assert {:ok, %WebhookDelivery{} = persisted_delivery} =
             WebhookDelivery.get_by_github_delivery_id(delivery_id, authorize?: false)

    assert persisted_delivery.event_type == "issue_comment"
    assert persisted_delivery.action == "created"
  end

  test "records issue_comment.created deliveries as no-op when follow-up trigger is disabled",
       %{conn: conn} do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    unique_suffix = System.unique_integer([:positive])
    owner = "comment-filter-owner-#{unique_suffix}"
    name = "comment-filter-repo-#{unique_suffix}"
    repo_full_name = "#{owner}/#{name}"

    _repo = create_repo!(%{owner: owner, name: name})

    {:ok, %Project{} = project} =
      Project.create(%{
        name: name,
        github_full_name: repo_full_name,
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{
              "enabled" => true,
              "webhook_events" => ["issues.opened"],
              "approval_mode" => "approval_required"
            }
          }
        }
      })

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(
        test_pid,
        {:verified_delivery_handoff, delivery.delivery_id, delivery.event, delivery.payload["action"]}
      )

      :ok
    end)

    payload =
      Jason.encode!(%{
        "action" => "created",
        "issue" => %{
          "id" => 90_007,
          "number" => 82,
          "url" => "https://api.github.com/repos/#{repo_full_name}/issues/82",
          "html_url" => "https://github.com/#{repo_full_name}/issues/82"
        },
        "comment" => %{
          "id" => 92_003,
          "body" => "/jido follow-up on flaky behavior",
          "author_association" => "MEMBER"
        },
        "repository" => %{"full_name" => repo_full_name}
      })

    delivery_id = "delivery-comment-filtered-#{System.unique_integer([:positive])}"

    log_output =
      capture_log([level: :info], fn ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-hub-signature-256", sign(payload, secret))
          |> put_req_header("x-github-delivery", delivery_id)
          |> put_req_header("x-github-event", "issue_comment")
          |> post(@webhook_path, payload)
          |> json_response(202)

        assert response["status"] == "accepted"
      end)

    refute_receive {:verified_delivery_handoff, ^delivery_id, _, _}
    assert log_output =~ "github_webhook_trigger_filtered outcome=noop"
    assert log_output =~ "policy=support_agent_config.github_issue_bot.webhook_events"
    assert log_output =~ "event=issue_comment.created"
    assert {:ok, []} = workflow_runs_for_project(project.id)

    assert {:ok, %WebhookDelivery{} = persisted_delivery} =
             WebhookDelivery.get_by_github_delivery_id(delivery_id, authorize?: false)

    assert persisted_delivery.event_type == "issue_comment"
    assert persisted_delivery.action == "created"
  end

  test "records issues.edited deliveries as no-op when filtered by project Issue Bot webhook policy",
       %{conn: conn} do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    unique_suffix = System.unique_integer([:positive])
    owner = "edited-filter-owner-#{unique_suffix}"
    name = "edited-filter-repo-#{unique_suffix}"
    repo_full_name = "#{owner}/#{name}"

    _repo = create_repo!(%{owner: owner, name: name})

    {:ok, %Project{} = project} =
      Project.create(%{
        name: name,
        github_full_name: repo_full_name,
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

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(
        test_pid,
        {:verified_delivery_handoff, delivery.delivery_id, delivery.event, delivery.payload["action"]}
      )

      :ok
    end)

    payload =
      Jason.encode!(%{
        "action" => "edited",
        "issue" => %{
          "id" => 90_004,
          "number" => 79,
          "url" => "https://api.github.com/repos/#{repo_full_name}/issues/79",
          "html_url" => "https://github.com/#{repo_full_name}/issues/79"
        },
        "repository" => %{"full_name" => repo_full_name}
      })

    delivery_id = "delivery-edited-filtered-#{System.unique_integer([:positive])}"

    log_output =
      capture_log([level: :info], fn ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-hub-signature-256", sign(payload, secret))
          |> put_req_header("x-github-delivery", delivery_id)
          |> put_req_header("x-github-event", "issues")
          |> post(@webhook_path, payload)
          |> json_response(202)

        assert response["status"] == "accepted"
      end)

    refute_receive {:verified_delivery_handoff, ^delivery_id, _, _}
    assert log_output =~ "github_webhook_trigger_filtered outcome=noop"
    assert log_output =~ "policy=support_agent_config.github_issue_bot.webhook_events"
    assert log_output =~ "event=issues.edited"

    assert {:ok, []} = workflow_runs_for_project(project.id)

    assert {:ok, %WebhookDelivery{} = persisted_delivery} =
             WebhookDelivery.get_by_github_delivery_id(delivery_id, authorize?: false)

    assert persisted_delivery.event_type == "issues"
    assert persisted_delivery.action == "edited"
  end

  test "records issues.opened deliveries as no-op when project Issue Bot is disabled", %{
    conn: conn
  } do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    unique_suffix = System.unique_integer([:positive])
    owner = "disabled-owner-#{unique_suffix}"
    name = "disabled-repo-#{unique_suffix}"
    repo_full_name = "#{owner}/#{name}"

    _repo = create_repo!(%{owner: owner, name: name})

    {:ok, %Project{} = project} =
      Project.create(%{
        name: name,
        github_full_name: repo_full_name,
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{
              "enabled" => false,
              "webhook_events" => ["issues.opened"]
            }
          }
        }
      })

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(
        test_pid,
        {:verified_delivery_handoff, delivery.delivery_id, delivery.event, delivery.payload["action"]}
      )

      :ok
    end)

    payload =
      Jason.encode!(%{
        "action" => "opened",
        "issue" => %{
          "id" => 90_002,
          "number" => 78,
          "url" => "https://api.github.com/repos/#{repo_full_name}/issues/78",
          "html_url" => "https://github.com/#{repo_full_name}/issues/78"
        },
        "repository" => %{"full_name" => repo_full_name}
      })

    delivery_id = "delivery-disabled-#{System.unique_integer([:positive])}"

    log_output =
      capture_log([level: :info], fn ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-hub-signature-256", sign(payload, secret))
          |> put_req_header("x-github-delivery", delivery_id)
          |> put_req_header("x-github-event", "issues")
          |> post(@webhook_path, payload)
          |> json_response(202)

        assert response["status"] == "accepted"
      end)

    refute_receive {:verified_delivery_handoff, ^delivery_id, _, _}
    assert log_output =~ "github_webhook_trigger_filtered outcome=noop"
    assert log_output =~ "policy=support_agent_config.github_issue_bot.enabled"

    assert {:ok, []} = workflow_runs_for_project(project.id)

    assert {:ok, %WebhookDelivery{} = persisted_delivery} =
             WebhookDelivery.get_by_github_delivery_id(delivery_id, authorize?: false)

    assert persisted_delivery.event_type == "issues"
    assert persisted_delivery.action == "opened"
  end

  test "rejects delivery when signature verification fails and does not route side effects", %{
    conn: conn
  } do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(test_pid, {:verified_delivery_handoff, delivery})
      :ok
    end)

    payload = Jason.encode!(%{"action" => "opened", "issue" => %{"number" => 43}})
    delivery_id = "delivery-#{System.unique_integer([:positive])}"
    event = "issues"

    log_output =
      capture_log(fn ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-hub-signature-256", "sha256=deadbeef")
          |> put_req_header("x-github-delivery", delivery_id)
          |> put_req_header("x-github-event", event)
          |> post(@webhook_path, payload)
          |> json_response(401)

        assert response["error"] == "invalid_signature"
      end)

    refute_receive {:verified_delivery_handoff, _delivery}
    assert log_output =~ "security_audit=github_webhook_signature_rejected"
    assert log_output =~ "delivery_id=#{delivery_id}"
    assert log_output =~ "event=#{event}"
  end

  test "fails closed when delivery ID cannot be persisted and does not dispatch triggers", %{
    conn: conn
  } do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)
    repo = create_repo!()

    test_pid = self()

    Application.put_env(:jido_code, :github_webhook_verified_dispatcher, fn delivery ->
      send(test_pid, {:verified_delivery_handoff, delivery})
      :ok
    end)

    payload =
      Jason.encode!(%{
        "action" => "opened",
        "issue" => %{"number" => 45},
        "repository" => %{"full_name" => repo.full_name}
      })

    event = "issues"

    log_output =
      capture_log(fn ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-hub-signature-256", sign(payload, secret))
          |> put_req_header("x-github-event", event)
          |> post(@webhook_path, payload)
          |> json_response(500)

        assert response["error"] == "delivery_processing_failed"
      end)

    refute_receive {:verified_delivery_handoff, _delivery}
    assert log_output =~ "github_webhook_delivery_persist_failed"
    assert log_output =~ "missing_delivery_id"
    assert {:ok, []} = WebhookDelivery.list_for_repo(%{repo_id: repo.id}, authorize?: false)
  end

  test "processes installation repository events and syncs repository availability metadata", %{
    conn: conn
  } do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    _existing_repo =
      create_repo!(%{
        owner: "owner",
        name: "repo-one",
        github_app_installation_id: 123
      })

    _added_repo =
      create_repo!(%{
        owner: "owner",
        name: "repo-two"
      })

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 7,
      onboarding_state: %{
        "4" => %{
          "github_credentials" => %{
            "paths" => [
              %{
                "path" => "github_app",
                "status" => "ready",
                "repository_access" => "confirmed",
                "repositories" => ["owner/repo-one"]
              }
            ]
          }
        }
      }
    })

    payload =
      Jason.encode!(%{
        "action" => "added",
        "installation" => %{
          "id" => 123,
          "repository_selection" => "selected"
        },
        "repositories_added" => [
          %{"id" => 200, "full_name" => "owner/repo-two"}
        ],
        "repositories_removed" => []
      })

    delivery_id = "delivery-#{System.unique_integer([:positive])}"
    event = "installation_repositories"

    log_output =
      capture_log([level: :info], fn ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-hub-signature-256", sign(payload, secret))
          |> put_req_header("x-github-delivery", delivery_id)
          |> put_req_header("x-github-event", event)
          |> post(@webhook_path, payload)
          |> json_response(202)

        assert response["status"] == "accepted"
      end)

    persisted_config = Application.get_env(:jido_code, :system_config)
    onboarding_state = Map.fetch!(persisted_config, :onboarding_state)

    installation_sync =
      onboarding_state
      |> Map.fetch!("7")
      |> Map.fetch!("installation_sync")

    assert installation_sync["status"] == "ready"
    assert installation_sync["event"] == "installation_repositories"
    assert installation_sync["action"] == "added"
    assert installation_sync["installation_id"] == 123

    assert Enum.map(installation_sync["accessible_repositories"], & &1["full_name"]) == [
             "owner/repo-one",
             "owner/repo-two"
           ]

    github_app_path =
      onboarding_state
      |> Map.fetch!("4")
      |> Map.fetch!("github_credentials")
      |> Map.fetch!("paths")
      |> Enum.find(fn path -> path["path"] == "github_app" end)

    assert github_app_path["status"] == "ready"
    assert github_app_path["repository_access"] == "confirmed"

    assert Enum.map(github_app_path["repositories"], & &1["full_name"]) == [
             "owner/repo-one",
             "owner/repo-two"
           ]

    assert log_output =~ "github_installation_sync outcome=updated"
    assert log_output =~ "affected_repositories=owner/repo-one,owner/repo-two"
  end

  test "marks installation sync metadata as stale with retry guidance when installation payload is invalid",
       %{conn: conn} do
    secret = "webhook-secret-#{System.unique_integer([:positive])}"
    Application.put_env(:jido_code, :github_webhook_secret, secret)

    _repo =
      create_repo!(%{
        owner: "owner",
        name: "repo-one"
      })

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 7,
      onboarding_state: %{
        "4" => %{
          "github_credentials" => %{
            "paths" => [
              %{
                "path" => "github_app",
                "status" => "ready",
                "repository_access" => "confirmed",
                "repositories" => ["owner/repo-one"]
              }
            ]
          }
        }
      }
    })

    payload =
      Jason.encode!(%{
        "action" => "created",
        "repositories" => [%{"full_name" => "owner/repo-one"}]
      })

    delivery_id = "delivery-#{System.unique_integer([:positive])}"
    event = "installation"

    log_output =
      capture_log([level: :info], fn ->
        response =
          conn
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-hub-signature-256", sign(payload, secret))
          |> put_req_header("x-github-delivery", delivery_id)
          |> put_req_header("x-github-event", event)
          |> post(@webhook_path, payload)
          |> json_response(202)

        assert response["status"] == "accepted"
      end)

    persisted_config = Application.get_env(:jido_code, :system_config)
    onboarding_state = Map.fetch!(persisted_config, :onboarding_state)

    installation_sync =
      onboarding_state
      |> Map.fetch!("7")
      |> Map.fetch!("installation_sync")

    assert installation_sync["status"] == "stale"
    assert installation_sync["error_type"] == "github_installation_sync_stale"
    assert installation_sync["detail"] =~ "Repository availability may be stale"
    assert installation_sync["remediation"] =~ "Retry repository refresh in step 7"

    repository_listing =
      onboarding_state
      |> Map.fetch!("7")
      |> Map.fetch!("repository_listing")

    assert repository_listing["status"] == "blocked"
    assert repository_listing["error_type"] == "github_installation_sync_stale"
    assert repository_listing["detail"] =~ "Repository availability may be stale"
    assert repository_listing["remediation"] =~ "Retry repository refresh in step 7"

    assert log_output =~ "github_installation_sync outcome=stale"
    assert log_output =~ "affected_repositories=owner/repo-one"
  end

  defp create_repo! do
    unique_suffix = System.unique_integer([:positive])

    {:ok, %GitHubRepo{} = repo} =
      GitHubRepo.create(
        %{
          owner: "webhook-owner-#{unique_suffix}",
          name: "webhook-repo-#{unique_suffix}"
        },
        authorize?: false
      )

    repo
  end

  defp create_repo!(attributes) when is_map(attributes) do
    owner = Map.fetch!(attributes, :owner)
    name = Map.fetch!(attributes, :name)

    {:ok, %GitHubRepo{} = repo} =
      GitHubRepo.create(
        %{
          owner: owner,
          name: name,
          github_app_installation_id: Map.get(attributes, :github_app_installation_id)
        },
        authorize?: false
      )

    repo
  end

  defp sign(payload, secret) do
    digest =
      :crypto.mac(:hmac, :sha256, secret, payload)
      |> Base.encode16(case: :lower)

    "sha256=#{digest}"
  end

  defp workflow_runs_for_project(project_id) do
    WorkflowRun.read(
      query: [filter: [project_id: project_id], sort: [inserted_at: :asc]],
      authorize?: false
    )
  end

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)

  defp restore_env(key, value) do
    Application.put_env(:jido_code, key, value)
  end
end
