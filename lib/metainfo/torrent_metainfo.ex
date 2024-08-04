defmodule HiveTorrent.Torrent do
  alias HiveTorrent.Bencode.Serializer
  alias HiveTorrent.Bencode.Parser

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
          },
          info_hash: <<_::20>>
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
    :pieces,
    :info_hash
  ]

  def parse(torrent_raw_data, opts \\ [download_path: ""]) when is_binary(torrent_raw_data) do
    with {:ok, torrent_data} <- Parser.parse(torrent_raw_data),
         {:ok, trackers} <- get_trackers(torrent_data),
         {:ok, info} <- get_info(torrent_data),
         {:ok, piece_length} <- get_piece_length(info),
         {:ok, name} <- Map.fetch(info, "name"),
         creation_date <- get_creation_date(torrent_data),
         comment <- Map.get(torrent_data, "comment", ""),
         created_by <- Map.get(torrent_data, "created by", "") do
      download_path = Keyword.get(opts, :download_path, "")
      files = get_files(info, name, download_path)
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

      {:ok, bencoded_info} = Serializer.encode(info)
      info_hash = :crypto.hash(:sha, bencoded_info)

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
         pieces: pieces_map,
         info_hash: info_hash
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

  defp get_piece_length(%{"piece length" => piece_length}), do: {:ok, piece_length}

  defp get_piece_length(_), do: {:error, :no_piece_length}

  defp get_info(%{"info" => info}), do: {:ok, info}

  defp get_info(_), do: {:error, :no_info}

  defp get_trackers(%{"announce-list" => announce_list}), do: {:ok, List.flatten(announce_list)}

  defp get_trackers(%{"announce" => announce}), do: {:ok, [announce]}

  defp get_trackers(_), do: {:error, :no_trackers}

  defp get_files(%{"files" => files}, name, download_path) do
    Enum.map(files, fn %{"length" => length, "path" => path} ->
      {Path.join([download_path, name, path]), length}
    end)
  end

  defp get_files(%{"length" => length}, name, download_path) do
    [{Path.join([download_path, name]), length}]
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
