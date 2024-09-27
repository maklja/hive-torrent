defmodule HiveTorrent.TrackerStorageTest do
  use ExUnit.Case, async: true

  doctest HiveTorrent.TrackerStorage

  alias HiveTorrent.Tracker
  alias HiveTorrent.TrackerStorage

  @mock %Tracker{
    tracker_url: "https://local-tracker.com:333/announce",
    complete: 100,
    incomplete: 3,
    downloaded: 300,
    interval: 60_000,
    min_interval: 30_000,
    peers: <<192, 168, 0, 1, 6345>>,
    updated_at: elem(DateTime.from_iso8601("2024-09-10T15:20:30Z"), 1)
  }

  setup do
    start_supervised!(TrackerStorage)

    TrackerStorage.put(@mock)

    :ok
  end

  test "retrieve non existing tracker data" do
    assert TrackerStorage.get("http://example-tracker.com:8999/announce") === :error
  end

  test "retrieve existing tracker data" do
    assert TrackerStorage.get("https://local-tracker.com:333/announce") ===
             {:ok, @mock}
  end

  test "retrieve all trackers data" do
    assert TrackerStorage.get_all() === [@mock]
  end
end
