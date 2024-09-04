defmodule HiveTorrent.HttpTrackerTest do
  use ExUnit.Case, async: true

  import Mock

  alias HiveTorrent.StatsStorage
  alias HiveTorrent.TrackerStorage
  alias HiveTorrent.HTTPTracker
  alias HiveTorrent.Bencode.Serializer

  doctest HiveTorrent.HTTPTracker

  @mock %{
    "complete" => 10,
    "downloaded" => 1496,
    "incomplete" => 0,
    "interval" => 1831,
    "min interval" => 915,
    "peers" =>
      <<159, 148, 57, 222, 243, 160, 159, 148, 57, 222, 241, 147, 222, 148, 157, 222, 255, 47>>
  }

  setup do
    info_hash = <<20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>

    tracker_params = %{
      tracker_url: "https://local-tracker.com:333/announce",
      info_hash: info_hash
    }

    start_supervised!({TrackerStorage, nil})

    start_supervised!(
      {StatsStorage,
       [
         %StatsStorage{
           info_hash: info_hash,
           peer_id: "12345678901234567890",
           port: 6881,
           uploaded: 0,
           downloaded: 0,
           left: 0,
           event: "started"
         }
       ]}
    )

    {:ok, tracker_params}
  end

  test "retrieve non existing tracker data1", %{tracker_url: tracker_url, info_hash: info_hash} do
    {:ok, mock_response} = Serializer.encode(@mock)
    mock_response = {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}

    with_mock HTTPoison,
      get: fn _tracker_url, _headers ->
        mock_response
      end do
      tracker_params = %{tracker_url: tracker_url, info_hash: info_hash, compact: 1}
      http_tracker_pid = start_supervised!({HTTPTracker, tracker_params})

      assert HTTPTracker.get_tracker_info(http_tracker_pid) == tracker_params

      # wait_until(fn -> Process.alive?(http_tracker_pid) end)
      IO.inspect(TrackerStorage.get(tracker_url))
      # assert called(HTTPotion.get(tracker_url, :_))
    end
  end
end
