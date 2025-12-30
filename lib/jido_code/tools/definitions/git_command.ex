defmodule JidoCode.Tools.Definitions.GitCommand do
  @moduledoc """
  Tool definition for git command execution.

  This module defines the git_command tool that can be registered with the
  Registry and used by the LLM agent for version control operations.

  ## Available Tools

  - `git_command` - Execute git commands with safety constraints

  ## Security

  The git_command tool enforces several security measures:
  - **Subcommand allowlist**: Only pre-approved git subcommands can be executed
  - **Destructive operation guards**: Force push, hard reset, etc. blocked by default
  - **Confirmation for modifying commands**: add, commit, merge require intent
  - **Project boundary enforcement**: Commands run in session's project directory

  ## Subcommand Categories

  ### Always Allowed (read-only)
  - status, diff, log, show, branch, remote, tag, stash list, rev-parse,
    describe, shortlog, config (read-only)

  ### Allowed with Confirmation (modifying)
  - add, commit, checkout, merge, rebase, stash push/pop/drop, cherry-pick,
    reset (soft/mixed), revert, fetch, pull, push (non-force)

  ### Blocked by Default (destructive)
  - push --force, push -f, reset --hard, clean -fd, clean -f

  ## Usage

      # Register the git tool
      :ok = Registry.register(GitCommand.git_command())

      # Or register all tools from this module
      for tool <- GitCommand.all() do
        :ok = Registry.register(tool)
      end
  """

  alias JidoCode.Tools.Tool

  # Git subcommands that are always allowed (read-only operations)
  @always_allowed_subcommands ~w(
    status
    diff
    log
    show
    branch
    remote
    tag
    rev-parse
    describe
    shortlog
    ls-files
    ls-tree
    cat-file
    blame
    reflog
  )

  # Git subcommands that modify state but are generally safe with confirmation
  @modifying_subcommands ~w(
    add
    commit
    checkout
    switch
    merge
    rebase
    stash
    cherry-pick
    reset
    revert
    fetch
    pull
    push
    restore
    rm
    mv
    init
    clone
    worktree
    submodule
    notes
    bisect
    apply
    am
    clean
  )

  # Combinations that are blocked by default (destructive)
  # These require allow_destructive: true to execute
  @destructive_patterns [
    # Force push variants
    {"push", ["--force"]},
    {"push", ["-f"]},
    {"push", ["--force-with-lease"]},
    # Hard reset
    {"reset", ["--hard"]},
    # Clean with force
    {"clean", ["-f"]},
    {"clean", ["-fd"]},
    {"clean", ["-fx"]},
    {"clean", ["-fxd"]},
    # Branch deletion with force
    {"branch", ["-D"]},
    {"branch", ["--delete", "--force"]}
  ]

  @doc """
  Returns the list of always-allowed (read-only) git subcommands.
  """
  @spec always_allowed_subcommands() :: [String.t()]
  def always_allowed_subcommands, do: @always_allowed_subcommands

  @doc """
  Returns the list of modifying git subcommands that require confirmation.
  """
  @spec modifying_subcommands() :: [String.t()]
  def modifying_subcommands, do: @modifying_subcommands

  @doc """
  Returns all allowed git subcommands (read-only + modifying).
  """
  @spec allowed_subcommands() :: [String.t()]
  def allowed_subcommands, do: @always_allowed_subcommands ++ @modifying_subcommands

  @doc """
  Returns the list of destructive patterns that are blocked by default.

  Each pattern is a tuple of {subcommand, args_containing_pattern}.
  """
  @spec destructive_patterns() :: [{String.t(), [String.t()]}]
  def destructive_patterns, do: @destructive_patterns

  @doc """
  Checks if a subcommand is allowed.

  ## Examples

      iex> GitCommand.subcommand_allowed?("status")
      true

      iex> GitCommand.subcommand_allowed?("gc")
      false
  """
  @spec subcommand_allowed?(String.t()) :: boolean()
  def subcommand_allowed?(subcommand) when is_binary(subcommand) do
    subcommand in allowed_subcommands()
  end

  @doc """
  Checks if a command with given args matches a destructive pattern.

  For patterns with multiple args (like `["--delete", "--force"]`), ALL
  pattern args must be present in the command args for a match.

  ## Examples

      iex> GitCommand.destructive?("push", ["--force", "origin", "main"])
      true

      iex> GitCommand.destructive?("push", ["origin", "main"])
      false

      iex> GitCommand.destructive?("reset", ["--hard", "HEAD~1"])
      true

      iex> GitCommand.destructive?("branch", ["--delete", "feature"])
      false

      iex> GitCommand.destructive?("branch", ["--delete", "--force", "feature"])
      true
  """
  @spec destructive?(String.t(), [String.t()]) :: boolean()
  def destructive?(subcommand, args) when is_binary(subcommand) and is_list(args) do
    Enum.any?(@destructive_patterns, fn {pattern_cmd, pattern_args} ->
      subcommand == pattern_cmd and pattern_matches?(pattern_args, args)
    end)
  end

  # Checks if ALL pattern args are present in the command args
  defp pattern_matches?(pattern_args, args) do
    Enum.all?(pattern_args, fn pattern_arg ->
      Enum.any?(args, fn arg ->
        String.starts_with?(arg, pattern_arg)
      end)
    end)
  end

  @doc """
  Returns all git tools.

  ## Returns

  List of `%Tool{}` structs ready for registration.
  """
  @spec all() :: [Tool.t()]
  def all do
    [
      git_command()
    ]
  end

  @doc """
  Returns the git_command tool definition.

  Executes git commands in the project directory with security validation.
  Read-only commands (status, diff, log, etc.) are always allowed. Modifying
  commands (add, commit, push, etc.) are allowed with normal usage. Destructive
  operations (force push, hard reset) are blocked unless explicitly allowed.

  ## Parameters

  - `subcommand` (required, string) - Git subcommand to execute (status, diff, log, etc.)
  - `args` (optional, array) - Additional arguments for the subcommand
  - `allow_destructive` (optional, boolean) - Allow destructive operations like force push (default: false)

  ## Subcommand Categories

  **Always Allowed (read-only):**
  status, diff, log, show, branch, remote, tag, stash list, rev-parse,
  describe, shortlog, ls-files, ls-tree, cat-file, blame, reflog

  **Allowed (modifying):**
  add, commit, checkout, switch, merge, rebase, stash, cherry-pick,
  reset (soft/mixed), revert, fetch, pull, push, restore, rm, mv, init

  **Blocked by Default (destructive):**
  push --force, push -f, reset --hard, clean -f/-fd, branch -D

  ## Output

  Returns JSON with:
  - `output` - Raw command output
  - `parsed` - Structured data for some commands (status, diff, log)
  - `exit_code` - Exit code of the command

  ## Examples

      # Check repository status
      %{"subcommand" => "status"}

      # View recent commits
      %{"subcommand" => "log", "args" => ["-5", "--oneline"]}

      # Stage files
      %{"subcommand" => "add", "args" => ["lib/my_module.ex"]}

      # Force push (requires explicit permission)
      %{"subcommand" => "push", "args" => ["--force"], "allow_destructive" => true}
  """
  @spec git_command() :: Tool.t()
  def git_command do
    Tool.new!(%{
      name: "git_command",
      description:
        "Execute git command in the project directory. " <>
          "Read-only commands (status, diff, log, show, branch) are always allowed. " <>
          "Modifying commands (add, commit, push, merge) are allowed for normal usage. " <>
          "Destructive operations (push --force, reset --hard, clean -f) are blocked " <>
          "unless allow_destructive is set to true.",
      handler: JidoCode.Tools.Handlers.Git.Command,
      parameters: [
        %{
          name: "subcommand",
          type: :string,
          description:
            "Git subcommand to execute (e.g., 'status', 'diff', 'log', 'add', 'commit'). " <>
              "See documentation for full list of allowed subcommands.",
          required: true
        },
        %{
          name: "args",
          type: :array,
          description:
            "Additional arguments for the git subcommand (e.g., ['-5', '--oneline'] for log, " <>
              "['lib/module.ex'] for add). Path traversal (..) is blocked.",
          required: false
        },
        %{
          name: "allow_destructive",
          type: :boolean,
          description:
            "Allow destructive operations like force push, hard reset, or clean. " <>
              "Default: false. Set to true only when the user explicitly requests it.",
          required: false
        }
      ]
    })
  end
end
