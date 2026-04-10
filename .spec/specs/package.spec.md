# Package

High-level package contract for `jido_code`.

```spec-meta
id: package.jido_code
kind: package
status: active
summary: jido_code is the primary implementation repo, maintains a package-local Spec Led workspace for current-truth product, architecture, and migration subjects, keeps contributor-facing quality, browser-boundary, development-command, shared product-helper surfaces, AgentWorkspace specialist-runner support code, AgentOS kernel-snapshot persistence helpers, and eager collaboration-state action surfaces version-controlled, carries the repository-local ElixirOntologies plus TripleStore semantic-analysis dependency stack in the root Mix surface for the SourceCodeGraphPod capability, now includes the repo-owned SPARQL query, stale-state, recovery, semantic helper action surface, repository-scoped AgentWorkspace recovery and queue-limit behavior for that capability, adds the repository-local memory-graph and workflow-provenance graph architecture plus the enhanced coding-memory ontology as first-class spec-owned package concerns, now includes the concrete MemoryGraph boundary, pod contract, specialist agent scaffolding, and ontology artifact under version control, defines a bounded memory capture plane for inserting semantic memory and workflow-provenance individuals over time, preserves stable code-graph linkage for those semantic layers, keeps the product-owned semantic service, semantic operator-surface shaping, view-model, semantic workflow boundary, and governed semantic-finding adoption layer built on top of runtime semantic capability, keeps repo-owned AI demo and folio agent surfaces aligned to the current supported Jido.AI agent API, and keeps first-run bootstrap plus signed start surfaces version-controlled inside the product while global deployment mode stays auto-detected and repository source identity is provisioned directly through canonical source-repo and managed-repo records without requiring legacy project mirrors.
decisions:
  - jido_code.auth_user_system
  - jido_code.canonical_repo_surface
  - jido_code.live_vue_frontend_adoption
  - jido_code.internal_cleanup_and_ui_convergence_foundation
  - jido_code.jido_os_deprecation
  - jido_code.memory_capture_plane_and_insertion_seams
  - jido_code.memory_graph_and_coding_memory_ontology_adoption
  - jido_code.source_code_graph_pod_and_named_graph_ingestion
  - jido_code.source_code_graph_product_adoption
  - jido_code.runtime_evidence_posture_and_rollout_convergence
  - jido_code.operator_surface_managed_repo_and_governed_run_adoption
surface:
  - AGENTS.md
  - mix.exs
  - .spec/README.md
  - .spec/AGENTS.md
  - .spec/specs/*.spec.md
  - .spec/decisions/*.md
  - .spec/planning/*.md
  - .github/
  - compat/
  - config/
  - Dockerfile
  - fly.toml
  - deploy/
  - lib/
  - lib/jido_code/agent_workspace/
  - lib/jido_code/mix/frontend_start.ex
  - lib/jido_code_web/components/operator_state_components.ex
  - lib/mix/tasks/*.ex
  - priv/ontologies/
  - priv/repo/migrations/
  - test/
  - test/support/conn_case.ex
```

## Requirements

```spec-requirements
- id: package.jido_code.primary_implementation_repo
  statement: The jido_code repository shall serve as the primary product and implementation repo for active work in this workspace.
  priority: must
  stability: stable

- id: package.jido_code.spec_led_workspace
  statement: The repository shall maintain a package-local .spec workspace for current-truth subject specs, durable ADRs, implementation planning, and generated spec state.
  priority: must
  stability: stable

- id: package.jido_code.auth_provider_foundation_in_repo
  statement: Auth-provider foundation work shall be specified and implemented inside jido_code rather than split into a separate product repo.
  priority: should
  stability: evolving

- id: package.jido_code.version_controlled_quality_surfaces
  statement: Contributor-facing quality, development-command, CI, release, and spec-alignment surfaces shall live in version-controlled repo files instead of ad hoc local state.
  priority: must
  stability: evolving

- id: package.jido_code.version_controlled_deploy_surfaces
  statement: Deployment entry files shall remain version-controlled, keeping top-level tooling entry files such as Dockerfile and fly.toml at the repo root while moving auxiliary deploy helpers under deploy/.
  priority: should
  stability: evolving

- id: package.jido_code.mix_first_cli_surface
  statement: Repository-owned terminal entrypoints shall prefer direct Mix tasks over repo-root shell wrapper scripts.
  priority: should
  stability: evolving

- id: package.jido_code.bootstrap_and_start_surfaces_in_repo
  statement: First-run bootstrap, signed-in start surfaces, auto-detected deployment-mode hints, and per-project repository source identity shall be specified and implemented inside jido_code rather than split into external installers or repo-local-only conventions.
  priority: must
  stability: evolving

- id: package.jido_code.repo_owned_ai_agent_surfaces_track_supported_api
  statement: Repo-owned AI demo and folio agent surfaces shall stay version-controlled inside jido_code and track the current supported Jido.AI agent macro surface instead of depending on removed compatibility aliases.
  priority: should
  stability: evolving
```

