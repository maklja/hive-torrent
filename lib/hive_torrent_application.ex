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
    IO.inspect(torrent)
  end
end
