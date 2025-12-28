# Phase 1: File Operations & Core Tools

This phase implements the foundational file system tools that form the basis of all code manipulation. These tools follow the read-before-write validation pattern used by all major coding assistants.

## Tools in This Phase

| Tool | Purpose | Priority |
|------|---------|----------|
| read_file | Read file contents with line numbers | MVP |
| write_file | Create/overwrite files with read validation | MVP |
| edit_file | Search/replace modifications | MVP |
| multi_edit | Atomic batch modifications | MVP |
| list_dir | Directory listing with ignore patterns | MVP |
| glob_search | Pattern-based file finding | MVP |
| delete_file | File removal with boundary validation | MVP |

---

## 1.1 Read File Tool

Implement the read_file tool for reading file contents with line numbers, offset support, and sensible defaults.

### 1.1.1 Tool Definition

Create the read_file tool definition with proper schema.

- [ ] 1.1.1.1 Create `lib/jido_code/tools/definitions/file_read.ex` with module documentation
- [ ] 1.1.1.2 Define tool schema with parameters:
  ```elixir
  %{
    path: %{type: :string, required: true, description: "Absolute path to file"},
    offset: %{type: :integer, required: false, description: "Line number to start from (1-indexed)"},
    limit: %{type: :integer, required: false, description: "Maximum lines to read (default: 2000)"}
  }
  ```
- [ ] 1.1.1.3 Set default limit to 2000 lines
- [ ] 1.1.1.4 Add max line length truncation (2000 characters)
- [ ] 1.1.1.5 Register tool in definitions module

### 1.1.2 Read Handler Implementation

Implement the handler for reading files with validation.

- [ ] 1.1.2.1 Create `lib/jido_code/tools/handlers/file_system/read_file.ex`
- [ ] 1.1.2.2 Implement path validation using session context
- [ ] 1.1.2.3 Implement file reading with offset/limit support
- [ ] 1.1.2.4 Format output with line numbers (cat -n style, 1-indexed)
- [ ] 1.1.2.5 Truncate long lines at 2000 characters with indicator
- [ ] 1.1.2.6 Handle binary file detection (reject with clear message)
- [ ] 1.1.2.7 Track read timestamp for concurrent modification detection
- [ ] 1.1.2.8 Return `{:ok, content}` or `{:error, reason}`

### 1.1.3 Unit Tests for Read File

- [ ] Test read_file with valid path returns line-numbered content
- [ ] Test read_file with offset skips initial lines
- [ ] Test read_file with limit caps output
- [ ] Test read_file truncates long lines
- [ ] Test read_file rejects binary files
- [ ] Test read_file rejects paths outside project boundary
- [ ] Test read_file handles non-existent files
- [ ] Test read_file handles permission errors

---

## 1.2 Write File Tool

Implement the write_file tool for creating new files, requiring prior read for existing files.

### 1.2.1 Tool Definition

Create the write_file tool definition.

- [ ] 1.2.1.1 Create tool definition in `lib/jido_code/tools/definitions/file_write.ex`
- [ ] 1.2.1.2 Define schema:
  ```elixir
  %{
    path: %{type: :string, required: true, description: "Absolute path for file"},
    content: %{type: :string, required: true, description: "File content to write"}
  }
  ```
- [ ] 1.2.1.3 Document read-before-write requirement in description

### 1.2.2 Write Handler Implementation

Implement the handler for writing files with validation.

- [ ] 1.2.2.1 Create `lib/jido_code/tools/handlers/file_system/write_file.ex`
- [ ] 1.2.2.2 Validate path is within project boundary
- [ ] 1.2.2.3 Check if file exists - if so, verify it was read in this session
- [ ] 1.2.2.4 Create parent directories if needed
- [ ] 1.2.2.5 Write content atomically (write to temp, rename)
- [ ] 1.2.2.6 Track write timestamp
- [ ] 1.2.2.7 Return `{:ok, path}` or `{:error, reason}`

### 1.2.3 Unit Tests for Write File

- [ ] Test write_file creates new file successfully
- [ ] Test write_file creates parent directories
- [ ] Test write_file rejects overwrite without prior read
- [ ] Test write_file allows overwrite with prior read
- [ ] Test write_file rejects paths outside boundary
- [ ] Test write_file handles permission errors
- [ ] Test write_file atomic write behavior

---

## 1.3 Edit File Tool

Implement the edit_file tool for surgical search/replace modifications with multi-strategy matching.

### 1.3.1 Tool Definition

Create the edit_file tool definition.

- [ ] 1.3.1.1 Create tool definition in `lib/jido_code/tools/definitions/file_edit.ex`
- [ ] 1.3.1.2 Define schema:
  ```elixir
  %{
    path: %{type: :string, required: true},
    old_string: %{type: :string, required: true, description: "Exact text to replace"},
    new_string: %{type: :string, required: true, description: "Replacement text"}
  }
  ```
