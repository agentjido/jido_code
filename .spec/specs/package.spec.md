# Package

High-level package contract for `jido_code`.

```spec-meta
id: package.jido_code
kind: package
status: active
summary: jido_code is the primary implementation repo, maintains a package-local Spec Led workspace, keeps contributor-facing quality surfaces version-controlled, and evolves auth-provider foundation, linking, login-policy, and GitHub service-credential work inside that repo.
decisions:
  - jido_code.auth_user_system
surface:
  - AGENTS.md
  - coveralls.json
  - mix.exs
  - .doctor.exs
  - .dialyzer_ignore.exs
  - .spec/README.md
  - .spec/specs/*.spec.md
  - .spec/decisions/*.md
  - .github/
  - config/
  - docs/
  - lib/
  - test/
```

## Requirements

```spec-requirements
- id: package.jido_code.primary_implementation_repo
  statement: The jido_code repository shall serve as the primary product and implementation repo for active work in this workspace.
  priority: must
  stability: stable

- id: package.jido_code.spec_led_workspace
  statement: The repository shall maintain a package-local .spec workspace for current-truth subject specs, durable ADRs, and generated spec state.
  priority: must
  stability: stable

- id: package.jido_code.auth_provider_foundation_in_repo
  statement: Auth-provider foundation work shall be specified and implemented inside jido_code rather than split into a separate product repo.
  priority: should
  stability: evolving

- id: package.jido_code.version_controlled_quality_surfaces
  statement: Contributor-facing quality, CI, release, and spec-alignment surfaces shall live in version-controlled repo files instead of ad hoc local state.
  priority: must
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
  target: mix.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: .doctor.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

- kind: source_file
  target: .dialyzer_ignore.exs
  covers:
    - package.jido_code.version_controlled_quality_surfaces

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
```
