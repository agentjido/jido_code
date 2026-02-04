defmodule AgentJido.Forge.SpriteClient.Fake do
  @moduledoc """
  Fake sprite client implementation for development and testing.

  Uses local temporary directories as isolated "sprites" and executes
  commands via System.cmd. State is managed by an Agent process.
  """

  @behaviour AgentJido.Forge.SpriteClient.Behaviour

  use Agent

  @impl true
  def impl_module, do: __MODULE__

  require Logger

  defstruct [:agent_pid]

  @type t :: %__MODULE__{agent_pid: pid()}

  @type sprite_state :: %{
          dir: String.t(),
          env: %{String.t() => String.t()}
        }

  @doc """
  Start the fake sprite client agent.
  """
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Child spec for supervision tree.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @impl true
  def create(spec) do
    {:ok, agent_pid} = Agent.start_link(fn -> %{} end)

    sprite_id = generate_sprite_id()
    base_dir = Map.get(spec, :base_dir, System.tmp_dir!())
    sprite_dir = Path.join(base_dir, "forge_sprite_#{sprite_id}")

    case File.mkdir_p(sprite_dir) do
      :ok ->
        state = %{dir: sprite_dir, env: %{}}

        Agent.update(agent_pid, fn sprites ->
          Map.put(sprites, sprite_id, state)
        end)

        Logger.debug("Created fake sprite #{sprite_id} at #{sprite_dir}")
        client = %__MODULE__{agent_pid: agent_pid}
        {:ok, client, sprite_id}

      {:error, reason} ->
        Agent.stop(agent_pid)
        {:error, {:mkdir_failed, reason}}
    end
  end

  @impl true
  def exec(%__MODULE__{agent_pid: agent_pid} = _client, command, opts) do
    ensure_agent_started(agent_pid)
    sprite_id = Keyword.get(opts, :sprite_id)
    timeout = Keyword.get(opts, :timeout, 60_000)

    sprite_state = get_sprite_state(agent_pid, sprite_id)

    env =
      sprite_state.env
      |> Enum.map(fn {k, v} -> {to_binary_string(k), to_binary_string(v)} end)

    cmd_opts = [
      cd: sprite_state.dir,
      env: env,
      stderr_to_stdout: true
    ]

    try do
      case System.cmd("sh", ["-c", command], cmd_opts) do
        {output, exit_code} ->
          {output, exit_code}
      end
    catch
      :exit, {:timeout, _} ->
        {"Command timed out after #{timeout}ms", 124}
    end
  end

  @impl true
  def spawn(%__MODULE__{agent_pid: agent_pid} = _client, command, args, opts) do
    ensure_agent_started(agent_pid)
    sprite_id = Keyword.get(opts, :sprite_id)
    sprite_state = get_sprite_state(agent_pid, sprite_id)

    env =
      sprite_state.env
      |> Enum.map(fn {k, v} -> {to_binary_string(k), to_binary_string(v)} end)

    port_opts = [
      :binary,
      :exit_status,
      :use_stdio,
      :stderr_to_stdout,
      {:cd, sprite_state.dir},
      {:env, env},
      {:args, args}
    ]

    try do
      port = Port.open({:spawn_executable, System.find_executable(command)}, port_opts)
      {:ok, port}
    rescue
      e -> {:error, e}
    end
  end

  @impl true
  def write_file(%__MODULE__{agent_pid: agent_pid} = _client, path, content) do
    ensure_agent_started(agent_pid)
    sprites = Agent.get(agent_pid, & &1)

    sprite_state =
      sprites
      |> Map.values()
      |> List.first()

    full_path = resolve_path(sprite_state.dir, path)

    with :ok <- File.mkdir_p(Path.dirname(full_path)),
         :ok <- File.write(full_path, content) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def read_file(%__MODULE__{agent_pid: agent_pid} = _client, path) do
    ensure_agent_started(agent_pid)
    sprites = Agent.get(agent_pid, & &1)

    sprite_state =
      sprites
      |> Map.values()
      |> List.first()

    full_path = resolve_path(sprite_state.dir, path)

    case File.read(full_path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def inject_env(%__MODULE__{agent_pid: agent_pid} = _client, env_map) do
    ensure_agent_started(agent_pid)
    sprites = Agent.get(agent_pid, & &1)

    case Map.keys(sprites) do
      [sprite_id | _] ->
        Agent.update(agent_pid, &merge_env_into_sprite(&1, sprite_id, env_map))
        :ok

      [] ->
        {:error, :no_sprite}
    end
  end

  defp merge_env_into_sprite(sprites, sprite_id, env_map) do
    normalized_map = normalize_env_map(env_map)
    update_in(sprites, [sprite_id, :env], &Map.merge(&1 || %{}, normalized_map))
  end

  defp normalize_env_map(env_map) do
    env_map
    |> Enum.map(fn {k, v} -> {to_binary_string(k), to_binary_string(v)} end)
    |> Map.new()
  end

  @impl true
  def destroy(%__MODULE__{agent_pid: agent_pid} = _client, sprite_id) do
    ensure_agent_started(agent_pid)
    sprite_state = Agent.get(agent_pid, fn sprites -> Map.get(sprites, sprite_id) end)

    case sprite_state do
      nil ->
        {:error, :not_found}

      %{dir: dir} ->
        File.rm_rf(dir)

        Agent.update(agent_pid, fn sprites ->
          Map.delete(sprites, sprite_id)
        end)

        Logger.debug("Destroyed fake sprite #{sprite_id}")
        :ok
    end
  end

  defp ensure_agent_started(agent_pid) do
    unless Process.alive?(agent_pid) do
      Agent.start_link(fn -> %{} end, name: __MODULE__)
    end
  end

  defp generate_sprite_id do
    :crypto.strong_rand_bytes(8)
    |> Base.hex_encode32(case: :lower, padding: false)
  end

  defp get_sprite_state(agent_pid, nil) do
    sprites = Agent.get(agent_pid, & &1)

    sprites
    |> Map.values()
    |> List.first()
  end

  defp get_sprite_state(agent_pid, sprite_id) do
    Agent.get(agent_pid, fn sprites -> Map.get(sprites, sprite_id) end)
  end

  defp resolve_path(base_dir, path) do
    if Path.type(path) == :absolute do
      path
    else
      Path.join(base_dir, path)
    end
  end

  defp to_binary_string(value) when is_binary(value), do: value
  defp to_binary_string(value) when is_list(value), do: :unicode.characters_to_binary(value)
end
