defmodule JidoCode.Forge.InfraClient do
  @moduledoc """
  Facade for infrastructure client operations.

  Delegates all calls to the appropriate implementation module based on
  the client struct type. For `create/1`, uses the configured implementation.

  Configure via:

      config :jido_code, :forge_infra_client, MyApp.InfraClient.Impl

  Defaults to `JidoCode.Forge.InfraClient.Fake` for development and testing.
  """

  @behaviour JidoCode.Forge.InfraClient.Behaviour

  alias JidoCode.Forge.InfraClient.Fake

  defp impl do
    Application.get_env(:jido_code, :forge_infra_client, Fake)
  end

  defp impl_for(%module{} = _client) when is_atom(module) do
    if function_exported?(module, :impl_module, 0) do
      module.impl_module()
    else
      module
    end
  end

  defp impl_for(client) do
    raise ArgumentError, "Unknown infra client struct: #{inspect(client)}"
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

  @impl true
  def read_file(client, path) do
    impl_for(client).read_file(client, path)
  end

  @impl true
  def inject_env(client, env_map) do
    impl_for(client).inject_env(client, env_map)
  end

  @impl true
  def destroy(client, infra_id) do
    impl_for(client).destroy(client, infra_id)
  end
end
