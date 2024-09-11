defmodule HiveTorrent.UDPServer do
  use GenServer

  require Logger

  alias HiveTorrent.UDPTracker

  # Client API

  def start_link(port) when is_integer(port) do
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  def send_message(message, ip, port) do
    GenServer.cast(__MODULE__, {:send, message, ip, port})
  end

  # Server Callbacks

  @impl true
  def init(port) do
    {:ok, socket} = :gen_udp.open(port, [:binary, active: true])
    {:ok, %{socket: socket}}
  end

  @impl true
  def handle_cast(
        {:send, message, ip, port},
        %{
          socket: socket
        } = state
      ) do
    case :gen_udp.send(socket, ip, port, message) do
      :ok ->
        Logger.info("Sent UDP connect message to #{format_address(ip, port)}.")

        {:noreply, state}

      {:error, reason} ->
        Logger.error(
          "Failed to send UDP connect message to #{format_address(ip, port)} with error #{reason}."
        )

        # TODO publish error
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:udp, socket, ip, port, data}, state) do
    address = format_address(ip, port)
    Logger.info("Received message on port #{inspect(socket)} from #{address}.")

    case UDPTracker.read_message_header(data) do
      {:ok, action, transaction_id} ->
        Logger.info(
          "Received message with action #{action} for transaction id #{transaction_id}."
        )

        broadcast_recv_message(data, address)

      {:error, reason} ->
        Logger.error("Dropping message, reason #{reason}.")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:udp_error, socket, :econnreset}, state) do
    Logger.error("Connection reset when sending message from socket: #{inspect(socket)}.")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{
        socket: socket
      }) do
    :gen_udp.close(socket)
  end

  defp format_address({a, b, c, d}, port), do: "#{a}.#{b}.#{c}.#{d}:#{port}"

  defp broadcast_recv_message(data, transaction_id) do
    Logger.info("Broadcasting response with transaction id #{transaction_id} to UPD trackers.")

    Registry.dispatch(HiveTorrent.TrackerRegistry, :udp_trackers, fn entries ->
      for {pid, _} <- entries do
        Logger.info(
          "Broadcasting response to #{inspect(pid)} with transaction id #{transaction_id}."
        )

        UDPTracker.broadcast_recv_message(pid, data)
      end
    end)
  end
end
