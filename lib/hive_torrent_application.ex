defmodule HiveTorrent.Application do
  use Application

  @moduledoc """
  Documentation for `HiveTorrentApplication`.
  """
  alias HiveTorrent.TrackerSupervisor
  alias HiveTorrent.StatsStorage

  @doc """

  """
  def start(_type, _args) do
    path = Path.join(:code.priv_dir(:hive_torrent), "example.torrent")
    {:ok, torrent} = HiveTorrent.Torrent.parse(File.read!(path))
    {:ok, pid} = HiveTorrent.Supervisor.start_link(torrent)

    peer_id = "12345678901234567890"

    # TODO validate which pieces are already downloaded later
    remaining_pieces =
      torrent.pieces
      |> Enum.map(fn {key, pieces} ->
        pieces_size = pieces |> Enum.map(&elem(&1, 2)) |> Enum.sum()
        {key, {pieces_size, false}}
      end)
      |> Map.new()

    StatsStorage.put(%StatsStorage{
      info_hash: torrent.info_hash,
      peer_id: peer_id,
      port: 6881,
      uploaded: 0,
      downloaded: 0,
      left: 0,
      completed: [],
      pieces: remaining_pieces
    })

    Enum.each(torrent.trackers, fn tracker_url ->
      tracker_params = %{
        tracker_url: tracker_url,
        info_hash: torrent.info_hash
      }

      TrackerSupervisor.start_tracker(tracker_params)
    end)

    {:ok, pid}
  end
end
