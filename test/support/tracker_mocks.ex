defmodule HiveTorrent.TrackerMocks do
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

    expected_address = Enum.map(address, fn {ip, ports} -> {ip_to_string(ip), ports} end)
    # peers = Enum.map(address, fn {ip, ports} -> {ip_to_string(ip), ports} end)

    IO.inspect(address)

    ip =
      create_ip()
      |> ip_to_string()

    IO.puts(ip)

    %{
      "complete" => :rand.uniform(100),
      "downloaded" => :rand.uniform(9999),
      "incomplete" => :rand.uniform(100),
      "interval" => :rand.uniform(2000),
      "min interval" => :rand.uniform(1000),
      "peers" =>
        <<159, 148, 57, 222, 243, 160, 159, 148, 57, 222, 241, 147, 222, 148, 157, 222, 255, 47>>
    }
  end

  def create_info_hash(),
    do: :crypto.strong_rand_bytes(20)

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
