# Phase 1 Review Fixes - Comprehensive Feature Planning Document

**Document Version**: 1.0
**Date**: 2026-01-09
**Status**: Planning
**Priority**: BLOCKERS must be resolved before Phase 2

---

## Problem Statement

The Phase 1 extensibility implementation (Configuration & Settings) is complete and functional with 158 passing tests and 90%+ coverage. However, a comprehensive review identified **8 blockers** that must be addressed before merging to main and proceeding to Phase 2:

### Security Blockers (4)
1. Environment variable leakage in error messages
2. Fail-open permission default (dangerous for production)
3. Missing auth token validation
4. Regex compilation error handling

### Architecture Blockers (2)
5. Missing root extensibility module (JidoCode.Extensibility)
6. Inconsistent error handling patterns

### Consistency Blockers (2)
7. Missing @typedoc annotations
8. Error return type inconsistency with existing codebase

Additionally, **5 concerns** and **7 suggestions** were identified for future improvement.

---

## Solution Overview

### Approach

1. **Security First**: Address all security blockers immediately as they represent production risks
2. **Architecture Foundation**: Create root extensibility module and standardize error handling
3. **Code Quality**: Ensure consistency with existing patterns (@typedoc, error types)
4. **Future-Proofing**: Address concerns that could cause technical debt
5. **Incremental Enhancement**: Implement suggestions as time permits

### Strategy

- **Minimize Code Churn**: Group related changes to reduce diff noise
- **Backward Compatibility**: Maintain all existing APIs and behavior
- **Test Coverage**: Ensure comprehensive tests for all fixes
- **Documentation**: Update docs to reflect security changes

---

## Agent Consultations Performed

None required - this planning document is based on the comprehensive review report from 6 parallel reviews (Factual, QA, Senior Engineer, Security, Consistency, Elixir).

---

## Technical Details

### Files to Modify

#### Security Fixes
1. **lib/jido_code/extensibility/channel_config.ex**
   - Line 137: Fix environment variable leakage
   - Lines 145-165: Add auth token validation
   - Line 128: Make expand_env_vars/1 return tagged tuples

2. **lib/jido_code/extensibility/permissions.ex**
   - Line 175: Make fail-open/fail-closed configurable
   - Line 284: Add regex compilation error handling
   - Lines 269-288: Add pattern caching for performance

#### Architecture Fixes
3. **lib/jido_code/extensibility.ex** (NEW FILE)
   - Root extensibility module
   - Public API entry point
   - Coordinated loading logic

4. **lib/jido_code/extensibility/error.ex** (NEW FILE)
   - Structured error types for extensibility system
   - Follow JidoCode.Error pattern
   - Error codes for validation, auth, permissions

5. **lib/jido_code/extensibility/channel_config.ex**
   - Add @typedoc annotations to all @type definitions
   - Change return types from {:error, String.t()} to {:error, %JidoCode.Error{}}

6. **lib/jido_code/extensibility/permissions.ex**
   - Add @typedoc annotations to all @type definitions
   - Change return types from {:error, String.t()} to {:error, %JidoCode.Error{}}

### New Files to Create