- [ ] 1.3.1.3 Document that old_string must be unique in file

### 1.3.2 Edit Handler Implementation

Implement the handler with multi-strategy matching (following OpenCode pattern).

- [ ] 1.3.2.1 Create `lib/jido_code/tools/handlers/file_system/edit_file.ex`
- [ ] 1.3.2.2 Validate path and verify file was read
- [ ] 1.3.2.3 Implement exact string match (primary strategy)
- [ ] 1.3.2.4 Implement line-trimmed match fallback
- [ ] 1.3.2.5 Implement whitespace-normalized match fallback
- [ ] 1.3.2.6 Implement indentation-flexible match fallback
- [ ] 1.3.2.7 Verify old_string is unique in file
- [ ] 1.3.2.8 Return error if multiple matches found
- [ ] 1.3.2.9 Apply replacement atomically
- [ ] 1.3.2.10 Return `{:ok, path}` or `{:error, reason}`

### 1.3.3 Unit Tests for Edit File

- [ ] Test edit_file with exact match succeeds
- [ ] Test edit_file with whitespace variations uses fallback
- [ ] Test edit_file with indentation differences uses fallback
- [ ] Test edit_file fails on multiple matches
- [ ] Test edit_file fails on no match
- [ ] Test edit_file requires prior read
- [ ] Test edit_file validates boundary
- [ ] Test edit_file preserves file permissions

---

## 1.4 Multi-Edit Tool

Implement the multi_edit tool for atomic batch modifications.

### 1.4.1 Tool Definition

Create the multi_edit tool definition for atomic batch edits.

- [ ] 1.4.1.1 Create tool definition in `lib/jido_code/tools/definitions/file_multi_edit.ex`
- [ ] 1.4.1.2 Define schema with edits list:
  ```elixir
  %{
    path: %{type: :string, required: true},
    edits: %{type: :array, required: true, items: %{
      old_string: %{type: :string},
      new_string: %{type: :string}
    }}
  }
  ```

### 1.4.2 Multi-Edit Handler Implementation

Implement the handler for atomic batch modifications.

- [ ] 1.4.2.1 Create `lib/jido_code/tools/handlers/file_system/multi_edit.ex`
- [ ] 1.4.2.2 Validate all edits can be applied (all old_strings found and unique)
- [ ] 1.4.2.3 Apply all edits sequentially in single transaction
- [ ] 1.4.2.4 Rollback on any failure (atomic - all or nothing)
- [ ] 1.4.2.5 Return `{:ok, path}` or `{:error, {index, reason}}`

### 1.4.3 Unit Tests for Multi-Edit

- [ ] Test multi_edit applies all edits atomically
- [ ] Test multi_edit rolls back on failure
- [ ] Test multi_edit handles overlapping edits
- [ ] Test multi_edit validates all edits before applying
- [ ] Test multi_edit preserves edit order

---

## 1.5 List Directory Tool

Implement the list_dir tool for directory listing with ignore patterns.

### 1.5.1 Tool Definition

Create the list_dir tool definition for directory listing.

- [ ] 1.5.1.1 Create tool definition in `lib/jido_code/tools/definitions/list_dir.ex`
- [ ] 1.5.1.2 Define schema:
  ```elixir
  %{
    path: %{type: :string, required: true},
    ignore_patterns: %{type: :array, required: false, description: "Glob patterns to ignore"}
  }
  ```

### 1.5.2 List Directory Handler Implementation

Implement the handler for directory listing with filtering.

- [ ] 1.5.2.1 Create `lib/jido_code/tools/handlers/file_system/list_dir.ex`
- [ ] 1.5.2.2 Validate path within boundary
- [ ] 1.5.2.3 List directory contents with file type indicators
- [ ] 1.5.2.4 Apply ignore patterns (respect .gitignore by default)
- [ ] 1.5.2.5 Sort entries (directories first, then alphabetically)
- [ ] 1.5.2.6 Return `{:ok, entries}` or `{:error, reason}`

### 1.5.3 Unit Tests for List Directory

- [ ] Test list_dir returns directory contents
- [ ] Test list_dir applies ignore patterns
- [ ] Test list_dir validates boundary
- [ ] Test list_dir handles non-existent path
- [ ] Test list_dir handles file path (not directory)

---

## 1.6 Glob Search Tool

Implement the glob_search tool for pattern-based file finding.

### 1.6.1 Tool Definition

Create the glob_search tool definition for pattern matching.

- [ ] 1.6.1.1 Create tool definition in `lib/jido_code/tools/definitions/glob_search.ex`
- [ ] 1.6.1.2 Define schema:
  ```elixir
  %{
    pattern: %{type: :string, required: true, description: "Glob pattern (**, *, {a,b}, [abc])"},
    path: %{type: :string, required: false, description: "Base directory (default: project root)"}
  }
  ```

### 1.6.2 Glob Search Handler Implementation

Implement the handler for glob pattern matching.

