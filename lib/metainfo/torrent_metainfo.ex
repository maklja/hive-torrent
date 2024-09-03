defmodule HiveTorrent.TorrentError do
  @moduledoc """
  Raised when torrent content is invalid.
  """

  defexception [:message]

  @type t :: %__MODULE__{message: String.t()}
end

defmodule HiveTorrent.Torrent do
  @moduledoc """
  Parse, validate and transform torrent content into the struct.

  ## Struct

  The `HiveTorrent.Torrent` struct contains the following fields:

  * `:trackers` - The list of the tracker urls.
  * `:name` - The name of the torrent.
  * `:comment` - A description or comment added to the torrent to provide additional context about its content.
  * `:created_by` - The identifier or name of the user who created the torrent.
  * `:creation_date` - The date and time when the torrent was created.
  * `:files` - A list of files included in the torrent. Each file entry contains:
    - The full path to the file.
    - The size of the file in bytes.
  * `:size` - The total size of all files contained within the torrent.
  * `:piece_length` - The length of a single piece of the torrent, in bytes.
  * `:pieces` - A map of pieces, where each entry represents a piece of the torrent. The key is the index of the piece, and the value is a map containing:
    - The hash of the piece.
    - The byte offset of the piece in the file.
    - The size of the piece in bytes.
    - The path of the file containing the piece.
  * `:info_hash` - The hash of the info section of the torrent, used for identifying the torrent with trackers.
  """

  alias HiveTorrent.Bencode.Serializer
  alias HiveTorrent.Bencode.Parser
  alias HiveTorrent.Bencode.SyntaxError

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
          info_hash: binary()
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

  @doc """
  Parse, validate and populate HiveTorrent.Torrent struct with torrent data.

  Returns {:ok, HiveTorrent.Torrent}, otherwise {:error, error}}

  ## Examples
      iex> torrent_file = %{
      ...> "announce" => "http://tracker.example.com:8080/announce",
      ...> "created by" => "Hive torrent",
      ...> "comment" => "Hive comment",
      ...> "creation date" => 1_722_686_833,
      ...> "info" => %{
      ...>   "length" => 60,
      ...>   "name" => "example.txt",
      ...>   "piece length" => 20,
      ...>   "pieces" => "abcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcde"
      ...> }
      ...> }
      ...> {:ok, torrent_data} = Serializer.encode(torrent_file)
      ...> Torrent.parse(torrent_data)
      {:ok, %HiveTorrent.Torrent {
        comment: "Hive comment",
        created_by: "Hive torrent",
        creation_date: ~U[2024-08-03 12:07:13Z],
        files: [{"example.txt", 60}],
        info_hash: <<107, 197, 55, 162, 99, 32, 240, 243, 229, 197, 95, 219, 153, 235, 56, 40, 255, 151, 162, 22>>,
        name: "example.txt",
        piece_length: 20,
        pieces: %{
          0 => [{"abcdeabcdeabcdeabcde", 0, 20, "example.txt"}],
          1 => [{"abcdeabcdeabcdeabcde", 20, 20, "example.txt"}],
          2 => [{"abcdeabcdeabcdeabcde", 40, 20, "example.txt"}]
        },
        size: 60,
        trackers: ["http://tracker.example.com:8080/announce"]
      }}

      iex> torrent_file = %{
      ...> # missing announce url
      ...> "created by" => "Hive torrent",
      ...> "comment" => "Hive comment",
      ...> "creation date" => 1_722_686_833,
      ...> "info" => %{
      ...>   "length" => 60,
      ...>   "name" => "example.txt",
      ...>   "piece length" => 20,
      ...>   "pieces" => "abcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcde"
      ...> }
      ...> }
      ...> {:ok, torrent_data} = Serializer.encode(torrent_file)
      ...> Torrent.parse(torrent_data)
      {:error, "No trackers found"}
  """
  @spec parse(iodata(), download_path: String.t()) ::
          {:ok, t()} | {:error, String.t() | SyntaxError.t()}
  def parse(torrent_raw_data, opts \\ [download_path: ""]) when is_binary(torrent_raw_data) do
    download_path = Keyword.get(opts, :download_path, "")

    with {:ok, torrent_data} <- Parser.parse(torrent_raw_data),
         {:ok, trackers} <- get_trackers(torrent_data),
         {:ok, info} <- get_info(torrent_data),
         {:ok, piece_length} <- get_piece_length(info),
         name <- Map.get(info, "name", "torrent_#{DateTime.now!("Etc/UTC")}"),
         {:ok, files} <- get_files(info, name, download_path),
         {:ok, pieces_hashes} <- get_hashes(Map.get(info, "pieces")) do
      creation_date = get_creation_date(torrent_data)
      comment = Map.get(torrent_data, "comment", "")
      created_by = Map.get(torrent_data, "created by", "")
      files_size = Enum.reduce(files, 0, &(elem(&1, 1) + &2))

      total_number_pieces_hashes = :math.ceil(files_size / piece_length)

      if map_size(pieces_hashes) != total_number_pieces_hashes do
        {:error, "Number of piece hashes not matching total file size pieces"}
      else
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
  end

  @doc """
  Parse, validate and populate HiveTorrent.Torrent struct with torrent data.

  Returns HiveTorrent.Torrent, otherwise throws a HiveTorrent.TorrentError.

  ## Examples
      iex> torrent_file = %{
      ...> "announce" => "http://tracker.example.com:8080/announce",
      ...> "created by" => "Hive torrent",
      ...> "comment" => "Hive comment",
      ...> "creation date" => 1_722_686_833,
      ...> "info" => %{
      ...>   "length" => 60,
      ...>   "name" => "example.txt",
      ...>   "piece length" => 20,
      ...>   "pieces" => "abcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcde"
      ...> }
      ...> }
      ...> {:ok, torrent_data} = Serializer.encode(torrent_file)
      ...> Torrent.parse!(torrent_data)
      %HiveTorrent.Torrent {
        comment: "Hive comment",
        created_by: "Hive torrent",
        creation_date: ~U[2024-08-03 12:07:13Z],
        files: [{"example.txt", 60}],
        info_hash: <<107, 197, 55, 162, 99, 32, 240, 243, 229, 197, 95, 219, 153, 235, 56, 40, 255, 151, 162, 22>>,
        name: "example.txt",
        piece_length: 20,
        pieces: %{
          0 => [{"abcdeabcdeabcdeabcde", 0, 20, "example.txt"}],
          1 => [{"abcdeabcdeabcdeabcde", 20, 20, "example.txt"}],
          2 => [{"abcdeabcdeabcdeabcde", 40, 20, "example.txt"}]
        },
        size: 60,
        trackers: ["http://tracker.example.com:8080/announce"]
      }

      iex> torrent_file = %{
      ...> # missing announce url
      ...> "created by" => "Hive torrent",
      ...> "comment" => "Hive comment",
      ...> "creation date" => 1_722_686_833,
      ...> "info" => %{
      ...>   "length" => 60,
      ...>   "name" => "example.txt",
      ...>   "piece length" => 20,
      ...>   "pieces" => "abcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcde"
      ...> }
      ...> }
      ...> {:ok, torrent_data} = Serializer.encode(torrent_file)
      ...> Torrent.parse!(torrent_data)
      ** (HiveTorrent.TorrentError) No trackers found
  """
  @spec parse!(iodata(), download_path: String.t()) :: t() | no_return()
  def parse!(torrent_raw_data, opts \\ [download_path: ""]) when is_binary(torrent_raw_data) do
    case parse(torrent_raw_data, opts) do
      {:ok, torrent} -> torrent
      {:error, reason} when is_bitstring(reason) -> raise HiveTorrent.TorrentError, reason
      {:error, e} when is_exception(e) -> raise e
      _ -> raise HiveTorrent.TorrentError, "Unknown error"
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

  defp get_piece_length(_), do: {:error, "No piece length"}

  defp get_info(%{"info" => info}), do: {:ok, info}

  defp get_info(_), do: {:error, "No info found"}

  defp get_trackers(%{"announce-list" => announce_list}), do: {:ok, List.flatten(announce_list)}

  defp get_trackers(%{"announce" => announce}), do: {:ok, [announce]}

  defp get_trackers(_), do: {:error, "No trackers found"}

  defp get_files(%{"files" => files}, name, download_path) do
    processed_files =
      Enum.map(files, fn %{"length" => length, "path" => path} ->
        {Path.join([download_path, name, path]), length}
      end)

    {:ok, processed_files}
  end

  defp get_files(%{"length" => length}, name, download_path) do
    {:ok, [{Path.join([download_path, name]), length}]}
  end

  defp get_files(_, _name, _download_path) do
    {:error, "No files found"}
  end

  defp get_hashes(hash, num \\ 0, acc \\ %{})

  defp get_hashes("", _num, acc), do: {:ok, acc}

  defp get_hashes(<<hash::bytes-size(20), rest::binary>>, num, acc),
    do: get_hashes(rest, num + 1, Map.put(acc, num, hash))

  defp get_hashes(<<_hash::binary>>, _num, _acc),
    do: {:error, "Corrupted pieces hash"}

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
