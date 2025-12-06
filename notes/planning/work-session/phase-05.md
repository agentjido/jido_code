# Phase 5: Session Commands

This phase implements the `/session` command family for managing sessions via the command interface. Commands allow creating, listing, switching, closing, and renaming sessions.

---

## 5.1 Command Parser Updates

Update the command parser to recognize session commands.

### 5.1.1 Session Command Registration
- [x] **Task 5.1.1** (completed 2025-12-06)

Add session commands to the command registry.

- [x] 5.1.1.1 Update command pattern matching in `Commands.parse/1`:
  ```elixir
  def parse("/session " <> args), do: {:session, parse_session_args(args)}
  def parse("/session"), do: {:session, :help}
  ```
- [x] 5.1.1.2 Define session subcommands:
  - `new [path] [--name=name]` - Create new session
  - `list` - List all sessions
  - `switch <id|index>` - Switch to session
  - `close [id|index]` - Close session
  - `rename <name>` - Rename current session
- [x] 5.1.1.3 Implement `parse_session_args/1` for subcommand parsing
- [x] 5.1.1.4 Write unit tests for command parsing (17 tests)

### 5.1.2 Session Argument Parser
- [x] **Task 5.1.2** (completed 2025-12-06)

Implement argument parsing for session subcommands.

- [x] 5.1.2.1 Implement `parse_session_args/1` (done in 5.1.1)
- [x] 5.1.2.2 Implement `parse_new_args/1` handling path and --name flag (done in 5.1.1)
- [x] 5.1.2.3 Implement `parse_close_args/1` handling optional target (done in 5.1.1)
- [x] 5.1.2.4 Implement `resolve_session_path/1` for path resolution:
  - Handle `~` expansion to home directory
  - Handle `.` and `..` for relative paths
  - Handle relative paths resolved against CWD
- [x] 5.1.2.5 Implement `validate_session_path/1` for path validation
- [x] 5.1.2.6 Write unit tests for path resolution (14 tests)

**Unit Tests for Section 5.1:**
- Test `/session new /path/to/project` parses correctly
- Test `/session new /path --name=MyProject` parses name flag
- Test `/session list` parses to :list
- Test `/session switch 1` parses index
- Test `/session switch abc123` parses ID
- Test `/session close` parses with no target
- Test `/session close 2` parses with index
- Test `/session rename NewName` parses name
- Test `/session` shows help

---

## 5.2 Session New Command

Implement the `/session new` command for creating sessions.

### 5.2.1 New Session Handler
- [x] **Task 5.2.1** (completed 2025-12-06)

Implement the handler for creating new sessions.

- [x] 5.2.1.1 Implement `execute_session({:new, opts}, model)` with path resolution
- [x] 5.2.1.2 Validate path exists before creating session (uses validate_session_path)
- [x] 5.2.1.3 Handle session limit (10 max) - returns `:session_limit_reached` error
- [x] 5.2.1.4 Handle duplicate project path - returns `:project_already_open` error
- [x] 5.2.1.5 Return `{:session_action, {:add_session, session}}` for TUI
- [x] 5.2.1.6 Write unit tests for new command (11 tests)
- [x] 5.2.1.7 Implement `execute_session(:help, model)` for session help
- [x] 5.2.1.8 Add stub handlers for :list, :switch, :close, :rename

### 5.2.2 Path Resolution
- [x] **Task 5.2.2** (completed in Task 5.1.2)

Implement path resolution for session creation.

- [x] 5.2.2.1 Handle relative paths (resolve against CWD)
- [x] 5.2.2.2 Handle `~` expansion for home directory
- [x] 5.2.2.3 Handle `.` for current directory
- [x] 5.2.2.4 Handle `..` for parent directory
- [x] 5.2.2.5 Validate resolved path exists and is directory
- [x] 5.2.2.6 Write unit tests for path resolution (14 tests)

### 5.2.3 TUI Integration for New Session
- [x] **Task 5.2.3** (completed 2025-12-06)

Handle `{:session, subcommand}` and `{:session_action, {:add_session, session}}` in TUI.

- [x] 5.2.3.1 Add `{:session, subcommand}` handling in `do_handle_command/2`
- [x] 5.2.3.2 Add `handle_session_command/2` to execute session subcommands
- [x] 5.2.3.3 Add `Model.add_session/2` to add session to model
- [x] 5.2.3.4 Add `Model.switch_to_session/2` to switch active session
- [x] 5.2.3.5 Add `Model.session_count/1` helper function
- [x] 5.2.3.6 Subscribe to session's PubSub topic on creation
- [x] 5.2.3.7 Write unit tests for Model helpers (8 tests)

