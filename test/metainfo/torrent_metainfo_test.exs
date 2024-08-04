defmodule HiveTorrent.TorrentTest do
  alias HiveTorrent.Torrent
  alias HiveTorrent.Bencode.Serializer
  alias HiveTorrent.Bencode.SyntaxError

  use ExUnit.Case

  doctest HiveTorrent.Torrent

  import Map, only: [fetch!: 2]

  test "parse valid torrent with length" do
    announce = "http://tracker.example.com:8080/announce"
    created_by = "Hive torrent"
    comment = "Hive comment"
    creation_date = 1_722_686_833
    piece_length = 20
    file_size = 60
    file_name = "example.txt"

    torrent_file_info = %{
      "length" => file_size,
      "name" => file_name,
      "piece length" => piece_length,
      "pieces" => "abcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcde"
    }

    torrent_file = %{
      "announce" => announce,
      "created by" => created_by,
      "comment" => comment,
      "creation date" => creation_date,
      "info" => torrent_file_info
    }

    {:ok, torrent_data} = Serializer.encode(torrent_file)
    {:ok, torrent} = Torrent.parse(torrent_data)

    assert torrent.trackers == [announce]
    assert torrent.name == fetch!(torrent_file_info, "name")
    assert torrent.comment == comment
    assert torrent.created_by == created_by
    assert torrent.creation_date == DateTime.from_unix!(creation_date)
    assert torrent.piece_length == piece_length
    assert torrent.size == file_size
    assert torrent.files == [{file_name, file_size}]

    assert torrent.pieces == %{
             0 => [{"abcdeabcdeabcdeabcde", 0, 20, "example.txt"}],
             1 => [{"abcdeabcdeabcdeabcde", 20, 20, "example.txt"}],
             2 => [{"abcdeabcdeabcdeabcde", 40, 20, "example.txt"}]
           }

    info_hash = :crypto.hash(:sha, Serializer.encode!(torrent_file_info))
    assert torrent.info_hash == info_hash
  end

  test "parse valid torrent with files" do
    announce_list = [
      "http://tracker.example.com:8080/announce",
      "https://tracker.example.com:8080/announce"
    ]

    created_by = "Hive torrent"
    comment = "Hive comment"
    creation_date = 1_722_686_833
    piece_length = 20
    file_name = "example"

    torrent_file_info = %{
      "name" => file_name,
      "piece length" => piece_length,
      "files" => [
        %{"path" => "exampe.txt", "length" => 33},
        %{"path" => "video.mp4", "length" => 27}
      ],
      "pieces" => "abcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcde"
    }

    torrent_file = %{
      "announce-list" => announce_list,
      "created by" => created_by,
      "comment" => comment,
      "creation date" => creation_date,
      "info" => torrent_file_info
    }

    {:ok, torrent_data} = Serializer.encode(torrent_file)
    {:ok, torrent} = Torrent.parse(torrent_data, download_path: "/tmp/torrent")

    assert torrent.trackers == announce_list
    assert torrent.name == fetch!(torrent_file_info, "name")
    assert torrent.comment == comment
    assert torrent.created_by == created_by
    assert torrent.creation_date == DateTime.from_unix!(creation_date)
    assert torrent.piece_length == piece_length
    assert torrent.size == 60

    assert torrent.files == [
             {"/tmp/torrent/example/exampe.txt", 33},
             {"/tmp/torrent/example/video.mp4", 27}
           ]

    assert torrent.pieces == %{
             0 => [{"abcdeabcdeabcdeabcde", 0, 20, "/tmp/torrent/example/exampe.txt"}],
             1 => [
               {"abcdeabcdeabcdeabcde", 20, 13, "/tmp/torrent/example/exampe.txt"},
               {"abcdeabcdeabcdeabcde", 33, 7, "/tmp/torrent/example/video.mp4"}
             ],
             2 => [{"abcdeabcdeabcdeabcde", 40, 20, "/tmp/torrent/example/video.mp4"}]
           }

    info_hash = :crypto.hash(:sha, Serializer.encode!(torrent_file_info))
    assert torrent.info_hash == info_hash
  end

  test "parse corrupted torrent content" do
    torrent_data = "d8:announce312e"
    {:error, error} = Torrent.parse(torrent_data)

    assert error == %SyntaxError{message: "Unexpected token '312e?' while parsing"}
  end

  test "parse torrent without trackers" do
    created_by = "Hive torrent"
    comment = "Hive comment"
    creation_date = 1_722_686_833
    piece_length = 20
    file_size = 60
    file_name = "example.txt"

    torrent_file_info = %{
      "length" => file_size,
      "name" => file_name,
      "piece length" => piece_length,
      "pieces" => "abcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcde"
    }

    torrent_file = %{
      "created by" => created_by,
      "comment" => comment,
      "creation date" => creation_date,
      "info" => torrent_file_info
    }

    {:ok, torrent_data} = Serializer.encode(torrent_file)
    assert Torrent.parse(torrent_data) == {:error, :no_trackers}
  end

  test "parse torrent without info" do
    announce = "http://tracker.example.com:8080/announce"
    created_by = "Hive torrent"
    comment = "Hive comment"
    creation_date = 1_722_686_833

    torrent_file = %{
      "announce" => announce,
      "created by" => created_by,
      "comment" => comment,
      "creation date" => creation_date
    }

    {:ok, torrent_data} = Serializer.encode(torrent_file)
    assert Torrent.parse(torrent_data) == {:error, :no_info}
  end

  test "parse torrent without piece length" do
    announce = "http://tracker.example.com:8080/announce"
    created_by = "Hive torrent"
    comment = "Hive comment"
    creation_date = 1_722_686_833
    file_size = 60
    file_name = "example.txt"

    torrent_file_info = %{
      "length" => file_size,
      "name" => file_name,
      "pieces" => "abcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcdeabcde"
    }

    torrent_file = %{
      "announce" => announce,
      "created by" => created_by,
      "comment" => comment,
      "creation date" => creation_date,
      "info" => torrent_file_info
    }

    {:ok, torrent_data} = Serializer.encode(torrent_file)
    assert Torrent.parse(torrent_data) == {:error, :no_piece_length}
  end
end
