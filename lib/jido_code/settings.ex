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

  @global_dir_name ".jido_code"
  @local_dir_name "jido_code"
  @settings_file "settings.json"

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
end
