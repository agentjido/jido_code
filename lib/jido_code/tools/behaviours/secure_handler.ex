defmodule JidoCode.Tools.Behaviours.SecureHandler do
  @moduledoc """
  Behavior for handlers to declare security properties.

  This behavior allows handlers to opt-in to the centralized security infrastructure
  by declaring their security properties, validation logic, and output sanitization.

  ## Security Tiers

  Handlers must declare one of four security tiers:

  - `:read_only` - Read-only operations (e.g., read_file, grep, find_files)
  - `:write` - Modify files or state (e.g., write_file, edit_file)
  - `:execute` - Run external commands (e.g., run_command, mix_task)
  - `:privileged` - System-level access (e.g., get_process_state, ets_inspect)

  ## Usage

      defmodule MyApp.Handlers.MyTool do
        use JidoCode.Tools.Behaviours.SecureHandler

        @impl true
        def security_properties do
          %{
            tier: :read_only,
            rate_limit: {100, :timer.minutes(1)},
            timeout_ms: 5000,
            requires_consent: false
          }
        end

        @impl true
        def validate_security(args, context) do
          # Custom validation logic
          :ok
        end

        def execute(args, context) do
          # Handler implementation
          {:ok, "result"}
        end
      end

  ## Default Implementations

  When using this behavior, default implementations are provided for:

  - `validate_security/2` - Returns `:ok` (no additional validation)
  - `sanitize_output/1` - Returns the result unchanged

  Only `security_properties/0` must be implemented by the handler.

  ## Telemetry

  When a handler using this behavior is compiled, the following telemetry event
  is emitted:

      [:jido_code, :security, :handler_loaded]

  With metadata:
  - `:module` - The handler module name
  - `:tier` - The declared security tier
  """

  @typedoc """
  Security properties map that handlers must return.

  ## Required Fields

  - `:tier` - The security tier (`:read_only`, `:write`, `:execute`, `:privileged`)

  ## Optional Fields

  - `:rate_limit` - Tuple of `{count, window_ms}` for rate limiting
  - `:timeout_ms` - Execution timeout in milliseconds
  - `:requires_consent` - Whether explicit user consent is required
  """
  @type security_properties :: %{
          required(:tier) => :read_only | :write | :execute | :privileged,
          optional(:rate_limit) => {pos_integer(), pos_integer()},
          optional(:timeout_ms) => pos_integer(),
          optional(:requires_consent) => boolean()
        }

  @typedoc """
  Security tier indicating the level of access a handler requires.

  - `:read_only` - Can only read data, no side effects
  - `:write` - Can modify files or application state
  - `:execute` - Can run external commands or processes
  - `:privileged` - Has elevated system access
  """
  @type tier :: :read_only | :write | :execute | :privileged

  @doc """
  Returns the security properties for this handler.

  This callback must be implemented by handlers using this behavior.
  The returned map declares the handler's security tier and optional
  constraints like rate limits and timeouts.

  ## Example

      @impl true
      def security_properties do
        %{
          tier: :write,
          rate_limit: {30, :timer.minutes(1)},
          timeout_ms: 10_000,
          requires_consent: true
        }
      end
  """
  @callback security_properties() :: security_properties()

  @doc """
  Validates security constraints before handler execution.

  This callback is called by the security middleware before the handler's
  `execute/2` function. Use this to implement custom security validation
  specific to this handler.

  ## Parameters

  - `args` - The arguments passed to the handler
  - `context` - The execution context (session_id, project_root, etc.)

  ## Returns

  - `:ok` - Validation passed, execution can proceed
  - `{:error, reason}` - Validation failed, execution blocked

  ## Default Implementation

  Returns `:ok` (no additional validation).

  ## Example

      @impl true
      def validate_security(%{"path" => path}, context) do
        if String.contains?(path, "..") do
          {:error, "path traversal not allowed"}
        else
          :ok
        end
      end
  """
  @callback validate_security(args :: map(), context :: map()) :: :ok | {:error, term()}

  @doc """
  Sanitizes the handler's output before returning to the caller.

  This callback is called after the handler's `execute/2` function returns
  a successful result. Use this to remove or redact sensitive information
  from the output.

  ## Parameters

  - `result` - The successful result from `execute/2`

  ## Returns

  The sanitized result.

  ## Default Implementation

  Returns the result unchanged.

  ## Example

      @impl true
      def sanitize_output(result) when is_binary(result) do
        # Redact API keys from output
        Regex.replace(~r/sk-[a-zA-Z0-9]{48,}/, result, "[REDACTED_API_KEY]")
      end

      def sanitize_output(result), do: result
  """
  @callback sanitize_output(result :: term()) :: term()

  @doc """
  Returns the list of valid security tiers in order of privilege.

  The order is: `:read_only` < `:write` < `:execute` < `:privileged`
  """
  @spec tier_hierarchy() :: [tier()]
  def tier_hierarchy, do: [:read_only, :write, :execute, :privileged]

  @doc """
  Checks if the first tier is at or below the level of the second tier.

  ## Examples

      iex> SecureHandler.tier_allowed?(:read_only, :write)
      true

      iex> SecureHandler.tier_allowed?(:execute, :write)
      false

      iex> SecureHandler.tier_allowed?(:write, :write)
      true
  """
  @spec tier_allowed?(tier(), tier()) :: boolean()
  def tier_allowed?(requested_tier, granted_tier) do
    hierarchy = tier_hierarchy()
    requested_index = Enum.find_index(hierarchy, &(&1 == requested_tier)) || 999
    granted_index = Enum.find_index(hierarchy, &(&1 == granted_tier)) || -1
    requested_index <= granted_index
  end

  @doc """
  Validates that a tier is a valid security tier.

  ## Examples

      iex> SecureHandler.valid_tier?(:read_only)
      true

      iex> SecureHandler.valid_tier?(:invalid)
      false
  """
  @spec valid_tier?(term()) :: boolean()
  def valid_tier?(tier) when tier in [:read_only, :write, :execute, :privileged], do: true
  def valid_tier?(_), do: false

  @doc """
  Validates security properties returned by a handler.

  Checks that:
  - The `:tier` field is present and valid
  - Optional fields have correct types

  ## Returns

  - `:ok` - Properties are valid
  - `{:error, reason}` - Properties are invalid
  """
  @spec validate_properties(map()) :: :ok | {:error, String.t()}
  def validate_properties(props) when is_map(props) do
    with :ok <- validate_tier(props),
         :ok <- validate_rate_limit(props),
         :ok <- validate_timeout(props),
         :ok <- validate_consent(props) do
      :ok
    end
  end

  def validate_properties(_), do: {:error, "security_properties must return a map"}

  defp validate_tier(%{tier: tier}) when tier in [:read_only, :write, :execute, :privileged],
    do: :ok

  defp validate_tier(%{tier: tier}), do: {:error, "invalid tier: #{inspect(tier)}"}
  defp validate_tier(_), do: {:error, "tier is required"}

  defp validate_rate_limit(%{rate_limit: {count, window}})
       when is_integer(count) and count > 0 and is_integer(window) and window > 0,
       do: :ok

  defp validate_rate_limit(%{rate_limit: invalid}),
    do: {:error, "rate_limit must be {pos_integer, pos_integer}, got: #{inspect(invalid)}"}

  defp validate_rate_limit(_), do: :ok

  defp validate_timeout(%{timeout_ms: timeout}) when is_integer(timeout) and timeout > 0, do: :ok

  defp validate_timeout(%{timeout_ms: invalid}),
    do: {:error, "timeout_ms must be a positive integer, got: #{inspect(invalid)}"}

  defp validate_timeout(_), do: :ok

  defp validate_consent(%{requires_consent: consent}) when is_boolean(consent), do: :ok

  defp validate_consent(%{requires_consent: invalid}),
    do: {:error, "requires_consent must be a boolean, got: #{inspect(invalid)}"}

  defp validate_consent(_), do: :ok

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour JidoCode.Tools.Behaviours.SecureHandler

      @before_compile JidoCode.Tools.Behaviours.SecureHandler

      @doc false
      def validate_security(_args, _context), do: :ok

      @doc false
      def sanitize_output(result), do: result

      defoverridable validate_security: 2, sanitize_output: 1
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    module = env.module

    quote do
      # Emit telemetry at compile time (deferred to runtime via module attribute)
      @doc false
      def __secure_handler_loaded__ do
        props = security_properties()

        :telemetry.execute(
          [:jido_code, :security, :handler_loaded],
          %{system_time: System.system_time()},
          %{module: unquote(module), tier: props[:tier]}
        )

        :ok
      end
    end
  end
end
