defmodule JidoCode.Forge.SpriteClient do
  @moduledoc """
  Facade for sprite client operations.

  Delegates all calls to the appropriate implementation module based on
  the client struct type. For `create/1`, uses the configured implementation.

  Configure via:

      config :jido_code, :forge_sprite_client, MyApp.SpriteClient.Impl

  Defaults to `JidoCode.Forge.SpriteClient.Fake` for development and testing.
  """

  @behaviour JidoCode.Forge.SpriteClient.Behaviour

  alias JidoCode.Forge.SpriteClient.Fake
  alias JidoCode.AgentWorkspace

  defp impl do
    Application.get_env(:jido_code, :forge_sprite_client, Fake)
  end

  defp impl_for(%module{} = _client) when is_atom(module) do
    if function_exported?(module, :impl_module, 0) do
      module.impl_module()
    else
      module
    end
  end

  defp impl_for(client) do
    raise ArgumentError, "Unknown sprite client struct: #{inspect(client)}"
  end

  @impl true
  def impl_module, do: impl()

  @impl true
  def create(spec) do
    impl().create(spec)
  end

  @impl true
  def exec(client, command, opts \\ []) do
    impl_for(client).exec(client, command, opts)
  end

  @impl true
  def spawn(client, command, args, opts \\ []) do
    impl_for(client).spawn(client, command, args, opts)
  end

  @impl true
  def write_file(client, path, content) do
    impl_for(client).write_file(client, path, content)
  end

  @doc """
  Writes a file and optionally notifies the repo-scoped source watcher.

  Pass `:managed_repo_id` and `:workspace_path` when the write is known to touch
  a managed repository workspace. Notification only happens after the write
  succeeds.
  """
  @spec write_file(term(), String.t(), binary(), keyword()) :: :ok | {:error, term()}
  def write_file(client, path, content, opts) when is_list(opts) do
    case write_file(client, path, content) do
      :ok ->
        maybe_notify_source_write(path, opts)
        :ok

      {:error, _reason} = error ->
        error
    end
  end

  @impl true
  def read_file(client, path) do
    impl_for(client).read_file(client, path)
  end

  @impl true
  def inject_env(client, env_map) do
    impl_for(client).inject_env(client, env_map)
  end

  @impl true
  def destroy(client, sprite_id) do
    impl_for(client).destroy(client, sprite_id)
  end

  defp maybe_notify_source_write(path, opts) do
    managed_repo_id = Keyword.get(opts, :managed_repo_id)
    workspace_path = Keyword.get(opts, :workspace_path)

    if is_binary(managed_repo_id) and is_binary(workspace_path) do
      changed_path = Keyword.get(opts, :source_path, path)

      AgentWorkspace.notify_workspace_source_changed(
        managed_repo_id,
        workspace_path,
        changed_path,
        event_source: Keyword.get(opts, :event_source, :tool_write),
        file_events: Keyword.get(opts, :file_events, [:modified]),
        start_file_system?: Keyword.get(opts, :start_file_system?, false),
        debounce_ms: Keyword.get(opts, :debounce_ms, 500)
      )
    end

    :ok
  end
end
