defmodule HiveTorrent.TorrentInfoMeta do
  defstruct [:files]
end

defmodule HiveTorrent.Torrent do
  defstruct [
    :trackers,
    :name,
    :comment,
    :created_by,
    :creation_date,
    :files,
    :size,
    :piece_length
  ]

  def parse(file_path) do
    with {:ok, data} <- File.read(file_path),
         {:ok, torrent_data} <- HiveTorrent.Bencode.Parser.parse(data),
         {:ok, trackers} <- get_trackers(torrent_data),
         {:ok, info} <- Map.fetch(torrent_data, "info"),
         {:ok, name} <- Map.fetch(info, "name"),
         {:ok, piece_length} <- Map.fetch(info, "piece length"),
         comment <- Map.get(torrent_data, "comment", ""),
         created_by <- Map.get(torrent_data, "created by", ""),
         {:ok, creation_date} <- Map.get(torrent_data, "creation date", 0) |> DateTime.from_unix() do
      files = get_files(info, name)
      files_size = Enum.reduce(files, 0, &(elem(&1, 1) + &2))
      pieces_hashes = get_hashes(Map.get(info, "pieces"))

      IO.inspect(torrent_data)

      test =
        {:ok,
         %__MODULE__{
           trackers: trackers,
           name: name,
           comment: comment,
           created_by: created_by,
           creation_date: creation_date,
           files: files,
           size: files_size,
           piece_length: piece_length
         }}

      IO.inspect(test)

      # IO.inspect(byte_size(Map.get(Map.get(torrent_data, "info"), "pieces")))
    end

    # %Torrent{
    #  name: name,
    #  info_hash: info_hash,
    #  files: files,
    #  size: size,
    #  trackers: trackers,
    #  piece_length: piece_length,
    #  pieces: piece_map
    #  }
  end

  defp get_trackers(%{"announce-list" => announce_list}), do: {:ok, List.flatten(announce_list)}

  defp get_trackers(%{"announce" => announce}), do: {:ok, [announce]}

  defp get_trackers(_), do: {:error, :no_trackers}

  defp get_files(%{"files" => files}, name) do
    Enum.map(files, fn %{"length" => length, "path" => path} ->
      {Path.join(name, path), length}
    end)
  end

  defp get_files(%{"length" => length}, name) do
    [{name, length}]
  end

  defp get_hashes(hash, num \\ 0, acc \\ %{})

  defp get_hashes("", _num, acc), do: acc

  defp get_hashes(<<hash::bytes-size(20), rest::binary>>, num, acc) do
    get_hashes(rest, num + 1, Map.put(acc, num, hash))
  end

  defp file_pieces(file_size, piece_length, piece_num \\ 0, pieces \\ [])

  defp file_pieces(file_size, piece_length, piece_num, pieces) do
    file_rem = file_size - piece_length * piece_num
  end

  # 150 40
  # 73 27 50
  # 40 33
  # 27
  # 40 10
end
