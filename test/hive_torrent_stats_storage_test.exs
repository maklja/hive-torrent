defmodule HiveTorrent.StatsStorageTest do
  use ExUnit.Case, async: true

  doctest HiveTorrent.StatsStorage

  alias HiveTorrent.StatsStorage

  import HiveTorrent.TrackerMocks

  setup do
    mock_doc_tests = %StatsStorage{
      info_hash: "56789",
      peer_id: "3456",
      downloaded: 256,
      left: 512,
      ip: "192.168.0.23",
      port: 6889,
      uploaded: 1000,
      completed: ["https://local-tracker.com:333/announce"],
      pieces: %{
        0 => {256, false},
        1 => {256, true},
        2 => {256, false}
      }
    }

    stats = create_stats()

    start_supervised!({StatsStorage, [mock_doc_tests]})

    {:ok, %{stats: stats}}
  end

  test "retrieve non existing stats data" do
    assert StatsStorage.get("non_existing") === :error
  end

  test "retrieve existing stats data", %{stats: stats} do
    assert StatsStorage.put(stats) === :ok
    assert StatsStorage.get(stats.info_hash) === {:ok, stats}
  end

  test "add new stats data" do
    mock_stats = create_stats()

    assert StatsStorage.put(mock_stats) == :ok
    assert StatsStorage.get(mock_stats.info_hash) == {:ok, mock_stats}
  end

  test "update upload amount stat", %{stats: stats} do
    expected_stats = %{stats | uploaded: stats.uploaded + 99}

    assert StatsStorage.put(stats) === :ok
    assert StatsStorage.uploaded(stats.info_hash, 99) == :ok
    assert StatsStorage.get(stats.info_hash) == {:ok, expected_stats}
  end

  test "mark piece that is not downloaded as downloaded", %{stats: stats} do
    {piece_idx_to_mark, {piece_size, _}} =
      stats.pieces
      |> Enum.filter(fn {_piece_idx, {_pieces_size, is_downloaded}} -> !is_downloaded end)
      |> List.first()

    expected_stats = %{
      stats
      | downloaded: stats.downloaded + piece_size,
        left: stats.left - piece_size,
        pieces: Map.put(stats.pieces, piece_idx_to_mark, {piece_size, true})
    }

    assert StatsStorage.put(stats) === :ok
    assert StatsStorage.downloaded(stats.info_hash, piece_idx_to_mark) == :ok
    assert StatsStorage.get(stats.info_hash) == {:ok, expected_stats}
  end

  test "mark piece that is downloaded as downloaded", %{stats: stats} do
    {piece_idx_to_mark, {piece_size, _}} =
      stats.pieces
      |> Enum.filter(fn {_piece_idx, {_pieces_size, is_downloaded}} -> is_downloaded end)
      |> List.first()

    expected_stats = %{
      stats
      | downloaded: stats.downloaded + piece_size
    }

    assert StatsStorage.put(stats) === :ok
    assert StatsStorage.downloaded(stats.info_hash, piece_idx_to_mark) == :ok
    assert StatsStorage.get(stats.info_hash) == {:ok, expected_stats}
  end

  test "mark piece doesn't exists", %{stats: stats} do
    piece_idx_to_mark = 1_000

    assert StatsStorage.put(stats) === :ok
    assert StatsStorage.downloaded(stats.info_hash, piece_idx_to_mark) == :ok
    assert StatsStorage.get(stats.info_hash) == {:ok, stats}
  end

  test "mark tracker as notified with completed event", %{stats: stats} do
    completed_url = create_http_tracker_announce_url()

    assert StatsStorage.put(stats) === :ok
    assert StatsStorage.completed(stats.info_hash, completed_url) == :ok
    {:ok, torrent_stats} = StatsStorage.get(stats.info_hash)
    assert StatsStorage.has_completed?(torrent_stats, completed_url)
  end
end
