defmodule HiveTorrent.UDPTracker do
  use GenServer, restart: :transient

  require Logger

  def start_link(tracker_params) when is_map(tracker_params) do
    GenServer.start_link(__MODULE__, tracker_params)
  end

  @impl true
  def init(tracker_params) do
    Logger.info("Started tracker #{tracker_params.tracker_url}")
    state = %{tracker_params: tracker_params, tracker_data: nil, error: nil}

    {:ok, state, {:continue, :fetch_tracker_data}}
  end

  @impl true
  def handle_continue(:fetch_tracker_data, %{tracker_params: tracker_params} = state) do
    Logger.info("Init tracker #{tracker_params.tracker_url}")

    case url_to_inet_address(tracker_params.tracker_url) do
      {:ok, ip, port} ->
        send_message(ip, port)
        {:noreply, state}

      {:fatal_error, message} ->
        Logger.error(message)
        {:stop, {:shutdown, message}, state}

      {:error, message} ->
        Logger.error(message)
        {:noreply, state}
    end
  end

  defp send_message(ip, port) do
    HiveTorrent.UDPServer.send_connect_message(self(), ip, port)
    # {:ok, socket} = :gen_udp.open(0, [:binary])
    # :ok = :gen_udp.send(socket, ip, random_number, message)

    # :gen_udp.close(socket)
  end

  defp url_to_inet_address(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: nil} ->
        {:fatal_error, "Invalid URL: Host not found with tracker #{url}"}

      %URI{port: nil} ->
        {:fatal_error, "Invalid URL: Port not found with tracker #{url}"}

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

      {:error, reason} ->
        {:error, "Failed to resolve hostname, reason #{reason} with tracker #{hostname}"}
    end
  end
end
