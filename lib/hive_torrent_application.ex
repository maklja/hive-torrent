defmodule HiveTorrentApplication do
  @moduledoc """
  Documentation for `HiveTorrentApplication`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> HiveTorrentApplication.hello()
      :world

  """
  def hello do
    path = Path.join(:code.priv_dir(:hive_torrent), "example_1.torrent")
    {:ok, file} = File.open(path, [:binary, :read])
    data = IO.binread(file, :eof)

    result = HiveTorrent.Bencode.Parser.parse!(data)
    IO.inspect(result)
    File.close(file)
  end
end
