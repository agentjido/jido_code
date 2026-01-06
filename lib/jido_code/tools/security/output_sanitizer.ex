defmodule JidoCode.Tools.Security.OutputSanitizer do
  @moduledoc """
  Automatic redaction of sensitive data from handler outputs.

  This module provides sanitization functions to remove or redact sensitive
  information (passwords, API keys, tokens, etc.) from tool outputs before
  they are returned to the LLM or displayed to users.

  ## Features

  - **Pattern-based redaction**: Regex patterns for common secrets
  - **Field name redaction**: Sensitive map keys have values replaced
  - **Recursive sanitization**: Handles nested maps and lists
  - **Telemetry integration**: Emits events when sanitization occurs

  ## Usage

      iex> OutputSanitizer.sanitize("API_KEY=sk-abc123...")
      "API_KEY=[REDACTED]"

      iex> OutputSanitizer.sanitize(%{password: "secret123"})
      %{password: "[REDACTED]"}

  ## Patterns

  The following patterns are redacted:
  - Password/secret/api_key/token assignments
  - Bearer tokens
  - OpenAI API keys (sk-...)
  - GitHub tokens (ghp_...)
  - AWS access keys (AKIA...)
  - Generic base64-encoded secrets

  ## Sensitive Fields

  Map keys matching these patterns have their values redacted:
  - password, passwd, pass
  - secret, api_key, apikey
  - token, auth, authorization
  - credential, private_key
  """

  require Logger

  # =============================================================================
  # Sensitive Patterns for String Content
  # =============================================================================

  @sensitive_patterns [
    # Password/secret/api_key/token with value assignments
    {~r/(?i)(password|passwd|pass|secret|api_?key|token)\s*[:=]\s*\S+/, "[REDACTED]"},
    # Bearer tokens
    {~r/(?i)bearer\s+[a-zA-Z0-9._\-]+/, "[REDACTED_BEARER]"},
    # OpenAI API keys (sk-...)
    {~r/sk-[a-zA-Z0-9]{20,}/, "[REDACTED_API_KEY]"},
    # GitHub personal access tokens (ghp_...)
    {~r/ghp_[a-zA-Z0-9]{36,}/, "[REDACTED_GITHUB_TOKEN]"},
    # GitHub OAuth tokens (gho_...)
    {~r/gho_[a-zA-Z0-9]{36,}/, "[REDACTED_GITHUB_TOKEN]"},
    # AWS access keys (AKIA...)
    {~r/AKIA[A-Z0-9]{16}/, "[REDACTED_AWS_KEY]"},
    # AWS secret access keys (40 char alphanumeric)
    {~r/(?i)aws_secret_access_key\s*[:=]\s*[A-Za-z0-9\/+=]{40}/, "[REDACTED_AWS_SECRET]"},
    # Slack tokens (xox...)
    {~r/xox[baprs]-[a-zA-Z0-9\-]+/, "[REDACTED_SLACK_TOKEN]"},
    # Anthropic API keys
    {~r/sk-ant-[a-zA-Z0-9\-]+/, "[REDACTED_ANTHROPIC_KEY]"},
    # Google Cloud API keys (AIza...)
    {~r/AIza[a-zA-Z0-9_\-]{35}/, "[REDACTED_GOOGLE_KEY]"},
    # Azure connection strings
    {~r/(?i)(AccountKey|SharedAccessKey)\s*[:=]\s*[A-Za-z0-9+\/=]{40,}/, "[REDACTED_AZURE_KEY]"},
    # JWT tokens (three base64 segments)
    {~r/eyJ[a-zA-Z0-9_-]*\.eyJ[a-zA-Z0-9_-]*\.[a-zA-Z0-9_-]+/, "[REDACTED_JWT]"},
    # SSH private keys
    {~r/-----BEGIN\s+(RSA|EC|DSA|OPENSSH)?\s*PRIVATE KEY-----/, "[REDACTED_SSH_KEY]"},
    # Database connection strings with passwords
    {~r/(?i)(mysql|postgres|postgresql|mongodb|redis):\/\/[^:]+:[^@]+@/, "[REDACTED_DB_URL]"},
    # Generic secret in JSON/env format
    {~r/"(password|secret|api_?key|token)"\s*:\s*"[^"]+"/i, "\"\\1\": \"[REDACTED]\""}
  ]

  # =============================================================================
  # Sensitive Field Names for Map Key Redaction
  # =============================================================================

  @sensitive_fields MapSet.new([
    # Password variations
    :password,
    :passwd,
    :pass,
    "password",
    "passwd",
    "pass",
    # Secret variations
    :secret,
    :secret_key,
    :secrets,
    "secret",
    "secret_key",
    "secrets",
    # API key variations
    :api_key,
    :apikey,
    :api_secret,
    "api_key",
    "apikey",
    "api_secret",
    # Token variations
    :token,
    :access_token,
    :refresh_token,
    :auth_token,
    "token",
    "access_token",
    "refresh_token",
    "auth_token",
    # Auth variations
    :auth,
    :authorization,
    :credentials,
    :credential,
    "auth",
    "authorization",
    "credentials",
    "credential",
    # Private key variations
    :private_key,
    :privatekey,
    "private_key",
    "privatekey",
    # AWS specific
    :aws_secret_access_key,
    :aws_access_key_id,
    "aws_secret_access_key",
    "aws_access_key_id"
  ])

  @redacted_value "[REDACTED]"
  @default_max_depth 50

  @typedoc """
  Options for sanitization.
  """
  @type option ::
          {:emit_telemetry, boolean()}
          | {:context, map()}
          | {:max_depth, pos_integer()}

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Sanitizes a value by redacting sensitive information.

  Handles strings, maps, lists, and tuples. For maps, both keys (sensitive field names)
  and values (pattern matching) are checked. Recursively sanitizes nested structures.

  ## Parameters

  - `value` - Any term to sanitize
  - `opts` - Options:
    - `:emit_telemetry` - Whether to emit telemetry events (default: true)
    - `:context` - Additional context for telemetry

  ## Returns

  The sanitized value with sensitive data redacted.

  ## Examples

      iex> OutputSanitizer.sanitize("password=secret123")
      "password=[REDACTED]"

      iex> OutputSanitizer.sanitize(%{username: "alice", password: "hunter2"})
      %{username: "alice", password: "[REDACTED]"}

      iex> OutputSanitizer.sanitize([%{token: "abc"}, "bearer xyz"])
      [%{token: "[REDACTED]"}, "[REDACTED_BEARER]"]
  """
  @spec sanitize(term(), [option()]) :: term()
  def sanitize(value, opts \\ [])

  def sanitize(value, opts) when is_binary(value) do
    sanitize_string(value, opts)
  end

  def sanitize(value, opts) when is_map(value) do
    max_depth = Keyword.get(opts, :max_depth, @default_max_depth)
    sanitize_map(value, opts, 0, max_depth)
  end

  def sanitize(value, opts) when is_list(value) do
    max_depth = Keyword.get(opts, :max_depth, @default_max_depth)
    sanitize_list(value, opts, 0, max_depth)
  end

  def sanitize({:ok, value}, opts) do
    {:ok, sanitize(value, opts)}
  end

  def sanitize({:error, value}, opts) do
    {:error, sanitize(value, opts)}
  end

  def sanitize(value, _opts) do
    # Numbers, atoms, PIDs, etc. - return as-is
    value
  end

  @doc """
  Checks if a value contains sensitive data without sanitizing it.

  Useful for conditional logic or logging decisions.

  ## Examples

      iex> OutputSanitizer.contains_sensitive?("password=secret")
      true

      iex> OutputSanitizer.contains_sensitive?("hello world")
      false
  """
  @spec contains_sensitive?(term()) :: boolean()
  def contains_sensitive?(value) when is_binary(value) do
    Enum.any?(@sensitive_patterns, fn {pattern, _replacement} ->
      Regex.match?(pattern, value)
    end)
  end

  def contains_sensitive?(value) when is_map(value) do
    Enum.any?(value, fn {key, val} ->
      MapSet.member?(@sensitive_fields, key) or contains_sensitive?(val)
    end)
  end

  def contains_sensitive?(value) when is_list(value) do
    Enum.any?(value, &contains_sensitive?/1)
  end

  def contains_sensitive?(_value), do: false

  @doc """
  Returns the list of sensitive patterns used for string matching.
  """
  @spec sensitive_patterns() :: [{Regex.t(), String.t()}]
  def sensitive_patterns, do: @sensitive_patterns

  @doc """
  Returns the set of sensitive field names for map key matching.
  """
  @spec sensitive_fields() :: MapSet.t()
  def sensitive_fields, do: @sensitive_fields

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp sanitize_string(value, opts) do
    {sanitized, redaction_count} = apply_patterns(value)

    if redaction_count > 0 do
      maybe_emit_telemetry(:string, redaction_count, opts)
    end

    sanitized
  end

  defp apply_patterns(value) do
    Enum.reduce(@sensitive_patterns, {value, 0}, fn {pattern, replacement}, {acc, count} ->
      if Regex.match?(pattern, acc) do
        {Regex.replace(pattern, acc, replacement), count + 1}
      else
        {acc, count}
      end
    end)
  end

  defp sanitize_map(map, opts, depth, max_depth) do
    # Stop recursion at max depth to prevent DoS attacks
    if depth >= max_depth do
      map
    else
      {sanitized, redaction_count} =
        Enum.reduce(map, {%{}, 0}, fn {key, value}, {acc, count} ->
          if MapSet.member?(@sensitive_fields, key) do
            {Map.put(acc, key, @redacted_value), count + 1}
          else
            # Recursively sanitize the value with incremented depth
            sanitized_value = sanitize_value(value, opts, depth + 1, max_depth)
            {Map.put(acc, key, sanitized_value), count}
          end
        end)

      if redaction_count > 0 do
        maybe_emit_telemetry(:map, redaction_count, opts)
      end

      sanitized
    end
  end

  defp sanitize_list(list, opts, depth, max_depth) do
    # Stop recursion at max depth to prevent DoS attacks
    if depth >= max_depth do
      list
    else
      Enum.map(list, fn item ->
        sanitize_value(item, opts, depth + 1, max_depth)
      end)
    end
  end

  # Internal recursive sanitization with depth tracking
  defp sanitize_value(value, opts, _depth, _max_depth) when is_binary(value) do
    sanitize_string(value, Keyword.put(opts, :emit_telemetry, false))
  end

  defp sanitize_value(value, opts, depth, max_depth) when is_map(value) do
    sanitize_map(value, Keyword.put(opts, :emit_telemetry, false), depth, max_depth)
  end

  defp sanitize_value(value, opts, depth, max_depth) when is_list(value) do
    sanitize_list(value, Keyword.put(opts, :emit_telemetry, false), depth, max_depth)
  end

  defp sanitize_value(value, _opts, _depth, _max_depth) do
    value
  end

  defp maybe_emit_telemetry(type, redaction_count, opts) do
    emit_telemetry = Keyword.get(opts, :emit_telemetry, true)
    context = Keyword.get(opts, :context, %{})

    if emit_telemetry do
      :telemetry.execute(
        [:jido_code, :security, :output_sanitized],
        %{redaction_count: redaction_count},
        Map.merge(context, %{type: type})
      )
    end
  end
end
