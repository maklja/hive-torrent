defmodule HiveTorrent.Torrent do
  @type t :: %__MODULE__{
          trackers: [String.t(), ...],
          name: String.t(),
          comment: String.t(),
          created_by: String.t(),
          creation_date: DateTime.t() | nil,
          files: [{String.t(), pos_integer()}, ...],
          size: pos_integer(),
          piece_length: pos_integer(),
          pieces: %{
            pos_integer() => [{<<_::20>>, pos_integer(), pos_integer(), String.t()}, ...]
          }
        }

  defstruct [
    :trackers,
    :name,
    :comment,
    :created_by,
    :creation_date,
    :files,
    :size,
    :piece_length,
    :pieces
  ]

  def parse(file_path) do
    with {:ok, data} <- File.read(file_path),
         {:ok, torrent_data} <- HiveTorrent.Bencode.Parser.parse(data),
         {:ok, trackers} <- get_trackers(torrent_data),
         {:ok, info} <- Map.fetch(torrent_data, "info"),
         {:ok, name} <- Map.fetch(info, "name"),
         {:ok, piece_length} <- Map.fetch(info, "piece length"),
         creation_date <- get_creation_date(torrent_data),
         comment <- Map.get(torrent_data, "comment", ""),
         created_by <- Map.get(torrent_data, "created by", "") do
      files = get_files(info, name)
      files_size = Enum.reduce(files, 0, &(elem(&1, 1) + &2))
      pieces_hashes = get_hashes(Map.get(info, "pieces"))

      pieces_map =
        files
        |> file_pieces(piece_length)
        |> Enum.reduce(Map.new(), fn {piece_num, piece_offset, piece_size, file_path},
                                     pieces_map ->
          {:ok, piece_hash} = Map.fetch(pieces_hashes, piece_num)
          piece_info = {piece_hash, piece_offset, piece_size, file_path}

          Map.update(pieces_map, piece_num, [piece_info], &[piece_info | &1])
        end)
        |> Enum.map(fn {key, value} -> {key, Enum.reverse(value)} end)
        |> Map.new()

      {:ok,
       %__MODULE__{
         trackers: trackers,
         name: name,
         comment: comment,
         created_by: created_by,
         creation_date: creation_date,
         files: files,
         size: files_size,
         piece_length: piece_length,
         pieces: pieces_map
       }}
    end
  end

  defp get_creation_date(%{"creation date" => creation_date}) do
    case DateTime.from_unix(creation_date) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp get_creation_date(_), do: nil

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

  defp get_hashes(<<hash::bytes-size(20), rest::binary>>, num, acc),
    do: get_hashes(rest, num + 1, Map.put(acc, num, hash))

  defp file_pieces(files, piece_length, piece_offset \\ 0, piece_num \\ 0, pieces \\ [])

  defp file_pieces([], _piece_length, _piece_offset, _piece_num, pieces),
    do: Enum.reverse(pieces)

  defp file_pieces([file | rest], piece_length, piece_offset, piece_num, pieces) do
    {file_path, file_size} = file

    piece_rem = piece_length - rem(piece_offset, piece_length)
    piece_chunk_size = if piece_rem == 0, do: piece_length, else: piece_rem
    file_size_rem = file_size - piece_chunk_size

    cond do
      file_size_rem == 0 ->
        new_piece_offset = piece_offset + piece_chunk_size
        piece = {piece_num, piece_offset, piece_chunk_size, file_path}

        file_pieces(
          rest,
          piece_length,
          new_piece_offset,
          piece_num + 1,
          [
            piece | pieces
          ]
        )

      file_size_rem > 0 ->
        new_piece_offset = piece_offset + piece_chunk_size
        piece = {piece_num, piece_offset, piece_chunk_size, file_path}

        file_pieces(
          [{file_path, file_size_rem} | rest],
          piece_length,
          new_piece_offset,
          piece_num + 1,
          [
            piece | pieces
          ]
        )

      true ->
        piece_size = piece_chunk_size + file_size_rem
        new_piece_offset = piece_offset + piece_size
        piece = {piece_num, piece_offset, piece_size, file_path}
        file_pieces(rest, piece_length, new_piece_offset, piece_num, [piece | pieces])
    end
  end
end
