defmodule JidoCode.GitHub.WebhookDeliveryStore do
  @moduledoc """
  Store-backed GitHub webhook delivery idempotency records.
  """

  alias JidoCode.ControlPlane.RecordStore, as: Store
  alias JidoCode.GitHub.{Repo, RepoStore, WebhookDelivery}

  @statuses %{
    "pending" => :pending,
    "processed" => :processed,
    "failed" => :failed,
    "skipped" => :skipped
  }

  @spec create(map(), keyword()) :: {:ok, WebhookDelivery.t()} | {:error, term()}
  def create(attrs, opts \\ [])

  def create(attrs, opts) when is_map(attrs) do
    attrs = normalize_record_map(attrs)
    github_delivery_id = normalize_optional_string(map_get(attrs, :github_delivery_id))

    with {:ok, nil} <- get_by_github_delivery_id(github_delivery_id, opts),
         record <- delivery_record(attrs, nil),
         {:ok, saved_record} <- Store.create(:webhook_delivery, record, opts) do
      {:ok, to_delivery(saved_record)}
    else
      {:ok, %WebhookDelivery{}} -> {:error, :duplicate_github_delivery}
      {:error, reason} -> {:error, reason}
    end
  end

  def create(_attrs, _opts), do: {:error, :invalid_webhook_delivery_attrs}

  @spec get_by_github_delivery_id(String.t() | nil, keyword()) ::
          {:ok, WebhookDelivery.t() | nil} | {:error, term()}
  def get_by_github_delivery_id(github_delivery_id, opts \\ [])

  def get_by_github_delivery_id(nil, _opts), do: {:ok, nil}

  def get_by_github_delivery_id(github_delivery_id, opts) when is_binary(github_delivery_id) do
    with {:ok, record} <-
           Store.get_by_identity(
             :webhook_delivery,
             :unique_github_delivery,
             "githubDeliveryId",
             github_delivery_id,
             opts
           ) do
      {:ok, record && to_delivery(record)}
    end
  end

  @spec list_pending(pos_integer(), keyword()) :: {:ok, [WebhookDelivery.t()]} | {:error, term()}
  def list_pending(batch_size, opts \\ []) do
    limit = if is_integer(batch_size) and batch_size > 0, do: batch_size, else: 10

    with {:ok, records} <-
           Store.list(
             :webhook_delivery,
             %{status: "pending"},
             Keyword.merge([query: %{limit: limit, offset: 0}], opts)
           ) do
      deliveries =
        records
        |> Enum.map(&to_delivery/1)
        |> Enum.sort_by(&sort_datetime(&1.inserted_at))

      {:ok, deliveries}
    end
  end

  @spec mark_processed(WebhookDelivery.t() | map(), keyword()) :: {:ok, WebhookDelivery.t()} | {:error, term()}
  def mark_processed(delivery, opts \\ []) do
    update_status(delivery, :processed, %{processed_at: now()}, opts)
  end

  @spec mark_failed(WebhookDelivery.t() | map(), String.t() | nil, keyword()) ::
          {:ok, WebhookDelivery.t()} | {:error, term()}
  def mark_failed(delivery, error_message, opts \\ []) do
    update_status(
      delivery,
      :failed,
      %{
        processed_at: now(),
        error_message: normalize_optional_string(error_message)
      },
      opts
    )
  end

  @spec attach_repo(WebhookDelivery.t(), keyword()) :: WebhookDelivery.t()
  def attach_repo(%WebhookDelivery{repo_id: repo_id} = delivery, opts \\ []) do
    case RepoStore.get_by_id(repo_id, opts) do
      {:ok, %Repo{} = repo} -> Map.put(delivery, :repo, repo)
      _other -> delivery
    end
  end

  def to_delivery(record) when is_map(record) do
    record = normalize_record_map(record)

    %WebhookDelivery{
      id: map_get(record, :webhook_delivery_id) || map_get(record, :id),
      github_delivery_id: map_get(record, :github_delivery_id),
      event_type: normalize_string(map_get(record, :event_type), "unknown"),
      action: normalize_optional_string(map_get(record, :action)),
      payload: decode_json_map(map_get(record, :payload, %{})),
      repo_id: map_get(record, :repo_id) || map_get(record, :managed_repo_id),
      status: normalize_status(map_get(record, :status)),
      error_message: normalize_optional_string(map_get(record, :error_message)),
      processed_at: normalize_datetime(map_get(record, :processed_at)),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
    |> Map.put(:__metadata__, %{control_plane_record: record})
  end

  defp update_status(delivery, status, attrs, opts) when is_map(delivery) and is_atom(status) and is_map(attrs) do
    record =
      delivery
      |> normalize_record_map()
      |> Map.merge(attrs)
      |> Map.put(:status, status)
      |> delivery_record(nil)

    with {:ok, saved_record} <- Store.upsert(:webhook_delivery, record, opts) do
      {:ok, to_delivery(saved_record)}
    end
  end

  defp delivery_record(attrs, existing) do
    now = now()

    %{
      webhook_delivery_id:
        existing_id(existing, :webhook_delivery_id) ||
          normalize_optional_string(map_get(attrs, :webhook_delivery_id) || map_get(attrs, :id)) ||
          JidoCode.UUID.generate(),
      github_delivery_id: normalize_string(map_get(attrs, :github_delivery_id), JidoCode.UUID.generate()),
      managed_repo_id: normalize_optional_string(map_get(attrs, :managed_repo_id) || map_get(attrs, :repo_id)),
      repo_id: normalize_optional_string(map_get(attrs, :repo_id)),
      event_type: normalize_string(map_get(attrs, :event_type), "unknown"),
      action: normalize_optional_string(map_get(attrs, :action)),
      payload: decode_json_map(map_get(attrs, :payload, %{})),
      status: normalize_status(map_get(attrs, :status)),
      error_message: normalize_optional_string(map_get(attrs, :error_message)),
      processed_at: normalize_datetime(map_get(attrs, :processed_at)),
      inserted_at: existing_datetime(existing, :inserted_at) || normalize_datetime(map_get(attrs, :inserted_at)) || now,
      updated_at: now,
      metadata: decode_json_map(map_get(attrs, :metadata, %{}))
    }
  end

  defp existing_id(nil, _field), do: nil
  defp existing_id(existing, field), do: normalize_optional_string(map_get(existing, field) || map_get(existing, :id))

  defp existing_datetime(nil, _field), do: nil
  defp existing_datetime(existing, field), do: normalize_datetime(map_get(existing, field))

  defp normalize_record_map(%_{} = value), do: value |> Map.from_struct() |> normalize_record_map()

  defp normalize_record_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {normalize_key(key), normalize_value(value)} end)
  end

  defp normalize_record_map(_value), do: %{}

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    case key do
      "id" -> :id
      "webhook_delivery_id" -> :webhook_delivery_id
      "webhookDeliveryId" -> :webhook_delivery_id
      "github_delivery_id" -> :github_delivery_id
      "githubDeliveryId" -> :github_delivery_id
      "repo_id" -> :repo_id
      "managed_repo_id" -> :managed_repo_id
      "managedRepoId" -> :managed_repo_id
      "githubRepoId" -> :repo_id
      "event_type" -> :event_type
      "eventType" -> :event_type
      "action" -> :action
      "payload" -> :payload
      "payloadJson" -> :payload
      "status" -> :status
      "recordStatus" -> :status
      "error_message" -> :error_message
      "errorMessage" -> :error_message
      "processed_at" -> :processed_at
      "processedAt" -> :processed_at
      "inserted_at" -> :inserted_at
      "insertedAt" -> :inserted_at
      "updated_at" -> :updated_at
      "updatedAt" -> :updated_at
      "metadata" -> :metadata
      "metadataJson" -> :metadata
      other -> other
    end
  end

  defp normalize_key(key), do: key

  defp normalize_value(value) when is_map(value), do: normalize_record_map(value)
  defp normalize_value(value), do: value

  defp map_get(map, key, default \\ nil)
  defp map_get(%{} = map, key, default), do: Map.get(map, key, Map.get(map, to_string(key), default))
  defp map_get(_map, _key, default), do: default

  defp decode_json_map(value) when is_map(value), do: value

  defp decode_json_map(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _other -> %{}
    end
  end

  defp decode_json_map(_value), do: %{}

  defp normalize_status(value) when is_atom(value), do: normalize_status(Atom.to_string(value))
  defp normalize_status(value) when is_binary(value), do: Map.get(@statuses, String.trim(value), :pending)
  defp normalize_status(_value), do: :pending

  defp normalize_string(value, default) do
    normalize_optional_string(value) || default
  end

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :second)

  defp normalize_datetime(%NaiveDateTime{} = datetime) do
    datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.truncate(:second)
  end

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(String.trim(value)) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      _other -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp sort_datetime(%DateTime{} = datetime), do: datetime
  defp sort_datetime(_datetime), do: ~U[0000-01-01 00:00:00Z]

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
