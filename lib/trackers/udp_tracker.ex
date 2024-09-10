defmodule HiveTorrent.UDPTracker do
  use GenServer, restart: :transient

  require Logger

  alias HiveTorrent.StatsStorage

  @udp_protocol_id 0x0000041727101980

  def broadcast_recv_message(pid, message) do
    GenServer.cast(pid, {:broadcast, message})
  end

  def read_message_header(<<action::32, transaction_id::32, _rest::binary>>) do
    with {:ok, action_value} <- map_message_action(action),
         formatted_trans_id <- format_transaction_id(transaction_id) do
      {:ok, action_value, formatted_trans_id}
    end
  end

  def read_message_header(_message_resp) do
    {:error, "Invalid message format received"}
  end

  def start_link(tracker_params) when is_map(tracker_params) do
    GenServer.start_link(__MODULE__, tracker_params)
  end

  # Server Callbacks

  @impl true
  def init(tracker_params) do
    Logger.info("Started tracker #{tracker_params.tracker_url}")

    {:ok, _value} = Registry.register(HiveTorrent.TrackerRegistry, :udp_trackers, tracker_params)

    state = %{
      tracker_params: tracker_params,
      tracker_data: nil,
      error: nil,
      transaction_id: nil,
      action: nil,
      target_action: nil
    }

    {:ok, state, {:continue, :announce}}
  end

  @impl true
  def handle_continue(:announce, %{tracker_params: tracker_params} = state) do
    Logger.info("Init tracker #{tracker_params.tracker_url}")

    handle_info(:schedule_announce, state)
  end

  @impl true
  def handle_info(:schedule_announce, %{tracker_params: tracker_params} = state) do
    case url_to_inet_address(tracker_params.tracker_url) do
      {:ok, ip, port} ->
        transaction_id = send_connect_message(ip, port)

        Logger.info(
          "Sent connect request with transaction id #{format_transaction_id(transaction_id)}"
        )

        {:noreply, %{state | transaction_id: transaction_id, action: 0, target_action: 1}}

      {:fatal_error, message} ->
        Logger.error(message)
        {:stop, {:shutdown, message}, state}

      {:error, message} ->
        Logger.error(message)
        {:noreply, state}
    end

    # tracker_data_response = fetch_tracker_data(tracker_params)

    # case tracker_data_response do
    #   {:ok, tracker_data} ->
    #     Logger.debug(
    #       "Received tracker(#{tracker_params.tracker_url}) data: #{inspect(tracker_data_response)}"
    #     )

    #     TrackerStorage.put(tracker_data)
    #     schedule_fetch(tracker_data)

    #     new_state = state |> Map.put(:tracker_data, tracker_data) |> Map.put(:error, nil)
    #     {:noreply, new_state}

    #   {:error, reason} ->
    #     Logger.error(reason)
    #     schedule_error_fetch()
    #     {:noreply, Map.put(state, :error, reason)}
    # end
  end

  @impl true
  def handle_cast(
        {:broadcast, message},
        %{transaction_id: transaction_id, action: action, tracker_params: tracker_params} = state
      ) do
    <<msg_action::32, msg_transaction_id::32, rest::binary>> = message

    cond do
      transaction_id !== msg_transaction_id ->
        Logger.debug("Transaction ids do not match, skipping message processing.")
        {:noreply, state}

      action !== msg_action ->
        Logger.error(
          "Received message with correct transaction id #{format_transaction_id(transaction_id)} but invalid actions. Expected action #{action}, received action #{msg_action}."
        )

        {:noreply, state}

      true ->
        Logger.info(
          "Start processing of the message received with transaction id #{transaction_id}"
        )

        <<connection_id::64>> = rest

        IO.puts(connection_id)
        IO.inspect(tracker_params)

        {:noreply, state}
    end
  end

  defp send_connect_message(ip, port) do
    transaction_id = :rand.uniform(0xFFFFFFFF)
    connect_message = <<@udp_protocol_id::64>> <> <<0::32>> <> <<transaction_id::32>>
    HiveTorrent.UDPServer.send_message(connect_message, ip, port)
    transaction_id
  end

  defp send_announce_message(connection_id, info_hash, ip, port) do
    {:ok,
     %StatsStorage{
       peer_id: peer_id,
       port: peer_port,
       uploaded: uploaded,
       downloaded: downloaded,
       left: left
     }} = StatsStorage.get(info_hash)

    action = 1
    transaction_id = :rand.uniform(0xFFFFFFFF)

    announce_message =
      <<connection_id::64>> <>
        <<action::32>> <>
        <<transaction_id::32>> <>
        info_hash <> peer_id <> <<downloaded::64>> <> <<left::64>> <> <<uploaded::64>>

    HiveTorrent.UDPServer.send_message(announce_message, ip, port)
    transaction_id
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

  defp map_message_action(action) do
    case action do
      0 -> {:ok, "connect"}
      1 -> {:ok, "announce"}
      2 -> {:ok, "scrape"}
      3 -> {:ok, "error"}
      val -> {:error, "Invalid value for action #{val}"}
    end
  end

  defp format_transaction_id(transaction_id) when is_integer(transaction_id),
    do: Integer.to_string(transaction_id, 16)
end
