defmodule HiveTorrent.TrackerSupervisor do
  use DynamicSupervisor

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
        start_http_tracker(tracker_params)

      %URI{scheme: "https"} ->
        start_http_tracker(tracker_params)

      %URI{scheme: "udp"} ->
        nil
    end
  end

  defp start_http_tracker(tracker_params) do
    spec =
      {HiveTorrent.HTTPTracker, tracker_params}

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @impl true
  def init(_init_args) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 3, max_seconds: 60)
  end
end
