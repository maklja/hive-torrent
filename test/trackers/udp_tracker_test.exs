defmodule HiveTorrent.UDPTrackerTest do
  use ExUnit.Case, async: false

  import Mock

  doctest HiveTorrent.UDPTracker

  @mock_updated_date DateTime.now!("Etc/UTC")

  # setup_with_mocks([
  #   {DateTime, [:passthrough],
  #    [
  #      utc_now: fn -> @mock_updated_date end,
  #      utc_now: fn _ -> @mock_updated_date end
  #    ]}
  # ]) do
  #   tracker_params = %{
  #     tracker_url: @tracker_url,
  #     info_hash: @info_hash
  #   }

  #   start_supervised!({TrackerStorage, nil})
  #   start_supervised!({Registry, keys: :duplicate, name: HiveTorrent.TrackerRegistry})

  #   start_supervised!({StatsStorage, [@stats]})

  #   {:ok, tracker_params}
  # end

  # test "ensure that udp tracker fetch the tracker data and store it in TrackerStorage", %{
  #   tracker_url: tracker_url,
  #   info_hash: info_hash
  # } do
  #   expected_tracker_data = %Tracker{
  #     info_hash: @info_hash,
  #     tracker_url: tracker_url,
  #     complete: 10,
  #     downloaded: 1496,
  #     incomplete: 0,
  #     interval: 1831,
  #     min_interval: 915,
  #     peers: %{"159.148.57.222" => [61843, 62368], "222.148.157.222" => [65327]},
  #     updated_at: @mock_updated_date
  #   }

  #   with_mock HTTPoison,
  #     get: fn _tracker_url, _headers ->
  #       {:ok, mock_response} = Serializer.encode(@mock)
  #       {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}
  #     end do
  #     tracker_params = %{
  #       tracker_url: tracker_url,
  #       info_hash: info_hash,
  #       compact: 1,
  #       num_want: nil
  #     }

  #     {:ok, http_tracker_pid} = HTTPTracker.start_link(tracker_params)
  #     tracker_info = HTTPTracker.get_tracker_info(http_tracker_pid)
  #     assert tracker_info.tracker_params == tracker_params
  #     assert tracker_info.error == nil
  #     assert tracker_info.tracker_data == expected_tracker_data
  #     assert TrackerStorage.get(tracker_url) == {:ok, expected_tracker_data}
  #     assert Registry.count(HiveTorrent.TrackerRegistry) == 1

  #     # stop the GenServer in order to invoke terminate callback that should send stop event to tracker
  #     GenServer.stop(http_tracker_pid)

  #     # two calls expected, the first one that is start event and the second one that is stopped event
  #     assert_called_exactly(HTTPoison.get(:_, :_), 2)
  #   end
  # end
end
