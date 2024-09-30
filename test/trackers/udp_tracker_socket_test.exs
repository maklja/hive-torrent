defmodule HiveTorrent.UDPTrackerSocketTest do
  use ExUnit.Case, async: true

  import Mock

  setup_with_mocks([
    {:gen_udp, [:passthrough, :unstick],
     [
       open: fn _port, _opts -> {:ok, "my_socket"} end
     ]}
  ]) do
    # tracker_params = %{
    #   tracker_url: @tracker_url,
    #   info_hash: @info_hash
    # }

    # start_supervised!({TrackerStorage, nil})
    # start_supervised!({Registry, keys: :duplicate, name: HiveTorrent.TrackerRegistry})

    # start_supervised!({StatsStorage, [@stats]})

    # {:ok, tracker_params}
    {:ok, %{}}
  end

  test "ensure that announce message is properly send and received by socket" do
    IO.puts("done")
    # with_mock :gen_udp,
    #   send: fn _socket, _ip, _port, _message ->
    #     :ok
    #   end do
    #   :ok
    #   # TODO
    # end
  end
end
