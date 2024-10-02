defmodule HiveTorrent.UDPTrackerSocketTest do
  use ExUnit.Case, async: true

  import Mock

  alias HiveTorrent.UDPTrackerSocket

  @connection_id :rand.uniform(0xFFFFFFFFFFFFFFFF)

  @protocol_id UDPTrackerSocket.protocol_id()

  @connect_action UDPTrackerSocket.connect_action()

  @announce_action UDPTrackerSocket.announce_action()

  @message_body <<:rand.uniform(0xFFFFFFFFFFFFFFFF)::64>>

  defp process_udp_message(<<@protocol_id::64, @connect_action::32, transaction_id::32>>) do
    {:ok, <<@connect_action::32, transaction_id::32, @connection_id::64>>}
  end

  defp process_udp_message(
         <<@connection_id::64, @announce_action::32, transaction_id::32, _rest::binary>>
       ) do
    {:ok, <<@announce_action::32, transaction_id::32>> <> @message_body}
  end

  defp process_udp_message(_req_message) do
    {:error, "Invalid request message received"}
  end

  test_with_mock "ensure that announce message is properly send and received by socket",
                 :gen_udp,
                 [:unstick, :passthrough],
                 open: fn _port, _opts -> {:ok, "my_socket"} end,
                 close: fn _socket -> :ok end,
                 send: fn socket, ip, port, message ->
                   {:ok, resp_message} = process_udp_message(message)

                   :ok =
                     Process.send(UDPTrackerSocket, {:udp, socket, ip, port, resp_message}, [
                       :noconnect
                     ])

                   :ok
                 end do
    port = 6888
    ip = {127, 0, 0, 1}
    test_pid = self()

    message_callback = fn message_type, transaction_id, data ->
      IO.inspect(message_type)
      IO.inspect(transaction_id)
      IO.inspect(data)
      send(test_pid, {:done})
    end

    pid = start_supervised!({UDPTrackerSocket, port: port, message_callback: message_callback})
    transaction_id = UDPTrackerSocket.send_announce_message(<<>>, ip, port)
    IO.inspect(transaction_id)

    assert_receive {:done}, 5000
  end
end
