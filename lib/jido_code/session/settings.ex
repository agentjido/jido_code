defmodule JidoCode.Session.Settings do
  @moduledoc """
  Per-session settings loader that respects project-local configuration.

  This module provides session-scoped settings by accepting a `project_path`
  parameter, unlike `JidoCode.Settings` which uses `File.cwd!()` for the local path.

  ## Settings Paths

  - **Global**: `~/.jido_code/settings.json` (managed by `JidoCode.Settings`)
  - **Local**: `{project_path}/.jido_code/settings.json`

  ## Merge Priority

  Local settings override global settings:

  ```
  global < local
  ```

  When loading settings for a session, the global settings are loaded first,
  then local settings are merged on top, with local values taking precedence.

  ## Settings Schema

  See `JidoCode.Settings` for the full settings schema documentation.
  This module uses the same schema and validation.

  ## Usage

      # Get local settings path for a project
      Session.Settings.local_path("/path/to/project")
      #=> "/path/to/project/.jido_code/settings.json"

      # Get local settings directory for a project
      Session.Settings.local_dir("/path/to/project")
      #=> "/path/to/project/.jido_code"

  ## Related Modules

  - `JidoCode.Settings` - Global settings management and caching
  - `JidoCode.Session` - Session struct with project_path field
  - `JidoCode.Session.Manager` - Per-session manager with security sandbox
  """

  require Logger

  alias JidoCode.Settings

  @local_dir_name ".jido_code"
  @settings_file "settings.json"

  # ============================================================================
  # Settings Loading
  # ============================================================================

  @doc """
  Loads and merges settings from global and local files for a project.

  Settings are loaded with the following precedence (highest to lowest):
  1. Local settings (`{project_path}/.jido_code/settings.json`)
  2. Global settings (`~/.jido_code/settings.json`)

  ## Parameters

  - `project_path` - Absolute path to the project root

  ## Returns

  Merged settings map. Missing files are treated as empty maps.

  ## Error Handling

  - Missing files return empty map (no error)
  - Malformed JSON logs a warning and returns empty map
  - Always returns a map, never fails

  ## Examples

      iex> Session.Settings.load("/path/to/project")
      %{"provider" => "anthropic", "model" => "gpt-4o"}
  """
  @spec load(String.t()) :: map()
  def load(project_path) when is_binary(project_path) do
    global = load_global()
    local = load_local(project_path)
    Map.merge(global, local)
  end

  @doc """
  Loads settings from the global settings file.

  Reads from `~/.jido_code/settings.json`.

  ## Returns

  Settings map from the global file, or empty map if file doesn't exist
  or contains invalid JSON.

  ## Examples

      iex> Session.Settings.load_global()
      %{"provider" => "anthropic"}

      # When file doesn't exist
      iex> Session.Settings.load_global()
      %{}
  """
  @spec load_global() :: map()
  def load_global do
    load_settings_file(Settings.global_path(), "global")
  end

  @doc """
  Loads settings from a project's local settings file.

  Reads from `{project_path}/.jido_code/settings.json`.

  ## Parameters

  - `project_path` - Absolute path to the project root

  ## Returns

  Settings map from the local file, or empty map if file doesn't exist
  or contains invalid JSON.

  ## Examples

      iex> Session.Settings.load_local("/path/to/project")
      %{"model" => "gpt-4o"}

      # When file doesn't exist
      iex> Session.Settings.load_local("/tmp/no-settings")
      %{}
  """
  @spec load_local(String.t()) :: map()
  def load_local(project_path) when is_binary(project_path) do
    load_settings_file(local_path(project_path), "local")
  end

  # ============================================================================
  # Private: Settings File Loading
  # ============================================================================

  defp load_settings_file(path, label) do
    case Settings.read_file(path) do
      {:ok, settings} ->
        settings

      {:error, :not_found} ->
        %{}

      {:error, {:invalid_json, reason}} ->
        Logger.warning("Malformed JSON in #{label} settings file #{path}: #{reason}")
        %{}

      {:error, reason} ->
        Logger.warning("Failed to read #{label} settings file #{path}: #{inspect(reason)}")
        %{}
    end
  end

  # ============================================================================
  # Path Helpers
  # ============================================================================

  @doc """
  Returns the local settings directory path for a project.

  The settings directory is `{project_path}/.jido_code`.

  ## Parameters

  - `project_path` - Absolute path to the project root

  ## Returns

  The full path to the settings directory.

  ## Examples

      iex> Session.Settings.local_dir("/home/user/myproject")
      "/home/user/myproject/.jido_code"

      iex> Session.Settings.local_dir("/tmp/test")
      "/tmp/test/.jido_code"
  """
  @spec local_dir(String.t()) :: String.t()
  def local_dir(project_path) when is_binary(project_path) do
    Path.join(project_path, @local_dir_name)
  end

  @doc """
  Returns the local settings file path for a project.

  The settings file is `{project_path}/.jido_code/settings.json`.

  ## Parameters

  - `project_path` - Absolute path to the project root

  ## Returns

  The full path to the settings JSON file.

  ## Examples

      iex> Session.Settings.local_path("/home/user/myproject")
      "/home/user/myproject/.jido_code/settings.json"

      iex> Session.Settings.local_path("/tmp/test")
      "/tmp/test/.jido_code/settings.json"
  """
  @spec local_path(String.t()) :: String.t()
  def local_path(project_path) when is_binary(project_path) do
    Path.join(local_dir(project_path), @settings_file)
  end

  @doc """
  Ensures the local settings directory exists for a project.

  Creates `{project_path}/.jido_code` directory if it doesn't exist.
  Uses `File.mkdir_p/1` for recursive directory creation.

  ## Parameters

  - `project_path` - Absolute path to the project root

  ## Returns

  - `{:ok, dir_path}` - Directory exists or was created successfully
  - `{:error, reason}` - Failed to create directory

  ## Examples

      iex> Session.Settings.ensure_local_dir("/path/to/project")
      {:ok, "/path/to/project/.jido_code"}

      iex> Session.Settings.ensure_local_dir("/readonly/path")
      {:error, :eacces}
  """
  @spec ensure_local_dir(String.t()) :: {:ok, String.t()} | {:error, File.posix()}
  def ensure_local_dir(project_path) when is_binary(project_path) do
    dir = local_dir(project_path)

    case File.mkdir_p(dir) do
      :ok -> {:ok, dir}
      {:error, reason} -> {:error, reason}
    end
  end
end
