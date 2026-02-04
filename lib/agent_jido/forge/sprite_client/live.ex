defmodule AgentJido.Forge.SpriteClient.Live do
  @moduledoc """
  Live sprite client implementation using the real Sprites SDK.

  Connects to the Sprites API to create and manage remote containers.

  ## Configuration

  Requires `SPRITES_TOKEN` environment variable to be set with a valid API token.

  Optional configuration via application env:

      config :agent_jido, AgentJido.Forge.SpriteClient.Live,
        base_url: "https://api.sprites.dev"
  """

  @behaviour AgentJido.Forge.SpriteClient.Behaviour

  require Logger

  @impl true
  def impl_module, do: __MODULE__

  defstruct [:sprites_client, :sprite, :sprite_id, :fs]

  @type t :: %__MODULE__{
          sprites_client: Sprites.client(),
          sprite: Sprites.sprite(),
          sprite_id: String.t(),
          fs: Sprites.Filesystem.t() | nil
        }

  @impl true
  def create(spec) do
    token = get_token()

    if is_nil(token) or token == "" do
      {:error, :missing_sprites_token}
    else
      do_create(token, spec)
    end
  end

  defp do_create(token, spec) do
    base_url = get_base_url()
    opts = if base_url, do: [base_url: base_url], else: []

    sprites_client = Sprites.new(token, opts)
    sprite_id = generate_sprite_id()
    sprite_name = Map.get(spec, :name, "forge-#{sprite_id}")

    Logger.debug("Creating live sprite: #{sprite_name}")

    case Sprites.create(sprites_client, sprite_name, config: Map.get(spec, :config, %{})) do
      {:ok, sprite} ->
        fs = Sprites.filesystem(sprite, "/")

        client = %__MODULE__{
          sprites_client: sprites_client,
          sprite: sprite,
          sprite_id: sprite_id,
          fs: fs
        }

        Logger.info("Created live sprite #{sprite_name} (id: #{sprite_id})")
        {:ok, client, sprite_id}

      {:error, reason} ->
        Logger.error("Failed to create sprite: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def exec(%__MODULE__{sprite: sprite} = _client, command, opts) do
    timeout = Keyword.get(opts, :timeout, :infinity)
    dir = Keyword.get(opts, :dir)

    cmd_opts =
      []
      |> maybe_add_opt(:dir, dir)
      |> maybe_add_timeout(timeout)

    wrapped_command = "if [ -f /tmp/forge_env.sh ]; then source /tmp/forge_env.sh; fi; #{command}"

    {output, exit_code} = Sprites.cmd(sprite, "bash", ["-c", wrapped_command], cmd_opts)
    {output, exit_code}
  end

  @impl true
  def spawn(%__MODULE__{sprite: sprite} = _client, command, args, opts) do
    Sprites.spawn(sprite, command, args, opts)
  end

  @impl true
  def write_file(%__MODULE__{sprite: sprite} = _client, path, content) do
    encoded = Base.encode64(content)
    dir = Path.dirname(path)

    {_, mkdir_code} = Sprites.cmd(sprite, "mkdir", ["-p", dir])

    if mkdir_code != 0 do
      {:error, {:mkdir_failed, dir}}
    else
      {output, exit_code} =
        Sprites.cmd(sprite, "bash", ["-c", "echo '#{encoded}' | base64 -d > '#{path}'"])

      if exit_code == 0 do
        :ok
      else
        {:error, {:write_failed, output, exit_code}}
      end
    end
  end

  @impl true
  def read_file(%__MODULE__{sprite: sprite} = _client, path) do
    {output, exit_code} = Sprites.cmd(sprite, "cat", [path])

    if exit_code == 0 do
      {:ok, output}
    else
      {:error, {:read_failed, output, exit_code}}
    end
  end

  @impl true
  def inject_env(%__MODULE__{} = _client, env_map) when map_size(env_map) == 0 do
    :ok
  end

  def inject_env(%__MODULE__{sprite: sprite} = _client, env_map) do
    env_lines =
      Enum.map_join(env_map, "\n", fn {k, v} -> "export #{k}=\"#{escape_value(v)}\"" end)

    encoded = Base.encode64(env_lines <> "\n")

    {_, exit_code} =
      Sprites.cmd(sprite, "bash", ["-c", "echo '#{encoded}' | base64 -d >> /tmp/forge_env.sh"])

    if exit_code == 0 do
      :ok
    else
      {:error, :env_injection_failed}
    end
  end

  defp escape_value(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("$", "\\$")
    |> String.replace("`", "\\`")
  end

  @impl true
  def destroy(%__MODULE__{sprite: sprite, sprite_id: sprite_id} = _client, _sprite_id) do
    Logger.debug("Destroying live sprite #{sprite_id}")

    case Sprites.destroy(sprite) do
      :ok ->
        Logger.info("Destroyed live sprite #{sprite_id}")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to destroy sprite #{sprite_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  List all sprites from the Sprites API.
  Returns {:ok, [sprite_info]} or {:error, reason}.
  """
  def list_sprites(opts \\ []) do
    token = get_token()

    if is_nil(token) or token == "" do
      {:error, :missing_sprites_token}
    else
      base_url = get_base_url()
      client_opts = if base_url, do: [base_url: base_url], else: []
      client = Sprites.new(token, client_opts)

      case Sprites.list(client, opts) do
        {:ok, sprites} -> {:ok, sprites}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Destroy a sprite by name directly (without a client struct).
  """
  def destroy_by_name(sprite_name) do
    token = get_token()

    if is_nil(token) or token == "" do
      {:error, :missing_sprites_token}
    else
      base_url = get_base_url()
      client_opts = if base_url, do: [base_url: base_url], else: []
      client = Sprites.new(token, client_opts)

      # Sprites.sprite/2 returns a sprite struct directly
      sprite = Sprites.sprite(client, sprite_name)

      case Sprites.destroy(sprite) do
        :ok ->
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Private helpers

  defp get_token do
    System.get_env("SPRITES_TOKEN") || System.get_env("SPRITE_TOKEN")
  end

  defp get_base_url do
    Application.get_env(:agent_jido, __MODULE__, [])
    |> Keyword.get(:base_url)
  end

  defp generate_sprite_id do
    :crypto.strong_rand_bytes(8)
    |> Base.hex_encode32(case: :lower, padding: false)
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_add_timeout(opts, :infinity), do: opts
  defp maybe_add_timeout(opts, timeout), do: Keyword.put(opts, :timeout, timeout)
end
