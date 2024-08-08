defmodule HiveTorrent.Bencode.Application do
  use Application

  @moduledoc """
  Documentation for `HiveTorrentApplication`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> HiveTorrentApplication.hello()
      :world

  """
  def start(_type, _args) do
    path = Path.join(:code.priv_dir(:hive_torrent), "example.torrent")
    {:ok, torrent} = HiveTorrent.Torrent.parse(File.read!(path))

    {:ok, pid} =
      HiveTorrent.HTTPTracker.start_link(%{
        tracker_url: "http://tracker.files.fm:6969/announce",
        info_hash: torrent.info_hash,
        peer_id: "12345678901234567890",
        port: 6881,
        uploaded: 0,
        downloaded: 0,
        left: 0,
        compact: 1,
        event: "started"
      })

    resp = HiveTorrent.HTTPTracker.fetch(pid)
    IO.inspect(resp)
  end
end
