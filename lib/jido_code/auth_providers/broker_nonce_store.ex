defmodule JidoCode.AuthProviders.BrokerNonceStore do
  @moduledoc """
  Lightweight replay guard for validated broker handoff nonces.
  """

  # covers: auth.provider_broker_handoff.nonce_replay_protection

  @table :jido_code_provider_auth_nonces

  @type consume_error :: :expired | :replayed

  @spec consume(String.t(), DateTime.t()) :: :ok | {:error, consume_error()}
  def consume(nonce, %DateTime{} = expires_at) when is_binary(nonce) do
    table = ensure_table()
    now_unix = DateTime.utc_now() |> DateTime.to_unix()
    expires_at_unix = DateTime.to_unix(expires_at)

    cleanup_expired(table, now_unix)

    cond do
      String.trim(nonce) == "" ->
        {:error, :replayed}

      expires_at_unix <= now_unix ->
        {:error, :expired}

      :ets.insert_new(table, {nonce, expires_at_unix}) ->
        :ok

      true ->
        {:error, :replayed}
    end
  end

  def consume(_nonce, _expires_at), do: {:error, :expired}

  @doc false
  def reset! do
    table = ensure_table()
    :ets.delete_all_objects(table)
    :ok
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
        rescue
          ArgumentError ->
            @table
        end

      _table ->
        @table
    end
  end

  defp cleanup_expired(table, now_unix) do
    match_spec = [{{:"$1", :"$2"}, [{:<, :"$2", now_unix}], [true]}]
    :ets.select_delete(table, match_spec)
  end
end
