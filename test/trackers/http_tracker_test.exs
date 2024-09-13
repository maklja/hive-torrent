defmodule HiveTorrent.HttpTrackerTest do
  use ExUnit.Case, async: true

  import Mock

  alias HiveTorrent.StatsStorage
  alias HiveTorrent.TrackerStorage
  alias HiveTorrent.HTTPTracker
  alias HiveTorrent.Tracker
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

  @mock_updated_date elem(DateTime.from_iso8601("2024-09-10T15:20:30Z"), 1)
  @tracker_url "https://local-tracker.com:333/announce"
  @info_hash <<20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>
  @stats %StatsStorage{
    info_hash: @info_hash,
    peer_id: "12345678901234567890",
    port: 6881,
    uploaded: 0,
    downloaded: 0,
    left: 0,
    completed: []
  }

  setup_with_mocks([
    {DateTime, [:passthrough],
     [
       utc_now: fn -> @mock_updated_date end,
       utc_now: fn _ -> @mock_updated_date end
     ]}
  ]) do
    tracker_params = %{
      tracker_url: @tracker_url,
      info_hash: @info_hash
    }

    start_supervised!({TrackerStorage, nil})
    start_supervised!({Registry, keys: :duplicate, name: HiveTorrent.TrackerRegistry})

    start_supervised!({StatsStorage, [@stats]})

    {:ok, tracker_params}
  end

  test "ensure that http tracker fetch the tracker data and store it in TrackerStorage", %{
    tracker_url: tracker_url,
    info_hash: info_hash
  } do
    expected_tracker_data = %Tracker{
      info_hash: @info_hash,
      tracker_url: tracker_url,
      complete: 10,
      downloaded: 1496,
      incomplete: 0,
      interval: 1831,
      min_interval: 915,
      peers: %{"159.148.57.222" => [61843, 62368], "222.148.157.222" => [65327]},
      updated_at: @mock_updated_date
    }

    with_mock HTTPoison,
      get: fn _tracker_url, _headers ->
        {:ok, mock_response} = Serializer.encode(@mock)
        {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}
      end do
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        compact: 1,
        num_want: nil
      }

      {:ok, http_tracker_pid} = HTTPTracker.start_link(tracker_params)
      tracker_info = HTTPTracker.get_tracker_info(http_tracker_pid)
      assert tracker_info.tracker_params == tracker_params
      assert tracker_info.error == nil
      assert tracker_info.tracker_data == expected_tracker_data
      assert TrackerStorage.get(tracker_url) == {:ok, expected_tracker_data}
      assert Registry.count(HiveTorrent.TrackerRegistry) == 1

      # stop the GenServer in order to invoke terminate callback that should send stop event to tracker
      GenServer.stop(http_tracker_pid)

      # two calls expected, the first one that is start event and the second one that is stopped event
      assert_called_exactly(HTTPoison.get(:_, :_), 2)
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
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        compact: 1,
        num_want: nil
      }

      http_tracker_pid = start_supervised!({HTTPTracker, tracker_params})

      tracker_info = HTTPTracker.get_tracker_info(http_tracker_pid)
      assert tracker_info.tracker_params == tracker_params

      assert tracker_info.error ==
               "Received status code 400 from tracker https://local-tracker.com:333/announce. Response: \"Invalid payload received.\""

      assert tracker_info.tracker_data == nil
      assert TrackerStorage.get(tracker_url) == :error
      assert Registry.count(HiveTorrent.TrackerRegistry) == 1
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
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        compact: 1,
        num_want: nil
      }

      http_tracker_pid = start_supervised!({HTTPTracker, tracker_params})

      tracker_info = HTTPTracker.get_tracker_info(http_tracker_pid)
      assert tracker_info.tracker_params == tracker_params

      assert tracker_info.error ==
               "Error timeout encountered during communication with tracker https://local-tracker.com:333/announce with info hash #{inspect(@info_hash)}."

      assert tracker_info.tracker_data == nil
      assert TrackerStorage.get(tracker_url) == :error
      assert Registry.count(HiveTorrent.TrackerRegistry) == 1
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
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        compact: 1,
        num_want: nil
      }

      http_tracker_pid = start_supervised!({HTTPTracker, tracker_params})

      tracker_info = HTTPTracker.get_tracker_info(http_tracker_pid)
      assert tracker_info.tracker_params == tracker_params

      assert tracker_info.error ==
               "Failed to parse tracker response: Unexpected token '<invalid_payload>' while parsing"

      assert tracker_info.tracker_data == nil
      assert TrackerStorage.get(tracker_url) == :error
      assert Registry.count(HiveTorrent.TrackerRegistry) == 1
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
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        compact: 1,
        num_want: nil
      }

      http_tracker_pid = start_supervised!({HTTPTracker, tracker_params})

      tracker_info = HTTPTracker.get_tracker_info(http_tracker_pid)
      assert tracker_info.tracker_params == tracker_params
      assert tracker_info.error == "Invalid tracker response body"
      assert tracker_info.tracker_data == nil
      assert TrackerStorage.get(tracker_url) == :error
      assert Registry.count(HiveTorrent.TrackerRegistry) == 1
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
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        compact: 1,
        num_want: nil
      }

      http_tracker_pid = start_supervised!({HTTPTracker, tracker_params})

      tracker_info = HTTPTracker.get_tracker_info(http_tracker_pid)
      assert tracker_info.tracker_params == tracker_params
      assert tracker_info.error == "Invalid tracker response body"
      assert tracker_info.tracker_data == nil
      assert TrackerStorage.get(tracker_url) == :error
      assert Registry.count(HiveTorrent.TrackerRegistry) == 1
    end
  end
end
