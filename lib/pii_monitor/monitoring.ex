defmodule PiiMonitor.Monitoring do
  @moduledoc """
  Main PII monitoring module.
  Coordinates the monitoring of Slack channels and Notion databases.
  """

  use GenServer
  require Logger
  alias PiiMonitor.NotionClient
  alias PiiMonitor.SlackClient

  @doc """
  Starts the monitoring server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Initializes the server state.
  """
  @impl true
  def init(_opts) do
    # Get configuration and convert it to a map
    config = Application.get_env(:pii_monitor, __MODULE__, []) |> Enum.into(%{})

    # Get the list of channels to monitor
    slack_channels =
      config
      |> Map.get(:slack_channels, "")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    # Get the list of Notion databases to monitor
    notion_databases =
      config
      |> Map.get(:notion_databases, "")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    # Monitoring interval (default 1 second)
    monitoring_interval_ms = Map.get(config, :monitoring_interval_ms, 1000)

    # Initialize state
    state = %{
      slack_channels: slack_channels,
      notion_databases: notion_databases,
      monitoring_interval_ms: monitoring_interval_ms,
      channel_last_check: %{},
      notion_last_check: %{}
    }

    # Start the monitoring process
    schedule_monitoring(monitoring_interval_ms)

    Logger.info(
      "PII monitoring started. Monitoring #{length(slack_channels)} Slack channels and #{length(notion_databases)} Notion databases."
    )

    {:ok, state}
  end

  @doc """
  Handles messages to start the monitoring process.
  """
  @impl true
  def handle_info(:monitor, state) do
    # Perform monitoring
    new_state = perform_monitoring(state)

    # Schedule next check
    schedule_monitoring(state.monitoring_interval_ms)

    {:noreply, new_state}
  end

  # Schedules monitoring execution
  defp schedule_monitoring(interval_ms) do
    Process.send_after(self(), :monitor, interval_ms)
  end

  # Performs Slack and Notion monitoring
  defp perform_monitoring(state) do
    # Monitor Slack channels
    state = monitor_slack_channels(state)

    # Monitor Notion databases
    state = monitor_notion_databases(state)

    state
  end

  # Monitors Slack channels
  defp monitor_slack_channels(state) do
    # Get current time
    now = DateTime.utc_now()

    # Go through all channels and check new messages
    channel_last_check =
      Enum.reduce(state.slack_channels, state.channel_last_check, fn channel_name, acc ->
        # Get time of last check (by default check the last hour)
        last_check = Map.get(acc, channel_name, DateTime.add(now, -3600, :second))
        unix_timestamp = DateTime.to_unix(last_check)

        # Find channel ID by name
        channel_id = get_channel_id_by_name(channel_name)

        if channel_id do
          # Get new messages from the channel
          case SlackClient.get_channel_messages(channel_id, unix_timestamp) do
            {:ok, messages} ->
              # Process each message
              Enum.each(messages, fn message ->
                SlackClient.process_message(channel_id, message)
              end)

              # Update last check time
              Map.put(acc, channel_name, now)

            {:error, error} ->
              Logger.error("Error monitoring channel #{channel_name}: #{inspect(error)}")
              acc
          end
        else
          Logger.warning("Could not find channel with name #{channel_name}")
          acc
        end
      end)

    %{state | channel_last_check: channel_last_check}
  end

  # Monitors Notion databases
  defp monitor_notion_databases(state) do
    # Get current time
    now = DateTime.utc_now()

    # Go through all databases and check new entries
    notion_last_check =
      Enum.reduce(state.notion_databases, state.notion_last_check, fn database_id, acc ->
        # Get time of last check
        # By default check the last hour
        last_check = Map.get(acc, database_id, DateTime.add(now, -3600, :second))

        # Get new entries from the database
        case NotionClient.get_database_entries(database_id, last_check) do
          {:ok, pages} ->
            # Process each page
            Enum.each(pages, fn page ->
              NotionClient.process_page(page)
            end)

            # Update last check time
            Map.put(acc, database_id, now)

          {:error, error} ->
            Logger.error("Error monitoring Notion database #{database_id}: #{inspect(error)}")

            acc
        end
      end)

    %{state | notion_last_check: notion_last_check}
  end

  # Gets channel ID by name using SlackClient
  defp get_channel_id_by_name(channel_name) do
    case SlackClient.call_slack_api("conversations.list", %{
           types: "public_channel,private_channel"
         }) do
      {:ok, %{"ok" => true, "channels" => channels}} ->
        channel =
          Enum.find(channels, fn channel ->
            channel["name"] == channel_name
          end)

        if channel, do: channel["id"], else: nil

      {:ok, %{"ok" => false, "error" => error}} ->
        Logger.error("Slack API responded with error: #{error}")
        nil

      {:error, error} ->
        Logger.error("Error getting list of channels: #{inspect(error)}")
        nil
    end
  end
end
