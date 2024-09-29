defmodule HiveTorrent.UDPTrackerSocket do
  use GenServer

  require Logger

  alias HiveTorrent.Tracker

  @udp_protocol_id 0x0000041727101980
  @connect_action 0
  @announce_action 1
  @scrape_action 2
  @error_action 3

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def send_announce_message(message, ip, port) do
    GenServer.call(__MODULE__, {:send_announce, message, ip, port})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    port = Keyword.fetch!(opts, :port)
    message_callback = Keyword.fetch!(opts, :message_callback)

    {:ok, socket} = :gen_udp.open(port, [:binary, active: true])
    {:ok, %{socket: socket, message_callback: message_callback, requests: %{}}}
  end

  @impl true
  def handle_call({:send_announce, message_chunk, ip, port}, _from, state) do
    transaction_id = :rand.uniform(0xFFFFFFFF)

    transaction_data = %{
      id: transaction_id,
      action: @connect_action,
      target_action: @announce_action,
      message: message_chunk,
      ip: ip,
      port: port,
      connection_id: nil
    }

    Process.send(self(), {:send_request, transaction_id}, [:noconnect])

    updated_requests =
      Map.put(
        state.requests,
        transaction_id,
        transaction_data
      )

    {:reply, transaction_id, %{state | requests: updated_requests}}
  end

  @impl true
  def handle_info(
        {:send_request, transaction_id},
        %{requests: requests, message_callback: message_callback, socket: socket} = state
      ) do
    formatted_trans_id = Tracker.format_transaction_id(transaction_id)

    with {:ok, %{ip: ip, port: port} = transaction_data} <-
           Map.fetch(requests, transaction_id),
         {:ok, message} <- create_message(transaction_data),
         :ok <- :gen_udp.send(socket, ip, port, message) do
      Logger.info("Sent UDP connect message to #{format_address(ip, port)}.")
      {:noreply, state}
    else
      {:error, reason} ->
        Logger.error(
          "Failed to send UDP connect message for transaction #{formatted_trans_id}, reason #{reason}, data #{inspect(Map.get(requests, transaction_id))}."
        )

        broadcast_message(@error_action, reason, transaction_id, message_callback)
        {:noreply, %{state | requests: Map.delete(requests, transaction_id)}}

      _ ->
        Logger.error(
          "Failed to send UDP connect message for transaction #{transaction_id}, data #{inspect(Map.get(requests, transaction_id))}."
        )

        broadcast_message(
          @error_action,
          "Unknown error received on transaction #{formatted_trans_id}.",
          transaction_id,
          message_callback
        )

        {:noreply, %{state | requests: Map.delete(requests, transaction_id)}}
    end
  end

  @impl true
  def handle_info({:udp, socket, ip, port, data}, state) do
    address = format_address(ip, port)
    Logger.info("Received message on port #{inspect(socket)} from #{address}.")

    with {:ok, action, transaction_id, message_body} <- parse_recv_message(data),
         {:ok, transaction_data} <- Map.fetch(state.requests, transaction_id),
         {:done, message_body, transaction_data} <-
           handle_recv_message(action, transaction_data, message_body) do
      Logger.info(
        "Received message with action #{action} for transaction id #{Tracker.format_transaction_id(transaction_id)}."
      )

      broadcast_message(
        transaction_data.action,
        message_body,
        transaction_data.id,
        state.message_callback
      )

      {:noreply, %{state | requests: Map.delete(state.requests, transaction_data.id)}}
    else
      {:cont, transaction_data} ->
        Logger.info(
          "Sending next action #{transaction_data.action} for transaction id #{Tracker.format_transaction_id(transaction_data.id)}."
        )

        Process.send(self(), {:send_request, transaction_data.id}, [:noconnect])

        {:noreply,
         %{state | requests: Map.put(state.requests, transaction_data.id, transaction_data)}}

      :error ->
        Logger.error("Transaction data not found.")

        {:noreply, state}

      {:error, reason} ->
        Logger.error("Dropping message, reason #{reason}.")
        {:noreply, state}

      {:error, reason, transaction_data} ->
        Logger.error(reason)

        broadcast_message(
          @error_action,
          reason,
          transaction_data.id,
          state.message_callback
        )

        {:noreply, %{state | requests: Map.delete(state.requests, transaction_data.id)}}

      {:fatal_error, reason} ->
        Logger.critical(reason)
        {:stop, {:error, reason}, state}
    end
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

  defp handle_recv_message(recv_action, transaction_data, message_body) do
    %{id: transaction_id, action: action, target_action: target_action} = transaction_data

    cond do
      recv_action === @error_action ->
        {
          :error,
          "Received error response for transaction #{Tracker.format_transaction_id(transaction_id)}, reason #{message_body}.",
          transaction_data
        }

      recv_action !== action ->
        {:error,
         "Requested action #{action} is not matched with received action #{recv_action} for transaction #{Tracker.format_transaction_id(transaction_id)}.",
         transaction_data}

      action === @connect_action ->
        <<connection_id::64>> = message_body

        {:cont, %{transaction_data | action: target_action, connection_id: connection_id}}

      action === @announce_action ->
        {:done, message_body, transaction_data}

      true ->
        # this shouldn't happen ever, crash in case happens because it is unexpected state
        {:fatal_error, "Process unsupported action #{recv_action}."}
    end
  end

  defp parse_recv_message(<<action::32, transaction_id::32, message_body::binary>>) do
    {:ok, action, transaction_id, message_body}
  end

  defp parse_recv_message(_message) do
    {:error, "Invalid message format received."}
  end

  defp create_message(%{action: @connect_action, id: transaction_id}) do
    {:ok, <<@udp_protocol_id::64, @connect_action::32, transaction_id::32>>}
  end

  defp create_message(%{
         action: @announce_action,
         id: transaction_id,
         connection_id: connection_id,
         message: message
       }) do
    {:ok, <<connection_id::64, @announce_action::32, transaction_id::32>> <> message}
  end

  defp create_message(invalid_transaction_data) do
    {:error, "Unsupported transaction data structure #{inspect(invalid_transaction_data)}."}
  end

  defp format_address({a, b, c, d}, port), do: "#{a}.#{b}.#{c}.#{d}:#{port}"

  defp broadcast_message(@announce_action, data, transaction_id, message_callback) do
    message_callback.(:announce, transaction_id, data)
  end

  defp broadcast_message(@scrape_action, data, transaction_id, message_callback) do
    message_callback.(:scrape, transaction_id, data)
  end

  defp broadcast_message(@error_action, error, transaction_id, message_callback) do
    message_callback.(:error, transaction_id, error)
  end
end
