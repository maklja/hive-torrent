defmodule HiveTorrent.UDPServer do
  use GenServer

  require Logger

  @udp_protocol_id 0x0000041727101980

  # Client API

  def start_link(port) when is_integer(port) do
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  def send_connect_message(pid, ip, port) do
    GenServer.cast(__MODULE__, {:send_connect, pid, ip, port})
  end

  # Server Callbacks

  @impl true
  def init(port) do
    {:ok, socket} = :gen_udp.open(port, [:binary, active: true])
    {:ok, %{socket: socket, transactions: %{}}}
  end

  @impl true
  def handle_cast(
        {:send_connect, pid, ip, port},
        state
      ) do
    %{
      socket: socket,
      transactions: transactions
    } = state

    case send_connect_request(socket, ip, port) do
      {:ok, transaction_id} ->
        Logger.info("Sent UDP connect message to #{format_address(ip, port)}.")

        updated_transactions = Map.put(transactions, transaction_id, pid)
        {:noreply, %{state | transactions: updated_transactions}}

      {:error, reason} ->
        Logger.error(
          "Failed to send UDP connect message to #{format_address(ip, port)} with error #{reason}."
        )

        # TODO send error to the client
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:udp, socket, ip, port, data}, %{transactions: transactions} = state) do
    {action, transaction_id} = get_message_header(data)
    address = format_address(ip, port)

    Logger.info(
      "Received message on port #{inspect(socket)} with with header (#{map_message_action(action)}, #{transaction_id}) from #{address}"
    )

    case Map.fetch(transactions, transaction_id) do
      {:ok, pid} ->
        Logger.info("Returning response to #{inspect(pid)} received from #{address}")

      :error ->
        Logger.error("Unknown transaction id #{transaction_id}, dropping message from #{address}")
    end

    IO.puts("Received '#{inspect(data)}' from #{format_ip(ip)}:#{port}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:udp_error, socket, :econnreset}, state) do
    Logger.error("Connection reset when sending message from socket: #{inspect(socket)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(:timeout, state) do
    # Handle other timeouts or periodic tasks here
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{
        socket: socket
      }) do
    :gen_udp.close(socket)
  end

  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  defp format_address({a, b, c, d}, port), do: "#{a}.#{b}.#{c}.#{d}:#{port}"

  defp send_connect_request(socket, ip, port) do
    transaction_id = :rand.uniform(0xFFFFFFFF)
    message = <<@udp_protocol_id::64>> <> <<0::32>> <> <<transaction_id::32>>

    case :gen_udp.send(socket, ip, port, message) do
      :ok -> {:ok, transaction_id}
      error -> error
    end
  end

  defp get_message_header(<<action::32, transaction_id::32, _rest::binary>>),
    do: {action, transaction_id}

  defp map_message_action(action) when is_integer(action) do
    case action do
      0 -> "connect"
      1 -> "announce"
      2 -> "scrape"
    end
  end
end