**Unit Tests for Section 5.2:**
- Test `/session new` creates session for CWD
- Test `/session new /path` creates session for path
- Test `/session new /path --name=Foo` uses custom name
- Test `/session new` fails at 10 sessions
- Test `/session new` fails for duplicate path
- Test `/session new` fails for non-existent path
- Test relative path resolution
- Test TUI adds session to tabs

---

## 5.3 Session List Command

Implement the `/session list` command.

### 5.3.1 List Handler
- [x] **Task 5.3.1** (completed 2025-12-06)

Implement the handler for listing sessions.

- [x] 5.3.1.1 Implement `execute_session(:list, model)`
- [x] 5.3.1.2 Implement `format_session_list/2` helper
- [x] 5.3.1.3 Implement `truncate_path/1` helper
- [x] 5.3.1.4 Show index number (1-10)
- [x] 5.3.1.5 Show asterisk for active session
- [x] 5.3.1.6 Show truncated project path with ~ for home
- [x] 5.3.1.7 Write unit tests for list command (8 tests)

### 5.3.2 Empty List Handling
- [x] **Task 5.3.2** (completed 2025-12-06)

Handle empty session list.

- [x] 5.3.2.1 Return helpful message when no sessions
- [x] 5.3.2.2 Update unit test for empty list

**Unit Tests for Section 5.3:**
- Test `/session list` shows all sessions
- Test list includes index numbers
- Test active session marked with asterisk
- Test paths truncated appropriately
- Test empty list shows help message

---

## 5.4 Session Switch Command

Implement the `/session switch` command.

### 5.4.1 Switch by Index
- [x] **Task 5.4.1** (completed 2025-12-06)

Implement switching by tab index.

- [x] 5.4.1.1 Implement `execute_session({:switch, target}, model)`
- [x] 5.4.1.2 Implement `resolve_session_target/2` with helpers
- [x] 5.4.1.3 Support index 1-10 (0 means 10)
- [x] 5.4.1.4 Support switch by session ID
- [x] 5.4.1.5 Support switch by session name
- [x] 5.4.1.6 Write unit tests for switch command (8 tests)

### 5.4.2 Switch by ID or Name
- [ ] **Task 5.4.2**

Implement switching by session ID or name.

- [ ] 5.4.2.1 Implement `find_session_by_name/2`:
  ```elixir
  defp find_session_by_name(name, model) do
    case Enum.find(model.sessions, fn {_id, s} -> s.name == name end) do
      {id, _} -> {:ok, id}
      nil -> {:error, :not_found}
    end
  end
  ```
- [ ] 5.4.2.2 Support partial name matching (prefix)
- [ ] 5.4.2.3 Handle ambiguous names (multiple matches)
- [ ] 5.4.2.4 Write unit tests for ID/name switching

### 5.4.3 TUI Integration for Switch
- [ ] **Task 5.4.3**

Handle `{:switch_session, id}` action in TUI.

- [ ] 5.4.3.1 Update `update({:command_result, {:switch_session, id}}, model)`:
  ```elixir
  def update({:command_result, {:switch_session, session_id}}, model) do
    %{model | active_session_id: session_id}
  end
  ```
- [ ] 5.4.3.2 Write integration tests

**Unit Tests for Section 5.4:**
- Test `/session switch 1` switches to first session
- Test `/session switch 0` switches to 10th session
- Test `/session switch abc123` switches by ID
- Test `/session switch MyProject` switches by name
- Test `/session switch` with invalid target shows error
- Test partial name matching works
- Test ambiguous name shows error

---

## 5.5 Session Close Command

Implement the `/session close` command.

### 5.5.1 Close Handler
- [ ] **Task 5.5.1**

Implement the handler for closing sessions.

- [ ] 5.5.1.1 Implement `execute_session({:close, target}, model)`:
  ```elixir
  def execute_session({:close, target}, model) do
    session_id = target || model.active_session_id

    case resolve_session_target(session_id, model) do
      {:ok, id} ->
        session = model.sessions[id]
        SessionSupervisor.stop_session(id)
        {:ok, "Closed session: #{session.name}", {:remove_session, id}}
      {:error, :not_found} ->
        {:error, "Session not found: #{target}"}
    end
  end
  ```
- [ ] 5.5.1.2 Default to active session if no target
- [ ] 5.5.1.3 Prevent closing if it's the last session (optional)
- [ ] 5.5.1.4 Write unit tests for close command

### 5.5.2 Close Cleanup
- [ ] **Task 5.5.2**

Implement proper cleanup when closing session.

- [ ] 5.5.2.1 Stop session processes via SessionSupervisor
- [ ] 5.5.2.2 Unregister from SessionRegistry
- [ ] 5.5.2.3 Unsubscribe from PubSub topic
- [ ] 5.5.2.4 Save session state for /resume (Phase 6)
- [ ] 5.5.2.5 Write unit tests for cleanup

### 5.5.3 TUI Integration for Close
- [ ] **Task 5.5.3**

