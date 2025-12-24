defmodule JidoCode.TUI.Clipboard do
  @moduledoc """
  Cross-platform clipboard integration for the TUI.

  Detects available clipboard commands based on the operating system and provides
  functions to copy text to and paste text from the system clipboard.

  ## Supported Platforms

  - macOS: `pbcopy` / `pbpaste`
  - Linux X11: `xclip` or `xsel`
  - Linux Wayland: `wl-copy` / `wl-paste`
  - WSL/Windows: `clip.exe` / `powershell.exe Get-Clipboard`

  ## Usage

      iex> JidoCode.TUI.Clipboard.copy_to_clipboard("Hello, World!")
      :ok

      iex> JidoCode.TUI.Clipboard.paste_from_clipboard()
      {:ok, "Hello, World!"}

      iex> JidoCode.TUI.Clipboard.available?()
      true
  """

  require Logger

  # Copy commands (write to clipboard)
  @clipboard_copy_commands [
    # macOS
    {"pbcopy", []},
    # Linux Wayland
    {"wl-copy", []},
    # Linux X11 - xclip
    {"xclip", ["-selection", "clipboard"]},
    # Linux X11 - xsel
    {"xsel", ["--clipboard", "--input"]},
    # WSL/Windows
    {"clip.exe", []}
  ]

  # Paste commands (read from clipboard)
  @clipboard_paste_commands [
    # macOS
    {"pbpaste", []},
    # Linux Wayland
    {"wl-paste", ["--no-newline"]},
    # Linux X11 - xclip
    {"xclip", ["-selection", "clipboard", "-o"]},
    # Linux X11 - xsel
    {"xsel", ["--clipboard", "--output"]},
    # WSL/Windows - use PowerShell Get-Clipboard
    {"powershell.exe", ["-command", "Get-Clipboard"]}
  ]

  # Cache the detected command at compile time for performance
  # This will be re-evaluated at runtime on first call
  @detected_command :not_checked

  @doc """
  Returns the detected clipboard copy command and arguments, or nil if none available.

  The result is cached after first detection.

  ## Examples

      iex> JidoCode.TUI.Clipboard.detect_clipboard_command()
      {"pbcopy", []}

      iex> JidoCode.TUI.Clipboard.detect_clipboard_command()
      nil
  """
  @spec detect_clipboard_command() :: {String.t(), [String.t()]} | nil
  def detect_clipboard_command do
    case :persistent_term.get({__MODULE__, :clipboard_copy_command}, @detected_command) do
      :not_checked ->
        command = do_detect_command(@clipboard_copy_commands)
        :persistent_term.put({__MODULE__, :clipboard_copy_command}, command)
        command

      cached ->
        cached
    end
  end

  @doc """
  Returns the detected clipboard paste command and arguments, or nil if none available.

  The result is cached after first detection.

  ## Examples

      iex> JidoCode.TUI.Clipboard.detect_paste_command()
      {"pbpaste", []}

      iex> JidoCode.TUI.Clipboard.detect_paste_command()
      nil
  """
  @spec detect_paste_command() :: {String.t(), [String.t()]} | nil
  def detect_paste_command do
    case :persistent_term.get({__MODULE__, :clipboard_paste_command}, @detected_command) do
      :not_checked ->
        command = do_detect_command(@clipboard_paste_commands)
        :persistent_term.put({__MODULE__, :clipboard_paste_command}, command)
        command

      cached ->
        cached
    end
  end

  @doc """
  Returns true if a clipboard command is available for copying.

  ## Examples

      iex> JidoCode.TUI.Clipboard.available?()
      true
  """
  @spec available?() :: boolean()
  def available? do
    detect_clipboard_command() != nil
  end

  @doc """
  Returns true if a clipboard paste command is available.

  ## Examples

      iex> JidoCode.TUI.Clipboard.paste_available?()
      true
  """
  @spec paste_available?() :: boolean()
  def paste_available? do
    detect_paste_command() != nil
  end

  @doc """
  Copies the given text to the system clipboard.

  Returns `:ok` on success, `{:error, reason}` on failure.

  ## Examples

      iex> JidoCode.TUI.Clipboard.copy_to_clipboard("Hello!")
      :ok

      iex> JidoCode.TUI.Clipboard.copy_to_clipboard("Hello!")
      {:error, :clipboard_unavailable}
  """
  @spec copy_to_clipboard(String.t()) :: :ok | {:error, atom() | String.t()}
  def copy_to_clipboard(text) when is_binary(text) do
    case detect_clipboard_command() do
      nil ->
        Logger.warning("No clipboard command available - copy operation skipped")
        {:error, :clipboard_unavailable}

      {command, args} ->
        do_copy(command, args, text)
    end
  end

  def copy_to_clipboard(_text) do
    {:error, :invalid_text}
  end

  @doc """
  Pastes text from the system clipboard.

  Returns `{:ok, text}` on success, `{:error, reason}` on failure.

  ## Examples

      iex> JidoCode.TUI.Clipboard.paste_from_clipboard()
      {:ok, "Hello!"}

      iex> JidoCode.TUI.Clipboard.paste_from_clipboard()
      {:error, :clipboard_unavailable}
  """
  @spec paste_from_clipboard() :: {:ok, String.t()} | {:error, atom() | String.t()}
  def paste_from_clipboard do
    case detect_paste_command() do
      nil ->
        Logger.warning("No clipboard paste command available")
        {:error, :clipboard_unavailable}

      {command, args} ->
        do_paste(command, args)
    end
  end

  # Private functions

  @spec do_detect_command([{String.t(), [String.t()]}]) :: {String.t(), [String.t()]} | nil
  defp do_detect_command(commands) do
    Enum.find(commands, fn {command, _args} ->
      command_available?(command)
    end)
  end

  @spec command_available?(String.t()) :: boolean()
  defp command_available?(command) do
    case System.find_executable(command) do
      nil -> false
      _path -> true
    end
  end

  @spec do_copy(String.t(), [String.t()], String.t()) :: :ok | {:error, atom() | String.t()}
  defp do_copy(command, args, text) do
    port_opts = [
      :binary,
      :exit_status,
      :hide,
      args: args
    ]

    try do
      port = Port.open({:spawn_executable, System.find_executable(command)}, port_opts)
      Port.command(port, text)
      Port.close(port)

      # Give a small amount of time for the clipboard command to process
      receive do
        {^port, {:exit_status, 0}} -> :ok
        {^port, {:exit_status, status}} -> {:error, "exit status #{status}"}
      after
        100 ->
          # Command likely succeeded if no exit status received quickly
          :ok
      end
    rescue
      e ->
        Logger.warning("Clipboard copy failed: #{inspect(e)}")
        {:error, :copy_failed}
    end
  end

  @spec do_paste(String.t(), [String.t()]) :: {:ok, String.t()} | {:error, atom() | String.t()}
  defp do_paste(command, args) do
    case System.find_executable(command) do
      nil ->
        {:error, :command_not_found}

      executable ->
        try do
          case System.cmd(executable, args, stderr_to_stdout: true) do
            {output, 0} ->
              # Trim trailing newline that some clipboard tools add
              {:ok, String.trim_trailing(output, "\n")}

            {error, status} ->
              Logger.warning("Clipboard paste failed with status #{status}: #{error}")
              {:error, "exit status #{status}"}
          end
        rescue
          e ->
            Logger.warning("Clipboard paste failed: #{inspect(e)}")
            {:error, :paste_failed}
        end
    end
  end

  @doc """
  Clears the cached clipboard command detection.

  Useful for testing or when system state changes.
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    :persistent_term.erase({__MODULE__, :clipboard_copy_command})
    :persistent_term.erase({__MODULE__, :clipboard_paste_command})
    :ok
  rescue
    ArgumentError -> :ok
  end
end
