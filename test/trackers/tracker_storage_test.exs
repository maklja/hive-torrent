defmodule HiveTorrent.TrackerStorageTest do
  use ExUnit.Case, async: true

  doctest HiveTorrent.TrackerStorage

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
    start_supervised!(HiveTorrent.TrackerStorage)

    HiveTorrent.TrackerStorage.put(@mock)

    :ok
  end

  test "retrieve non existing tracker data" do
    assert HiveTorrent.TrackerStorage.get("http://example-tracker.com:8999/announce") === :error
  end

  test "retrieve existing tracker data" do
    assert HiveTorrent.TrackerStorage.get("https://local-tracker.com:333/announce") ===
             {:ok, @mock}
  end
end
