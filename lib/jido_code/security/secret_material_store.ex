defmodule JidoCode.Security.SecretMaterialStore do
  @moduledoc """
  File-backed encrypted secret material sidecar for store-backed SecretRefs.

  The semantic graph stores only SecretRef metadata. Encrypted blobs live in this
  sidecar under the embedded store runtime path, keyed by SecretRef id.
  """

  alias JidoCode.ControlPlane.{ProductStore, StoreServer}

  @filename "secret_material.json"

  @spec put(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def put(secret_ref_id, ciphertext, opts \\ []) when is_binary(secret_ref_id) and is_binary(ciphertext) do
    update(opts, fn state ->
      secrets =
        state
        |> Map.get("secrets", %{})
        |> Map.put(secret_ref_id, %{
          "ciphertext" => ciphertext,
          "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

      Map.put(state, "secrets", secrets)
    end)
  end

  @spec get(String.t(), keyword()) :: {:ok, String.t()} | {:error, :not_found | term()}
  def get(secret_ref_id, opts \\ []) when is_binary(secret_ref_id) do
    with {:ok, state} <- read(opts),
         %{"ciphertext" => ciphertext} when is_binary(ciphertext) <-
           state |> Map.get("secrets", %{}) |> Map.get(secret_ref_id) do
      {:ok, ciphertext}
    else
      nil -> {:error, :not_found}
      _other -> {:error, :not_found}
    end
  end

  @spec delete(String.t(), keyword()) :: :ok | {:error, term()}
  def delete(secret_ref_id, opts \\ []) when is_binary(secret_ref_id) do
    update(opts, fn state ->
      secrets =
        state
        |> Map.get("secrets", %{})
        |> Map.delete(secret_ref_id)

      Map.put(state, "secrets", secrets)
    end)
  end

  defp update(opts, fun) do
    with {:ok, state} <- read(opts),
         next_state <- fun.(state),
         :ok <- write(next_state, opts) do
      :ok
    end
  end

  defp read(opts) do
    path = material_path(opts)

    cond do
      not File.exists?(path) ->
        {:ok, empty_state()}

      true ->
        case path |> File.read!() |> Jason.decode() do
          {:ok, %{} = state} -> {:ok, state}
          _other -> {:ok, empty_state()}
        end
    end
  rescue
    exception -> {:error, {exception.__struct__, Exception.message(exception)}}
  end

  defp write(state, opts) do
    path = material_path(opts)
    tmp_path = path <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(tmp_path, Jason.encode!(state)),
         :ok <- File.rename(tmp_path, path) do
      :ok
    end
  rescue
    exception -> {:error, {exception.__struct__, Exception.message(exception)}}
  end

  defp empty_state, do: %{"version" => 1, "secrets" => %{}}

  defp material_path(opts) do
    explicit_path =
      Keyword.get(opts, :material_path) ||
        Application.get_env(:jido_code, :secret_material_store_path)

    cond do
      is_binary(explicit_path) and explicit_path != "" ->
        explicit_path

      true ->
        ProductStore.store(opts)
        |> StoreServer.health()
        |> Map.fetch!(:path)
        |> Path.join(@filename)
    end
  catch
    :exit, _reason ->
      Path.join(System.tmp_dir!(), "jido_code_secret_material/#{@filename}")
  end
end
