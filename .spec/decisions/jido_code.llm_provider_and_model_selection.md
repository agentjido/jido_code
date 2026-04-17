---
id: jido_code.llm_provider_and_model_selection
status: accepted
date: 2026-04-17
affects:
  - package.jido_code
  - architecture.agent_os_integration
  - architecture.conversation_orchestration
related:
  - jido_code.jido_agent_os_integration
  - jido_code.work_item_scoped_conversations_as_canonical_productive_threads
---

<!-- covers: architecture.agent_os_integration.specialist_llm_selection_is_product_owned_and_concrete -->
<!-- covers: architecture.conversation_orchestration.repo_and_conversation_llm_selection_is_explicit -->
<!-- covers: architecture.conversation_orchestration.conversation_llm_selection_overrides_repo_default -->
<!-- covers: architecture.conversation_orchestration.selected_llm_provider_readiness_is_validated -->
<!-- covers: package.jido_code.spec_led_workspace -->

# LLM Provider And Model Selection

## Context

`jido_code` already routes productive coding work through a real LLM-backed
runtime, but the surrounding product contract is still too narrow. Current
runtime and setup surfaces assume a small fixed provider list and the AgentOS
specialist examples still encode abstract model-tier atoms.

That shape is not durable enough for the product we want. The runtime boundary
already depends on `jido_ai`, which in turn builds on `req_llm`. The operator
goal is to choose concrete providers and models per repository and, when
needed, per productive conversation without turning specialist identity into a
proxy for provider choice.

## Decision

`jido_code` shall treat LLM provider and model selection as a product-owned
runtime boundary above `jido_ai` and the `req_llm` provider catalog.

The product target is to allow selection of any provider exposed through
`req_llm` that the adopted `jido_ai` execution path can actually run, with
support expressed as product catalog data and readiness policy rather than as
hardcoded provider enums in UI, readiness checks, or specialist modules.

Managed repositories shall carry a concrete default LLM selection in bounded
execution settings. That selection should include, at minimum, provider
identity, model identity, and any provider-specific connection or credential
metadata needed by the runtime.

Productive conversations may carry an explicit concrete LLM override in
conversation-owned metadata or an equivalent bounded runtime input. Resolution
precedence shall be:

1. conversation override
2. repository default
3. system default

Every level in that precedence chain shall resolve to a concrete provider and
model pair. Abstract model-tier atoms are not part of the product contract and
shall not remain as fallback selection modes.

Workflow and specialist routing remain deterministic and product-owned, but
that routing boundary is distinct from LLM selection. The product decides which
specialist handles the work. The LLM selection boundary decides which concrete
provider and model that specialist will use for the run.

Readiness and failure handling shall validate the selected provider and its
provider-specific runtime requirements instead of checking a fixed global
shortlist. Credential shape, transport configuration, or host requirements may
vary by provider and must therefore be evaluated against the concrete selection
that will execute the turn.

Concrete provider and model identity should also remain available to runtime
provenance, event metadata, and later governed or semantic capture paths so the
system can explain what actually executed.

## Consequences

- Specialist modules and AgentOS topology may remain role-oriented, but they no
  longer define stable model-tier behavior.
- Repo and conversation surfaces can expose bounded LLM selection without
  changing the canonical work-item, coordinator, or specialist-routing model.
- Provider readiness, credential storage, and settings UIs must become
  provider-aware and data-driven instead of special-casing a short list.
- Adding a new provider becomes a product adoption step through the catalog and
  readiness boundary rather than a rewrite of specialist contracts.
