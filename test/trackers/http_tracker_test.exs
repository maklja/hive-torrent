defmodule HiveTorrent.HttpTrackerTest do
  use ExUnit.Case, async: false

  import Mock

  alias HiveTorrent.StatsStorage
  alias HiveTorrent.TrackerStorage
  alias HiveTorrent.HTTPTracker
  alias HiveTorrent.Tracker
  alias HiveTorrent.Bencode.Serializer

  import HiveTorrent.TrackerMocks

  doctest HiveTorrent.HTTPTracker

  @mock_updated_date DateTime.now!("Etc/UTC")

  setup_with_mocks([
    {DateTime, [:passthrough],
     [
       utc_now: fn -> @mock_updated_date end,
       utc_now: fn _ -> @mock_updated_date end
     ]}
  ]) do
    stats = create_stats()

    params = %{
      tracker_url: create_http_tracker_announce_url(),
      info_hash: stats.info_hash,
      stats: stats
    }

    start_supervised!({TrackerStorage, nil})
    start_supervised!({Registry, keys: :duplicate, name: HiveTorrent.TrackerRegistry})
    start_supervised!({StatsStorage, [stats]})

    {:ok, params}
  end

  test "ensure HTTPTracker fetch the tracker data and store it in TrackerStorage", %{
    tracker_url: tracker_url,
    info_hash: info_hash,
    stats: stats
  } do
    {tracker_resp, expected_peers} = http_tracker_response()

    expected_tracker_data = %Tracker{
      info_hash: info_hash,
      tracker_url: tracker_url,
      complete: Map.fetch!(tracker_resp, "complete"),
      downloaded: Map.fetch!(tracker_resp, "downloaded"),
      incomplete: Map.fetch!(tracker_resp, "incomplete"),
      interval: Map.fetch!(tracker_resp, "interval"),
      min_interval: Map.fetch!(tracker_resp, "min interval"),
      peers: expected_peers,
      updated_at: @mock_updated_date
    }

    with_mock HTTPoison,
      get: fn _tracker_url, _headers, _opts ->
        {:ok, mock_response} = Serializer.encode(tracker_resp)
        {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}
      end do
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        compact: 1,
        num_want: nil
      }

      {:ok, http_tracker_pid} = HTTPTracker.start_link(tracker_params: tracker_params)
      tracker_info = HTTPTracker.get_tracker_info(http_tracker_pid)
      assert tracker_info.tracker_params == tracker_params
      assert tracker_info.error == nil
      assert tracker_info.tracker_data == expected_tracker_data
      assert TrackerStorage.get(tracker_url) == {:ok, expected_tracker_data}
      assert Registry.count(HiveTorrent.TrackerRegistry) == 1

      expected_query_params = %{
        info_hash: info_hash,
        peer_id: stats.peer_id,
        port: stats.port,
        uploaded: stats.uploaded,
        downloaded: stats.downloaded,
        left: stats.left,
        compact: 1,
        key: tracker_info.key
      }

      # stop the GenServer in order to invoke terminate callback that should send stop event to tracker
      :ok = GenServer.stop(http_tracker_pid)

      qp_with_start_event =
        expected_query_params
        |> Map.put(:event, Tracker.started().value)
        |> URI.encode_query()

      # the first request is sent with start event
      assert_called_exactly(HTTPoison.get("#{tracker_url}?#{qp_with_start_event}", :_, :_), 1)

      qp_with_stopped_event =
        expected_query_params
        |> Map.put(:event, Tracker.stopped().value)
        |> URI.encode_query()

      # the second request is sent with stop event on process shutdown
      assert_called_exactly(HTTPoison.get("#{tracker_url}?#{qp_with_stopped_event}", :_, :_), 1)
    end
  end

  test "ensure HTTPTracker sends complete event on download completed", %{
    tracker_url: tracker_url,
    info_hash: info_hash,
    stats: stats
  } do
    {tracker_resp, expected_peers} = http_tracker_response()

    # fully completed the download of the file pieces
    Enum.each(stats.pieces, fn {piece_idx, _} ->
      StatsStorage.downloaded(info_hash, piece_idx)
    end)

    test_pid = self()

    with_mock HTTPoison,
      get: fn tracker_url, _headers, _opts ->
        query_params = tracker_url |> String.split("?") |> Enum.at(1) |> URI.decode_query()

        cond do
          Map.get(query_params, "event") === Tracker.started().value ->
            send(test_pid, :started)

          Map.get(query_params, "event") === Tracker.completed().value ->
            send(test_pid, :completed)

          Map.get(query_params, "event") === Tracker.completed().value ->
            send(test_pid, :completed)
        end

        {:ok, mock_response} =
          Serializer.encode(%{tracker_resp | "min interval" => 1, "interval" => 1})

        {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}
      end do
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        compact: 1,
        num_want: nil
      }

      {:ok, http_tracker_pid} = HTTPTracker.start_link(tracker_params: tracker_params)
      tracker_info = HTTPTracker.get_tracker_info(http_tracker_pid)

      assert_receive :started, 2_000

      assert_receive :completed, 2_000

      # # stop the GenServer in order to invoke terminate callback that should send stop event to tracker
      # :ok = GenServer.stop(http_tracker_pid)

      # qp_with_start_event =
      #   expected_query_params
      #   |> Map.put(:event, Tracker.started().value)
      #   |> URI.encode_query()

      # # the first request is sent with start event
      # assert_called_exactly(HTTPoison.get("#{tracker_url}?#{qp_with_start_event}", :_, :_), 1)

      # qp_with_stopped_event =
      #   expected_query_params
      #   |> Map.put(:event, Tracker.stopped().value)
      #   |> URI.encode_query()

      # # the second request is sent with stop event on process shutdown
      # assert_called_exactly(HTTPoison.get("#{tracker_url}?#{qp_with_stopped_event}", :_, :_), 1)
    end
  end

  test "ensure HTTPTracker fetch fails on not 200 status code", %{
    tracker_url: tracker_url,
    info_hash: info_hash
  } do
    with_mock HTTPoison,
      get: fn _tracker_url, _headers, _opts ->
        {:ok, %HTTPoison.Response{status_code: 400, body: "Invalid payload received."}}
      end do
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        compact: 1,
        num_want: nil
      }

      http_tracker_pid = start_supervised!({HTTPTracker, tracker_params: tracker_params})

      tracker_info = HTTPTracker.get_tracker_info(http_tracker_pid)
      assert tracker_info.tracker_params == tracker_params

      assert tracker_info.error ==
               "Received status code 400 from tracker #{tracker_url}. Response: \"Invalid payload received.\""

      assert tracker_info.tracker_data == nil
      assert TrackerStorage.get(tracker_url) == :error
      assert Registry.count(HiveTorrent.TrackerRegistry) == 1
    end
  end

  test "ensure HTTPTracker fetch fails on network errors", %{
    tracker_url: tracker_url,
    info_hash: info_hash
  } do
    with_mock HTTPoison,
      get: fn _tracker_url, _headers, _opts ->
        {:error, %HTTPoison.Error{id: nil, reason: :timeout}}
      end do
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        compact: 1,
        num_want: nil
      }

      http_tracker_pid = start_supervised!({HTTPTracker, tracker_params: tracker_params})

      tracker_info = HTTPTracker.get_tracker_info(http_tracker_pid)
      assert tracker_info.tracker_params == tracker_params

      assert tracker_info.error ==
               "Error timeout encountered during communication with tracker #{tracker_url} with info hash #{inspect(info_hash)}."

      assert tracker_info.tracker_data == nil
      assert TrackerStorage.get(tracker_url) == :error
      assert Registry.count(HiveTorrent.TrackerRegistry) == 1
    end
  end

  test "ensure HTTPTracker fails on the invalid payload response", %{
    tracker_url: tracker_url,
    info_hash: info_hash
  } do
    with_mock HTTPoison,
      get: fn _tracker_url, _headers, _opts ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "<invalid_payload>"}}
      end do
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        compact: 1,
        num_want: nil
      }

      http_tracker_pid = start_supervised!({HTTPTracker, tracker_params: tracker_params})

      tracker_info = HTTPTracker.get_tracker_info(http_tracker_pid)
      assert tracker_info.tracker_params == tracker_params

      assert tracker_info.error ==
               "Failed to parse tracker response: Unexpected token '<invalid_payload>' while parsing."

      assert tracker_info.tracker_data == nil
      assert TrackerStorage.get(tracker_url) == :error
      assert Registry.count(HiveTorrent.TrackerRegistry) == 1
    end
  end

  test "ensure HTTPTracker fails on the missing peers data", %{
    tracker_url: tracker_url,
    info_hash: info_hash
  } do
    with_mock HTTPoison,
      get: fn _tracker_url, _headers, _opts ->
        {:ok, mock_response} =
          http_tracker_response()
          |> elem(0)
          |> Map.delete("peers")
          |> Serializer.encode()

        {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}
      end do
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        compact: 1,
        num_want: nil
      }

      http_tracker_pid = start_supervised!({HTTPTracker, tracker_params: tracker_params})

      tracker_info = HTTPTracker.get_tracker_info(http_tracker_pid)
      assert tracker_info.tracker_params == tracker_params
      assert tracker_info.error == "Invalid tracker response body."
      assert tracker_info.tracker_data == nil
      assert TrackerStorage.get(tracker_url) == :error
      assert Registry.count(HiveTorrent.TrackerRegistry) == 1
    end
  end

  test "ensure HTTPTracker fails on the missing interval data", %{
    tracker_url: tracker_url,
    info_hash: info_hash
  } do
    with_mock HTTPoison,
      get: fn _tracker_url, _headers, _opts ->
        {:ok, mock_response} =
          http_tracker_response()
          |> elem(0)
          |> Map.delete("interval")
          |> Serializer.encode()

        {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}
      end do
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        compact: 1,
        num_want: nil
      }

      http_tracker_pid = start_supervised!({HTTPTracker, tracker_params: tracker_params})

      tracker_info = HTTPTracker.get_tracker_info(http_tracker_pid)
      assert tracker_info.tracker_params == tracker_params
      assert tracker_info.error == "Invalid tracker response body."
      assert tracker_info.tracker_data == nil
      assert TrackerStorage.get(tracker_url) == :error
      assert Registry.count(HiveTorrent.TrackerRegistry) == 1
    end
  end
end
