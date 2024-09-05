defmodule HiveTorrent.StatsStorageTest do
  use ExUnit.Case, async: true

  doctest HiveTorrent.StatsStorage

  alias HiveTorrent.StatsStorage

  @mock %StatsStorage{
    info_hash: "12345",
    event: "started",
    peer_id: "3456",
    downloaded: 100,
    left: 8,
    port: 6889,
    uploaded: 1000
  }

  setup do
    start_supervised!({StatsStorage, [@mock]})

    :ok
  end

  test "retrieve non existing stats data" do
    assert StatsStorage.get("non_existing") === :error
  end

  test "retrieve existing stats data" do
    assert StatsStorage.get("12345") === {:ok, @mock}
  end

  test "add new stats data" do
    mock_stats = %StatsStorage{
      info_hash: "new",
      event: "stopped",
      peer_id: "555",
      downloaded: 99,
      left: 8,
      port: 6889,
      uploaded: 999
    }

    assert StatsStorage.put(mock_stats) == :ok
    assert StatsStorage.get("new") == {:ok, mock_stats}
  end

  test "update upload amount stat" do
    expected_stats = %StatsStorage{
      info_hash: "12345",
      event: "started",
      peer_id: "3456",
      downloaded: 100,
      left: 8,
      port: 6889,
      uploaded: 1099
    }

    assert StatsStorage.uploaded("12345", 99) == :ok
    assert StatsStorage.get("12345") == {:ok, expected_stats}
  end
end
