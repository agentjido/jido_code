# Collaboration Workflow

This subject defines the repository collaboration and local work-management contract.

```spec-meta
id: collaboration.workflow
kind: policy
status: active
summary: jido_code uses Beadwork for local durable agent state and GitHub issues plus pull requests for shared collaboration.
surface:
  - AGENTS.md
```

## Requirements

```spec-requirements
- id: collaboration.workflow.beadwork_enabled
  statement: The repository shall instruct agents to run bw prime before starting work and use Beadwork for durable local work state.
  priority: must
  stability: stable

- id: collaboration.workflow.github_prs
  statement: The repository shall prefer GitHub issues and pull requests for non-trivial collaboration and shall avoid landing changes directly on main.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: source_file
  target: AGENTS.md
  covers:
    - collaboration.workflow.beadwork_enabled
    - collaboration.workflow.github_prs
```
