# Task 3.1.1 Git Command Tool Definition

**Status**: Complete
**Branch**: `feature/3.1.1-git-command-definition`
**Planning Reference**: `notes/planning/tooling/phase-03-tools.md` Section 3.1.1

## Summary

This task implements the tool definition for the `git_command` tool, including schema definition, subcommand categorization, and destructive operation detection.

## Files Created/Modified

| File | Action | Description |
|------|--------|-------------|
| `lib/jido_code/tools/definitions/git_command.ex` | Created | Tool definition with schema and subcommand helpers |
| `lib/jido_code/tools/handlers/git.ex` | Created | Placeholder handler with validation logic |
| `lib/jido_code/tools.ex` | Modified | Added GitCommand to `register_all/0` |
| `test/jido_code/tools/definitions/git_command_test.exs` | Created | 39 unit tests for definition |
| `test/jido_code/tools/handlers/git_test.exs` | Created | 20 unit tests for handler validation |

## Tool Schema

```elixir
%{
  name: "git_command",
  description: "Execute git command in the project directory...",
  parameters: [
    %{name: "subcommand", type: :string, required: true},
    %{name: "args", type: :array, required: false},
    %{name: "allow_destructive", type: :boolean, required: false}
  ]
}
```

## Subcommand Categories

### Always Allowed (Read-Only)

```
status, diff, log, show, branch, remote, tag, rev-parse,
describe, shortlog, ls-files, ls-tree, cat-file, blame, reflog
```

### Allowed with Confirmation (Modifying)

```
add, commit, checkout, switch, merge, rebase, stash, cherry-pick,
reset, revert, fetch, pull, push, restore, rm, mv, init, clone,
worktree, submodule, notes, bisect, apply, am, clean
```

### Blocked by Default (Destructive)

| Pattern | Description |
|---------|-------------|
| `push --force` / `-f` | Force push |
| `push --force-with-lease` | Force push with lease |
| `reset --hard` | Hard reset |
| `clean -f` / `-fd` / `-fx` / `-fxd` | Force clean |
| `branch -D` | Force delete branch |
| `branch --delete --force` | Force delete branch (long form) |

## Key Functions

| Function | Purpose |
|----------|---------|
| `git_command/0` | Returns the tool definition |
| `all/0` | Returns list of all git tools |
| `subcommand_allowed?/1` | Checks if subcommand is in allowlist |
| `destructive?/2` | Checks if command matches destructive pattern |
| `always_allowed_subcommands/0` | Returns read-only subcommands |
| `modifying_subcommands/0` | Returns state-changing subcommands |
| `destructive_patterns/0` | Returns blocked patterns |

## Handler Validation

The placeholder handler (`Git.Command`) implements early validation:

1. **Subcommand validation** - Rejects nil, non-string, or disallowed subcommands
2. **Destructive operation blocking** - Blocks destructive patterns unless `allow_destructive: true`
3. **Context validation** - Requires `project_root` in context

Full handler implementation is deferred to Phase 3.1.2.

## Test Coverage

| Test File | Tests | Coverage |
|-----------|-------|----------|
| `git_command_test.exs` | 39 | Schema, subcommand categories, destructive detection, tool validation |
| `git_test.exs` | 20 | Handler validation, destructive blocking, context validation |
| **Total** | **59** | |

## Example Usage

```elixir
# Check repository status
%{"subcommand" => "status"}

# View recent commits
%{"subcommand" => "log", "args" => ["-5", "--oneline"]}

# Stage files
%{"subcommand" => "add", "args" => ["lib/my_module.ex"]}

# Force push (requires explicit permission)
%{"subcommand" => "push", "args" => ["--force"], "allow_destructive" => true}
```

## Running Tests

```bash
# Run all git tool tests
mix test test/jido_code/tools/definitions/git_command_test.exs test/jido_code/tools/handlers/git_test.exs

# Run with verbose output
mix test test/jido_code/tools/definitions/git_command_test.exs --trace
```

## Next Steps

- **3.1.2** - Bridge Function Implementation (lua_git/3)
- **3.1.3** - Manager API (git/3)
- **3.1.4** - Additional unit tests for bridge function
