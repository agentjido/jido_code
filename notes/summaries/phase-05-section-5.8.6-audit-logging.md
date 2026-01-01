# Summary: Phase 5 Section 5.8.6 - Audit Logging

## Overview

Implemented the AuditLogger module for Phase 5 Handler Security Infrastructure.
This provides comprehensive invocation logging with an ETS ring buffer, privacy-
preserving argument hashing, and telemetry integration.

## Files Created

| File | Purpose |
|------|---------|
| `lib/jido_code/tools/security/audit_logger.ex` | Audit logging module |
| `test/jido_code/tools/security/audit_logger_test.exs` | Comprehensive unit tests |

## Implementation Details

### AuditLogger

**Location:** `lib/jido_code/tools/security/audit_logger.ex`

Main function: `log_invocation/5`

```elixir
@spec log_invocation(String.t(), String.t(), status(), non_neg_integer(), [log_option()]) ::
        pos_integer()
def log_invocation(session_id, tool, status, duration_us, opts \\ [])
```

**Options:**
- `:args` - Tool arguments (will be hashed for privacy)
- `:emit_telemetry` - Whether to emit telemetry (default: true)
- `:log_blocked` - Whether to log blocked invocations to Logger (default: true)

### Audit Entry Structure

| Field | Type | Description |
|-------|------|-------------|
| `id` | `pos_integer()` | Unique entry identifier |
| `timestamp` | `DateTime.t()` | UTC timestamp of invocation |
| `session_id` | `String.t()` | Session identifier |
| `tool` | `String.t()` | Tool name |
| `status` | `:ok \| :error \| :blocked` | Invocation status |
| `duration_us` | `non_neg_integer()` | Execution duration in microseconds |
| `args_hash` | `String.t() \| nil` | Truncated SHA256 hash of arguments |

### Functions

| Function | Purpose |
|----------|---------|
| `log_invocation/5` | Log a tool invocation |
| `get_audit_log/1` | Get audit log (optionally filtered by session) |
| `get_audit_log/2` | Get audit log with options |
| `clear_all/0` | Clear all audit entries |
| `clear_session/1` | Clear entries for a session |
| `count/0` | Get current entry count |
| `buffer_size/0` | Get configured buffer size |
| `hash_args/1` | Hash arguments for privacy |

### Features

| Feature | Implementation |
|---------|----------------|
| Ring Buffer | ETS table with fixed max size (default 10,000) |
| Privacy Protection | Arguments hashed with SHA256, truncated to 16 chars |
| Atomic Counter | Uses `:atomics` for thread-safe ID generation |
| Session Filtering | Query by session ID |
| Ordering | Ascending or descending by entry ID |
| Logger Integration | Warning logs for blocked invocations |
| Telemetry | Events on each log invocation |

### Configuration

```elixir
# Configure buffer size (default: 10,000)
config :jido_code, audit_buffer_size: 20_000
```

## Test Coverage

**43 tests, 0 failures**

| Category | Tests |
|----------|-------|
| `log_invocation/5` | 10 |
| Ring buffer behavior | 2 |
| `get_audit_log/1` and `/2` | 8 |
| `clear_all/0` | 2 |
| `clear_session/1` | 2 |
| `count/0` | 2 |
| `hash_args/1` | 5 |
| Telemetry emission | 2 |
| Logger integration | 4 |
| Edge cases | 6 |
| ETS table management | 2 |

### Edge Cases Tested

- Special characters in session_id and tool name
- Zero and very large durations
- Empty args map
- Concurrent logging from multiple processes

## Telemetry

Event: `[:jido_code, :security, :audit]`

| Field | Description |
|-------|-------------|
| `duration_us` | Execution duration in microseconds |
| `session_id` | Session identifier |
| `tool` | Tool name |
| `status` | `:ok`, `:error`, or `:blocked` |
| `entry_id` | Unique entry identifier |

## Planning Items Completed

- [x] 5.8.6.1 Create `audit_logger.ex`
- [x] 5.8.6.2 Define audit entry structure
- [x] 5.8.6.3 Implement `log_invocation/4`
- [x] 5.8.6.4 Hash arguments for privacy
- [x] 5.8.6.5 Store in ETS ring buffer
- [x] 5.8.6.6 Implement `get_audit_log/1`
- [x] 5.8.6.7 Emit telemetry
- [x] 5.8.6.8 Integrate with Logger for blocked invocations

## Usage Example

```elixir
alias JidoCode.Tools.Security.AuditLogger

# Log a successful invocation
AuditLogger.log_invocation("session_123", "read_file", :ok, 1500,
  args: %{"path" => "/tmp/file.txt"}
)

# Log a blocked invocation (also logs warning)
AuditLogger.log_invocation("session_123", "run_command", :blocked, 0,
  args: %{"command" => "rm -rf /"}
)

# Get audit log for a session
entries = AuditLogger.get_audit_log("session_123", limit: 100, order: :desc)

# Get full audit log
all_entries = AuditLogger.get_audit_log()

# Clear session data on session end
AuditLogger.clear_session("session_123")

# Check current entry count
count = AuditLogger.count()
```

## Ring Buffer Behavior

When the buffer reaches capacity (default 10,000 entries):
1. The oldest entry (lowest ID) is removed
2. New entry is inserted
3. Buffer size remains at capacity

This ensures bounded memory usage while maintaining a rolling audit trail.

## Privacy Considerations

Arguments are never stored in raw form. Instead:
1. Arguments are serialized with `:erlang.term_to_binary/1`
2. SHA256 hash is computed
3. Hash is truncated to 16 hex characters
4. Only the truncated hash is stored

This allows correlation between entries without exposing sensitive data.

## Next Steps

Section 5.8.7 - Permission Tiers (partially complete):
- Add `granted_tier` and `consented_tools` to Session.State
- Implement `grant_tier/2` for permission upgrades
- Implement `record_consent/2` for explicit consent

## References

- [ADR-0003](../decisions/0003-handler-security-infrastructure.md) - Security infrastructure decision
- [Phase 5 Planning](../planning/tooling/phase-05-tools.md) - Section 5.8.6
- [Section 5.8.5 Summary](./phase-05-section-5.8.5-rate-limiting.md) - Rate Limiting
