# ADR-0003: Handler Security Infrastructure

## Status

Proposed

## Date

2026-01-01

## Context

ADR-0002 established that Phase 5 tools use the Handler pattern (direct Elixir execution via
`Tools.Executor`) instead of the Lua sandbox. While this provides an honest security model where
controls are explicit in Handler code, it creates a gap: each Handler must independently implement
security measures like input validation, output sanitization, and rate limiting.

### Current State

- Handlers implement security ad-hoc (allowlists, blocklists, path validation)
- No centralized enforcement of security policies
- No rate limiting to prevent abuse
- No automatic output sanitization for sensitive data
- No audit trail of tool invocations
- No permission tiers for graduated access control
- No process isolation for potentially dangerous operations

### Problems

1. **Inconsistent Security**: Each Handler author must remember to implement security checks.
   Missing a check creates a vulnerability.

2. **No Defense in Depth**: If a Handler's validation is bypassed, there's no fallback protection.

3. **Sensitive Data Leakage**: Tool outputs may contain passwords, API keys, or tokens that get
   returned to the LLM and potentially logged.

4. **Abuse Potential**: Without rate limiting, a compromised or malicious LLM session could
   rapidly invoke tools to exfiltrate data or cause denial of service.

5. **No Audit Trail**: Tool invocations aren't logged, making incident investigation difficult.

6. **All-or-Nothing Access**: Tools are either available or not; no graduated permission model.

## Decision

Implement a centralized, opt-in security infrastructure for Handler-based tools. This consists
of seven components that integrate with the existing Executor without requiring changes to
existing handlers.

### Components

#### 1. SecureHandler Behavior

A behavior that handlers can optionally implement to declare security properties:

```elixir
defmodule JidoCode.Tools.Behaviours.SecureHandler do
  @type security_properties :: %{
    required(:tier) => :read_only | :write | :execute | :privileged,
    optional(:rate_limit) => {count :: pos_integer(), window_ms :: pos_integer()},
    optional(:timeout_ms) => pos_integer(),
    optional(:requires_consent) => boolean()
  }

  @callback security_properties() :: security_properties()
  @callback validate_security(args :: map(), context :: map()) :: :ok | {:error, term()}
  @callback sanitize_output(result :: term()) :: term()
end
```

Handlers that don't implement this behavior use default security settings.

#### 2. Security Middleware

Pre-execution checks run before every Handler invocation:

```elixir
def run_checks(tool, args, context) do
  with :ok <- check_rate_limit(tool, context),
       :ok <- check_permission_tier(tool, context),
       :ok <- check_consent_requirement(tool, context) do
    :ok
  end
end
```

Enabled via config: `config :jido_code, security_middleware: true`

#### 3. Process Isolation

Execute handlers in isolated processes with resource limits:

- Spawned via `Task.Supervisor` for crash isolation
- Memory limit via `:max_heap_size` process flag
- Timeout enforcement with graceful shutdown
- Crash doesn't affect main application

#### 4. Output Sanitization

Automatic redaction of sensitive patterns in tool outputs:

```elixir
@sensitive_patterns [
  {~r/(?i)(password|secret|api_?key|token)\s*[:=]\s*\S+/, "[REDACTED]"},
  {~r/(?i)bearer\s+[a-zA-Z0-9._-]+/, "[REDACTED_BEARER]"},
  {~r/sk-[a-zA-Z0-9]{48,}/, "[REDACTED_API_KEY]"},
  {~r/ghp_[a-zA-Z0-9]{36,}/, "[REDACTED_GITHUB_TOKEN]"}
]
```

Applied recursively to strings and maps.

#### 5. Rate Limiting

Per-session, per-tool rate limiting using sliding window:

```elixir
@default_limits %{
  read_only: {100, :timer.minutes(1)},
  write: {30, :timer.minutes(1)},
  execute: {10, :timer.minutes(1)},
  privileged: {5, :timer.minutes(1)}
}
```

Backed by ETS for performance with periodic cleanup.

#### 6. Audit Logging

Comprehensive invocation logging:

- Timestamp, session ID, tool name, status, duration
- Arguments hashed for privacy (not logged raw)
- Stored in ETS ring buffer (10,000 entries default)
- Session-specific audit trail retrieval
- Blocked invocations logged via Logger

#### 7. Permission Tiers

Graduated access control:

| Tier | Description | Example Tools |
|------|-------------|---------------|
| `:read_only` | Read-only operations | read_file, grep, find_files |
| `:write` | Modify files/state | write_file, edit_file |
| `:execute` | Run external commands | run_command, mix_task |
| `:privileged` | System-level access | get_process_state, ets_inspect |

Sessions start with `:read_only` tier; higher tiers require explicit grant.

### Integration Point

The Executor is modified to optionally run middleware:

```elixir
def execute(tool, args, context) do
  if security_middleware_enabled?() do
    with :ok <- Middleware.run_checks(tool, args, context) do
      execute_with_isolation(tool, args, context)
    end
  else
    execute_handler(tool, args, context)
  end
end
```

## Consequences

### Positive

- **Centralized Security**: One place to enforce and audit security policies
- **Defense in Depth**: Multiple layers of protection (middleware, isolation, sanitization)
- **Sensitive Data Protection**: Automatic redaction prevents accidental leakage
- **Abuse Prevention**: Rate limiting stops runaway tool invocations
- **Incident Response**: Audit log enables investigation
- **Graduated Access**: Permission tiers allow fine-grained control
- **Backward Compatible**: Opt-in design; existing handlers work unchanged
- **Observable**: All security events emit telemetry

### Negative

- **Complexity**: Seven new modules to maintain
- **Performance Overhead**: Middleware checks add latency (mitigated by ETS)
- **Configuration Burden**: Security policies require tuning
- **False Positives**: Output sanitization may redact non-sensitive data matching patterns

### Neutral

- **Opt-in Model**: Users must explicitly enable security features
- **Handler Migration**: Existing handlers can optionally adopt SecureHandler behavior

## Alternatives Considered

### Alternative 1: Mandatory Security for All Handlers

Force all handlers to implement SecureHandler behavior.

**Pros:**
- Guaranteed security coverage
- Consistent security model

**Cons:**
- Breaking change for existing handlers
- Overhead for simple, safe handlers
- Slows development velocity

**Why not chosen:** Opt-in approach allows incremental adoption without breaking changes.

### Alternative 2: External Security Proxy

Run tools through an external security service (separate process/container).

**Pros:**
- Strong isolation
- Language-agnostic

**Cons:**
- Significant latency
- Complex deployment
- Serialization overhead

**Why not chosen:** Overhead too high for interactive tool use. Process isolation provides
sufficient protection for our threat model.

### Alternative 3: Capability-Based Security

Pass explicit capability tokens to handlers.

**Pros:**
- Fine-grained access control
- Unforgeable capabilities

**Cons:**
- Complex API changes
- All handlers must be rewritten
- Capability management overhead

**Why not chosen:** Too invasive. Permission tiers provide graduated access without API changes.

## References

- [ADR-0001: Tool Security Architecture](./0001-tool-security-architecture.md) - Original Lua sandbox design
- [ADR-0002: Phase 5 Tool Security and Architecture Revision](./0002-phase5-tool-security-and-architecture.md) - Handler pattern decision
- [Phase 5 Planning](../planning/tooling/phase-05-tools.md) - Section 5.8 implementation details
