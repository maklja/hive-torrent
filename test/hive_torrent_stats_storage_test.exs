defmodule HiveTorrent.StatsStorageTest do
  use ExUnit.Case, async: true

  doctest HiveTorrent.StatsStorage

  alias HiveTorrent.StatsStorage

  import HiveTorrent.TrackerMocks

  @mock_doc_tests %StatsStorage{
    info_hash: "56789",
    peer_id: "3456",
    downloaded: 100,
    left: 8,
    ip: "192.168.0.23",
    port: 6889,
    uploaded: 1000,
    completed: ["https://local-tracker.com:333/announce"]
  }

  setup do
    stats = create_stats()

    start_supervised!({StatsStorage, [stats, @mock_doc_tests]})

    {:ok, %{stats: stats}}
  end

  test "retrieve non existing stats data" do
    assert StatsStorage.get("non_existing") === :error
  end

  test "retrieve existing stats data", %{stats: stats} do
    assert StatsStorage.get(stats.info_hash) === {:ok, stats}
  end

  test "add new stats data" do
    mock_stats = create_stats()

    assert StatsStorage.put(mock_stats) == :ok
    assert StatsStorage.get(mock_stats.info_hash) == {:ok, mock_stats}
  end

  test "update upload amount stat", %{stats: stats} do
    expected_stats = %{stats | uploaded: stats.uploaded + 99}

    assert StatsStorage.uploaded(stats.info_hash, 99) == :ok
    assert StatsStorage.get(stats.info_hash) == {:ok, expected_stats}
  end

  test "mark tracker as notified with completed event", %{stats: stats} do
    completed_url = create_http_tracker_announce_url()

    assert StatsStorage.completed(stats.info_hash, completed_url) == :ok
    {:ok, torrent_stats} = StatsStorage.get(stats.info_hash)
    assert StatsStorage.has_completed?(torrent_stats, completed_url)
  end
end
