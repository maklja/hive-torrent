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

  test "ensure that http tracker fetch the tracker data and store it in TrackerStorage", %{
    tracker_url: tracker_url,
    info_hash: info_hash
  } do
    expected_tracker_data = %HTTPTracker{
      tracker_url: tracker_url,
      complete: 10,
      downloaded: 1496,
      incomplete: 0,
      interval: 1831,
      min_interval: 915,
      peers: %{"159.148.57.222" => [61843, 62368], "222.148.157.222" => [65327]}
    }

    with_mock HTTPoison,
      get: fn _tracker_url, _headers ->
        {:ok, mock_response} = Serializer.encode(@mock)
        {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}
      end do
      tracker_params = %{tracker_url: tracker_url, info_hash: info_hash, compact: 1}
      http_tracker_pid = start_supervised!({HTTPTracker, tracker_params})

      tracker_info = HTTPTracker.get_tracker_info(http_tracker_pid)
      assert tracker_info.tracker_params == tracker_params
      assert tracker_info.error == nil
      assert tracker_info.tracker_data == expected_tracker_data
      assert TrackerStorage.get(tracker_url) == {:ok, expected_tracker_data}
    end
  end

  test "ensure that http tracker fetch fails on not 200 status code", %{
    tracker_url: tracker_url,
    info_hash: info_hash
  } do
    with_mock HTTPoison,
      get: fn _tracker_url, _headers ->
        {:ok, %HTTPoison.Response{status_code: 400, body: "Invalid payload received."}}
      end do
      tracker_params = %{tracker_url: tracker_url, info_hash: info_hash, compact: 1}
      http_tracker_pid = start_supervised!({HTTPTracker, tracker_params})

      tracker_info = HTTPTracker.get_tracker_info(http_tracker_pid)
      assert tracker_info.tracker_params == tracker_params

      assert tracker_info.error ==
               "Received status code 400 from tracker https://local-tracker.com:333/announce. Response: \"Invalid payload received.\""

      assert tracker_info.tracker_data == nil
      assert TrackerStorage.get(tracker_url) == :error
    end
  end

  test "ensure that http tracker fetch fails on network errors", %{
    tracker_url: tracker_url,
    info_hash: info_hash
  } do
    with_mock HTTPoison,
      get: fn _tracker_url, _headers ->
        {:error, %HTTPoison.Error{id: nil, reason: :timeout}}
      end do
      tracker_params = %{tracker_url: tracker_url, info_hash: info_hash, compact: 1}
      http_tracker_pid = start_supervised!({HTTPTracker, tracker_params})

      tracker_info = HTTPTracker.get_tracker_info(http_tracker_pid)
      assert tracker_info.tracker_params == tracker_params

      assert tracker_info.error ==
               "Error timeout encountered during communication with tracker https://local-tracker.com:333/announce."

      assert tracker_info.tracker_data == nil
      assert TrackerStorage.get(tracker_url) == :error
    end
  end

  test "ensure that http tracker fails on the invalid payload response", %{
    tracker_url: tracker_url,
    info_hash: info_hash
  } do
    with_mock HTTPoison,
      get: fn _tracker_url, _headers ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "<invalid_payload>"}}
      end do
      tracker_params = %{tracker_url: tracker_url, info_hash: info_hash, compact: 1}
      http_tracker_pid = start_supervised!({HTTPTracker, tracker_params})

      tracker_info = HTTPTracker.get_tracker_info(http_tracker_pid)
      assert tracker_info.tracker_params == tracker_params

      assert tracker_info.error ==
               "Failed to parse tracker response: Unexpected token '<invalid_payload>' while parsing"

      assert tracker_info.tracker_data == nil
      assert TrackerStorage.get(tracker_url) == :error
    end
  end

  test "ensure that http tracker fails on the missing peers data", %{
    tracker_url: tracker_url,
    info_hash: info_hash
  } do
    with_mock HTTPoison,
      get: fn _tracker_url, _headers ->
        {:ok, mock_response} = Serializer.encode(Map.delete(@mock, "peers"))
        {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}
      end do
      tracker_params = %{tracker_url: tracker_url, info_hash: info_hash, compact: 1}
      http_tracker_pid = start_supervised!({HTTPTracker, tracker_params})

      tracker_info = HTTPTracker.get_tracker_info(http_tracker_pid)
      assert tracker_info.tracker_params == tracker_params
      assert tracker_info.error == "Invalid tracker response body"
      assert tracker_info.tracker_data == nil
      assert TrackerStorage.get(tracker_url) == :error
    end
  end

  test "ensure that http tracker fails on the missing interval data", %{
    tracker_url: tracker_url,
    info_hash: info_hash
  } do
    with_mock HTTPoison,
      get: fn _tracker_url, _headers ->
        {:ok, mock_response} = Serializer.encode(Map.delete(@mock, "interval"))
        {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}
      end do
      tracker_params = %{tracker_url: tracker_url, info_hash: info_hash, compact: 1}
      http_tracker_pid = start_supervised!({HTTPTracker, tracker_params})

      tracker_info = HTTPTracker.get_tracker_info(http_tracker_pid)
      assert tracker_info.tracker_params == tracker_params
      assert tracker_info.error == "Invalid tracker response body"
      assert tracker_info.tracker_data == nil
      assert TrackerStorage.get(tracker_url) == :error
    end
  end
end
