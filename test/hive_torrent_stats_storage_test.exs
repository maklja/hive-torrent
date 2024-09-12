defmodule HiveTorrent.StatsStorageTest do
  use ExUnit.Case, async: true

  doctest HiveTorrent.StatsStorage

  alias HiveTorrent.StatsStorage

  @mock %StatsStorage{
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
    start_supervised!({StatsStorage, [@mock]})

    :ok
  end

  test "retrieve non existing stats data" do
    assert StatsStorage.get("non_existing") === :error
  end

  test "retrieve existing stats data" do
    assert StatsStorage.get("56789") === {:ok, @mock}
  end

  test "add new stats data" do
    mock_stats = %StatsStorage{
      info_hash: "new",
      peer_id: "555",
      downloaded: 99,
      left: 8,
      port: 6889,
      uploaded: 999,
      completed: []
    }

    assert StatsStorage.put(mock_stats) == :ok
    assert StatsStorage.get("new") == {:ok, mock_stats}
  end

  test "update upload amount stat" do
    expected_stats = %{@mock | uploaded: 1099}

    assert StatsStorage.uploaded("56789", 99) == :ok
    assert StatsStorage.get("56789") == {:ok, expected_stats}
  end

  test "mark tracker as notified with completed event" do
    assert StatsStorage.completed("56789", "https://new-tracker.com:333/announce") == :ok
    {:ok, torrent_stats} = StatsStorage.get("56789")
    assert StatsStorage.has_completed?(torrent_stats, "https://new-tracker.com:333/announce")
  end
end
