defmodule HiveTorrent.UDPTrackerTest do
  use ExUnit.Case, async: false

  doctest HiveTorrent.UDPTracker

  @mock_updated_date DateTime.now!("Etc/UTC")

  setup_with_mocks([
    {DateTime, [:passthrough],
     [
       utc_now: fn -> @mock_updated_date end,
       utc_now: fn _ -> @mock_updated_date end
     ]}
  ]) do
    tracker_params = %{
      tracker_url: @tracker_url,
      info_hash: @info_hash
    }

    start_supervised!({TrackerStorage, nil})
    start_supervised!({Registry, keys: :duplicate, name: HiveTorrent.TrackerRegistry})

    start_supervised!({StatsStorage, [@stats]})

    {:ok, tracker_params}
  end
end
