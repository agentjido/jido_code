defmodule JidoCode.Tools.Security.Permissions do
  @moduledoc """
  Tool categorization and permission tier management.

  This module provides graduated access control for tools based on security tiers.
  Sessions start with `:read_only` access and can be granted higher tiers.

  ## Tier Hierarchy

  Tiers are ordered by privilege level:

  1. `:read_only` - Read-only operations (lowest privilege)
  2. `:write` - Can modify files and state
  3. `:execute` - Can run external commands
  4. `:privileged` - System-level access (highest privilege)

  ## Default Tool Mappings

  Tools are mapped to tiers based on their capabilities:

  | Tier | Tools |
  |------|-------|
  | `:read_only` | read_file, list_directory, file_info, grep, find_files, fetch_elixir_docs |
  | `:write` | write_file, edit_file, create_directory, delete_file, livebook_edit |
  | `:execute` | run_command, mix_task, run_exunit, git_command |
  | `:privileged` | get_process_state, inspect_supervisor, ets_inspect, spawn_task |

  ## Usage

      # Get a tool's required tier
      tier = Permissions.get_tool_tier("read_file")
      # => :read_only

      # Check if session can use a tool
      Permissions.check_permission("write_file", :read_only, [])
      # => {:error, {:permission_denied, ...}}

      Permissions.check_permission("write_file", :write, [])
      # => :ok
  """

  alias JidoCode.Tools.Behaviours.SecureHandler

  @default_tool_tiers %{
    # Read-only tools
    "read_file" => :read_only,
    "list_directory" => :read_only,
    "file_info" => :read_only,
    "grep" => :read_only,
    "find_files" => :read_only,
    "fetch_elixir_docs" => :read_only,
    "web_fetch" => :read_only,
    "web_search" => :read_only,
    "recall" => :read_only,
    "todo_read" => :read_only,

    # Write tools
    "write_file" => :write,
    "edit_file" => :write,
    "create_directory" => :write,
    "delete_file" => :write,
    "livebook_edit" => :write,
    "remember" => :write,
    "forget" => :write,
    "todo_write" => :write,

    # Execute tools
    "run_command" => :execute,
    "mix_task" => :execute,
    "run_exunit" => :execute,
    "git_command" => :execute,
    "lsp_request" => :execute,

    # Privileged tools
    "get_process_state" => :privileged,
    "inspect_supervisor" => :privileged,
    "ets_inspect" => :privileged,
    "spawn_task" => :privileged
  }

  @default_rate_limits %{
    read_only: {100, 60_000},
    write: {30, 60_000},
    execute: {10, 60_000},
    privileged: {5, 60_000}
  }

  @doc """
  Returns the security tier required for a tool.

  If the tool is not in the default mapping, returns `:read_only`.

  ## Examples

      iex> Permissions.get_tool_tier("read_file")
      :read_only

      iex> Permissions.get_tool_tier("run_command")
      :execute

      iex> Permissions.get_tool_tier("unknown_tool")
      :read_only
  """
  @spec get_tool_tier(String.t()) :: SecureHandler.tier()
  def get_tool_tier(tool_name) do
    Map.get(@default_tool_tiers, tool_name, :read_only)
  end

  @doc """
  Returns the default rate limit for a tier.

  ## Examples

      iex> Permissions.default_rate_limit(:read_only)
      {100, 60_000}

      iex> Permissions.default_rate_limit(:privileged)
      {5, 60_000}
  """
  @spec default_rate_limit(SecureHandler.tier()) :: {pos_integer(), pos_integer()}
  def default_rate_limit(tier) do
    Map.get(@default_rate_limits, tier, {100, 60_000})
  end

  @typedoc """
  Options for permission checking.
  """
  @type check_option :: {:emit_telemetry, boolean()}

  @doc """
  Checks if a tool can be used with the given permissions.

  ## Parameters

  - `tool_name` - Name of the tool
  - `granted_tier` - The tier granted to the session
  - `consented_tools` - List of tools the user has explicitly consented to
  - `opts` - Options:
    - `:emit_telemetry` - Whether to emit telemetry on denial (default: true)

  ## Returns

  - `:ok` - Permission granted
  - `{:error, {:permission_denied, details}}` - Insufficient permissions

  ## Telemetry

  When permission is denied and `:emit_telemetry` is true (default), emits:
  `[:jido_code, :security, :permission_denied]` with:
  - measurements: `%{}`
  - metadata: `%{tool: string, required_tier: atom, granted_tier: atom}`
  """
  @spec check_permission(String.t(), SecureHandler.tier(), [String.t()], [check_option()]) ::
          :ok | {:error, {:permission_denied, map()}}
  def check_permission(tool_name, granted_tier, consented_tools \\ [], opts \\ []) do
    required_tier = get_tool_tier(tool_name)

    cond do
      # Explicit consent overrides tier requirements
      tool_name in consented_tools ->
        :ok

      # Check tier hierarchy
      SecureHandler.tier_allowed?(required_tier, granted_tier) ->
        :ok

      true ->
        details = %{
          tool: tool_name,
          required_tier: required_tier,
          granted_tier: granted_tier
        }

        maybe_emit_permission_denied_telemetry(details, opts)

        {:error, {:permission_denied, details}}
    end
  end

  @doc """
  Returns all tools mapped to a specific tier.

  ## Examples

      iex> Permissions.tools_for_tier(:read_only)
      ["read_file", "list_directory", ...]
  """
  @spec tools_for_tier(SecureHandler.tier()) :: [String.t()]
  def tools_for_tier(tier) do
    @default_tool_tiers
    |> Enum.filter(fn {_name, t} -> t == tier end)
    |> Enum.map(fn {name, _t} -> name end)
    |> Enum.sort()
  end

  @doc """
  Returns all default tool tier mappings.
  """
  @spec all_tool_tiers() :: %{String.t() => SecureHandler.tier()}
  def all_tool_tiers do
    @default_tool_tiers
  end

  @doc """
  Returns all default rate limits by tier.
  """
  @spec all_rate_limits() :: %{SecureHandler.tier() => {pos_integer(), pos_integer()}}
  def all_rate_limits do
    @default_rate_limits
  end

  @doc """
  Upgrades a session's permission tier.

  This function validates that the new tier is valid and returns the upgraded tier.
  The actual session state update should be performed by the caller.

  ## Parameters

  - `current_tier` - The current tier of the session
  - `new_tier` - The tier to upgrade to

  ## Returns

  - `{:ok, new_tier}` - Upgrade successful
  - `{:error, :invalid_tier}` - The requested tier is not valid
  - `{:error, :tier_downgrade}` - Cannot downgrade to a lower tier

  ## Examples

      iex> Permissions.grant_tier(:read_only, :write)
      {:ok, :write}

      iex> Permissions.grant_tier(:execute, :read_only)
      {:error, :tier_downgrade}
  """
  @spec grant_tier(SecureHandler.tier(), SecureHandler.tier()) ::
          {:ok, SecureHandler.tier()} | {:error, :invalid_tier | :tier_downgrade}
  def grant_tier(current_tier, new_tier) do
    valid_tiers = [:read_only, :write, :execute, :privileged]

    cond do
      new_tier not in valid_tiers ->
        {:error, :invalid_tier}

      tier_level(new_tier) < tier_level(current_tier) ->
        {:error, :tier_downgrade}

      true ->
        {:ok, new_tier}
    end
  end

  @doc """
  Records explicit consent for a tool.

  This function validates the tool name and returns the updated consent list.
  The actual session state update should be performed by the caller.

  ## Parameters

  - `consented_tools` - Current list of consented tools
  - `tool_name` - Tool to add consent for

  ## Returns

  - `{:ok, updated_list}` - Consent recorded
  - `{:error, :already_consented}` - Tool already in consent list

  ## Examples

      iex> Permissions.record_consent([], "run_command")
      {:ok, ["run_command"]}

      iex> Permissions.record_consent(["run_command"], "run_command")
      {:error, :already_consented}
  """
  @spec record_consent([String.t()], String.t()) ::
          {:ok, [String.t()]} | {:error, :already_consented}
  def record_consent(consented_tools, tool_name) do
    if tool_name in consented_tools do
      {:error, :already_consented}
    else
      {:ok, [tool_name | consented_tools]}
    end
  end

  @doc """
  Revokes consent for a tool.

  ## Parameters

  - `consented_tools` - Current list of consented tools
  - `tool_name` - Tool to revoke consent for

  ## Returns

  - `{:ok, updated_list}` - Consent revoked
  - `{:error, :not_consented}` - Tool was not in consent list

  ## Examples

      iex> Permissions.revoke_consent(["run_command"], "run_command")
      {:ok, []}

      iex> Permissions.revoke_consent([], "run_command")
      {:error, :not_consented}
  """
  @spec revoke_consent([String.t()], String.t()) ::
          {:ok, [String.t()]} | {:error, :not_consented}
  def revoke_consent(consented_tools, tool_name) do
    if tool_name in consented_tools do
      {:ok, List.delete(consented_tools, tool_name)}
    else
      {:error, :not_consented}
    end
  end

  @doc """
  Returns the numeric level for a tier (higher = more privileged).
  """
  @spec tier_level(SecureHandler.tier()) :: non_neg_integer()
  def tier_level(:read_only), do: 0
  def tier_level(:write), do: 1
  def tier_level(:execute), do: 2
  def tier_level(:privileged), do: 3
  def tier_level(_), do: 0

  @doc """
  Returns the list of all valid tiers in order of privilege.
  """
  @spec valid_tiers() :: [SecureHandler.tier()]
  def valid_tiers do
    [:read_only, :write, :execute, :privileged]
  end

  @doc """
  Checks if a tier is valid.
  """
  @spec valid_tier?(atom()) :: boolean()
  def valid_tier?(tier) do
    tier in valid_tiers()
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp maybe_emit_permission_denied_telemetry(details, opts) do
    emit_telemetry = Keyword.get(opts, :emit_telemetry, true)

    if emit_telemetry do
      :telemetry.execute(
        [:jido_code, :security, :permission_denied],
        %{},
        details
      )
    end
  end
end
