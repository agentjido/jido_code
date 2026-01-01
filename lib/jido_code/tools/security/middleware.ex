defmodule JidoCode.Tools.Security.Middleware do
  @moduledoc """
  Pre-execution security checks for tool invocations.

  This middleware provides centralized security enforcement for all Handler-based tools.
  It performs rate limiting, permission tier verification, and consent checks before
  a tool is executed.

  ## Configuration

  Enable security middleware via application config:

      config :jido_code, security_middleware: true

  ## Usage

  The middleware is automatically invoked by the Executor when enabled:

      # In Executor.execute/2
      if Middleware.enabled?() do
        with :ok <- Middleware.run_checks(tool, args, context) do
          execute_handler(tool, args, context)
        end
      else
        execute_handler(tool, args, context)
      end

  ## Checks Performed

  1. **Rate Limiting** - Enforces per-session, per-tool rate limits
  2. **Permission Tier** - Validates tool's tier against session's granted tier
  3. **Consent Requirement** - Checks if tool requires explicit consent

  ## Telemetry

  Emits `[:jido_code, :security, :middleware_check]` on each check with:
  - `:tool` - Tool name
  - `:session_id` - Session identifier
  - `:result` - `:allowed` or `:blocked`
  - `:reason` - Reason for blocking (if blocked)
  """

  require Logger

  alias JidoCode.Tools.Behaviours.SecureHandler
  alias JidoCode.Tools.Security.{Permissions, RateLimiter}

  @typedoc """
  Result of middleware checks.
  """
  @type check_result :: :ok | {:error, {:rate_limited, map()}} | {:error, {:permission_denied, map()}} | {:error, {:consent_required, map()}}

  @doc """
  Returns whether security middleware is enabled.

  Checks application config for `:security_middleware` setting.

  ## Examples

      iex> Application.put_env(:jido_code, :security_middleware, true)
      iex> Middleware.enabled?()
      true

      iex> Application.put_env(:jido_code, :security_middleware, false)
      iex> Middleware.enabled?()
      false
  """
  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:jido_code, :security_middleware, false)
  end

  @doc """
  Runs all security checks for a tool invocation.

  Checks are run in order:
  1. Rate limiting
  2. Permission tier
  3. Consent requirement

  If any check fails, execution stops and an error is returned.

  ## Parameters

  - `tool` - The tool struct or map with `:name` and optionally `:handler`
  - `args` - The arguments passed to the tool
  - `context` - Execution context with `:session_id` and optionally `:granted_tier`, `:consented_tools`

  ## Returns

  - `:ok` - All checks passed
  - `{:error, {:rate_limited, details}}` - Rate limit exceeded
  - `{:error, {:permission_denied, details}}` - Insufficient permissions
  - `{:error, {:consent_required, details}}` - Tool requires consent

  ## Examples

      iex> tool = %{name: "read_file", handler: ReadFileHandler}
      iex> context = %{session_id: "sess_123", granted_tier: :read_only}
      iex> Middleware.run_checks(tool, %{"path" => "file.txt"}, context)
      :ok
  """
  @spec run_checks(map(), map(), map()) :: check_result()
  def run_checks(tool, _args, context) do
    start_time = System.monotonic_time(:microsecond)

    result =
      with :ok <- check_rate_limit(tool, context),
           :ok <- check_permission_tier(tool, context),
           :ok <- check_consent_requirement(tool, context) do
        :ok
      end

    emit_telemetry(tool, context, result, start_time)
    result
  end

  @doc """
  Checks if the tool invocation is within rate limits.

  Uses the RateLimiter module to track invocations per session/tool.

  ## Parameters

  - `tool` - Tool with `:name` and optionally `:handler` with security properties
  - `context` - Context with `:session_id`

  ## Returns

  - `:ok` - Within rate limits
  - `{:error, {:rate_limited, details}}` - Rate limit exceeded

  ## Details Map

  When rate limited, the error includes:
  - `:tool` - Tool name
  - `:limit` - Maximum allowed invocations
  - `:window_ms` - Time window in milliseconds
  - `:retry_after_ms` - Milliseconds until rate limit resets
  """
  @spec check_rate_limit(map(), map()) :: :ok | {:error, {:rate_limited, map()}}
  def check_rate_limit(tool, context) do
    session_id = Map.get(context, :session_id)
    tool_name = get_tool_name(tool)

    if is_nil(session_id) do
      # No session means no rate limiting
      :ok
    else
      # Get rate limit from handler's security properties or use defaults
      {limit, window_ms} = get_rate_limit(tool)

      case RateLimiter.check_rate(session_id, tool_name, limit, window_ms) do
        :ok ->
          :ok

        {:error, retry_after_ms} ->
          {:error,
           {:rate_limited,
            %{
              tool: tool_name,
              limit: limit,
              window_ms: window_ms,
              retry_after_ms: retry_after_ms
            }}}
      end
    end
  end

  @doc """
  Checks if the session has permission to use the tool.

  Compares the tool's required tier against the session's granted tier.

  ## Parameters

  - `tool` - Tool with `:name` and optionally `:handler` with security properties
  - `context` - Context with `:granted_tier` (defaults to `:read_only`)

  ## Returns

  - `:ok` - Permission granted
  - `{:error, {:permission_denied, details}}` - Insufficient permissions

  ## Details Map

  When denied, the error includes:
  - `:tool` - Tool name
  - `:required_tier` - Tier required by the tool
  - `:granted_tier` - Tier granted to the session
  """
  @spec check_permission_tier(map(), map()) :: :ok | {:error, {:permission_denied, map()}}
  def check_permission_tier(tool, context) do
    tool_name = get_tool_name(tool)
    required_tier = get_required_tier(tool)
    granted_tier = Map.get(context, :granted_tier, :read_only)

    if SecureHandler.tier_allowed?(required_tier, granted_tier) do
      :ok
    else
      {:error,
       {:permission_denied,
        %{
          tool: tool_name,
          required_tier: required_tier,
          granted_tier: granted_tier
        }}}
    end
  end

  @doc """
  Checks if the tool requires explicit consent and if consent was given.

  Some tools require explicit user consent before execution.

  ## Parameters

  - `tool` - Tool with `:name` and optionally `:handler` with security properties
  - `context` - Context with `:consented_tools` (list of tool names user has consented to)

  ## Returns

  - `:ok` - Consent not required or already given
  - `{:error, {:consent_required, details}}` - Tool requires consent

  ## Details Map

  When consent required, the error includes:
  - `:tool` - Tool name
  - `:tier` - Tool's security tier
  """
  @spec check_consent_requirement(map(), map()) :: :ok | {:error, {:consent_required, map()}}
  def check_consent_requirement(tool, context) do
    tool_name = get_tool_name(tool)
    requires_consent = get_requires_consent(tool)
    consented_tools = Map.get(context, :consented_tools, [])

    cond do
      not requires_consent ->
        :ok

      tool_name in consented_tools ->
        :ok

      true ->
        {:error,
         {:consent_required,
          %{
            tool: tool_name,
            tier: get_required_tier(tool)
          }}}
    end
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp get_tool_name(%{name: name}), do: name
  defp get_tool_name(tool) when is_binary(tool), do: tool
  defp get_tool_name(_), do: "unknown"

  defp get_rate_limit(tool) do
    case get_security_properties(tool) do
      %{rate_limit: {count, window}} -> {count, window}
      _ -> get_default_rate_limit(tool)
    end
  end

  defp get_default_rate_limit(tool) do
    tier = get_required_tier(tool)
    Permissions.default_rate_limit(tier)
  end

  defp get_required_tier(tool) do
    case get_security_properties(tool) do
      %{tier: tier} -> tier
      _ -> Permissions.get_tool_tier(get_tool_name(tool))
    end
  end

  defp get_requires_consent(tool) do
    case get_security_properties(tool) do
      %{requires_consent: consent} -> consent
      _ -> false
    end
  end

  defp get_security_properties(%{handler: handler}) when is_atom(handler) do
    if function_exported?(handler, :security_properties, 0) do
      handler.security_properties()
    else
      %{}
    end
  end

  defp get_security_properties(_), do: %{}

  defp emit_telemetry(tool, context, result, start_time) do
    duration = System.monotonic_time(:microsecond) - start_time
    tool_name = get_tool_name(tool)
    session_id = Map.get(context, :session_id)

    {status, reason} =
      case result do
        :ok -> {:allowed, nil}
        {:error, {reason_type, _details}} -> {:blocked, reason_type}
      end

    :telemetry.execute(
      [:jido_code, :security, :middleware_check],
      %{duration: duration},
      %{
        tool: tool_name,
        session_id: session_id,
        result: status,
        reason: reason
      }
    )
  end
end
