defmodule HiveTorrent.TorrentInfoStorageTest do
  use ExUnit.Case, async: true

  import HiveTorrent.TrackerMocks

  doctest HiveTorrent.TorrentInfoStorage

  alias HiveTorrent.Tracker
  alias HiveTorrent.TorrentInfoStorage

  @mock %Tracker{
    info_hash:
      <<179, 113, 122, 146, 100, 7, 66, 32, 44, 230, 243, 244, 233, 164, 177, 130, 46, 138, 145,
        40>>,
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
    start_supervised!(TorrentInfoStorage)

    {peers, _expected_addresses} = create_peers_response()

    mock = %Tracker{
      info_hash: create_info_hash(),
      tracker_url: create_http_tracker_announce_url(),
      complete: Faker.random_between(0, 100),
      incomplete: Faker.random_between(0, 3),
      downloaded: Faker.random_between(0, 300),
      interval: Faker.random_between(0, 60_000),
      min_interval: Faker.random_between(0, 30_000),
      peers: peers,
      updated_at: elem(DateTime.from_iso8601("2024-09-10T15:20:30Z"), 1)
    }

    TorrentInfoStorage.put(@mock)

    {:ok, %{mock: mock}}
  end

  test "retrieve non existing tracker torrent data" do
    assert TorrentInfoStorage.get_torrent(create_http_tracker_announce_url(), create_info_hash()) ===
             :error
  end

  test "retrieve non existing tracker torrents data" do
    assert TorrentInfoStorage.get_torrents(create_http_tracker_announce_url()) === []
  end

  test "retrieve existing tracker torrent data", %{mock: mock} do
    TorrentInfoStorage.put(mock)

    assert TorrentInfoStorage.get_torrent(mock.tracker_url, mock.info_hash) ===
             {:ok, mock}
  end

  test "retrieve existing tracker torrents data", %{mock: mock} do
    TorrentInfoStorage.put(mock)

    assert TorrentInfoStorage.get_torrents(mock.tracker_url) === [mock]
  end

  test "retrieve all trackers torrents data", %{mock: mock} do
    TorrentInfoStorage.put(mock)

    sorter = fn t_1, t_2 -> t_1.tracker_url < t_2.tracker_url end

    expected_trackers = Enum.sort([mock, @mock], sorter)

    trackers =
      TorrentInfoStorage.get_all_torrents()
      |> Enum.sort(sorter)

    assert expected_trackers === trackers
  end
end
