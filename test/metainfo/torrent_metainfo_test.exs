defmodule HiveTorrent.TorrentTest do
  alias HiveTorrent.Torrent
  use ExUnit.Case
  doctest HiveTorrent.Torrent

  test "parse valid torrent with length" do
    torrent_path = Path.join([__DIR__, ~c"fixtures", ~c"torrent", ~c"valid.torrent"])

    {:ok, torrent} = Torrent.parse(torrent_path)

    IO.inspect(torrent)
    # File.read(torrent_path) |> IO.inspect()
    # {value, expected} = fixture.test_numbers.positive_int
    # assert value |> IO.iodata_to_binary() |> Parser.parse() == {:ok, expected}
  end
end
