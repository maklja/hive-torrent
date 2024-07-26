defmodule HiveTorrent.TorrentInfoMeta do
  defstruct [:files]
end

defmodule HiveTorrent.Torrent do
  defstruct [:announce, :name, :announce_list, :comment, :created_by, :creation_date, :info]

  def parse(file_path) do
    with {:ok, data} <- File.read(file_path),
         {:ok, torrent_data} <- HiveTorrent.Bencode.Parser.parse(data),
         {:ok, announce} <- Map.fetch(torrent_data, "announce"),
         {:ok, info} <- Map.fetch(torrent_data, "info"),
         announce_list <- Map.get(torrent_data, "announce-list", []),
         comment <- Map.get(torrent_data, "comment", ""),
         created_by <- Map.get(torrent_data, "created by", ""),
         creation_date <- Map.get(torrent_data, "creation date") do
      IO.inspect(torrent_data)
      IO.inspect(byte_size(Map.get(Map.get(torrent_data, "info"), "pieces")))
    end

    # with {:ok, file} <- File.read(path),
    #      {:ok, torrent} <- Bento.decode(file),
    #      {:ok, info} <- Map.fetch(torrent, "info"),
    #      {:ok, name} <- Map.fetch(info, "name"),
    #      {:ok, pieces} <- Map.fetch(info, "pieces"),
    #      {:ok, piece_length} <- Map.fetch(info, "piece length"),
    #      {:ok, trackers} <- get_trackers(torrent) do
  end
end
