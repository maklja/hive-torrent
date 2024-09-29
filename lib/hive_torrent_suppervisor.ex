defmodule HiveTorrent.Supervisor do
  use Supervisor

  require Logger

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_args) do
    children = [
      {HiveTorrent.StatsStorage, []},
      {HiveTorrent.TrackerStorage, nil},
      {Registry, keys: :duplicate, name: HiveTorrent.TrackerRegistry},
      {HiveTorrent.UDPTrackerSocket,
       port: 6888, message_callback: &broadcast_message_to_trackers/3},
      {HiveTorrent.TrackerSupervisor, nil}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp broadcast_message_to_trackers(:announce, transaction_id, error) do
    broadcast_message_to_trackers(
      transaction_id,
      error,
      &HiveTorrent.UDPTracker.broadcast_announce_message/3
    )
  end

  defp broadcast_message_to_trackers(:scrape, transaction_id, error) do
    broadcast_message_to_trackers(
      transaction_id,
      error,
      &HiveTorrent.UDPTracker.broadcast_scrape_message/3
    )
  end

  defp broadcast_message_to_trackers(:error, transaction_id, error) do
    broadcast_message_to_trackers(
      transaction_id,
      error,
      &HiveTorrent.UDPTracker.broadcast_error_message/3
    )
  end

  defp broadcast_message_to_trackers(transaction_id, data, broadcast_callback) do
    formatted_trans_id = HiveTorrent.Tracker.format_transaction_id(transaction_id)

    Logger.info(
      "Broadcasting response with transaction id #{formatted_trans_id} to UPD trackers as #{inspect(broadcast_callback)}."
    )

    Registry.dispatch(HiveTorrent.TrackerRegistry, :udp_trackers, fn entries ->
      for {pid, _} <- entries do
        Logger.info(
          "Broadcasting response to #{inspect(pid)} with transaction id #{formatted_trans_id}."
        )

        broadcast_callback.(pid, transaction_id, data)
      end
    end)
  end
end