Handle `{:remove_session, id}` action in TUI.

- [ ] 5.5.3.1 Update `update({:command_result, {:remove_session, id}}, model)`:
  ```elixir
  def update({:command_result, {:remove_session, session_id}}, model) do
    new_order = List.delete(model.session_order, session_id)
    new_sessions = Map.delete(model.sessions, session_id)

    # Switch to adjacent session
    new_active = find_adjacent_session(model.session_order, session_id)

    unsubscribe_from_session(session_id)

    %{model |
      sessions: new_sessions,
      session_order: new_order,
      active_session_id: new_active
    }
  end
  ```
- [ ] 5.5.3.2 Find adjacent session (prefer next, fallback to previous)
- [ ] 5.5.3.3 Handle closing last session (show welcome screen)
- [ ] 5.5.3.4 Write integration tests

**Unit Tests for Section 5.5:**
- Test `/session close` closes active session
- Test `/session close 2` closes by index
- Test `/session close abc123` closes by ID
- Test close stops session processes
- Test close unregisters from registry
- Test TUI switches to adjacent session
- Test closing last session shows welcome

---

## 5.6 Session Rename Command

Implement the `/session rename` command.

### 5.6.1 Rename Handler
- [ ] **Task 5.6.1**

Implement the handler for renaming sessions.

- [ ] 5.6.1.1 Implement `execute_session({:rename, name}, model)`:
  ```elixir
  def execute_session({:rename, name}, model) do
    session_id = model.active_session_id

    case Session.rename(model.sessions[session_id], name) do
      {:ok, updated} ->
        SessionRegistry.update(updated)
        {:ok, "Renamed to: #{name}", {:update_session, updated}}
      {:error, reason} ->
        {:error, "Invalid name: #{reason}"}
    end
  end
  ```
- [ ] 5.6.1.2 Validate new name (non-empty, max 50 chars)
- [ ] 5.6.1.3 Update session in registry
- [ ] 5.6.1.4 Write unit tests for rename command

### 5.6.2 TUI Integration for Rename
- [ ] **Task 5.6.2**

Handle `{:update_session, session}` action in TUI.

- [ ] 5.6.2.1 Update `update({:command_result, {:update_session, session}}, model)`:
  ```elixir
  def update({:command_result, {:update_session, session}}, model) do
    %{model | sessions: Map.put(model.sessions, session.id, session)}
  end
  ```
- [ ] 5.6.2.2 Tab label updates automatically on next render
- [ ] 5.6.2.3 Write integration tests

**Unit Tests for Section 5.6:**
- Test `/session rename NewName` renames active session
- Test rename updates registry
- Test rename fails for empty name
- Test rename fails for too-long name
- Test TUI updates session in model

---

## 5.7 Help and Error Handling

Implement help output and error handling for session commands.

### 5.7.1 Session Help
- [ ] **Task 5.7.1**

Implement help output for session commands.

- [ ] 5.7.1.1 Implement `execute_session(:help, _model)`:
  ```elixir
  def execute_session(:help, _model) do
    help = """
    Session Commands:
      /session new [path] [--name=name]  Create new session
      /session list                       List all sessions
      /session switch <index|id|name>     Switch to session
      /session close [index|id]           Close session
      /session rename <name>              Rename current session

    Keyboard Shortcuts:
      Ctrl+1 to Ctrl+0  Switch to session 1-10
      Ctrl+Tab          Next session
      Ctrl+Shift+Tab    Previous session
      Ctrl+W            Close current session
      Ctrl+N            New session
    """
    {:ok, help, :no_change}
  end
  ```
- [ ] 5.7.1.2 Write unit tests for help output

### 5.7.2 Error Messages
- [ ] **Task 5.7.2**

Define clear error messages for all failure cases.

- [ ] 5.7.2.1 Define error messages:
  ```elixir
  @error_messages %{
    session_limit_reached: "Maximum 10 sessions reached. Close a session first.",
    project_already_open: "Project already open in another session.",
    invalid_path: "Path does not exist or is not a directory.",
    session_not_found: "Session not found.",
    invalid_name: "Name must be 1-50 characters.",
    no_active_session: "No active session."
  }
  ```
- [ ] 5.7.2.2 Use consistent error formatting
- [ ] 5.7.2.3 Write unit tests for error messages

**Unit Tests for Section 5.7:**
- Test `/session` shows help
- Test `/session foo` (unknown subcommand) shows help
- Test error messages are clear and helpful
- Test all error cases have proper messages

---

## 5.8 Phase 5 Integration Tests

Comprehensive integration tests verifying all Phase 5 command components work together correctly.

### 5.8.1 Session New Command Integration
- [ ] **Task 5.8.1**

Test `/session new` command end-to-end.

