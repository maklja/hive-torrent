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

      files_1 = [{"Test1", 73}, {"Test2", 37}, {"Test3", 40}]

      files_pieces =
        files_1
        |> find_files_pieces(40)

      # files_pieces = file_pieces(40, 40)
      IO.inspect(files_pieces)

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

      # IO.inspect(test)

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

  defp find_files_pieces(files, piece_length, last_piece \\ {-1, 0, 0}, pieces \\ [])

  defp find_files_pieces([], _piece_length, _last_piece, pieces), do: Enum.reverse(pieces)

  defp find_files_pieces([file | rest], piece_length, last_piece, pieces) do
    {file_name, file_size} = file
    {piece_num, piece_offset, piece_size} = last_piece

    # case file_pieces(file_size, piece_length, piece_offset + piece_size, piece_num + 1) do
    #   {new_pieces, nil} ->
    #     last_piece = List.first(new_pieces)
    #     new_pieces = Enum.map(new_pieces, &Tuple.append(&1, file_name))
    #     find_files_pieces(rest, piece_length, last_piece, new_pieces ++ pieces)

    #   {new_pieces, last_piece} ->
    #     new_pieces = Enum.map(new_pieces, &Tuple.append(&1, file_name))
    #     # new_pieces = if length(rest) > 0, do: [last_piece | new_pieces], else: new_pieces
    #     find_files_pieces(rest, piece_length, last_piece, new_pieces ++ pieces)
    # end
  end

  defp file_pieces(file_size, piece_length, piece_offset, piece_num, pieces \\ [])

  defp file_pieces(file_size, piece_length, piece_offset, piece_num, pieces) when file_size > 0 do
    piece_length_rem = piece_length - rem(piece_offset, piece_length)
    file_size_rem = file_size - piece_length_rem

    cond do
      file_size_rem >= 0 ->
        piece = {piece_num, piece_offset, piece_length}

        file_pieces(file_size_rem, piece_length, piece_offset + piece_length, piece_num + 1, [
          piece | pieces
        ])

      true ->
        piece_size = piece_length + file_size_rem
        piece = {piece_num, piece_offset, piece_size}

        file_pieces(file_size_rem, piece_length, piece_offset + piece_size, piece_num, [
          piece | pieces
        ])
    end
  end

  defp file_pieces(_file_size, _piece_length, _piece_offset, _piece_num, pieces), do: pieces

  # you don't need last piece, you can just use offset
  # 40 - rem(80, 40)
end