- [ ] 1.6.2.1 Create `lib/jido_code/tools/handlers/search/glob.ex`
- [ ] 1.6.2.2 Use Path.wildcard for pattern matching
- [ ] 1.6.2.3 Validate all results within project boundary
- [ ] 1.6.2.4 Sort by modification time (newest first)
- [ ] 1.6.2.5 Return `{:ok, file_paths}` or `{:error, reason}`

### 1.6.3 Unit Tests for Glob Search

- [ ] Test glob_search with ** pattern
- [ ] Test glob_search with extension filter (*.ex)
- [ ] Test glob_search with directory prefix
- [ ] Test glob_search respects boundary
- [ ] Test glob_search handles empty results

---

## 1.7 Delete File Tool

Implement the delete_file tool for file removal.

### 1.7.1 Tool Definition

Create the delete_file tool definition.

- [ ] 1.7.1.1 Create tool definition in `lib/jido_code/tools/definitions/delete_file.ex`
- [ ] 1.7.1.2 Define schema:
  ```elixir
  %{
    path: %{type: :string, required: true, description: "Absolute path to file"}
  }
  ```

### 1.7.2 Delete File Handler Implementation

Implement the handler for file deletion.

- [ ] 1.7.2.1 Create `lib/jido_code/tools/handlers/file_system/delete_file.ex`
- [ ] 1.7.2.2 Validate path within boundary
- [ ] 1.7.2.3 Check file exists
- [ ] 1.7.2.4 Delete file (not directories)
- [ ] 1.7.2.5 Return `{:ok, path}` or `{:error, reason}`

### 1.7.3 Unit Tests for Delete File

- [ ] Test delete_file removes existing file
- [ ] Test delete_file fails for non-existent file
- [ ] Test delete_file fails for directories
- [ ] Test delete_file validates boundary
- [ ] Test delete_file handles permission errors

---

## 1.8 Phase 1 Integration Tests

Comprehensive integration tests verifying all Phase 1 file operation tools work together.

### 1.8.1 File Lifecycle Integration

Test complete file lifecycle workflows.

- [ ] 1.8.1.1 Create `test/jido_code/integration/tools_phase1_test.exs`
- [ ] 1.8.1.2 Test: Create file -> read -> edit -> verify content
- [ ] 1.8.1.3 Test: Create file -> multi_edit -> verify all changes
- [ ] 1.8.1.4 Test: Create file -> delete -> verify removed
- [ ] 1.8.1.5 Test: Create multiple files -> glob_search finds them
- [ ] 1.8.1.6 Test: Create directory structure -> list_dir shows contents

### 1.8.2 Security Boundary Integration

Test security boundaries are enforced across all tools.

- [ ] 1.8.2.1 Test: All tools reject paths outside project boundary
- [ ] 1.8.2.2 Test: Symlinks resolved and validated
- [ ] 1.8.2.3 Test: Path traversal attempts blocked

### 1.8.3 Read-Before-Write Integration

Test read-before-write validation pattern.

- [ ] 1.8.3.1 Test: write_file requires read for existing files
- [ ] 1.8.3.2 Test: edit_file requires read
- [ ] 1.8.3.3 Test: multi_edit requires read

---

## Phase 1 Success Criteria

1. **read_file**: Returns line-numbered content with offset/limit support
2. **write_file**: Creates files, requires prior read for overwrites
3. **edit_file**: Search/replace with multi-strategy matching
4. **multi_edit**: Atomic batch edits with rollback
5. **list_dir**: Directory listing with ignore patterns
6. **glob_search**: Pattern-based file finding
7. **delete_file**: File removal with boundary validation
8. **Test Coverage**: Minimum 80% for Phase 1 tools

---

## Phase 1 Critical Files

**New Files:**
- `lib/jido_code/tools/definitions/file_read.ex`
- `lib/jido_code/tools/definitions/file_write.ex`
- `lib/jido_code/tools/definitions/file_edit.ex`
- `lib/jido_code/tools/definitions/file_multi_edit.ex`
- `lib/jido_code/tools/definitions/list_dir.ex`
- `lib/jido_code/tools/definitions/glob_search.ex`
- `lib/jido_code/tools/definitions/delete_file.ex`
- `lib/jido_code/tools/handlers/file_system/read_file.ex`
- `lib/jido_code/tools/handlers/file_system/write_file.ex`
- `lib/jido_code/tools/handlers/file_system/edit_file.ex`
- `lib/jido_code/tools/handlers/file_system/multi_edit.ex`
- `lib/jido_code/tools/handlers/file_system/list_dir.ex`
- `lib/jido_code/tools/handlers/search/glob.ex`
- `lib/jido_code/tools/handlers/file_system/delete_file.ex`
- `test/jido_code/tools/handlers/file_system_test.exs`
- `test/jido_code/integration/tools_phase1_test.exs`

**Modified Files:**
- `lib/jido_code/tools/definitions.ex` - Register new tools
