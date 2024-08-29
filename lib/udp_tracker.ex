defmodule HiveTorrent.UDPTracker do
  use GenServer

  def start_link(port) do
    GenServer.start_link(__MODULE__, port)
  end

  @impl true
  def init(port) do
    {:ok, socket} = :gen_udp.open(port, [:binary, active: true])
    {:ok, socket}
  end

  @impl true
  def handle_call({:send}, _from, state) do
    socket = state
    {:ok, ip, port} = url_to_inet_address("udp://tracker.tiny-vps.com:6969/announce")
    response = :gen_udp.send(socket, ip, port, <<>>)

    IO.inspect(response)

    {:reply, nil, state}
  end

  # udp://tracker.tiny-vps.com:6969/announce
  def handle_info({:udp, _socket, ip, port, message}, socket) do
    IO.puts("Received message from #{inspect(ip)}:#{port}: #{message}")
    {:noreply, socket}
  end

  defp url_to_inet_address(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: nil} ->
        {:error, "Invalid URL: Host not found"}

      %URI{port: nil} ->
        {:error, "Invalid URL: Port not found"}

      %URI{host: host, port: port} ->
        host_to_inet_address(host, port)
    end
  end

  defp host_to_inet_address(host, port) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip_address} ->
        {:ok, ip_address, port}

      {:error, :einval} ->
        resolve_hostname_to_inet_address(host, port)
    end
  end

  defp resolve_hostname_to_inet_address(hostname, port) do
    case :inet.getaddr(String.to_charlist(hostname), :inet) do
      {:ok, ip_address} ->
        {:ok, ip_address, port}

      {:error, _reason} ->
        {:error, "Failed to resolve hostname"}
    end
  end

  # def send_message(ip, port, message) do
  #   :gen_udp.send(socket, ip, port, message)
  # end
end
