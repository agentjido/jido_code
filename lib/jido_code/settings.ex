defmodule JidoCode.Settings do
  @moduledoc """
  Two-level JSON configuration system for JidoCode.

  Settings are stored in two locations:
  - **Global**: `~/.jido_code/settings.json` - applies to all projects
  - **Local**: `./jido_code/settings.json` - project-specific overrides

  ## Settings Schema

  ```json
  {
    "provider": "anthropic",
    "model": "claude-3-5-sonnet",
    "providers": ["anthropic", "openai", "openrouter"],
    "models": {
      "anthropic": ["claude-3-5-sonnet", "claude-3-opus"],
      "openai": ["gpt-4o", "gpt-4-turbo"]
    }
  }
  ```

  All keys are optional. Local settings override global settings.

  ## Usage

      # Load merged settings (cached)
      JidoCode.Settings.load()
      #=> {:ok, %{"provider" => "anthropic", "model" => "gpt-4o"}}

      # Get individual values
      JidoCode.Settings.get("provider")
      #=> "anthropic"

      JidoCode.Settings.get("missing", "default")
      #=> "default"

      # Force reload from disk
      JidoCode.Settings.reload()
      #=> {:ok, %{...}}

      # Get paths
      JidoCode.Settings.global_path()
      #=> "/home/user/.jido_code/settings.json"

      JidoCode.Settings.local_path()
      #=> "/path/to/project/jido_code/settings.json"

      # Validate settings
      JidoCode.Settings.validate(%{"provider" => "anthropic"})
      #=> {:ok, %{"provider" => "anthropic"}}

      # Ensure directories exist
      JidoCode.Settings.ensure_global_dir()
      #=> :ok
  """

  require Logger

  @global_dir_name ".jido_code"
  @local_dir_name "jido_code"
  @settings_file "settings.json"
  @cache_table :jido_code_settings_cache
  @cache_key :settings

  # Valid top-level keys and their expected types
  @valid_keys %{
    "provider" => :string,
    "model" => :string,
    "providers" => :list_of_strings,
    "models" => :map_of_string_lists
  }

  # ============================================================================
  # Path Helpers
  # ============================================================================

  @doc """
  Returns the global settings directory path.

  ## Example

      iex> JidoCode.Settings.global_dir()
      "/home/user/.jido_code"
  """
  @spec global_dir() :: String.t()
  def global_dir do
    Path.join(System.user_home!(), @global_dir_name)
  end

  @doc """
  Returns the global settings file path.

  ## Example

      iex> JidoCode.Settings.global_path()
      "/home/user/.jido_code/settings.json"
  """
  @spec global_path() :: String.t()
  def global_path do
    Path.join(global_dir(), @settings_file)
  end

  @doc """
  Returns the local settings directory path (relative to current working directory).

  ## Example

      iex> JidoCode.Settings.local_dir()
      "/path/to/project/jido_code"
  """
  @spec local_dir() :: String.t()
  def local_dir do
    Path.join(File.cwd!(), @local_dir_name)
  end

  @doc """
  Returns the local settings file path.

  ## Example

      iex> JidoCode.Settings.local_path()
      "/path/to/project/jido_code/settings.json"
  """
  @spec local_path() :: String.t()
  def local_path do
    Path.join(local_dir(), @settings_file)
  end

  # ============================================================================
  # Schema Validation
  # ============================================================================

  @doc """
  Validates a settings map against the expected schema.

  All keys are optional. Returns `{:ok, settings}` if valid,
  or `{:error, reason}` if invalid.

  ## Valid Keys

  - `"provider"` - String, the LLM provider name
  - `"model"` - String, the model identifier
  - `"providers"` - List of strings, allowed provider names
  - `"models"` - Map of provider name to list of model strings

  ## Examples

      iex> JidoCode.Settings.validate(%{"provider" => "anthropic"})
      {:ok, %{"provider" => "anthropic"}}

      iex> JidoCode.Settings.validate(%{"provider" => 123})
      {:error, "provider must be a string, got: 123"}

      iex> JidoCode.Settings.validate(%{"unknown_key" => "value"})
      {:error, "unknown key: unknown_key"}
  """
  @spec validate(map()) :: {:ok, map()} | {:error, String.t()}
  def validate(settings) when is_map(settings) do
    case validate_keys(settings) do
      :ok -> {:ok, settings}
      {:error, _} = error -> error
    end
  end

  def validate(other) do
    {:error, "settings must be a map, got: #{inspect(other)}"}
  end

  defp validate_keys(settings) do
    Enum.reduce_while(settings, :ok, fn {key, value}, :ok ->
      case validate_key(key, value) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp validate_key(key, value) do
    case Map.get(@valid_keys, key) do
      nil -> {:error, "unknown key: #{key}"}
      expected_type -> validate_type(key, value, expected_type)
    end
  end

  defp validate_type(_key, value, :string) when is_binary(value), do: :ok

  defp validate_type(key, value, :string) do
    {:error, "#{key} must be a string, got: #{inspect(value)}"}
  end

  defp validate_type(key, value, :list_of_strings) when is_list(value) do
    if Enum.all?(value, &is_binary/1) do
      :ok
    else
      {:error, "#{key} must be a list of strings, got: #{inspect(value)}"}
    end
  end

  defp validate_type(key, value, :list_of_strings) do
    {:error, "#{key} must be a list of strings, got: #{inspect(value)}"}
  end

  defp validate_type(key, value, :map_of_string_lists) when is_map(value) do
    invalid =
      Enum.find(value, fn {k, v} ->
        not is_binary(k) or not is_list(v) or not Enum.all?(v, &is_binary/1)
      end)

    case invalid do
      nil -> :ok
      {k, v} -> {:error, "#{key}[#{inspect(k)}] must be a list of strings, got: #{inspect(v)}"}
    end
  end

  defp validate_type(key, value, :map_of_string_lists) do
    {:error, "#{key} must be a map of string lists, got: #{inspect(value)}"}
  end

  # ============================================================================
  # Directory Management
  # ============================================================================

  @doc """
  Ensures the global settings directory exists.

  Creates `~/.jido_code/` if it doesn't exist.

  ## Returns

  - `:ok` - Directory exists or was created
  - `{:error, reason}` - Failed to create directory

  ## Example

      iex> JidoCode.Settings.ensure_global_dir()
      :ok
  """
  @spec ensure_global_dir() :: :ok | {:error, term()}
  def ensure_global_dir do
    ensure_dir(global_dir())
  end

  @doc """
  Ensures the local settings directory exists.

  Creates `./jido_code/` if it doesn't exist.

  ## Returns

  - `:ok` - Directory exists or was created
  - `{:error, reason}` - Failed to create directory

  ## Example

      iex> JidoCode.Settings.ensure_local_dir()
      :ok
  """
  @spec ensure_local_dir() :: :ok | {:error, term()}
  def ensure_local_dir do
    ensure_dir(local_dir())
  end

  defp ensure_dir(path) do
    case File.mkdir_p(path) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ============================================================================
  # File Reading
  # ============================================================================

  @doc """
  Reads and parses a settings JSON file.

  ## Returns

  - `{:ok, map}` - Successfully read and parsed
  - `{:error, :not_found}` - File does not exist
  - `{:error, {:invalid_json, reason}}` - File exists but contains invalid JSON

  ## Example

      iex> JidoCode.Settings.read_file("/path/to/settings.json")
      {:ok, %{"provider" => "anthropic"}}

      iex> JidoCode.Settings.read_file("/nonexistent/path.json")
      {:error, :not_found}
  """
  @spec read_file(String.t()) :: {:ok, map()} | {:error, :not_found | {:invalid_json, term()}}
  def read_file(path) do
    case File.read(path) do
      {:ok, content} -> parse_json(content)
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_json(content) do
    case Jason.decode(content) do
      {:ok, data} when is_map(data) -> {:ok, data}
      {:ok, data} -> {:error, {:invalid_json, "expected object, got: #{inspect(data)}"}}
      {:error, %Jason.DecodeError{} = error} -> {:error, {:invalid_json, Exception.message(error)}}
    end
  end

  # ============================================================================
  # Settings Loading and Caching
  # ============================================================================

  @doc """
  Loads and merges settings from global and local files.

  Settings are loaded with the following precedence (highest to lowest):
  1. Local settings (`./jido_code/settings.json`)
  2. Global settings (`~/.jido_code/settings.json`)

  Results are cached in memory. Use `reload/0` to force a fresh load.

  ## Returns

  - `{:ok, merged_settings}` - Successfully loaded and merged settings

  ## Error Handling

  - Missing files are treated as empty (no error)
  - Malformed JSON logs a warning and is treated as empty
  - Always returns `{:ok, map}`, never fails

  ## Examples

      iex> JidoCode.Settings.load()
      {:ok, %{"provider" => "anthropic", "model" => "gpt-4o"}}
  """
  @spec load() :: {:ok, map()}
  def load do
    case get_cached() do
      {:ok, settings} ->
        {:ok, settings}

      :miss ->
        settings = load_and_merge()
        put_cached(settings)
        {:ok, settings}
    end
  end

  @doc """
  Clears the settings cache and reloads from disk.

  ## Returns

  - `{:ok, merged_settings}` - Freshly loaded settings

  ## Example

      iex> JidoCode.Settings.reload()
      {:ok, %{"provider" => "anthropic"}}
  """
  @spec reload() :: {:ok, map()}
  def reload do
    clear_cache()
    load()
  end

  @doc """
  Gets a single setting value by key.

  Loads settings from cache (or disk on first access).

  ## Returns

  - The value if present
  - `nil` if the key doesn't exist

  ## Examples

      iex> JidoCode.Settings.get("provider")
      "anthropic"

      iex> JidoCode.Settings.get("nonexistent")
      nil
  """
  @spec get(String.t()) :: term() | nil
  def get(key) when is_binary(key) do
    {:ok, settings} = load()
    Map.get(settings, key)
  end

  @doc """
  Gets a single setting value by key, with a default.

  Loads settings from cache (or disk on first access).

  ## Returns

  - The value if present
  - The default value if the key doesn't exist

  ## Examples

      iex> JidoCode.Settings.get("provider", "openai")
      "anthropic"

      iex> JidoCode.Settings.get("nonexistent", "default")
      "default"
  """
  @spec get(String.t(), term()) :: term()
  def get(key, default) when is_binary(key) do
    {:ok, settings} = load()
    Map.get(settings, key, default)
  end

  @doc """
  Clears the settings cache.

  The next call to `load/0` or `get/1` will read from disk.

  ## Example

      iex> JidoCode.Settings.clear_cache()
      :ok
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    ensure_cache_table()

    :ets.delete(@cache_table, @cache_key)
    :ok
  end

  # ============================================================================
  # Private: Cache Management
  # ============================================================================

  defp ensure_cache_table do
    case :ets.whereis(@cache_table) do
      :undefined ->
        :ets.new(@cache_table, [:set, :public, :named_table])

      _tid ->
        :ok
    end
  end

  defp get_cached do
    ensure_cache_table()

    case :ets.lookup(@cache_table, @cache_key) do
      [{@cache_key, settings}] -> {:ok, settings}
      [] -> :miss
    end
  end

  defp put_cached(settings) do
    ensure_cache_table()
    :ets.insert(@cache_table, {@cache_key, settings})
    :ok
  end

  # ============================================================================
  # Private: Loading and Merging
  # ============================================================================

  defp load_and_merge do
    global = load_settings_file(global_path(), "global")
    local = load_settings_file(local_path(), "local")

    deep_merge(global, local)
  end

  defp load_settings_file(path, label) do
    case read_file(path) do
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

  defp deep_merge(base, overlay) do
    Map.merge(base, overlay, fn
      # Deep merge the "models" key (map of provider -> model list)
      "models", base_models, overlay_models when is_map(base_models) and is_map(overlay_models) ->
        Map.merge(base_models, overlay_models)

      # For all other keys, overlay wins
      _key, _base_value, overlay_value ->
        overlay_value
    end)
  end
end
