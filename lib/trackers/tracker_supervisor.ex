defmodule HiveTorrent.TrackerSupervisor do
  use DynamicSupervisor

  require Logger

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start_tracker(
        %{
          tracker_url: tracker_url
        } = tracker_params
      ) do
    case URI.parse(tracker_url) do
      %URI{scheme: "http"} ->
        Logger.info("Starting HTTP tracker: #{tracker_url}")
        start_http_tracker(tracker_params)

      %URI{scheme: "https"} ->
        Logger.info("Starting HTTPS tracker: #{tracker_url}")
        start_http_tracker(tracker_params)

      %URI{scheme: "udp"} ->
        Logger.info("Starting UDP tracker: #{tracker_url}")
        start_udp_tracker(tracker_params)

      _ ->
        Logger.error("Unsupported tracker type: #{tracker_url}")
    end
  end

  defp start_http_tracker(tracker_params) do
    spec = {HiveTorrent.HTTPTracker, tracker_params}

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  defp start_udp_tracker(tracker_params) do
    spec = {HiveTorrent.UDPTracker, tracker_params: tracker_params}

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @impl true
  def init(_init_args) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 3, max_seconds: 60)
  end
end
