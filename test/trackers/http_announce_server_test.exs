defmodule HiveTorrent.HttpAnnounceServerTest do
  use ExUnit.Case, async: true

  import Mock

  alias HiveTorrent.StatsStorage
  alias HiveTorrent.TorrentInfoStorage
  alias HiveTorrent.HTTPAnnounceServer
  alias HiveTorrent.HTTPTracker
  alias HiveTorrent.Tracker
  alias HiveTorrent.TrackerRegistry

  import HiveTorrent.TrackerMocks

  doctest HiveTorrent.HTTPAnnounceServer

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

    start_supervised!({TorrentInfoStorage, nil})
    start_supervised!({Registry, keys: :duplicate, name: TrackerRegistry})
    start_supervised!({StatsStorage, [stats]})

    {:ok, params}
  end

  test "ensure HTTPAnnounceServer fetch the tracker data and store it in TorrentInfoStorage",
       %{
         tracker_url: tracker_url,
         info_hash: info_hash,
         stats: stats
       } do
    {tracker_resp, expected_peers} = http_tracker_announce_response()

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

    with_mock HTTPTracker, [:passthrough],
      send_announce_request: fn _tracker_params, _opts ->
        {:ok, expected_tracker_data}
      end do
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        compact: 1,
        num_want: nil
      }

      {:ok, http_tracker_pid} = HTTPAnnounceServer.start_link(tracker_params: tracker_params)

      :ok = HTTPAnnounceServer.send_announce_request(http_tracker_pid)

      tracker_info = HTTPAnnounceServer.get_tracker_info(http_tracker_pid)
      assert tracker_info.tracker_params == tracker_params
      assert tracker_info.error == nil
      assert tracker_info.tracker_data == expected_tracker_data

      assert TorrentInfoStorage.get_torrent(tracker_url, info_hash) ==
               {:ok, expected_tracker_data}

      assert Registry.count(HiveTorrent.TrackerRegistry) == 1

      expected_tracker_params = %{
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

      tracker_params_with_start_event =
        expected_tracker_params
        |> Map.put(:event, HTTPTracker.started())

      # the first request is sent with start event
      assert_called_exactly(
        HTTPTracker.send_announce_request(tracker_params_with_start_event, :_),
        1
      )

      tracker_params_with_stopped_event =
        expected_tracker_params
        |> Map.put(:event, HTTPTracker.stopped())

      # the second request is sent with stop event on process shutdown
      assert_called_exactly(
        HTTPTracker.send_announce_request(tracker_params_with_stopped_event, :_),
        1
      )
    end
  end

  test "ensure HTTPAnnounceServer fail when error is received", %{
    tracker_url: tracker_url,
    info_hash: info_hash
  } do
    error_reason = Faker.Lorem.sentence()

    with_mock HTTPTracker, [:passthrough],
      send_announce_request: fn _tracker_params, _opts ->
        {:error, error_reason}
      end do
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        compact: 1,
        num_want: nil
      }

      http_tracker_pid = start_supervised!({HTTPAnnounceServer, tracker_params: tracker_params})
      HTTPAnnounceServer.send_announce_request(http_tracker_pid)

      tracker_info = HTTPAnnounceServer.get_tracker_info(http_tracker_pid)

      assert tracker_info.error == error_reason
      assert tracker_info.tracker_data == nil
      assert TorrentInfoStorage.get_torrent(tracker_url, info_hash) == :error
      assert Registry.count(HiveTorrent.TrackerRegistry) == 1
    end
  end

  test "ensure HTTPAnnounceServer sends complete event on download completed", %{
    tracker_url: tracker_url,
    info_hash: info_hash,
    stats: stats
  } do
    {tracker_resp, expected_peers} = http_tracker_announce_response()

    expected_tracker_data = %Tracker{
      info_hash: info_hash,
      tracker_url: tracker_url,
      complete: Map.fetch!(tracker_resp, "complete"),
      downloaded: Map.fetch!(tracker_resp, "downloaded"),
      incomplete: Map.fetch!(tracker_resp, "incomplete"),
      interval: 1,
      min_interval: 1,
      peers: expected_peers,
      updated_at: @mock_updated_date
    }

    # fully completed the download of the file pieces
    Enum.each(stats.pieces, fn {piece_idx, _} ->
      StatsStorage.downloaded(info_hash, piece_idx)
    end)

    test_pid = self()

    with_mock HTTPTracker, [:passthrough],
      send_announce_request: fn tracker_params, _opts ->
        send(test_pid, {tracker_params.tracker_url, tracker_params})

        {:ok, expected_tracker_data}
      end do
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        compact: 1,
        num_want: nil
      }

      http_tracker_pid =
        start_supervised!({HTTPAnnounceServer, tracker_params: tracker_params})

      :ok = HTTPAnnounceServer.send_announce_request(http_tracker_pid)

      tracker_info = HTTPAnnounceServer.get_tracker_info(http_tracker_pid)
      {:ok, updated_stats} = StatsStorage.get(info_hash)

      expected_tracker_params = %{
        compact: 1,
        port: updated_stats.port,
        ip: updated_stats.ip,
        left: updated_stats.left,
        uploaded: updated_stats.uploaded,
        downloaded: updated_stats.downloaded,
        key: tracker_info.key,
        tracker_url: tracker_url,
        info_hash: info_hash,
        num_want: nil,
        peer_id: updated_stats.peer_id
      }

      params_with_started_event =
        Map.put(expected_tracker_params, :event, HTTPTracker.started())

      assert_receive {^tracker_url, ^params_with_started_event}, 2_000

      HTTPAnnounceServer.send_announce_request(http_tracker_pid)

      params_with_completed_event =
        Map.put(expected_tracker_params, :event, HTTPTracker.completed())

      assert_receive {^tracker_url, ^params_with_completed_event}, 2_000

      HTTPAnnounceServer.send_announce_request(http_tracker_pid)

      params_with_none_event =
        Map.put(expected_tracker_params, :event, HTTPTracker.none())

      assert_receive {^tracker_url, ^params_with_none_event}, 2_000
    end
  end
end
