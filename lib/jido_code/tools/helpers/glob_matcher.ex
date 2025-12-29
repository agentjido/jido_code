defmodule JidoCode.Tools.Helpers.GlobMatcher do
  @moduledoc """
  Shared glob pattern matching utilities for file listing tools.

  This module provides glob pattern matching functionality used by both
  the ListDir handler and the lua_list_dir bridge function, eliminating
  code duplication and ensuring consistent behavior.

  ## Supported Glob Patterns

  - `*` - Match any sequence of characters (except path separator)
  - `?` - Match any single character
  - Literal characters are matched exactly

  ## Limitations

  The following advanced glob features are NOT supported:
  - `**` for recursive directory matching (treated as `*`)
  - `[abc]` character classes
  - `{a,b}` brace expansion
  - `!pattern` negation

  ## Security

  All regex metacharacters are properly escaped to prevent regex injection
  attacks. Invalid patterns are logged and treated as non-matching.

  ## See Also

  - `JidoCode.Tools.Handlers.FileSystem.ListDir` - Handler using this module
  - `JidoCode.Tools.Bridge.lua_list_dir/3` - Bridge function using this module
  """

  require Logger

  @doc """
  Checks if an entry matches any of the provided ignore patterns.

  Returns `true` if the entry matches at least one pattern, `false` otherwise.
  An empty pattern list always returns `false`.

  ## Examples

      iex> GlobMatcher.matches_any?("test.log", ["*.log", "*.tmp"])
      true

      iex> GlobMatcher.matches_any?("readme.md", ["*.log"])
      false

      iex> GlobMatcher.matches_any?("file.txt", [])
      false

  """
  @spec matches_any?(String.t(), list(String.t())) :: boolean()
  def matches_any?(_entry, []), do: false

  def matches_any?(entry, patterns) when is_binary(entry) and is_list(patterns) do
    Enum.any?(patterns, &matches_glob?(entry, &1))
  end

  def matches_any?(_entry, _patterns), do: false

  @doc """
  Checks if an entry matches a single glob pattern.

  Converts the glob pattern to a regex and tests for a match.
  Invalid patterns log a warning and return `false`.

  ## Examples

      iex> GlobMatcher.matches_glob?("test.log", "*.log")
      true

      iex> GlobMatcher.matches_glob?("config.json", "config.???")
      false

      iex> GlobMatcher.matches_glob?("config.json", "config.????")
      true

  """
  @spec matches_glob?(String.t(), String.t()) :: boolean()
  def matches_glob?(entry, pattern) when is_binary(entry) and is_binary(pattern) do
    regex_pattern = glob_to_regex(pattern)

    case Regex.compile("^#{regex_pattern}$") do
      {:ok, regex} ->
        Regex.match?(regex, entry)

      {:error, reason} ->
        Logger.warning("Invalid glob pattern #{inspect(pattern)}: #{inspect(reason)}")
        false
    end
  end

  def matches_glob?(_entry, _pattern), do: false

  @doc """
  Sorts entries with directories first, then alphabetically within each group.

  ## Examples

      iex> GlobMatcher.sort_directories_first(["file.txt", "dir", "another.md"], "/path")
      ["dir", "another.md", "file.txt"]  # assuming "dir" is a directory

  """
  @spec sort_directories_first(list(String.t()), String.t()) :: list(String.t())
  def sort_directories_first(entries, parent_path) when is_list(entries) and is_binary(parent_path) do
    Enum.sort_by(entries, fn entry ->
      full_path = Path.join(parent_path, entry)
      is_dir = File.dir?(full_path)
      # Directories first (false < true when negated), then alphabetically
      {not is_dir, entry}
    end)
  end

  @doc """
  Returns information about a directory entry.

  ## Examples

      iex> GlobMatcher.entry_info("/path/to/dir", "subdir")
      %{name: "subdir", type: "directory"}

      iex> GlobMatcher.entry_info("/path/to/dir", "file.txt")
      %{name: "file.txt", type: "file"}

  """
  @spec entry_info(String.t(), String.t()) :: %{name: String.t(), type: String.t()}
  def entry_info(parent_path, entry) when is_binary(parent_path) and is_binary(entry) do
    full_path = Path.join(parent_path, entry)
    type = if File.dir?(full_path), do: "directory", else: "file"
    %{name: entry, type: type}
  end

  # Private: Convert glob pattern to regex pattern with proper escaping
  @spec glob_to_regex(String.t()) :: String.t()
  defp glob_to_regex(pattern) do
    pattern
    # Escape all regex metacharacters except * and ?
    |> escape_regex_metacharacters()
    # Convert glob wildcards to regex equivalents
    |> String.replace("\\*", ".*")
    |> String.replace("\\?", ".")
  end

  # Escape all regex metacharacters using Regex.escape, then restore * and ?
  @spec escape_regex_metacharacters(String.t()) :: String.t()
  defp escape_regex_metacharacters(pattern) do
    # Use Regex.escape to escape all metacharacters properly
    escaped = Regex.escape(pattern)
    # Regex.escape converts * to \* and ? to \?, which we want for now
    # We'll convert them back to regex wildcards in glob_to_regex
    escaped
  end
end
