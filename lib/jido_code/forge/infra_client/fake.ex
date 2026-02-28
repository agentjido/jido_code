defmodule JidoCode.Forge.InfraClient.Fake do
  @moduledoc """
  Fake infrastructure client implementation for development and testing.

  Uses local temporary directories as isolated environments and executes
  commands via System.cmd. State is managed by an Agent process.
  """

  @behaviour JidoCode.Forge.InfraClient.Behaviour

  use Agent

  @impl true
  def impl_module, do: __MODULE__

  require Logger

  defstruct [:agent_pid]

  @type t :: %__MODULE__{agent_pid: pid()}

  @type infra_state :: %{
          dir: String.t(),
          env: %{String.t() => String.t()}
        }

  @doc """
  Start the fake infra client agent.
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

    infra_id = generate_infra_id()
    base_dir = Map.get(spec, :base_dir, System.tmp_dir!())
    infra_dir = Path.join(base_dir, "forge_infra_#{infra_id}")

    case File.mkdir_p(infra_dir) do
      :ok ->
        state = %{dir: infra_dir, env: %{}}

        Agent.update(agent_pid, fn envs ->
          Map.put(envs, infra_id, state)
        end)

        Logger.debug("Created fake infra #{infra_id} at #{infra_dir}")
        client = %__MODULE__{agent_pid: agent_pid}
        {:ok, client, infra_id}

      {:error, reason} ->
        Agent.stop(agent_pid)
        {:error, {:mkdir_failed, reason}}
    end
  end

  @impl true
  def exec(%__MODULE__{agent_pid: agent_pid} = _client, command, opts) do
    ensure_agent_started(agent_pid)
    infra_id = Keyword.get(opts, :infra_id) || Keyword.get(opts, :sprite_id)
    timeout = Keyword.get(opts, :timeout, 60_000)

    infra_state = get_infra_state(agent_pid, infra_id)

    env =
      infra_state.env
      |> Enum.map(fn {k, v} -> {to_binary_string(k), to_binary_string(v)} end)

    cmd_opts = [
      cd: infra_state.dir,
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
    infra_id = Keyword.get(opts, :infra_id) || Keyword.get(opts, :sprite_id)
    infra_state = get_infra_state(agent_pid, infra_id)

    env =
      infra_state.env
      |> Enum.map(fn {k, v} -> {to_binary_string(k), to_binary_string(v)} end)

    port_opts = [
      :binary,
      :exit_status,
      :use_stdio,
      :stderr_to_stdout,
      {:cd, infra_state.dir},
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
    envs = Agent.get(agent_pid, & &1)

    infra_state =
      envs
      |> Map.values()
      |> List.first()

    full_path = resolve_path(infra_state.dir, path)

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
    envs = Agent.get(agent_pid, & &1)

    infra_state =
      envs
      |> Map.values()
      |> List.first()

    full_path = resolve_path(infra_state.dir, path)

    case File.read(full_path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def inject_env(%__MODULE__{agent_pid: agent_pid} = _client, env_map) do
    ensure_agent_started(agent_pid)
    envs = Agent.get(agent_pid, & &1)

    case Map.keys(envs) do
      [infra_id | _] ->
        Agent.update(agent_pid, fn envs ->
          update_in(envs, [infra_id, :env], fn existing_env ->
            # Normalize all env values to strings (binaries)
            normalized_map =
              env_map
              |> Enum.map(fn {k, v} -> {to_binary_string(k), to_binary_string(v)} end)
              |> Map.new()

            Map.merge(existing_env || %{}, normalized_map)
          end)
        end)

        :ok

      [] ->
        {:error, :no_infra}
    end
  end

  @impl true
  def destroy(%__MODULE__{agent_pid: agent_pid} = _client, infra_id) do
    ensure_agent_started(agent_pid)
    infra_state = Agent.get(agent_pid, fn envs -> Map.get(envs, infra_id) end)

    case infra_state do
      nil ->
        {:error, :not_found}

      %{dir: dir} ->
        File.rm_rf(dir)

        Agent.update(agent_pid, fn envs ->
          Map.delete(envs, infra_id)
        end)

        Logger.debug("Destroyed fake infra #{infra_id}")
        :ok
    end
  end

  defp ensure_agent_started(agent_pid) do
    unless Process.alive?(agent_pid) do
      Agent.start_link(fn -> %{} end, name: __MODULE__)
    end
  end

  defp generate_infra_id do
    :crypto.strong_rand_bytes(8)
    |> Base.hex_encode32(case: :lower, padding: false)
  end

  defp get_infra_state(agent_pid, nil) do
    envs = Agent.get(agent_pid, & &1)

    envs
    |> Map.values()
    |> List.first()
  end

  defp get_infra_state(agent_pid, infra_id) do
    Agent.get(agent_pid, fn envs -> Map.get(envs, infra_id) end)
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
