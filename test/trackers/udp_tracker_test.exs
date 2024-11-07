defmodule HiveTorrent.UDPTrackerTest do
  use ExUnit.Case, async: false

  import Mock
  import HiveTorrent.TrackerMocks

  doctest HiveTorrent.UDPTracker

  alias HiveTorrent.TrackerStorage
  alias HiveTorrent.StatsStorage
  alias HiveTorrent.TrackerRegistry
  alias HiveTorrent.Tracker
  alias HiveTorrent.UDPTracker
  alias HiveTorrent.UDPTrackerSocket

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
      tracker_url: create_udp_tracker_announce_url(),
      info_hash: stats.info_hash,
      stats: stats
    }

    start_supervised!({TrackerStorage, nil})
    start_supervised!({Registry, keys: :duplicate, name: TrackerRegistry})
    start_supervised!({StatsStorage, [stats]})

    {:ok, params}
  end

  test "ensure UDPTracker fetch the tracker data and store it in TrackerStorage", %{
    tracker_url: tracker_url,
    info_hash: info_hash,
    stats: stats
  } do
    {tracker_resp, expected_values} = udp_tracker_announce_response()

    expected_tracker_data = %Tracker{
      info_hash: info_hash,
      tracker_url: tracker_url,
      complete: expected_values.seeders,
      downloaded: nil,
      incomplete: expected_values.leechers,
      interval: expected_values.interval,
      min_interval: nil,
      peers: expected_values.peers,
      updated_at: @mock_updated_date
    }

    tracker_ip = create_ip()
    tracker_port = create_port()
    transaction_id = Tracker.create_transaction_id()

    with_mocks [
      {
        Tracker,
        [:passthrough],
        udp_url_to_inet_address: fn _udp_tracker_url ->
          {:ok, tracker_ip, tracker_port}
        end
      },
      {
        UDPTrackerSocket,
        [:passthrough],
        send_announce_message: fn _message, _ip, _port ->
          transaction_id
        end
      }
    ] do
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        num_want: -1
      }

      {:ok, udp_tracker_pid} =
        UDPTracker.start_link(tracker_params: tracker_params, client: UDPTrackerSocket)

      UDPTracker.broadcast_announce_message(udp_tracker_pid, transaction_id, tracker_resp)
      tracker_info = UDPTracker.get_tracker_info(udp_tracker_pid)
      assert tracker_info.tracker_params == tracker_params
      assert tracker_info.error == nil
      assert tracker_info.tracker_data == expected_tracker_data
      assert TrackerStorage.get(tracker_url) == {:ok, expected_tracker_data}
      assert Registry.count(HiveTorrent.TrackerRegistry) == 1

      announce_with_started_event =
        <<info_hash::binary-size(20), stats.peer_id::binary-size(20), stats.downloaded::64,
          stats.left::64, stats.uploaded::64, Tracker.started().key::32, 0::32,
          tracker_info.key::32, tracker_params.num_want::32, stats.port::16>>

      # the first request is sent with start event
      assert_called_exactly(
        UDPTrackerSocket.send_announce_message(
          announce_with_started_event,
          tracker_ip,
          tracker_port
        ),
        1
      )

      # stop the GenServer in order to invoke terminate callback that should send stop event to tracker
      :ok = GenServer.stop(udp_tracker_pid)

      announce_with_stopped_event =
        <<info_hash::binary-size(20), stats.peer_id::binary-size(20), stats.downloaded::64,
          stats.left::64, stats.uploaded::64, Tracker.stopped().key::32, 0::32,
          tracker_info.key::32, tracker_params.num_want::32, stats.port::16>>

      # the second request is sent with stop event on process shutdown
      assert_called_exactly(
        UDPTrackerSocket.send_announce_message(
          announce_with_stopped_event,
          tracker_ip,
          tracker_port
        ),
        1
      )
    end
  end

  test "ensure UDPTracker fail when peers payload is invalid", %{
    tracker_url: tracker_url,
    info_hash: info_hash
  } do
    tracker_ip = create_ip()
    tracker_port = create_port()
    transaction_id = Tracker.create_transaction_id()

    with_mocks [
      {
        Tracker,
        [:passthrough],
        udp_url_to_inet_address: fn _udp_tracker_url ->
          {:ok, tracker_ip, tracker_port}
        end
      },
      {
        UDPTrackerSocket,
        [:passthrough],
        send_announce_message: fn _message, _ip, _port ->
          transaction_id
        end
      }
    ] do
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        num_want: -1
      }

      udp_tracker_pid =
        start_supervised!({UDPTracker, tracker_params: tracker_params, client: UDPTrackerSocket})

      {tracker_resp, _expected_values} = udp_tracker_announce_response()

      invalid_tracker_resp = tracker_resp <> <<:rand.uniform(255)::8>>

      UDPTracker.broadcast_announce_message(udp_tracker_pid, transaction_id, invalid_tracker_resp)
      tracker_info = UDPTracker.get_tracker_info(udp_tracker_pid)
      assert tracker_info.error == "Failed to parse IPv4 peers."
      assert tracker_info.tracker_data == nil
      assert TrackerStorage.get(tracker_url) == :error
      assert Registry.count(HiveTorrent.TrackerRegistry) == 1
    end
  end

  test "ensure UDPTracker fail when announce response is invalid", %{
    tracker_url: tracker_url,
    info_hash: info_hash
  } do
    tracker_ip = create_ip()
    tracker_port = create_port()
    transaction_id = Tracker.create_transaction_id()

    with_mocks [
      {
        Tracker,
        [:passthrough],
        udp_url_to_inet_address: fn _udp_tracker_url ->
          {:ok, tracker_ip, tracker_port}
        end
      },
      {
        UDPTrackerSocket,
        [:passthrough],
        send_announce_message: fn _message, _ip, _port ->
          transaction_id
        end
      }
    ] do
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        num_want: -1
      }

      udp_tracker_pid =
        start_supervised!({UDPTracker, tracker_params: tracker_params, client: UDPTrackerSocket})

      invalid_tracker_resp = <<:rand.uniform(255)::8>>

      UDPTracker.broadcast_announce_message(udp_tracker_pid, transaction_id, invalid_tracker_resp)
      tracker_info = UDPTracker.get_tracker_info(udp_tracker_pid)
      assert tracker_info.error == "Invalid message format for announce response."
      assert tracker_info.tracker_data == nil
      assert TrackerStorage.get(tracker_url) == :error
      assert Registry.count(HiveTorrent.TrackerRegistry) == 1
    end
  end

  test "ensure UDPTracker sends complete event on download completed", %{
    tracker_url: tracker_url,
    info_hash: info_hash,
    stats: stats
  } do
    # fully completed the download of the file pieces
    Enum.each(stats.pieces, fn {piece_idx, _} ->
      StatsStorage.downloaded(info_hash, piece_idx)
    end)

    tracker_ip = create_ip()
    tracker_port = create_port()
    transaction_id = Tracker.create_transaction_id()

    test_pid = self()

    with_mocks [
      {
        Tracker,
        [:passthrough],
        udp_url_to_inet_address: fn _udp_tracker_url ->
          {:ok, tracker_ip, tracker_port}
        end
      },
      {
        UDPTrackerSocket,
        [:passthrough],
        send_announce_message: fn message, _ip, _port ->
          <<_info_hash::binary-size(64), event::32, _rest::binary>> = message

          if event === Tracker.none().key do
            send(test_pid, :received_none_event)
          end

          transaction_id
        end
      }
    ] do
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        num_want: -1
      }

      {:ok, udp_tracker_pid} =
        UDPTracker.start_link(
          tracker_params: tracker_params,
          client: UDPTrackerSocket,
          timeout: 1
        )

      {tracker_resp, _expected_values} = udp_tracker_announce_response()

      <<_interval::32, rest::binary>> = tracker_resp

      UDPTracker.broadcast_announce_message(udp_tracker_pid, transaction_id, <<1::32>> <> rest)
      tracker_info = UDPTracker.get_tracker_info(udp_tracker_pid)

      {:ok, updated_stats} = StatsStorage.get(info_hash)

      assert_receive :received_none_event, 3_000

      gen_result_msg = fn event ->
        <<info_hash::binary-size(20), updated_stats.peer_id::binary-size(20),
          updated_stats.downloaded::64, updated_stats.left::64, updated_stats.uploaded::64,
          event::32, 0::32, tracker_info.key::32, tracker_params.num_want::32,
          updated_stats.port::16>>
      end

      announce_with_started_event = gen_result_msg.(Tracker.started().key)

      # the first request is sent with started event
      assert_called_exactly(
        UDPTrackerSocket.send_announce_message(
          announce_with_started_event,
          tracker_ip,
          tracker_port
        ),
        1
      )

      announce_with_completed_event = gen_result_msg.(Tracker.completed().key)

      # the second request is sent with completed event on process shutdown
      assert_called_exactly(
        UDPTrackerSocket.send_announce_message(
          announce_with_completed_event,
          tracker_ip,
          tracker_port
        ),
        1
      )

      announce_with_none_event = gen_result_msg.(Tracker.none().key)

      # the third request is sent with none event on process shutdown
      assert_called_exactly(
        UDPTrackerSocket.send_announce_message(
          announce_with_none_event,
          tracker_ip,
          tracker_port
        ),
        1
      )
    end
  end

  test "ensure UDPTracker fail when interval is zero", %{
    tracker_url: tracker_url,
    info_hash: info_hash
  } do
    tracker_ip = create_ip()
    tracker_port = create_port()
    transaction_id = Tracker.create_transaction_id()

    with_mocks [
      {
        Tracker,
        [:passthrough],
        udp_url_to_inet_address: fn _udp_tracker_url ->
          {:ok, tracker_ip, tracker_port}
        end
      },
      {
        UDPTrackerSocket,
        [:passthrough],
        send_announce_message: fn _message, _ip, _port ->
          transaction_id
        end
      }
    ] do
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        num_want: -1
      }

      udp_tracker_pid =
        start_supervised!({UDPTracker, tracker_params: tracker_params, client: UDPTrackerSocket})

      {tracker_resp, _expected_values} = udp_tracker_announce_response()
      <<_old_interval::unsigned-integer-size(32), rest::binary>> = tracker_resp

      invalid_tracker_resp = <<0::32>> <> rest

      UDPTracker.broadcast_announce_message(udp_tracker_pid, transaction_id, invalid_tracker_resp)
      tracker_info = UDPTracker.get_tracker_info(udp_tracker_pid)
      assert tracker_info.error == "Invalid message format for announce response."
      assert tracker_info.tracker_data == nil
      assert TrackerStorage.get(tracker_url) == :error
      assert Registry.count(HiveTorrent.TrackerRegistry) == 1
    end
  end

  test "ensure UDPTracker fail when error message is received", %{
    tracker_url: tracker_url,
    info_hash: info_hash
  } do
    tracker_ip = create_ip()
    tracker_port = create_port()
    transaction_id = Tracker.create_transaction_id()

    with_mocks [
      {
        Tracker,
        [:passthrough],
        udp_url_to_inet_address: fn _udp_tracker_url ->
          {:ok, tracker_ip, tracker_port}
        end
      },
      {
        UDPTrackerSocket,
        [:passthrough],
        send_announce_message: fn _message, _ip, _port ->
          transaction_id
        end
      }
    ] do
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: info_hash,
        num_want: -1
      }

      udp_tracker_pid =
        start_supervised!({UDPTracker, tracker_params: tracker_params, client: UDPTrackerSocket})

      error_message_response = Faker.Lorem.sentence()

      UDPTracker.broadcast_error_message(udp_tracker_pid, transaction_id, error_message_response)
      tracker_info = UDPTracker.get_tracker_info(udp_tracker_pid)
      assert tracker_info.error == error_message_response
      assert tracker_info.tracker_data == nil
      assert TrackerStorage.get(tracker_url) == :error
      assert Registry.count(HiveTorrent.TrackerRegistry) == 1
    end
  end
end
