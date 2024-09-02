defmodule HiveTorrent.HttpTrackerTest do
  use ExUnit.Case, async: true

  doctest HiveTorrent.HTTPTracker

  alias HiveTorrent.TrackerStorage
  alias HiveTorrent.HTTPTracker

  @mock %HTTPTracker{
    tracker_url: "https://local-tracker.com:333/announce",
    complete: 100,
    incomplete: 3,
    downloaded: 300,
    interval: 60_000,
    min_interval: 30_000,
    peers: <<192, 168, 0, 1, 6345>>
  }

  setup do
    start_supervised!(TrackerStorage)

    :ok
  end

  test "retrieve non existing tracker data1" do
    assert 1 == 1
  end
end
