defmodule HiveTorrent.TrackerMocks do
  alias HiveTorrent.StatsStorage

  def udp_tracker_announce_response() do
    interval = Faker.random_between(0, 2_000)
    leechers = Faker.random_between(0, 100)
    seeders = Faker.random_between(0, 100)
    {peers, expected_peers} = create_peers_response()

    tracker_response_mock =
      <<interval::unsigned-integer-size(32), leechers::unsigned-integer-size(32),
        seeders::unsigned-integer-size(32)>> <> peers

    {tracker_response_mock,
     %{
       interval: interval,
       leechers: leechers,
       seeders: seeders,
       peers: expected_peers
     }}
  end

  def http_tracker__announce_response() do
    {peers, expected_peers} = create_peers_response()

    tracker_response_mock = %{
      "complete" => Faker.random_between(0, 100),
      "downloaded" => Faker.random_between(0, 9999),
      "incomplete" => Faker.random_between(0, 100),
      "interval" => Faker.random_between(0, 2_000),
      "min interval" => Faker.random_between(0, 1_000),
      "peers" => peers
    }

    {tracker_response_mock, expected_peers}
  end

  def create_peers_response() do
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

    {peers, expected_address}
  end

  def create_http_tracker_announce_url() do
    port = create_port()
    "#{Faker.Internet.url()}:#{port}/announce"
  end

  @spec create_udp_tracker_announce_url() :: <<_::64, _::_*8>>
  def create_udp_tracker_announce_url() do
    port = create_port()
    "udp://#{Faker.Internet.domain_name()}:#{port}/announce"
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
      port: create_port(),
      uploaded: Faker.random_between(0, 1_000_000),
      downloaded: piece_size * Faker.random_between(0, 100),
      left: left,
      completed: [],
      pieces: pieces
    }
  end

  def create_ip() do
    Faker.Internet.ip_v4_address()
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
    |> List.to_tuple()
  end

  def create_port() do
    Faker.random_between(1024, 65535)
  end

  defp ip_to_string(ip),
    do:
      ip
      |> Tuple.to_list()
      |> Enum.map(&to_string/1)
      |> Enum.join(".")
end
