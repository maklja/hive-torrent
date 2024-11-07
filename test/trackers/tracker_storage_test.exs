defmodule HiveTorrent.TrackerStorageTest do
  use ExUnit.Case, async: true

  import HiveTorrent.TrackerMocks

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

    {peers, _expected_addresses} = create_peers_response()

    mock = %Tracker{
      tracker_url: create_http_tracker_announce_url(),
      complete: Faker.random_between(0, 100),
      incomplete: Faker.random_between(0, 3),
      downloaded: Faker.random_between(0, 300),
      interval: Faker.random_between(0, 60_000),
      min_interval: Faker.random_between(0, 30_000),
      peers: peers,
      updated_at: elem(DateTime.from_iso8601("2024-09-10T15:20:30Z"), 1)
    }

    TrackerStorage.put(@mock)

    {:ok, %{mock: mock}}
  end

  test "retrieve non existing tracker data" do
    assert TrackerStorage.get(create_http_tracker_announce_url()) === :error
  end

  test "retrieve existing tracker data", %{mock: mock} do
    TrackerStorage.put(mock)

    assert TrackerStorage.get(mock.tracker_url) ===
             {:ok, mock}
  end

  test "retrieve all trackers data", %{mock: mock} do
    TrackerStorage.put(mock)
    [first_tracker_data | _rest] = TrackerStorage.get_all()
    assert mock === first_tracker_data
  end
end
