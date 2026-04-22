defmodule JidoCode.Config.RuntimeEnv do
  @moduledoc false
  # covers: developer.workflow.local_dotenv_bootstrap

  @spec bootstrap(atom(), keyword()) :: {:ok, %{optional(String.t()) => String.t()}}
  def bootstrap(config_env, opts \\ [])

  def bootstrap(:dev, opts) do
    root = Keyword.get(opts, :root, File.cwd!())
    system_env = Keyword.get(opts, :system_env, System.get_env())
    put_env = Keyword.get(opts, :put_env, &System.put_env/1)
    sys_cmd_fn = Keyword.get(opts, :sys_cmd_fn, &reject_command_substitution/3)

    merged_vars =
      Dotenvy.source!(
        [system_env | dotenv_inputs(root, :dev)] ++ [system_env],
        sys_cmd_fn: sys_cmd_fn
      )

    additions = Map.drop(merged_vars, Map.keys(system_env))

    if additions != %{} do
      put_env.(additions)
    end

    {:ok, additions}
  end

  def bootstrap(_config_env, _opts), do: {:ok, %{}}

  defp dotenv_inputs(root, config_env) do
    [
      Path.join(root, ".env"),
      Path.join(root, ".env.local"),
      Path.join(root, ".env.#{config_env}.local")
    ]
  end

  defp reject_command_substitution(command, _args, _opts) do
    raise """
    Dotenv command substitution is disabled for Jido.Code local runtime bootstrap. \
    Remove $(...) from your local dotenv file or set the value in your shell before boot \
    (attempted command: #{inspect(command)}).
    """
  end
end
