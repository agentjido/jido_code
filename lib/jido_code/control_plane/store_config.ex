defmodule JidoCode.ControlPlane.StoreConfig do
  @moduledoc """
  Runtime configuration and path policy for the product control-plane store.

  Repository-local semantic graph stores remain separate. This module only
  governs the embedded store that will become product control-plane truth.
  """

  @default_open_timeout_ms 5_000
  @default_reset_policy :bootstrap_if_empty

  @spec store_path(keyword()) :: String.t()
  def store_path(opts \\ []) do
    cond do
      path = Keyword.get(opts, :path) ->
        Path.expand(path)

      path = Application.get_env(:jido_code, :control_plane_store_path) ->
        Path.expand(path)

      runtime_mode() == :test ->
        test_store_path(self())

      true ->
        Path.expand(".jido_code/control_plane/triple_store")
    end
  end

  @spec test_store_path(term()) :: String.t()
  def test_store_path(owner \\ self()) do
    partition = System.get_env("MIX_TEST_PARTITION") || "default"
    owner_hash = owner |> :erlang.phash2() |> Integer.to_string()

    Path.join([
      System.tmp_dir!(),
      "jido_code_control_plane_store",
      partition,
      owner_hash
    ])
  end

  @spec reset_policy(keyword()) :: :bootstrap_if_empty | :preserve | :reset_on_start
  def reset_policy(opts \\ []) do
    Keyword.get(
      opts,
      :reset_policy,
      Application.get_env(:jido_code, :control_plane_store_reset_policy, @default_reset_policy)
    )
  end

  @spec open_timeout_ms(keyword()) :: pos_integer()
  def open_timeout_ms(opts \\ []) do
    opts
    |> Keyword.get(
      :open_timeout_ms,
      Application.get_env(:jido_code, :control_plane_store_open_timeout_ms, @default_open_timeout_ms)
    )
    |> positive_integer(@default_open_timeout_ms)
  end

  defp runtime_mode do
    Application.get_env(:jido_code, :runtime_mode, :prod)
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default
end
