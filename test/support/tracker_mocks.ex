defmodule HiveTorrent.TrackerMocks do
  alias HiveTorrent.StatsStorage

  def http_tracker_response() do
    ip_addresses =
      1..:rand.uniform(10)
      |> Range.to_list()
      |> Enum.map(fn _ -> create_ip() end)

    address =
      for ip <- ip_addresses do
        ports = 1..:rand.uniform(3) |> Range.to_list() |> Enum.map(fn _ -> create_port() end)
        {ip, ports}
      end
      |> Enum.shuffle()

    expected_address =
      Enum.reduce(address, Map.new(), fn {ip, ports}, acc ->
        Map.put(acc, ip_to_string(ip), ports)
      end)

    peers =
      address
      |> Enum.flat_map(fn {ip, ports} ->
        {a, b, c, d} = ip
        ip_bytes = <<a::8, b::8, c::8, d::8>>
        Enum.map(ports, fn port -> ip_bytes <> <<port::16>> end)
      end)
      |> Enum.reduce(fn address, acc -> address <> acc end)

    tracker_response_mock = %{
      "complete" => :rand.uniform(100),
      "downloaded" => :rand.uniform(9999),
      "incomplete" => :rand.uniform(100),
      "interval" => :rand.uniform(2000),
      "min interval" => :rand.uniform(1000),
      "peers" => peers
    }

    {tracker_response_mock, expected_address}
  end

  def create_http_tracker_announce_url() do
    protocol = ["http://", "https://"]
    domains = ["com", "io", "org"]
    letters = Enum.to_list(?A..?Z) ++ Enum.to_list(?a..?z) ++ Enum.to_list(?0..?9) ++ [?-, ?_]
    url_base = Enum.shuffle(letters) |> Enum.take(:rand.uniform(15))
    port = :rand.uniform(0xFFFF)
    "#{Enum.random(protocol)}#{url_base}.#{Enum.random(domains)}:#{port}/announce"
  end

  def create_info_hash(),
    do: :crypto.strong_rand_bytes(20)

  def create_stats(info_hash \\ create_info_hash()) when is_binary(info_hash) do
    piece_size = Enum.shuffle([256, 512, 1024, 2048]) |> List.first()
    pieces_idx = 0..(:rand.uniform(9) + 2) |> Range.to_list()

    pieces =
      pieces_idx
      |> Enum.map(fn piece_idx -> {piece_idx, {piece_size, false}} end)
      |> Map.new()

    pieces =
      Enum.shuffle(pieces_idx)
      |> Enum.take(round(length(pieces_idx) / 2))
      |> Enum.reduce(
        pieces,
        &Map.update!(&2, &1, fn {piece_size, _} -> {piece_size, true} end)
      )

    left =
      pieces
      |> Enum.filter(fn {_piece_idx, piece_stats} -> !elem(piece_stats, 1) end)
      |> Enum.reduce(0, fn {_, {piece_size, _}}, acc -> acc + piece_size end)

    %StatsStorage{
      info_hash: info_hash,
      # TODO later with random func that will be used in app
      peer_id: "12345678901234567890",
      port: :rand.uniform(65_536),
      uploaded: :rand.uniform(1_000_000),
      downloaded: piece_size * :rand.uniform(100),
      left: left,
      completed: [],
      pieces: pieces
    }
  end

  defp create_ip() do
    {:rand.uniform(255), :rand.uniform(255), :rand.uniform(255), :rand.uniform(255)}
  end

  defp ip_to_string(ip),
    do:
      ip
      |> Tuple.to_list()
      |> Enum.map(&to_string/1)
      |> Enum.join(".")

  defp create_port() do
    :rand.uniform(65_536)
  end
end
