defmodule HiveTorrent.TorrentTest do
  use ExUnit.Case
  doctest HiveTorrent.Torrent

  test "parse valid torrent with length" do
    torrent_path = Path.join([__DIR__, ~c"fixtures", ~c"torrent", ~c"valid.torrent"])
    assert torrent_path === __DIR__ <> "/fixtures/torrent/valid.torrent"
    # File.read(torrent_path) |> IO.inspect()
    # {value, expected} = fixture.test_numbers.positive_int
    # assert value |> IO.iodata_to_binary() |> Parser.parse() == {:ok, expected}
  end
end
