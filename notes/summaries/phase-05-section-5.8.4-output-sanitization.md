# Summary: Phase 5 Section 5.8.4 - Output Sanitization

## Overview

Implemented the OutputSanitizer module for Phase 5 Handler Security Infrastructure.
This provides automatic redaction of sensitive data from handler outputs including
passwords, API keys, tokens, and other secrets.

## Files Created

| File | Purpose |
|------|---------|
| `lib/jido_code/tools/security/output_sanitizer.ex` | Output sanitization module |
| `test/jido_code/tools/security/output_sanitizer_test.exs` | Comprehensive unit tests |

## Implementation Details

### OutputSanitizer

**Location:** `lib/jido_code/tools/security/output_sanitizer.ex`

Main function: `sanitize/2`

```elixir
@spec sanitize(term(), [option()]) :: term()
def sanitize(value, opts \\ [])
```

**Options:**
- `:emit_telemetry` - Whether to emit telemetry events (default: true)
- `:context` - Additional context for telemetry metadata

### Sensitive Patterns

| Pattern | Replacement | Example Match |
|---------|-------------|---------------|
| password/secret/api_key/token assignments | `[REDACTED]` | `password=secret123` |
| Bearer tokens | `[REDACTED_BEARER]` | `Bearer eyJhbGc...` |
| OpenAI API keys | `[REDACTED_API_KEY]` | `sk-abc123...` |
| GitHub tokens (ghp_, gho_) | `[REDACTED_GITHUB_TOKEN]` | `ghp_abc123...` |
| AWS access keys | `[REDACTED_AWS_KEY]` | `AKIAIOSFODNN7...` |
| AWS secret access keys | `[REDACTED_AWS_SECRET]` | `aws_secret_access_key=...` |
| Slack tokens | `[REDACTED_SLACK_TOKEN]` | `xoxb-1234...` |
| Anthropic API keys | `[REDACTED_ANTHROPIC_KEY]` | `sk-ant-api03-...` |

### Sensitive Field Names

Map keys matching these patterns have their values replaced with `[REDACTED]`:

| Category | Field Names |
|----------|-------------|
| Password | `:password`, `:passwd`, `:pass` |
| Secret | `:secret`, `:secret_key`, `:secrets` |
| API Key | `:api_key`, `:apikey`, `:api_secret` |
| Token | `:token`, `:access_token`, `:refresh_token`, `:auth_token` |
| Auth | `:auth`, `:authorization`, `:credentials`, `:credential` |
| Private Key | `:private_key`, `:privatekey` |
| AWS | `:aws_access_key_id`, `:aws_secret_access_key` |

Both atom and string keys are supported.

### Features

| Feature | Implementation |
|---------|----------------|
| String sanitization | Regex pattern matching and replacement |
| Map sanitization | Field name lookup + recursive value sanitization |
| List sanitization | Iterative element sanitization |
| Tuple handling | Supports `{:ok, value}` and `{:error, value}` |
| Telemetry | Emits on each redaction operation |

### Helper Functions

| Function | Purpose |
|----------|---------|
| `contains_sensitive?/1` | Check if value contains sensitive data |
| `sensitive_patterns/0` | Get list of regex patterns |
| `sensitive_fields/0` | Get MapSet of sensitive field names |

## Test Coverage

**61 tests, 0 failures**

| Category | Tests |
|----------|-------|
| String pattern redaction | 13 |
| Map field redaction | 12 |
| List sanitization | 5 |
| Tuple handling | 3 |
| Other types passthrough | 5 |
| `contains_sensitive?/1` | 8 |
| `sensitive_patterns/0` | 1 |
| `sensitive_fields/0` | 1 |
| Telemetry emission | 5 |
| Edge cases | 5 |

### Edge Cases Tested

- Deeply nested structures (3+ levels)
- Mixed nesting of lists and maps
- Large strings (20KB+)
- Unicode content
- Special regex characters in values

## Telemetry

Event: `[:jido_code, :security, :output_sanitized]`

| Field | Description |
|-------|-------------|
| `redaction_count` | Number of redactions performed |
| `type` | `:string` or `:map` |
| Additional context | Passed via `:context` option |

## Planning Items Completed

- [x] 5.8.4.1 Create `output_sanitizer.ex`
- [x] 5.8.4.2 Define sensitive patterns
- [x] 5.8.4.3 Implement `sanitize/1` for strings
- [x] 5.8.4.4 Implement `sanitize/1` for maps (recursive)
- [x] 5.8.4.5 Define sensitive field names for map key redaction
- [ ] 5.8.4.6 Apply in Executor after handler returns (deferred)
- [x] 5.8.4.7 Emit telemetry

## Usage Example

```elixir
alias JidoCode.Tools.Security.OutputSanitizer

# Sanitize string content
OutputSanitizer.sanitize("config: password=secret123 api_key=abc")
# => "config: [REDACTED] [REDACTED]"

# Sanitize map with sensitive fields
OutputSanitizer.sanitize(%{
  username: "alice",
  password: "hunter2",
  settings: %{
    api_key: "sk-abc123..."
  }
})
# => %{username: "alice", password: "[REDACTED]", settings: %{api_key: "[REDACTED]"}}

# Check if data contains sensitive content
OutputSanitizer.contains_sensitive?("bearer eyJ...")
# => true

# Sanitize handler results with telemetry context
OutputSanitizer.sanitize(result, context: %{tool: "read_file", session_id: "sess_123"})
```

## Next Steps

Section 5.8.6 - Audit Logging:
- Create `lib/jido_code/tools/security/audit_logger.ex`
- Define audit entry structure
- Implement `log_invocation/4`
- Hash arguments for privacy

## References

- [ADR-0003](../decisions/0003-handler-security-infrastructure.md) - Security infrastructure decision
- [Phase 5 Planning](../planning/tooling/phase-05-tools.md) - Section 5.8.4
- [Section 5.8.3 Summary](./phase-05-section-5.8.3-process-isolation.md) - Process Isolation
