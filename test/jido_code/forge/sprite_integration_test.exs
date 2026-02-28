defmodule JidoCode.Forge.SpriteIntegrationTest do
  @moduledoc """
  Integration tests for Forge with the live Sprites API.

  These tests require SPRITES_TOKEN or SPRITE_TOKEN environment variable.
  They create real remote containers and are excluded from normal test runs.

  Run with: mix test test/jido_code/forge/sprite_integration_test.exs --include sprite_integration
  """

  use ExUnit.Case, async: false

  alias JidoCode.Forge
  alias JidoCode.Forge.PubSub, as: ForgePubSub
  alias JidoCode.Forge.InfraClient.Sprite, as: Live

  @moduletag :sprite_integration

  setup do
    token = System.get_env("SPRITES_TOKEN") || System.get_env("SPRITE_TOKEN")

    if is_nil(token) or token == "" do
      {:ok, skip: true}
    else
      original_client = Application.get_env(:jido_code, :forge_infra_client)
      original_persistence = Application.get_env(:jido_code, JidoCode.Forge.Persistence)

      Application.put_env(:jido_code, :forge_infra_client, Live)
      Application.put_env(:jido_code, JidoCode.Forge.Persistence, enabled: false)

      on_exit(fn ->
        if original_client do
          Application.put_env(:jido_code, :forge_infra_client, original_client)
        else
          Application.delete_env(:jido_code, :forge_infra_client)
        end

        if original_persistence do
          Application.put_env(:jido_code, JidoCode.Forge.Persistence, original_persistence)
        else
          Application.delete_env(:jido_code, JidoCode.Forge.Persistence)
        end
      end)

      {:ok, skip: false, token: token}
    end
  end

  describe "SpriteClient.Live direct" do
    @tag timeout: 180_000
    test "create, execute, and destroy lifecycle", %{skip: skip} do
      skip_if(skip)

      {:ok, client, sprite_id} = Live.create(%{})

      try do
        assert %Live{} = client
        assert is_binary(sprite_id)

        {output, 0} = Live.exec(client, "echo 'Hello from Sprites!'", [])
        assert output =~ "Hello from Sprites!"

        {pwd_output, 0} = Live.exec(client, "pwd", [])
        assert is_binary(pwd_output)

        assert :ok = Live.write_file(client, "/tmp/test.txt", "integration test")
        {:ok, content} = Live.read_file(client, "/tmp/test.txt")
        assert String.trim(content) == "integration test"
      after
        result = Live.destroy(client, sprite_id)
        assert result == :ok
      end
    end
  end

  describe "Forge session lifecycle" do
    @tag timeout: 180_000
    test "full session with proper cleanup via terminate/2", %{skip: skip} do
      skip_if(skip)

      session_id = "integ-#{System.unique_integer([:positive])}"

      :ok = ForgePubSub.subscribe_session(session_id)

      spec = %{
        runner: :shell,
        runner_config: %{},
        sprite: %{},
        env: %{"TEST_VAR" => "hello_forge"},
        bootstrap: [
          %{type: "exec", command: "mkdir -p /app"},
          %{type: "file", path: "/app/test.txt", content: "Hello!\n"}
        ]
      }

      {:ok, handle} = Forge.start_session(session_id, spec)
      {:ok, pid} = Forge.Manager.get_session(session_id)
      ref = Process.monitor(pid)

      try do
        assert :ok = wait_for_ready(session_id, 60_000)

        {:ok, status} = Forge.status(session_id)
        assert status.state == :ready

        {output, 0} = Forge.exec(session_id, "cat /app/test.txt", [])
        assert output =~ "Hello!"

        {env_output, 0} = Forge.exec(session_id, "echo $TEST_VAR", [])
        assert env_output =~ "hello_forge"

        {cmd_output, 0} = Forge.cmd(handle, "echo", ["test"])
        assert cmd_output =~ "test"
      after
        :ok = Forge.stop_session(session_id)

        assert_receive {:DOWN, ^ref, :process, ^pid, reason}, 10_000
        assert reason in [:shutdown, :normal]

        flush_until_stopped()

        assert {:error, :not_found} = Forge.Manager.get_session(session_id)
      end
    end

    @tag timeout: 180_000
    test "pubsub broadcasts state transitions", %{skip: skip} do
      skip_if(skip)

      session_id = "pubsub-#{System.unique_integer([:positive])}"

      :ok = ForgePubSub.subscribe_session(session_id)

      spec = %{
        runner: :shell,
        runner_config: %{},
        sprite: %{}
      }

      {:ok, _handle} = Forge.start_session(session_id, spec)
      {:ok, pid} = Forge.Manager.get_session(session_id)
      ref = Process.monitor(pid)

      try do
        assert_receive {:status, %{state: :bootstrapping}}, 30_000

        assert_receive {:status, %{state: :initializing}}, 30_000

        assert_receive {:status, %{state: :ready}}, 30_000

        {:ok, status} = Forge.status(session_id)
        assert status.state == :ready
      after
        :ok = Forge.stop_session(session_id)

        assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 10_000
      end
    end

    @tag timeout: 180_000
    test "handles concurrent exec commands", %{skip: skip} do
      skip_if(skip)

      session_id = "concurrent-#{System.unique_integer([:positive])}"

      spec = %{
        runner: :shell,
        runner_config: %{},
        sprite: %{}
      }

      {:ok, handle} = Forge.start_session(session_id, spec)
      {:ok, pid} = Forge.Manager.get_session(session_id)
      ref = Process.monitor(pid)

      try do
        assert :ok = wait_for_ready(session_id, 60_000)

        tasks = [
          Task.async(fn -> Forge.cmd(handle, "echo", ["one"]) end),
          Task.async(fn -> Forge.cmd(handle, "echo", ["two"]) end),
          Task.async(fn -> Forge.cmd(handle, "echo", ["three"]) end)
        ]

        results = Task.await_many(tasks, 30_000)

        assert Enum.all?(results, fn {_, exit_code} -> exit_code == 0 end)

        outputs =
          results
          |> Enum.map(fn {output, _} -> String.trim(output) end)
          |> Enum.sort()

        assert outputs == ["one", "three", "two"]
      after
        :ok = Forge.stop_session(session_id)

        assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 10_000
      end
    end
  end

  defp skip_if(true), do: raise(ExUnit.AssertionError, message: "SPRITES_TOKEN not set")
  defp skip_if(false), do: :ok

  defp flush_until_stopped do
    receive do
      {:stopped, _reason} -> :ok
      {:status, _} -> flush_until_stopped()
      {:output, _} -> flush_until_stopped()
      {:needs_input, _} -> flush_until_stopped()
    after
      1_000 -> :ok
    end
  end

  defp wait_for_ready(session_id, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_for_ready(session_id, deadline)
  end

  defp do_wait_for_ready(session_id, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :timeout}
    else
      case Forge.status(session_id) do
        {:ok, %{state: :ready}} ->
          :ok

        {:ok, %{state: state}} when state in [:starting, :provisioning, :bootstrapping, :initializing] ->
          Process.sleep(500)
          do_wait_for_ready(session_id, deadline)

        {:ok, %{state: other}} ->
          {:error, {:unexpected_state, other}}

        {:error, :not_found} ->
          Process.sleep(200)
          do_wait_for_ready(session_id, deadline)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
