defmodule HiveTorrent.UDPTrackerSocketTest do
  use ExUnit.Case, async: false

  doctest HiveTorrent.UDPTrackerSocket

  import Mock

  alias HiveTorrent.UDPTrackerSocket
  alias HiveTorrent.Tracker

  @connection_id :rand.uniform(0xFFFFFFFFFFFFFFFF)

  @protocol_id UDPTrackerSocket.protocol_id()

  @connect_action UDPTrackerSocket.connect_action()

  @announce_action UDPTrackerSocket.announce_action()

  @error_action UDPTrackerSocket.error_action()

  @message_body <<:rand.uniform(0xFFFFFFFFFFFFFFFF)::64>>

  @port :rand.uniform(0xFFFF)

  @ip {:rand.uniform(0xFF), :rand.uniform(0xFF), :rand.uniform(0xFF), :rand.uniform(0xFF)}

  @req_body <<:rand.uniform(0xFFFFFFFFFFFFFFFF)::64>>

  setup_with_mocks([
    {:gen_udp, [:unstick, :passthrough],
     [open: &open_socket_success/2, close: &close_socket_success/1]}
  ]) do
    :ok
  end

  test_with_mock "ensure that error response ia handled correctly",
                 :gen_udp,
                 [:unstick, :passthrough],
                 send: &send_error_message/4 do
    test_pid = self()

    message_callback = fn message_type, transaction_id, data ->
      send(test_pid, {message_type, transaction_id, data})
    end

    _pid = start_supervised!({UDPTrackerSocket, port: @port, message_callback: message_callback})
    transaction_id = UDPTrackerSocket.send_announce_message(@req_body, @ip, @port)

    error_message =
      "Received error response for transaction #{Tracker.format_transaction_id(transaction_id)}, reason Invalid request."

    assert_receive {:error, ^transaction_id, ^error_message}
  end

  test_with_mock "ensure that error is returned in case response action mismatch",
                 :gen_udp,
                 [:unstick, :passthrough],
                 send: &send_invalid_message/4 do
    test_pid = self()

    message_callback = fn message_type, transaction_id, data ->
      send(test_pid, {message_type, transaction_id, data})
    end

    _pid = start_supervised!({UDPTrackerSocket, port: @port, message_callback: message_callback})
    transaction_id = UDPTrackerSocket.send_announce_message(@req_body, @ip, @port)

    error_message =
      "Requested action 0 is not matched with received action 100 for transaction #{Tracker.format_transaction_id(transaction_id)}."

    assert_receive {:error, ^transaction_id, ^error_message}
  end

  test_with_mock "ensure that announce message is properly send and response received",
                 :gen_udp,
                 [:unstick, :passthrough],
                 send: &send_message/4 do
    test_pid = self()

    message_callback = fn message_type, transaction_id, data ->
      send(test_pid, {message_type, transaction_id, data})
    end

    _pid = start_supervised!({UDPTrackerSocket, port: @port, message_callback: message_callback})
    transaction_id = UDPTrackerSocket.send_announce_message(@req_body, @ip, @port)

    assert_receive {:announce, ^transaction_id, @message_body}
  end

  test_with_mock "ensure that sending announce message the errors are propagated",
                 :gen_udp,
                 [:unstick, :passthrough],
                 open: &open_socket_success/2,
                 close: &close_socket_success/1,
                 send: &sending_error/4 do
    test_pid = self()

    message_callback = fn message_type, transaction_id, data ->
      send(test_pid, {message_type, transaction_id, data})
    end

    _pid = start_supervised!({UDPTrackerSocket, port: @port, message_callback: message_callback})
    transaction_id = UDPTrackerSocket.send_announce_message(@req_body, @ip, @port)

    assert_receive {:error, ^transaction_id, :failed}
  end

  test_with_mock "ensure that sending announce message the unknown errors are propagated",
                 :gen_udp,
                 [:unstick, :passthrough],
                 send: &sending_unknown_error/4 do
    test_pid = self()

    message_callback = fn message_type, transaction_id, data ->
      send(test_pid, {message_type, transaction_id, data})
    end

    _pid = start_supervised!({UDPTrackerSocket, port: @port, message_callback: message_callback})
    transaction_id = UDPTrackerSocket.send_announce_message(@req_body, @ip, @port)

    error_message =
      "Unknown error received on transaction #{Tracker.format_transaction_id(transaction_id)}."

    assert_receive {:error, ^transaction_id, ^error_message}
  end

  test_with_mock "socket should fail if can't be open",
                 :gen_udp,
                 [:unstick, :passthrough],
                 open: &open_socket_error/2 do
    message_callback = fn _message_type, _transaction_id, _data ->
      :error
    end

    result = start_supervised({UDPTrackerSocket, port: @port, message_callback: message_callback})

    assert elem(result, 0) == :error
  end

  defp process_udp_message(<<@protocol_id::64, @connect_action::32, transaction_id::32>>) do
    {:ok, <<@connect_action::32, transaction_id::32, @connection_id::64>>}
  end

  defp process_udp_message(
         <<@connection_id::64, @announce_action::32, transaction_id::32, _rest::binary>>
       ) do
    {:ok, <<@announce_action::32, transaction_id::32>> <> @message_body}
  end

  defp open_socket_success(_port, _opts), do: {:ok, "my_socket"}

  defp open_socket_error(_port, _opts), do: {:error, "Error"}

  defp close_socket_success(_socket), do: :ok

  defp send_message(socket, ip, port, message) do
    {:ok, resp_message} = process_udp_message(message)

    :ok =
      Process.send(UDPTrackerSocket, {:udp, socket, ip, port, resp_message}, [
        :noconnect
      ])

    :ok
  end

  defp send_error_message(socket, ip, port, message) do
    <<@protocol_id::64, @connect_action::32, transaction_id::32>> = message
    error_resp_message = <<@error_action::32, transaction_id::32, "Invalid request">>

    :ok =
      Process.send(
        UDPTrackerSocket,
        {:udp, socket, ip, port, error_resp_message},
        [
          :noconnect
        ]
      )

    :ok
  end

  defp send_invalid_message(socket, ip, port, message) do
    <<@protocol_id::64, @connect_action::32, transaction_id::32>> = message
    invalid_resp_message = <<100::32, transaction_id::32, @connection_id::64>>

    :ok =
      Process.send(
        UDPTrackerSocket,
        {:udp, socket, ip, port, invalid_resp_message},
        [
          :noconnect
        ]
      )

    :ok
  end

  defp sending_error(_socket, _ip, _port, _message), do: {:error, :failed}

  defp sending_unknown_error(_socket, _ip, _port, _message), do: :unknown_error
end
