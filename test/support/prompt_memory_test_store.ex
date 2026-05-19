defmodule JidoCode.PromptMemoryTestStore do
  @moduledoc """
  Test fixture helpers for prompt-memory ETS stores.

  The production prompt-memory boundary is configured through application env,
  but tests need per-test ETS table families so teardown cannot delete a store
  still referenced by another prompt-memory fixture.
  """

  @default_config [
    enabled?: false,
    provider: :basic,
    store_opts: [],
    retrieval_limit: 4,
    max_instruction_lines: 4,
    max_instruction_bytes: 1_000,
    ttl_ms: 60_000
  ]

  @table_suffixes [:records, :ns_time, :ns_class_time, :ns_tag]

  @type fixture :: %{
          table: atom(),
          store: {module(), keyword()},
          config: keyword()
        }

  @doc """
  Configures a unique prompt-memory ETS store for the current test.
  """
  @spec setup!(keyword()) :: fixture()
  def setup!(opts \\ []) when is_list(opts) do
    previous = Application.get_env(:jido_code, :conversation_context_memory, [])

    table =
      Keyword.get_lazy(opts, :table, fn -> unique_table(Keyword.get(opts, :prefix, :jido_code_prompt_memory_test)) end)

    store = {Jido.Memory.Store.ETS, [table: table]}

    fixture = %{
      table: table,
      store: store,
      config: build_config(store, Keyword.get(opts, :config, []))
    }

    cleanup_store!(fixture)
    Application.put_env(:jido_code, :conversation_context_memory, fixture.config)

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:jido_code, :conversation_context_memory, previous)
      cleanup_store!(fixture)
    end)

    fixture
  end

  @doc """
  Replaces prompt-memory config for the fixture's unique store.
  """
  @spec configure!(fixture(), keyword()) :: :ok
  def configure!(%{store: store} = _fixture, overrides) when is_list(overrides) do
    Application.put_env(:jido_code, :conversation_context_memory, build_config(store, overrides))
    :ok
  end

  @doc """
  Deletes all ETS tables derived from the fixture's base table.
  """
  @spec cleanup_store!(fixture() | atom()) :: :ok
  def cleanup_store!(%{table: table}), do: cleanup_store!(table)

  def cleanup_store!(table) when is_atom(table) do
    table
    |> table_names()
    |> Enum.each(&delete_table/1)

    :ok
  end

  @doc """
  Returns the four ETS table names derived by `Jido.Memory.Store.ETS`.
  """
  @spec table_names(atom()) :: [atom()]
  def table_names(table) when is_atom(table) do
    Enum.map(@table_suffixes, &:"#{table}_#{&1}")
  end

  defp build_config(store, overrides) do
    @default_config
    |> Keyword.put(:store, store)
    |> Keyword.merge(overrides)
  end

  defp unique_table(prefix) when is_atom(prefix) do
    :"#{prefix}_#{System.unique_integer([:positive, :monotonic])}"
  end

  defp delete_table(table) do
    if :ets.whereis(table) != :undefined do
      :ets.delete(table)
    end

    :ok
  rescue
    ArgumentError -> :ok
  end
end
