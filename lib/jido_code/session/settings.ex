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

  @local_dir_name ".jido_code"
  @settings_file "settings.json"

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
end
