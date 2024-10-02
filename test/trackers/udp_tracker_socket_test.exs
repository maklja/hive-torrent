defmodule HiveTorrent.UDPTrackerSocketTest do
  use ExUnit.Case, async: true

  import Mock

  alias HiveTorrent.UDPTrackerSocket

  setup do
    # tracker_params = %{
    #   tracker_url: @tracker_url,
    #   info_hash: @info_hash
    # }

    # start_supervised!({TrackerStorage, nil})
    # start_supervised!({Registry, keys: :duplicate, name: HiveTorrent.TrackerRegistry})

    # start_supervised!({StatsStorage, [@stats]})

    # {:ok, tracker_params}
    :ok
  end

  test "ensure that announce message is properly send and received by socket" do
    port = 6888
    ip = {127, 0, 0, 1}

    message_callback = fn message_type, transaction_id, data ->
      IO.inspect(message_type)
      GenServer.call(self(), {:done})
    end

    with_mock :gen_udp, [:unstick],
      open: fn _port, _opts -> {:ok, "my_socket"} end,
      send: fn _socket, _ip, _port, _message ->
        IO.puts("called")
        :ok
      end do
      pid = start_supervised!({UDPTrackerSocket, port: port, message_callback: message_callback})

      transaction_id = UDPTrackerSocket.send_announce_message(<<>>, ip, port)
      IO.inspect(transaction_id)
    end

    assert_receive {:done}
  end
end
