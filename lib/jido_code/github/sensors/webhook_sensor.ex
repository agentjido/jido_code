defmodule JidoCode.GitHub.Sensors.WebhookSensor do
  @moduledoc """
  A sensor that translates GitHub webhook deliveries into Jido signals.

  This sensor listens for webhook delivery records stored in the database
  and translates them into signals that agents can subscribe to.

  ## Signal Types

  The sensor emits signals with types based on the GitHub event:

  - `github.issue.opened` - New issue created
  - `github.issue.edited` - Issue edited
  - `github.issue.closed` - Issue closed
  - `github.issue_comment.created` - Comment added to issue
  - `github.pull_request.opened` - New PR opened
  - `github.pull_request.merged` - PR merged
  - etc.

  ## Configuration

  - `poll_interval` - How often to check for new deliveries (default: 5000ms)
  - `batch_size` - Max deliveries to process per poll (default: 10)

  ## Example

      # Start the sensor
      {:ok, pid} = Jido.Sensor.Runtime.start_link(
        sensor: JidoCode.GitHub.Sensors.WebhookSensor,
        config: %{poll_interval: 5000, batch_size: 10}
      )

  ## Signal Data

  Each emitted signal contains:

  - `delivery_id` - The WebhookDelivery record ID
  - `repo` - The Repo struct (owner, name, full_name, settings)
  - `event_type` - GitHub event type (issues, pull_request, etc.)
  - `action` - The action within the event (opened, closed, etc.)
  - `payload` - The full webhook payload from GitHub
  """

  use Jido.Sensor,
    name: "github_webhook",
    description: "Translates GitHub webhook deliveries into Jido signals",
    schema:
      Zoi.object(
        %{
          poll_interval:
            Zoi.integer(description: "Interval between polls in milliseconds")
            |> Zoi.default(5000),
          batch_size:
            Zoi.integer(description: "Maximum deliveries to process per poll")
            |> Zoi.default(10)
        },
        coerce: true
      )

  alias JidoCode.GitHub.{Repo, WebhookDelivery, WebhookDeliveryStore}

  @impl Jido.Sensor
  def init(config, context) do
    state = %{
      target: context[:agent_ref],
      poll_interval: config.poll_interval,
      batch_size: config.batch_size
    }

    {:ok, state, [{:schedule, config.poll_interval}]}
  end

  @impl Jido.Sensor
  def handle_event(:tick, state) do
    case fetch_pending_deliveries(state.batch_size) do
      {:ok, []} ->
        {:ok, state, [{:schedule, state.poll_interval}]}

      {:ok, deliveries} ->
        signals = Enum.flat_map(deliveries, &delivery_to_signals/1)
        {:ok, state, signals ++ [{:schedule, state.poll_interval}]}

      {:error, reason} ->
        require Logger
        Logger.error("WebhookSensor failed to fetch deliveries: #{inspect(reason)}")
        {:ok, state, [{:schedule, state.poll_interval}]}
    end
  end

  defp fetch_pending_deliveries(batch_size) do
    with {:ok, deliveries} <- WebhookDeliveryStore.list_pending(batch_size) do
      {:ok, Enum.map(deliveries, &WebhookDeliveryStore.attach_repo/1)}
    end
  end

  defp delivery_to_signals(%WebhookDelivery{repo: %Repo{} = repo} = delivery) do
    signal_type = build_signal_type(delivery.event_type, delivery.action)

    signal =
      Jido.Signal.new!(%{
        source: "/sensor/github_webhook/#{repo.full_name}",
        type: signal_type,
        data: %{
          delivery_id: delivery.id,
          repo: %{
            id: repo.id,
            owner: repo.owner,
            name: repo.name,
            full_name: repo.full_name,
            settings: repo.settings
          },
          event_type: delivery.event_type,
          action: delivery.action,
          payload: delivery.payload
        }
      })

    mark_delivery_processed(delivery)

    [{:emit, signal}]
  end

  defp delivery_to_signals(%WebhookDelivery{} = delivery) do
    mark_delivery_processed(delivery)
    []
  end

  defp build_signal_type(event_type, nil), do: "github.#{event_type}"
  defp build_signal_type(event_type, action), do: "github.#{event_type}.#{action}"

  defp mark_delivery_processed(delivery) do
    case WebhookDeliveryStore.mark_processed(delivery) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        require Logger
        Logger.warning("Failed to mark delivery #{delivery.id} as processed: #{inspect(reason)}")
    end
  end
end