- [ ] 5.8.1.1 Create `test/jido_code/integration/session_phase5_test.exs`
- [ ] 5.8.1.2 Test: `/session new /path` → session created → tab added → switched to new session
- [ ] 5.8.1.3 Test: `/session new` (no path) → uses CWD → session created
- [ ] 5.8.1.4 Test: `/session new --name=Foo` → custom name in tab and registry
- [ ] 5.8.1.5 Test: `/session new` at limit (10) → error message → no session created
- [ ] 5.8.1.6 Test: `/session new` duplicate path → error message → no session created
- [ ] 5.8.1.7 Write all new command integration tests

### 5.8.2 Session List Command Integration
- [ ] **Task 5.8.2**

Test `/session list` command end-to-end.

- [ ] 5.8.2.1 Test: Create 3 sessions → `/session list` → shows all 3 with indices
- [ ] 5.8.2.2 Test: Active session marked with asterisk in list
- [ ] 5.8.2.3 Test: Empty session list → helpful message shown
- [ ] 5.8.2.4 Test: List shows truncated paths correctly
- [ ] 5.8.2.5 Write all list command integration tests

### 5.8.3 Session Switch Command Integration
- [ ] **Task 5.8.3**

Test `/session switch` command end-to-end.

- [ ] 5.8.3.1 Test: `/session switch 2` → active session changes → view updates
- [ ] 5.8.3.2 Test: `/session switch MyProject` → switches by name
- [ ] 5.8.3.3 Test: `/session switch abc123` → switches by ID
- [ ] 5.8.3.4 Test: `/session switch 99` (invalid) → error message → no change
- [ ] 5.8.3.5 Test: Partial name match → switches to matching session
- [ ] 5.8.3.6 Write all switch command integration tests

### 5.8.4 Session Close Command Integration
- [ ] **Task 5.8.4**

Test `/session close` command end-to-end.

- [ ] 5.8.4.1 Test: `/session close` → active session stopped → removed from tabs → switch to adjacent
- [ ] 5.8.4.2 Test: `/session close 2` → specific session closed
- [ ] 5.8.4.3 Test: Close last session → welcome screen appears
- [ ] 5.8.4.4 Test: Close → processes terminated → registry updated → PubSub unsubscribed
- [ ] 5.8.4.5 Write all close command integration tests

### 5.8.5 Session Rename Command Integration
- [ ] **Task 5.8.5**

Test `/session rename` command end-to-end.

- [ ] 5.8.5.1 Test: `/session rename NewName` → tab label updates → registry updates
- [ ] 5.8.5.2 Test: `/session rename` with invalid name → error message → no change
- [ ] 5.8.5.3 Test: Rename → `/session list` shows new name
- [ ] 5.8.5.4 Write all rename command integration tests

### 5.8.6 Command-TUI Flow Integration
- [ ] **Task 5.8.6**

Test command execution integrates properly with TUI state.

- [ ] 5.8.6.1 Test: Command result {:add_session, session} → TUI model updated correctly
- [ ] 5.8.6.2 Test: Command result {:switch_session, id} → TUI switches active session
- [ ] 5.8.6.3 Test: Command result {:remove_session, id} → TUI removes from tabs
- [ ] 5.8.6.4 Test: Command result {:update_session, session} → TUI updates session data
- [ ] 5.8.6.5 Test: Command error → displayed in TUI feedback area
- [ ] 5.8.6.6 Write all TUI flow integration tests

**Integration Tests for Section 5.8:**
- All session commands work end-to-end
- Commands properly update TUI state
- Error cases handled with clear feedback
- Command results flow correctly to TUI

---

## Success Criteria

1. **New Command**: `/session new` creates sessions with path/name options
2. **List Command**: `/session list` shows all sessions with indices
3. **Switch Command**: `/session switch` works with index, ID, and name
4. **Close Command**: `/session close` stops and cleans up session
5. **Rename Command**: `/session rename` updates session name
6. **Help Output**: `/session` shows comprehensive help
7. **Path Resolution**: Relative paths, ~, ., .. all work
8. **Error Handling**: Clear messages for all error cases
9. **TUI Integration**: Commands update TUI model correctly
10. **Test Coverage**: Minimum 80% coverage for phase 5 code
11. **Integration Tests**: All Phase 5 components work together correctly (Section 5.8)

---

## Critical Files

**New Files:**
- `lib/jido_code/commands/session.ex` - Session command implementation (optional, or inline)
- `test/jido_code/commands/session_test.exs` - Session command tests
- `test/jido_code/integration/session_phase5_test.exs`

**Modified Files:**
- `lib/jido_code/commands.ex` - Add session command handlers
- `lib/jido_code/tui.ex` - Handle command result actions

---

## Dependencies

- **Depends on Phase 1**: SessionSupervisor, SessionRegistry, Session struct
- **Depends on Phase 4**: TUI model structure with sessions
- **Phase 6 depends on this**: /resume command builds on close cleanup