## Verification

```spec-verification
- kind: source_file
  target: AGENTS.md
  covers:
    - package.jido_code.primary_implementation_repo

- kind: source_file
  target: .spec/README.md
  covers:
    - package.jido_code.spec_led_workspace

- kind: source_file
  target: .spec/planning/README.md
  covers:
    - package.jido_code.spec_led_workspace

- kind: source_file
  target: .spec/planning/phase-14-incremental-operator-surface-adoption.md
  covers:
    - package.jido_code.spec_led_workspace

- kind: source_file
  target: .spec/planning/phase-18-internal-domain-and-execution-canonicalization.md
  covers:
    - package.jido_code.spec_led_workspace

- kind: source_file
  target: .spec/planning/phase-20-source-code-graph-pod-foundation.md
  covers:
    - package.jido_code.spec_led_workspace

- kind: source_file
  target: .spec/planning/phase-21-full-ontology-analysis-and-named-graph-load.md
  covers:
    - package.jido_code.spec_led_workspace

- kind: source_file
  target: .spec/planning/phase-27-semantic-product-hardening-and-contributor-convergence.md
  covers:
    - package.jido_code.spec_led_workspace

- kind: source_file
  target: .spec/planning/phase-28-memory-graph-pod-and-store-foundation.md
  covers:
    - package.jido_code.spec_led_workspace

- kind: source_file
  target: .spec/specs/demand_ingress.spec.md
  covers:
    - package.jido_code.spec_led_workspace

- kind: source_file
  target: .spec/specs/event_assessment_synthesis.spec.md
  covers:
    - package.jido_code.spec_led_workspace

- kind: source_file
  target: .spec/specs/work_synthesis.spec.md
  covers:
    - package.jido_code.spec_led_workspace

- kind: source_file
  target: .spec/specs/run_governance.spec.md
  covers:
    - package.jido_code.spec_led_workspace

- kind: source_file
  target: .spec/specs/repo_posture.spec.md
  covers:
    - package.jido_code.spec_led_workspace

- kind: source_file
  target: test/jido_code/operations/phase_two_integration_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/operations/repo_native_state_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/governance/policy_bridge_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/governance/phase_five_integration_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: .spec/decisions/jido_code.operator_surface_managed_repo_and_governed_run_adoption.md
  covers:
    - package.jido_code.spec_led_workspace

- kind: source_file
  target: .spec/decisions/jido_code.jido_os_deprecation.md
  covers:
    - package.jido_code.spec_led_workspace

- kind: source_file
  target: .spec/decisions/jido_code.runtime_evidence_posture_and_rollout_convergence.md
  covers:
    - package.jido_code.spec_led_workspace

- kind: source_file
  target: test/jido_code/control/repo_bridge_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code_web/live/dashboard_live_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code_web/live/security_settings_live_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code_web/live/project_inventory_live_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code_web/live/agents_live_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code_web/live/workflows_live_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/agent_os/phase_twenty_eight_integration_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/memory_graph_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/memory_graph_actions_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/memory_graph_workspace_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/agent_os/pods_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/agent_os/phase_twenty_one_integration_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/source_code_graph_product_service_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/source_code_graph_workflow_service_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/source_code_graph_governed_adoption_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/source_code_graph_materialization_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/phase_twenty_four_integration_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/phase_twenty_six_integration_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/phase_twenty_seven_integration_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code_web/live/phase_twenty_five_integration_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code_web/live/phase_twenty_seven_integration_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: lib/jido_code/governance/runtime_evidence_feed.ex
  covers:
    - package.jido_code.primary_implementation_repo

- kind: source_file
  target: lib/jido_code_web/live/dashboard_live.ex
  covers:
    - package.jido_code.primary_implementation_repo

- kind: source_file
  target: lib/jido_code_web/live/run_detail_live.ex
  covers:
    - package.jido_code.primary_implementation_repo

- kind: source_file
  target: lib/jido_code_web.ex
  covers:
    - package.jido_code.primary_implementation_repo

- kind: source_file
  target: lib/jido_code_web/components/live_vue_components.ex
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: mix.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces
    - package.jido_code.mix_first_cli_surface

- kind: source_file
  target: README.md
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: CONTRIBUTING.md
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: AGENTS.md
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: lib/jido_code_web/frontend_assets.ex
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/support/conn_case.ex
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/support/live_vue_case.ex
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/support/live_vue_boundary_live.ex
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/agent_workspace_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/agent_os_integration_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/agent_os/manager_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code_web/components/live_vue_components_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code_web/frontend_assets_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code_web/live/phase_fifteen_integration_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code_web/live/phase_thirteen_integration_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/governance/runtime_evidence_feed_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/governance/run_governance_bridge_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/governance/posture_bridge_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code_web/live/dashboard_live_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code_web/live/run_detail_live_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/agent_os/phase_twenty_integration_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/source_code_graph_actions_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: test/jido_code/source_code_graph_workspace_test.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: mix.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: priv/repo/migrations/20260409130000_add_agent_os_kernel_snapshots.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: command
  target: test -f Dockerfile -a -f fly.toml -a -f deploy/Procfile -a -f deploy/entrypoint.sh -a -f deploy/docker-compose.dev.yml
  covers:
    - package.jido_code.version_controlled_deploy_surfaces

- kind: command
  target: mix help command
  covers:
    - package.jido_code.mix_first_cli_surface

- kind: command
  target: test ! -e jido -a ! -e jidocode -a ! -e bin/jido -a ! -e bin/jidocode
  covers:
    - package.jido_code.mix_first_cli_surface

- kind: command
  target: test ! -e lib/mix/tasks/jido.ex -a ! -e lib/mix/tasks/jidocode.ex
  covers:
    - package.jido_code.mix_first_cli_surface

- kind: source_file
  target: .spec/specs/provider_auth_foundation.spec.md
  covers:
    - package.jido_code.auth_provider_foundation_in_repo

- kind: source_file
  target: .spec/specs/provider_identity_linking.spec.md
  covers:
    - package.jido_code.auth_provider_foundation_in_repo

- kind: source_file
  target: .spec/specs/provider_login_policy.spec.md
  covers:
    - package.jido_code.auth_provider_foundation_in_repo

- kind: source_file
  target: .spec/specs/github_service_credentials.spec.md
  covers:
    - package.jido_code.auth_provider_foundation_in_repo

- kind: source_file
  target: .spec/specs/provider_broker_handoff.spec.md
  covers:
    - package.jido_code.auth_provider_foundation_in_repo

- kind: source_file
  target: .spec/specs/provider_login_flow.spec.md
  covers:
    - package.jido_code.auth_provider_foundation_in_repo

- kind: source_file
  target: .spec/specs/source_provider_adapter.spec.md
  covers:
    - package.jido_code.auth_provider_foundation_in_repo

- kind: source_file
  target: .spec/specs/operator_auth_settings.spec.md
  covers:
    - package.jido_code.auth_provider_foundation_in_repo

- kind: source_file
  target: .spec/specs/self_hosted_provider_integration.spec.md
  covers:
    - package.jido_code.auth_provider_foundation_in_repo

- kind: source_file
  target: .spec/specs/operator_provider_auth_guide.spec.md
  covers:
    - package.jido_code.auth_provider_foundation_in_repo

- kind: source_file
  target: .spec/specs/setup_onboarding.spec.md
  covers:
    - package.jido_code.bootstrap_and_start_surfaces_in_repo

- kind: command
  target: "rg -n 'use Jido\\.AI\\.Agent|Jido\\.AI\\.Agent with' lib/jido_code/demos/chat_agent.ex lib/jido_code/folio/folio_agent.ex lib/jido_code_web/live/demos/chat_live.ex"
  covers:
    - package.jido_code.repo_owned_ai_agent_surfaces_track_supported_api
```
