# Source Provider Adapter

This subject defines the provider-neutral adapter boundary for deployment-local source control service integrations. It is part of the repo-local auth-provider and Git service foundation captured by `package.jido_code.auth_provider_foundation_in_repo`.

```spec-meta
id: source.provider_adapter
kind: feature
status: active
summary: jido_code routes GitHub service credential and repository-access checks through a provider-neutral adapter boundary and keeps explicit placeholder adapters for GitLab and Bitbucket.
surface:
  - lib/jido_code/source_providers.ex
  - lib/jido_code/source_providers/adapter.ex
  - lib/jido_code/source_providers/github_adapter.ex
  - lib/jido_code/source_providers/gitlab_adapter.ex
  - lib/jido_code/source_providers/bitbucket_adapter.ex
  - lib/jido_code/setup/github_credential_checks.ex
  - test/jido_code/source_providers/source_providers_test.exs
  - test/jido_code/source_providers/github_adapter_test.exs
```

## Requirements

```spec-requirements
- id: source.provider_adapter.provider_catalog
  statement: The source provider boundary shall enumerate GitHub, GitLab, and Bitbucket adapter modules through a shared provider catalog.
  priority: must
  stability: evolving

- id: source.provider_adapter.behavior_contract
  statement: Source provider adapters shall implement a shared behavior for configuration, service credential resolution, API token lookup, and repository listing.
  priority: must
  stability: evolving

- id: source.provider_adapter.github_adapter
  statement: GitHub service credential checks shall delegate provider-specific credential and repository-access logic through the GitHub adapter rather than reaching directly into GitHub modules.
  priority: must
  stability: evolving

- id: source.provider_adapter.github_app_preferred
  statement: The GitHub adapter shall preserve GitHub App preference ahead of PAT fallback in the setup-path model.
  priority: must
  stability: stable

- id: source.provider_adapter.placeholder_adapters
  statement: GitLab and Bitbucket shall have explicit placeholder adapters so unsupported provider integrations fail through named boundaries rather than implicit missing-module behavior.
  priority: should
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: source.provider_adapter.scenario.github_setup_checks
  covers:
    - source.provider_adapter.behavior_contract
    - source.provider_adapter.github_adapter
    - source.provider_adapter.github_app_preferred
  given:
    - Setup needs to validate deployment-local GitHub service credentials.
  when:
    - GitHub credential checks enumerate credential paths and request accessible repositories.
  then:
    - The checks call the GitHub adapter boundary and keep GitHub App ahead of PAT fallback.

- id: source.provider_adapter.scenario.placeholder_registry
  covers:
    - source.provider_adapter.provider_catalog
    - source.provider_adapter.placeholder_adapters
  given:
    - Future GitLab and Bitbucket integration is not implemented yet.
  when:
    - The source provider registry is queried.
  then:
    - The registry resolves named placeholder adapters for those providers.
```

## Verification

```spec-verification
- kind: source_file
  target: lib/jido_code/source_providers.ex
  covers:
    - source.provider_adapter.provider_catalog
    - source.provider_adapter.placeholder_adapters

- kind: source_file
  target: lib/jido_code/source_providers/adapter.ex
  covers:
    - source.provider_adapter.behavior_contract

- kind: source_file
  target: lib/jido_code/source_providers/github_adapter.ex
  covers:
    - source.provider_adapter.behavior_contract
    - source.provider_adapter.github_adapter
    - source.provider_adapter.github_app_preferred

- kind: source_file
  target: lib/jido_code/source_providers/gitlab_adapter.ex
  covers:
    - source.provider_adapter.placeholder_adapters

- kind: source_file
  target: lib/jido_code/source_providers/bitbucket_adapter.ex
  covers:
    - source.provider_adapter.placeholder_adapters

- kind: source_file
  target: lib/jido_code/setup/github_credential_checks.ex
  covers:
    - source.provider_adapter.github_adapter

- kind: source_file
  target: test/jido_code/source_providers/source_providers_test.exs
  covers:
    - source.provider_adapter.provider_catalog
    - source.provider_adapter.placeholder_adapters

- kind: source_file
  target: test/jido_code/source_providers/github_adapter_test.exs
  covers:
    - source.provider_adapter.behavior_contract
    - source.provider_adapter.github_adapter
    - source.provider_adapter.github_app_preferred
```
