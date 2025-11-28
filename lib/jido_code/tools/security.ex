defmodule JidoCode.Tools.Security do
  @moduledoc """
  Security boundary enforcement for tool operations.

  This module provides path validation to ensure file operations stay within
  the project boundary. It is used by bridge functions to validate paths
  before performing any file system operations.

  ## Security Checks

  - **Absolute paths**: Must start with project root
  - **Relative paths**: Resolved relative to project root
  - **Path traversal**: `..` sequences resolved and validated
  - **Symlinks**: Followed and validated against boundary

  ## Usage

      # Validate a path
      {:ok, safe_path} = Security.validate_path("src/file.ex", "/project")

      # Path traversal blocked
      {:error, :path_escapes_boundary} = Security.validate_path("../../../etc/passwd", "/project")

      # Absolute path outside project
      {:error, :path_outside_boundary} = Security.validate_path("/etc/passwd", "/project")

  ## Logging

  All security violations are logged as warnings for debugging. Set the
  `:log_violations` option to `false` to disable logging (useful in tests).
  """

  require Logger

  @type validation_error ::
          :path_escapes_boundary
          | :path_outside_boundary
          | :symlink_escapes_boundary
          | :invalid_path

  @type validate_opts :: [log_violations: boolean()]

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Validates that a path is within the project boundary.

  Resolves the path (handling `..` and symlinks) and ensures the result
  is within the project root directory.

  ## Parameters

  - `path` - The path to validate (relative or absolute)
  - `project_root` - The project root directory (must be absolute)
  - `opts` - Options:
    - `:log_violations` - Log security violations (default: true)

  ## Returns

  - `{:ok, resolved_path}` - Path is valid and resolved
  - `{:error, reason}` - Path violates security boundary

  ## Examples

      # Valid relative path
      {:ok, "/project/src/file.ex"} = validate_path("src/file.ex", "/project")

      # Valid absolute path within project
      {:ok, "/project/src/file.ex"} = validate_path("/project/src/file.ex", "/project")

      # Path traversal attack
      {:error, :path_escapes_boundary} = validate_path("../../../etc/passwd", "/project")

      # Absolute path outside project
      {:error, :path_outside_boundary} = validate_path("/etc/passwd", "/project")
  """
  @spec validate_path(String.t(), String.t(), validate_opts()) ::
          {:ok, String.t()} | {:error, validation_error()}
  def validate_path(path, project_root, opts \\ [])

  def validate_path(path, project_root, opts) when is_binary(path) and is_binary(project_root) do
    log_violations = Keyword.get(opts, :log_violations, true)

    # Normalize project root (ensure no trailing slash, expanded)
    normalized_root = normalize_path(project_root)

    # Resolve the path
    resolved =
      if Path.type(path) == :absolute do
        normalize_path(path)
      else
        # Relative path - expand relative to project root
        normalize_path(Path.join(project_root, path))
      end

    # Check if resolved path is within project boundary
    if within_boundary?(resolved, normalized_root) do
      # Check for symlinks if path exists
      check_symlinks(resolved, normalized_root, log_violations)
    else
      reason = determine_violation_reason(path)
      maybe_log_violation(reason, path, log_violations)
      {:error, reason}
    end
  end

  def validate_path(_, _, _), do: {:error, :invalid_path}

  @doc """
  Checks if a path is within the project boundary.

  This is a simpler check that doesn't follow symlinks. Use `validate_path/3`
  for full validation.

  ## Parameters

  - `path` - The resolved path to check
  - `project_root` - The project root directory

  ## Returns

  - `true` if path is within boundary
  - `false` otherwise
  """
  @spec within_boundary?(String.t(), String.t()) :: boolean()
  def within_boundary?(path, project_root) do
    normalized_path = normalize_path(path)
    normalized_root = normalize_path(project_root)

    # Path must start with project root
    # We add a trailing slash to prevent matching partial directory names
    # e.g., /project shouldn't match /project2/file
    String.starts_with?(normalized_path, normalized_root <> "/") or
      normalized_path == normalized_root
  end

  @doc """
  Resolves a path relative to the project root.

  This expands the path and resolves `..` sequences, but does not
  validate the result. Use `validate_path/3` for validation.

  ## Parameters

  - `path` - The path to resolve
  - `project_root` - The project root directory

  ## Returns

  The resolved absolute path.
  """
  @spec resolve_path(String.t(), String.t()) :: String.t()
  def resolve_path(path, project_root) do
    if Path.type(path) == :absolute do
      normalize_path(path)
    else
      normalize_path(Path.join(project_root, path))
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp determine_violation_reason(path) do
    if Path.type(path) == :absolute do
      :path_outside_boundary
    else
      :path_escapes_boundary
    end
  end

  defp maybe_log_violation(reason, path, true) do
    Logger.warning("Security violation: #{reason} - attempted path: #{path}")
  end

  defp maybe_log_violation(_reason, _path, false), do: :ok

  defp normalize_path(path) do
    # Expand to absolute path, resolving . and ..
    # Remove trailing slash for consistent comparison
    path
    |> Path.expand()
    |> String.trim_trailing("/")
  end

  defp check_symlinks(path, project_root, log_violations) do
    case resolve_symlink_chain(path, project_root, MapSet.new()) do
      {:ok, final_path} ->
        {:ok, final_path}

      {:error, :symlink_escapes_boundary} = error ->
        if log_violations do
          Logger.warning("Security violation: symlink_escapes_boundary - path: #{path}")
        end

        error

      {:error, :symlink_loop} ->
        if log_violations do
          Logger.warning("Security violation: symlink_loop - path: #{path}")
        end

        {:error, :invalid_path}
    end
  end

  defp resolve_symlink_chain(path, project_root, seen) do
    if MapSet.member?(seen, path) do
      {:error, :symlink_loop}
    else
      resolve_symlink_target(path, project_root, seen)
    end
  end

  defp resolve_symlink_target(path, project_root, seen) do
    case File.read_link(path) do
      {:ok, target} ->
        handle_symlink_target(path, target, project_root, seen)

      {:error, :einval} ->
        # Not a symlink - path is valid
        {:ok, path}

      {:error, :enoent} ->
        # Path doesn't exist - OK for paths we're about to create
        {:ok, path}

      {:error, _} ->
        # Other error - path is valid (not a symlink)
        {:ok, path}
    end
  end

  defp handle_symlink_target(path, target, project_root, seen) do
    resolved_target = resolve_symlink_path(target, path)

    if within_boundary?(resolved_target, project_root) do
      resolve_symlink_chain(resolved_target, project_root, MapSet.put(seen, path))
    else
      {:error, :symlink_escapes_boundary}
    end
  end

  defp resolve_symlink_path(target, symlink_path) do
    if Path.type(target) == :absolute do
      normalize_path(target)
    else
      # Relative symlink - resolve relative to symlink's directory
      normalize_path(Path.join(Path.dirname(symlink_path), target))
    end
  end
end
