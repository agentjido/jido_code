# Phase 7 - Product Surface Cutover And Ash/Postgres Removal

Back to plan: [README](./README.md)

**Description:** This phase cuts product callers over to TripleStore-backed services and removes Ash/Postgres from the runtime. Because the project is greenfield, this phase removes the old data plane instead of keeping compatibility shims.

- [x] 7 Phase - Product surface cutover and Ash/Postgres removal.

  Description: Finish the replacement by deleting direct Ash/Ecto dependencies from runtime paths, tests, config, and generated artifacts.

## 7.1 Section - Product Caller Cutover

**Description:** This section removes direct calls to Ash, Ash domains, Ash resources, and `JidoCode.Repo` from product code.

- [x] 7.1 Section - Product caller cutover.

  Description: Web, workflow, agent, setup, and runtime modules should call product services backed by the store behaviour.

  Phase 5.1 deletion target note: `Project` references left after managed-repo/source-repo cutover are concentrated in `lib/jido_code/projects*`, `lib/jido_code/orchestration/workflow_run.ex`, `test/support/conn_case.ex`, `test/support/browser_setup.ex`, and older LiveView/integration fixtures that still create WorkflowRun-era projects. Remove these alongside the product caller and fixture cutover once Phase 5.2, Phase 5.3, and Phase 6 replacement services are in place.

  - [x] 7.1.1 Task - Rewire web and LiveView surfaces.

    Description: Operator routes should read shaped projections from product services, not Ash query results.

    - [x] 7.1.1.1 Subtask - Rewire dashboard, managed repo detail, workbench, settings, setup, run detail, and conversation surfaces.
    - [x] 7.1.1.2 Subtask - Replace form changeset assumptions with product validation result rendering.
    - [x] 7.1.1.3 Subtask - Preserve degraded and empty states when store graphs are not ready.

  - [x] 7.1.2 Task - Rewire workflow, agent, and service callers.

    Description: Background flows and agent workspace helpers should use the same product boundaries as UI callers.

    - [x] 7.1.2.1 Subtask - Rewire AgentWorkspace, workflow services, GitHub webhook pipeline, source watchers, memory adoption, and governed follow-up services.
    - [x] 7.1.2.2 Subtask - Replace Ash query filters with named product query helpers.
    - [x] 7.1.2.3 Subtask - Replace Ash changesets with command builders and validators.

## 7.2 Section - Dependency And Supervision Removal

**Description:** This section removes the old persistence stack from application configuration and runtime supervision.

- [x] 7.2 Section - Dependency and supervision removal.

  Description: Runtime should no longer compile or start Ash/Postgres components after product callers have moved.

  - [x] 7.2.1 Task - Remove Ash/Postgres dependencies and config.

    Description: Mix dependencies and application config should match the new embedded store architecture.

    - [x] 7.2.1.1 Subtask - Remove `ash`, Ash extensions, `phoenix_ecto`, `ecto_sql`, and `postgrex` dependencies when no longer referenced.
    - [x] 7.2.1.2 Subtask - Remove `ecto_repos`, Ash domain config, repo config, and AshAuthentication supervisor setup.
    - [x] 7.2.1.3 Subtask - Replace Phoenix repo status checks and Ecto sandbox test setup.

  - [x] 7.2.2 Task - Remove Ash resources, migrations, and snapshots.

    Description: Generated resource metadata should leave the repo once it is not runtime truth.

    - [x] 7.2.2.1 Subtask - Delete Ash resource modules replaced by product services.
    - [x] 7.2.2.2 Subtask - Delete obsolete migrations and resource snapshots.
    - [x] 7.2.2.3 Subtask - Remove Ash usage rules from local dependency guidance if the dependency is gone.

## 7.3 Section - Test And Fixture Cutover

**Description:** This section replaces database sandbox fixtures with embedded store fixtures.

- [x] 7.3 Section - Test and fixture cutover.

  Description: Tests should create records through product service helpers and isolated embedded store paths.

  - [x] 7.3.1 Task - Replace test data helpers.

    Description: DataCase and factory helpers should no longer start Ecto sandbox owners.

    - [x] 7.3.1.1 Subtask - Replace `JidoCode.DataCase` sandbox setup with store fixture setup.
    - [x] 7.3.1.2 Subtask - Add helper functions for managed repo, work item, run, user, conversation, and execution runtime fixtures.
    - [x] 7.3.1.3 Subtask - Ensure async tests use unique store paths or fake store instances.

  - [x] 7.3.2 Task - Replace generated resource assertions.

    Description: Tests should assert product projections and graph facts, not Ash struct internals.

    - [x] 7.3.2.1 Subtask - Replace changeset assertions with validation result assertions.
    - [x] 7.3.2.2 Subtask - Replace preload assumptions with explicit product projection assertions.
    - [x] 7.3.2.3 Subtask - Add graph-level assertions only in store integration tests.

## 7.4 Section - Integration Tests

**Description:** This final section proves the application runs without Ash/Postgres installed or configured.

- [x] 7.4 Section - Integration tests.

  Description: The decisive acceptance test is a compile and runtime boot where no product path references Ash or Ecto.

  - [x] 7.4.1 Task - Add removal gate coverage.

    Description: Static and compile gates should fail if Ash/Postgres dependencies reappear.

    - [x] 7.4.1.1 Subtask - Add a check that rejects `use Ash.Resource`, `use Ash.Domain`, `JidoCode.Repo`, and `Ecto.Adapters.SQL.Sandbox` in runtime paths.
    - [x] 7.4.1.2 Subtask - Add a dependency check that rejects Ash/Postgres packages after removal.
    - [x] 7.4.1.3 Subtask - Add a config check that rejects `ecto_repos` and repo config.

  - [x] 7.4.2 Task - Add end-to-end smoke coverage.

    Description: Smoke tests should prove the product can bootstrap, sign in, import a repo, open work, and run a conversation using only embedded storage.

    - [x] 7.4.2.1 Subtask - Run setup bootstrap and sign-in through the web surface.
    - [x] 7.4.2.2 Subtask - Import or create a managed repo, synthesize work, launch a governed run, and record evidence.
    - [x] 7.4.2.3 Subtask - Open a work-item conversation and verify event replay after application restart.