1. **lib/jido_code/extensibility.ex** - Root module
2. **lib/jido_code/extensibility/error.ex** - Error handling
3. **lib/jido_code/extensibility/validation_helper.ex** - Shared validation logic (optional, for concern #2)

### Test Files to Update

1. **test/jido_code/extensibility/channel_config_test.exs**
   - Add tests for env var error handling
   - Add tests for auth token validation
   - Update tests for new error return types

2. **test/jido_code/extensibility/permissions_test.exs**
   - Add tests for fail-closed mode
   - Add tests for regex compilation errors
   - Update tests for new error return types

3. **test/jido_code/extensibility/extensibility_test.exs** (NEW)
   - Tests for root module API
   - Tests for coordinated loading

---

## Success Criteria

### Blockers (Must Complete)

#### Security Blockers
- [ ] Environment variables are never included in error messages
- [ ] Env var errors return {:error, {:missing_env_var, var_name}} tuples
- [ ] Fail-closed mode is available and documented
- [ ] Auth tokens are validated for format after expansion
- [ ] Regex compilation failures are logged and return errors

#### Architecture Blockers
- [ ] JidoCode.Extensibility root module exists with public API
- [ ] All extensibility modules use consistent error handling
- [ ] Error handling follows JidoCode.Error pattern
- [ ] Root module provides coordinated loading function

#### Consistency Blockers
- [ ] All @type definitions have @typedoc annotations
- [ ] All functions return {:error, %JidoCode.Error{}} or {:error, atom()}
- [ ] No {:error, String.t()} returns in extensibility modules

### Concerns (Should Complete)

- [ ] Merge strategy is extractable and testable (or documented as tech debt)
- [ ] Settings validation is delegable (or documented as tech debt)
- [ ] Env var expansion is functional (no side effects during validation)
- [ ] Permission glob patterns handle edge cases (or documented)
- [ ] Settings tests are properly isolated (no race conditions)

### Suggestions (Nice to Have)

- [ ] Complex map types have specific type specs
- [ ] Protocol-based permission system designed (or documented)
- [ ] Configuration caching implemented (or documented)
- [ ] Extensibility lifecycle behavior defined (or documented)
- [ ] Magic strings extracted to module attributes
- [ ] Test files split into focused files
- [ ] Property-based tests added for critical functions

### Test Coverage Targets

- [ ] Maintain 90%+ coverage for extensibility modules
- [ ] All new error paths have tests
- [ ] All security fixes have regression tests
- [ ] Integration tests cover new API surface

---

## Implementation Plan

### Phase 1: Security Blockers (Priority: CRITICAL)

#### 1.1 Fix Environment Variable Leakage
**File**: `lib/jido_code/extensibility/channel_config.ex`

**Changes**:
```elixir
# Before (line 128-143)
def expand_env_vars(value) when is_binary(value) do
  Regex.replace(~r/\$\{([^}:}]+)(?::-([^}]*))?\}/, value, fn _whole, var_name, default ->
    case System.fetch_env(var_name) do
      {:ok, value} -> value
      :error when is_nil(default) or default == "" ->
        raise RuntimeError, "environment variable #{var_name} is not set"
      :error -> default
    end
  end)
end

# After
@spec expand_env_vars(String.t()) :: {:ok, String.t()} | {:error, {:missing_env_var, String.t()}}
def expand_env_vars(value) when is_binary(value) do
  try do
    expanded = do_expand_env_vars(value, [])
    {:ok, expanded}
  rescue
    e in RuntimeError -> {:error, {:missing_env_var, e.message}}
  end
end

defp do_expand_env_vars(value, acc) do
  # Implementation with tagged returns
end
```

**Tests**:
- Test missing required env var returns error tuple
- Test missing optional env var uses default
- Test multiple env vars in one string
- Test no env vars returns original string

**Estimated Time**: 2 hours

#### 1.2 Make Fail-Open/Fail-Closed Configurable
**File**: `lib/jido_code/extensibility/permissions.ex`

**Changes**:
```elixir
# Add to struct
defstruct allow: [], deny: [], ask: [], default_mode: :allow

@type default_mode :: :allow | :deny

# Update check_permission
def check_permission(%__MODULE__{default_mode: mode} = permissions, category, action) do
  target = format_target(category, action)

  cond do
    matches_any?(target, permissions.deny) -> :deny
    matches_any?(target, permissions.ask) -> :ask
    matches_any?(target, permissions.allow) -> :allow
    true -> mode  # Use configured default
  end
end

# Update defaults to use :deny for production
def defaults do
  %__MODULE__{
    allow: [...],
    deny: [...],
    ask: [...],
    default_mode: :deny  # Secure by default
  }
end
```

**Tests**:
- Test fail-open mode (backward compatibility)
- Test fail-closed mode (secure default)
- Test explicit allow/deny still works
- Test default can be configured

**Estimated Time**: 2 hours

#### 1.3 Add Auth Token Validation
**File**: `lib/jido_code/extensibility/channel_config.ex`

**Changes**:
```elixir
defp validate_auth(nil), do: :ok
defp validate_auth(auth) when is_map(auth) do
  with {:ok, type} <- validate_auth_type(Map.get(auth, "type")),
       :ok <- validate_auth_token(type, Map.get(auth, "token")) do
    :ok
  end
end

defp validate_auth_type(nil), do: {:error, "auth.type is required"}
defp validate_auth_type(type) when type in ["token", "basic", "custom"], do: {:ok, type}
defp validate_auth_type(type), do: {:error, "auth.type must be one of: token, basic, custom"}

defp validate_auth_token("token", nil), do: {:error, "auth.token is required for token type"}
defp validate_auth_token("token", token) when is_binary(token) do
  # After expansion, validate format
  case expand_env_vars(token) do
    {:ok, expanded} -> validate_token_format(expanded)
    {:error, _} = error -> error
  end
end
defp validate_auth_token("basic", nil), do: {:error, "auth.credentials are required for basic type"}
defp validate_auth_token("custom", _), do: :ok

defp validate_token_format(token) do
  cond do
    # Bearer token format
    String.starts_with?(token, "Bearer ") ->
      if String.length(token) > 20, do: :ok, else: {:error, "token too short"}

    # JWT format (header.payload.signature)
    String.contains?(token, ".") and count_dots(token) == 2 ->
      :ok

    # Generic token (at least 20 chars)
    String.length(token) >= 20 ->
      :ok

    true ->
      {:error, "token format invalid (must be Bearer token, JWT, or >= 20 chars)"}
  end
end

defp count_dots(str), do: str |> String.graphemes() |> Enum.count(&(&1 == "."))
```

**Tests**:
- Test Bearer token format validation
- Test JWT format validation
- Test generic token validation
- Test invalid token rejection
- Test token with env var expansion

**Estimated Time**: 3 hours

#### 1.4 Add Regex Compilation Error Handling
**File**: `lib/jido_code/extensibility/permissions.ex`

**Changes**:
```elixir
defp glob_match?(target, pattern) when is_binary(target) and is_binary(pattern) do
  regex_pattern = build_regex_from_pattern(pattern)

  case Regex.compile(regex_pattern) do
    {:ok, regex} ->
      Regex.match?(regex, target)

    {:error, reason} ->
      require Logger
      Logger.warning("Invalid permission pattern: #{pattern} - #{inspect(reason)}")
      false
  end
end
```

**Tests**:
- Test invalid regex pattern returns false
- Test regex error is logged
- Test valid patterns still match correctly

**Estimated Time**: 1 hour

**Subtotal Phase 1**: 8 hours

### Phase 2: Architecture Blockers (Priority: HIGH)

#### 2.1 Create Root Extensibility Module
**File**: `lib/jido_code/extensibility.ex` (NEW)

**Implementation**:
```elixir
defmodule JidoCode.Extensibility do
  @moduledoc """
  Extensibility system for JidoCode.

  This module provides the public API for the extensibility system including:
  - Configuration management (channels, settings)
  - Permissions (allow/deny/ask patterns)
  - Hooks (future phases)
  - Agents (future phases)
  - Plugins (future phases)

  ## Overview

  The extensibility system allows JidoCode to be configured and extended
  through JSON settings files, enabling runtime customization without code changes.

  ## Public API

      # Load extensions from settings
      {:ok, extensions} = JidoCode.Extensibility.load_extensions(settings)

      # Validate configuration
      {:ok, config} = JidoCode.Extensibility.validate_channel_config(channel_map)

      # Check permissions
      :allow = JidoCode.Extensibility.check_permission(permissions, "Read", "file.txt")

  ## Architecture

  The extensibility system is organized into:
  - `JidoCode.Extensibility.ChannelConfig` - Phoenix channel configuration
  - `JidoCode.Extensibility.Permissions` - Permission patterns and checks
  - `JidoCode.Extensibility.Error` - Structured error types

  Future phases will add:
  - `JidoCode.Extensibility.Hooks` - Event hook configuration
  - `JidoCode.Extensibility.Agents` - Agent configuration
  - `JidoCode.Extensibility.Plugins` - Plugin management
  """

  alias JidoCode.Extensibility.{ChannelConfig, Permissions, Error}

  @typedoc """
  Aggregate extensibility configuration.
  """
  @type t :: %__MODULE__{
          channels: %{String.t() => ChannelConfig.t()},
          permissions: Permissions.t() | nil
        }

  defstruct channels: %{}, permissions: nil

  @doc """
  Loads and validates extensibility configuration from settings.

  ## Parameters

  - `settings` - JidoCode.Settings struct containing extensibility fields

  ## Returns

  - `{:ok, extensibility}` - Successfully loaded configuration
  - `{:error, %JidoCode.Extensibility.Error{}}` - Validation failed

  ## Examples

      {:ok, ext} = JidoCode.Extensibility.load_extensions(settings)
      ext.channels["ui_state"].topic
      #=> "jido:ui"
  """
  @spec load_extensions(JidoCode.Settings.t()) :: {:ok, t()} | {:error, Error.t()}
  def load_extensions(%JidoCode.Settings{} = settings) do
    with {:ok, channels} <- load_channels(settings),
         {:ok, permissions} <- load_permissions(settings) do
      {:ok, %__MODULE__{channels: channels, permissions: permissions}}
    end
  end

  @doc """
  Validates a channel configuration map.

  Delegates to `ChannelConfig.validate/1`.
  """
  @spec validate_channel_config(map()) :: {:ok, ChannelConfig.t()} | {:error, Error.t()}
  def validate_channel_config(config) when is_map(config) do
    case ChannelConfig.validate(config) do
      {:ok, channel} -> {:ok, channel}
      {:error, reason} -> {:error, Error.validation_failed("channel config", reason)}
    end
  end

  @doc """
  Validates a permissions configuration map.

  Delegates to `Permissions.from_json/1`.
  """
  @spec validate_permissions(map()) :: {:ok, Permissions.t()} | {:error, Error.t()}
  def validate_permissions(json) when is_map(json) do
    case Permissions.from_json(json) do
      {:ok, perms} -> {:ok, perms}
      {:error, reason} -> {:error, Error.validation_failed("permissions", reason)}
    end
  end

  @doc """
  Checks if a permission is granted.

  Delegates to `Permissions.check_permission/3`.
  """
  @spec check_permission(Permissions.t(), String.t() | atom(), String.t() | atom()) ::
          Permissions.decision()
  def check_permission(%Permissions{} = perms, category, action) do
    Permissions.check_permission(perms, category, action)
  end

  @doc """
  Returns default extensibility configuration.

  ## Examples

      defaults = JidoCode.Extensibility.defaults()
      defaults.channels["ui_state"].topic
      #=> "jido:ui"

      defaults.permissions.default_mode
      #=> :deny
  """
  @spec defaults() :: t()
  def defaults do
    %__MODULE__{
      channels: ChannelConfig.defaults(),
      permissions: Permissions.defaults()
    }
  end

  # Private Functions

  defp load_channels(%JidoCode.Settings{channels: channels}) when is_map(channels) do
    Enum.reduce_while(channels, {:ok, %{}}, fn {name, config}, {:ok, acc} ->
      case validate_channel_config(config) do
        {:ok, channel} -> {:cont, {:ok, Map.put(acc, name, channel)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp load_channels(%JidoCode.Settings{channels: nil}), do: {:ok, ChannelConfig.defaults()}

  defp load_permissions(%JidoCode.Settings{permissions: perms}) when is_map(perms) do
    validate_permissions(perms)
  end

  defp load_permissions(%JidoCode.Settings{permissions: nil}), do: {:ok, nil}
end
```

**Tests**:
- Test load_extensions with valid settings
- Test load_extensions with invalid channels
- Test load_extensions with invalid permissions
- Test defaults returns proper structure
- Test validate_channel_config delegation
- Test validate_permissions delegation
- Test check_permission delegation

**Estimated Time**: 3 hours

#### 2.2 Standardize Error Handling
**File**: `lib/jido_code/extensibility/error.ex` (NEW)

**Implementation**:
```elixir
defmodule JidoCode.Extensibility.Error do
  @moduledoc """
  Structured error types for the extensibility system.

  Follows the JidoCode.Error pattern for consistency across the codebase.

  ## Error Codes

  Configuration:
  - `:channel_config_invalid` - Channel configuration validation failed
  - `:socket_invalid` - Socket URL is not a valid WebSocket URL
  - `:topic_invalid` - Topic contains invalid characters
  - `:auth_invalid` - Authentication configuration is invalid
  - `:token_invalid` - Auth token format is invalid

  Permissions:
  - `:permissions_invalid` - Permissions configuration validation failed
  - `:pattern_invalid` - Permission pattern has invalid syntax
  - `:permission_denied` - Permission check returned :deny

  Environment:
  - `:missing_env_var` - Required environment variable is not set

  General:
  - `:validation_failed` - Generic validation failure
  - `:not_found` - Resource not found
  - `:internal_error` - Unexpected internal error

  ## Usage

      error = Error.new(:channel_config_invalid, "socket must be a WebSocket URL")
      #=> %JidoCode.Extensibility.Error{code: :channel_config_invalid, message: "...", details: nil}

      {:error, error}
      #=> {:error, %JidoCode.Extensibility.Error{...}}
  """

  @type t :: %__MODULE__{
          code: atom(),
          message: String.t(),
          details: map() | nil
        }

  defstruct [:code, :message, :details]

  @doc """
  Creates a new extensibility error.
  """
  @spec new(atom(), String.t(), map() | nil) :: t()
  def new(code, message, details \\ nil) when is_atom(code) and is_binary(message) do
    %__MODULE__{
      code: code,
      message: message,
      details: details
    }
  end

  @doc """
  Creates a validation error for a specific field.
  """
  @spec validation_failed(String.t(), String.t()) :: t()
  def validation_failed(field, reason) do
    new(:validation_failed, "#{field} validation failed: #{reason}", %{field: field})
  end

  @doc """
  Creates a channel configuration error.
  """
  @spec channel_config_invalid(String.t()) :: t()
  def channel_config_invalid(reason) do
    new(:channel_config_invalid, reason, %{reason: reason})
  end

  @doc """
  Creates a permissions error.
  """
  @spec permissions_invalid(String.t()) :: t()
  def permissions_invalid(reason) do
    new(:permissions_invalid, reason, %{reason: reason})
  end

  @doc """
  Creates a missing environment variable error.
  """
  @spec missing_env_var(String.t()) :: t()
  def missing_env_var(var_name) do
    new(:missing_env_var, "required environment variable not set: #{var_name}", %{
      var_name: var_name
    })
  end

  @doc """
  Wraps an error in a tuple for consistent return values.
  """
  @spec wrap(atom(), String.t(), map() | nil) :: {:error, t()}
  def wrap(code, message, details \\ nil) do
    {:error, new(code, message, details)}
  end
end
```

**Update ChannelConfig to use new error types**:
```elixir
# In channel_config.ex
alias JidoCode.Extensibility.Error

@spec validate(map()) :: {:ok, t()} | {:error, Error.t()}
def validate(config) when is_map(config) do
  with :ok <- validate_socket(Map.get(config, "socket")),
       :ok <- validate_topic(Map.get(config, "topic")),
       :ok <- validate_auth(Map.get(config, "auth")),
       :ok <- validate_broadcast_events(Map.get(config, "broadcast_events")) do
    # ... rest of function
  else
    {:error, reason} when is_binary(reason) ->
      {:error, Error.channel_config_invalid(reason)}
  end
end

@spec expand_env_vars(String.t()) :: {:ok, String.t()} | {:error, Error.t()}
def expand_env_vars(value) when is_binary(value) do
  try do
    expanded = do_expand_env_vars(value, [])
    {:ok, expanded}
  rescue
    e in RuntimeError ->
      {:error, Error.missing_env_var(e.message)}
  end
end
```

**Update Permissions to use new error types**:
```elixir
# In permissions.ex
alias JidoCode.Extensibility.Error

@spec from_json(map()) :: {:ok, t()} | {:error, Error.t()}
def from_json(json) when is_map(json) do
  with :ok <- validate_field_list(json, "allow"),
       :ok <- validate_field_list(json, "deny"),
       :ok <- validate_field_list(json, "ask"),
       :ok <- validate_patterns(json, "allow"),
       :ok <- validate_patterns(json, "deny"),
       :ok <- validate_patterns(json, "ask") do
    permissions = %__MODULE__{
      allow: Map.get(json, "allow", []),
      deny: Map.get(json, "deny", []),
      ask: Map.get(json, "ask", [])
    }

    {:ok, permissions}
  else
    {:error, reason} when is_binary(reason) ->
      {:error, Error.permissions_invalid(reason)}
  end
end
```

**Tests**:
- Test all error constructors
- Test error wrapping
- Test validation errors
- Test channel config errors
- Test permissions errors
- Test missing env var errors

**Estimated Time**: 4 hours

**Subtotal Phase 2**: 7 hours

### Phase 3: Consistency Blockers (Priority: HIGH)

#### 3.1 Add @typedoc Annotations
**Files**: `channel_config.ex`, `permissions.ex`

**Changes**:
```elixir
# In channel_config.ex
@typedoc """
Channel configuration for Phoenix connections.

## Fields

- `:socket` - WebSocket URL (e.g., "ws://localhost:4000/socket")
- `:topic` - Channel topic (e.g., "jido:agent")
- `:auth` - Authentication configuration map
- `:broadcast_events` - List of events to broadcast on this channel
"""
@type t :: %__MODULE__{
        socket: String.t() | nil,
        topic: String.t() | nil,
        auth: map() | nil,
        broadcast_events: [String.t()] | nil
      }

@typedoc """
Permission decision: :allow | :deny | :ask
"""
@type decision :: :allow | :deny | :ask

@typedoc """
Permission category (e.g., "Read", "Edit", "run_command")
"""
@type category :: String.t() | atom()

@typedoc """
Permission action (e.g., "file.txt", "delete", "make")
"""
@type action :: String.t() | atom()
```

**Tests**: No tests needed (documentation only)

**Estimated Time**: 1 hour

**Subtotal Phase 3**: 1 hour

### Phase 4: Concerns (Priority: MEDIUM)

#### 4.1 Fix Environment Variable Expansion Side Effects
**File**: `lib/jido_code/extensibility/channel_config.ex`

**Current Issue**: `expand_env_vars/1` raises RuntimeError, breaking functional purity

**Solution**: Already addressed in Phase 1 (1.1) - now returns tagged tuples

**Verification**: Ensure all callers handle tagged tuples properly

**Estimated Time**: 1 hour

#### 4.2 Document Merge Strategy and Validation Coupling
**Files**: `lib/jido_code/settings.ex`, documentation

**Approach**: Since extraction would be significant refactoring, document as technical debt with clear plan for Phase 2:

```elixir
# In settings.ex, add documentation:
@moduledoc """
...
## Extensibility Merge Strategy

The `deep_merge/2` function includes extensibility-specific merge logic
inline. This is a known technical debt item (tracked in GitHub issue #XXX).

Future phases should extract this to a strategy pattern:
- Define `MergeStrategy` behavior
- Implement `ChannelMergeStrategy`, `PermissionsMergeStrategy`, etc.
- Allow extensibility modules to define their own merge semantics

For now, extensibility merge logic is:
- `channels`: Map merge (values override by key)
- `permissions`: Pattern union (allow/deny/ask lists concatenated)
- Other fields: Standard deep merge
"""
```

**Estimated Time**: 1 hour

#### 4.3 Add Permission Pattern Caching
**File**: `lib/jido_code/extensibility/permissions.ex`

**Implementation**:
```elixir
# Add module attribute for cache
@compile {:inline, glob_match?: 2}

# Use ETS table for pattern cache
def init_cache do
  :ets.new(:permission_pattern_cache, [:named_table, :public, read_concurrency: true])
end

defp glob_match?(target, pattern) when is_binary(target) and is_binary(pattern) do
  cache_key = {pattern, target}

  case :ets.lookup(:permission_pattern_cache, cache_key) do
    [{^cache_key, result}] -> result
    [] ->
      result = do_glob_match(target, pattern)
      :ets.insert(:permission_pattern_cache, {cache_key, result})
      result
  end
end

defp do_glob_match(target, pattern) do
  # Original implementation
end
```

**Note**: This is a suggestion (low priority). Can defer to Phase 2.

**Estimated Time**: 2 hours

#### 4.4 Fix Settings Test Pollution
**File**: `test/jido_code/settings_test.exs`

**Current Issue**: Tests clear cache without coordination

**Solution**: Use `ExUnit.Callbacks` for proper setup/teardown:

```elixir
defmodule JidoCode.SettingsTest do
  use ExUnit.Case, async: false

  setup do
    # Get unique cache key for this test
    test_pid = self()
    unique_cache_key = {:settings_test, test_pid}

    # Ensure clean state
    JidoCode.Settings.clear_cache(unique_cache_key)

    on_exit(fn ->
      JidoCode.Settings.clear_cache(unique_cache_key)
    end)

    {:ok, cache_key: unique_cache_key}
  end

  test "settings merge", %{cache_key: cache_key} do
    # Use cache_key for operations
  end
end
```

**Estimated Time**: 2 hours

**Subtotal Phase 4**: 6 hours

### Phase 5: Suggestions (Priority: LOW)

#### 5.1 Extract Magic Strings to Module Attributes
**File**: `lib/jido_code/extensibility/channel_config.ex`

**Changes**:
```elixir
defmodule JidoCode.Extensibility.ChannelConfig do
  # Extract magic strings
  @valid_auth_types ~w(token basic custom)
  @valid_socket_schemes ~w(ws wss)
  @topic_regex ~r/^[a-zA-Z0-9:_\-\.]+$/

  # Use in validation
  defp validate_auth(nil), do: :ok
  defp validate_auth(auth) when is_map(auth) do
    case Map.get(auth, "type") do
      nil -> {:error, "auth.type is required"}
      type when type in @valid_auth_types -> :ok
      type -> {:error, "auth.type must be one of: #{Enum.join(@valid_auth_types, ", ")}. Got: #{type}"}
    end
  end

  defp validate_socket(nil), do: :ok
  defp validate_socket("") do
    {:error, "socket cannot be empty string"}
  end
  defp validate_socket(socket) when is_binary(socket) do
    uri = URI.parse(socket)
    if uri.scheme in @valid_socket_schemes do
      :ok
    else
      {:error, "socket must be a valid WebSocket URL (ws:// or wss://)"}
    end
  end

  defp validate_topic(nil) do
    {:error, "topic is required"}
  end
  defp validate_topic("") do
    {:error, "topic cannot be empty"}
  end
  defp validate_topic(topic) when is_binary(topic) do
    if Regex.match?(@topic_regex, topic) do
      :ok
    else
      {:error, "topic must contain only alphanumeric characters, colons, underscores, hyphens, or dots"}
    end
  end
end
```

**Estimated Time**: 1 hour

#### 5.2 Add Complex Type Specifications
**File**: `lib/jido_code/extensibility/channel_config.ex`

**Changes**:
```elixir
@typedoc """
Authentication configuration.

Supported types:
- `token`: Bearer token or JWT
- `basic`: Basic auth with username/password
- `custom`: Custom authentication scheme
"""
@type auth_config :: %{
          String.t() => String.t() | nil
        }

@typedoc """
Broadcast events list (nil means use defaults)
"""
@type broadcast_events :: [String.t()] | nil
```

**Estimated Time**: 1 hour

#### 5.3 Define Extensibility Lifecycle Behavior
**File**: `lib/jido_code/extensibility/component.ex` (NEW)

**Implementation**:
```elixir
defmodule JidoCode.Extensibility.Component do
  @moduledoc """
  Behavior for extensibility components.

  Defines the lifecycle for extensibility components:
  - Channels (Phase 1)
  - Hooks (Phase 3)
  - Agents (Phase 6)
  - Plugins (Phase 5)

  ## Example

      defmodule MyExtension do
        @behaviour JidoCode.Extensibility.Component

        @impl true
        def defaults, do: %{enabled: true}

        @impl true
        def validate(config), do: {:ok, config}

        @impl true
        def from_settings(settings), do: settings.my_extension
      end
  """

  @doc """
  Returns default configuration for this component.
  """
  @callback defaults() :: map()

  @doc """
  Validates configuration for this component.

  Should return `{:ok, validated}` or `{:error, reason}`.
  """
  @callback validate(map()) :: {:ok, map()} | {:error, term()}

  @doc """
  Extracts this component's configuration from settings.
  """
  @callback from_settings(JidoCode.Settings.t()) :: map() | nil

  @optional_callbacks [defaults: 0, validate: 1, from_settings: 1]
end
```

**Note**: This is a design artifact - actual implementation would be in Phase 2+.

**Estimated Time**: 2 hours (design only, no implementation)

**Subtotal Phase 5**: 4 hours

---

## Testing Strategy

### Unit Tests

#### Security Fixes
1. **Environment Variable Error Handling**
   - Test missing required var returns {:error, {:missing_env_var, var_name}}
   - Test missing optional var uses default
   - Test multiple vars in one string
   - Test no vars returns original
   - Test env var values never appear in error messages

2. **Fail-Closed Permissions**
   - Test default_mode: :deny blocks unmatched
   - Test default_mode: :allow permits unmatched
   - Test explicit deny still overrides
   - Test explicit ask still works
   - Test explicit allow still works

3. **Auth Token Validation**
   - Test Bearer token format (length, prefix)
   - Test JWT format (3 parts separated by dots)
   - Test generic token (length >= 20)
   - Test token too short rejected
   - Test token with env var expansion

4. **Regex Compilation Errors**
   - Test invalid pattern returns false
   - Test regex error logged at warning level
   - Test valid patterns still match

#### Architecture Fixes
5. **Root Extensibility Module**
   - Test load_extensions with valid settings
   - Test load_extensions with invalid channels
   - Test load_extensions with invalid permissions
   - Test load_extensions with nil channels (uses defaults)
   - Test load_extensions with nil permissions
   - Test validate_channel_config delegation
   - Test validate_permissions delegation
   - Test check_permission delegation
   - Test defaults returns proper structure

6. **Error Handling**
   - Test Error.new/3 creates proper struct
   - Test Error.validation_failed/2
   - Test Error.channel_config_invalid/1
   - Test Error.permissions_invalid/1
   - Test Error.missing_env_var/1
   - Test Error.wrap/3
   - Test ChannelConfig.validate returns error tuples
   - Test Permissions.from_json returns error tuples

### Integration Tests

1. **End-to-End Extensibility Loading**
   - Test loading extensions from complete settings
   - Test validation errors propagate correctly
   - Test defaults are used when fields are nil

2. **Permission Checking with New Defaults**
   - Test fail-closed mode in realistic scenarios
   - Test backward compatibility with fail-open

3. **Error Propagation**
   - Test errors from ChannelConfig bubble up to root module
   - Test errors from Permissions bubble up to root module
   - Test error messages are user-friendly

### Regression Tests

1. **Backward Compatibility**
   - Test existing settings files still load
   - Test existing permission patterns still work
   - Test existing channel configs still validate

2. **Performance**
   - Test permission pattern caching doesn't slow down checks
   - Test regex compilation is cached appropriately

### Test Coverage Goals

- **Blockers**: 100% coverage of all new code paths
- **Concerns**: 90%+ coverage of modified code
- **Suggestions**: 80%+ coverage of any implemented features
- **Overall**: Maintain 90%+ coverage for extensibility modules

---

## Notes and Considerations

### Security Considerations

1. **Fail-Closed Default**
   - Changing default from `:allow` to `:deny` is a breaking change
   - Must document migration path for existing users
   - Consider deprecation period with warnings

2. **Environment Variable Leakage**
   - Ensure logger doesn't capture env var values
   - Add security tests to verify no leakage in stack traces

3. **Auth Token Validation**
   - Token format validation is basic, not a security guarantee
   - Document that actual token validity is checked at connection time
   - Don't give false sense of security

### Backward Compatibility

1. **Error Return Types**
   - Changing from `{:error, String.t()}` to `{:error, %Error{}}` breaks existing callers
   - Consider adding `JidoCode.Error.from_legacy/1` compatibility layer
   - Document migration guide

2. **Fail-Closed Permissions**
   - Existing users may rely on fail-open behavior
   - Add configuration option in settings to choose mode
   - Default to `:deny` for new installations, `:allow` for upgrades

### Dependencies

1. **Phase 2 Cannot Start Until Blockers Resolved**
   - Signal Bus (Phase 2) depends on extensibility infrastructure
   - Must have root module for coordinated loading
   - Must have consistent error handling

2. **Settings Module Coupling**
   - Cannot extract merge strategy without breaking Settings
   - Defer to Phase 2 when refactoring is less disruptive

### Risks

1. **Breaking Changes**
   - Error type changes break existing code
   - Fail-closed default breaks existing permissions
   - Mitigation: Provide compatibility layer and migration guide

2. **Test Failures**
   - Many tests need updating for new error types
   - Integration tests may fail on fail-closed default
   - Mitigation: Update all tests in same PR as fixes

3. **Performance Regression**
   - Pattern caching may add overhead
   - Regex compilation on every match is slow
   - Mitigation: Benchmark before/after, optimize if needed

### Migration Guide

#### For Error Types

```elixir
# Before
case ChannelConfig.validate(config) do
  {:ok, channel} -> channel
  {:error, message} -> IO.puts("Error: #{message}")
end

# After
case ChannelConfig.validate(config) do
  {:ok, channel} -> channel
  {:error, %JidoCode.Extensibility.Error{message: message}} ->
    IO.puts("Error: #{message}")
end
```

#### For Permissions Default Mode

```elixir
# In settings.json
{
  "permissions": {
    "default_mode": "deny",  // Explicit (secure)
    "allow": ["Read:*"],
    "deny": ["*delete*"]
  }
}
```

### Open Questions

1. Should we support both error return types during transition period?
2. Should fail-closed be the only default or configurable?
3. Should pattern caching be in Phase 1 or Phase 2?
4. Should we create a compatibility shim for legacy error handling?

### Technical Debt Tracking

Create GitHub issues for:
1. Extract merge strategy to strategy pattern (Settings coupling)
2. Implement validation delegation to extensibility modules
3. Add protocol-based permission system (future phases)
4. Implement configuration caching GenServer
5. Add property-based tests for critical functions
6. Split settings_test.exs into focused files

---

## Timeline Estimate

| Phase | Tasks | Estimated Time | Priority |
|-------|-------|----------------|----------|
| Phase 1 | Security Blockers | 8 hours | CRITICAL |
| Phase 2 | Architecture Blockers | 7 hours | HIGH |
| Phase 3 | Consistency Blockers | 1 hour | HIGH |
| Phase 4 | Concerns | 6 hours | MEDIUM |
| Phase 5 | Suggestions | 4 hours | LOW |
| **Total** | **All items** | **26 hours** | - |

### Recommended Schedule

**Week 1: Critical Fixes (16 hours)**
- Phase 1: Security Blockers (8 hours)
- Phase 2: Architecture Blockers (7 hours)
- Phase 3: Consistency Blockers (1 hour)

**Week 2: Improvements (10 hours)**
- Phase 4: Concerns (6 hours)
- Phase 5: Suggestions (4 hours)

---

## Success Metrics

### Before Merge to Main

- [ ] All 8 blockers resolved
- [ ] All tests passing (158+)
- [ ] Coverage maintained at 90%+
- [ ] No security vulnerabilities
- [ ] Backward compatibility maintained
- [ ] Documentation updated

### Before Phase 2 Start

- [ ] Root extensibility module stable
- [ ] Error handling consistent across all modules
- [ ] Security concerns addressed
- [ ] Migration guide published
- [ ] Technical debt tracked

### Quality Gates

- [ ] Code review approved by 2 reviewers
- [ ] Security review passed
- [ ] Integration tests passing
- [ ] Performance benchmarks acceptable
- [ ] Documentation complete

---

## Appendix

### Related Documents

- [Phase 1 Implementation Plan](../planning/phase1-implementation.md)
- [Phase 1 Review Report](../reviews/phase1-review-2026-01-09.md)
- [Extensibility Architecture](../architecture/1.00-extensibility-architecture.md)

### References

- Elixir Guidelines: https://hexdocs.pm/elixir/style-guide.html
- Security Best Practices: https://hexdocs.pm/elixir/security.html
- JidoCode Error Handling: `/lib/jido_code/error.ex`

### Change Log

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-09 | Initial planning document |

---

## Sign-Off

**Prepared By**: Feature Planner Agent
**Date**: 2026-01-09
**Status**: Ready for Review
**Next Step**: Present plan to team for approval and prioritization
