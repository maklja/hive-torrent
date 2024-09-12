defmodule HiveTorrent.UDPTracker do
  use GenServer, restart: :transient

  require Logger

  # TODO timeout UDP
  # TODO closed callback
  # TODO scrape

  alias HiveTorrent.StatsStorage
  alias HiveTorrent.Tracker
  alias HiveTorrent.TrackerStorage

  @default_interval 30 * 60
  @default_error_interval 30
  @udp_protocol_id 0x0000041727101980
  @connect_action 0
  @announce_action 1
  # @scrape_action 2
  @error_action 3

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
    {:error, "Invalid message format received."}
  end

  def start_link(tracker_params) when is_map(tracker_params) do
    GenServer.start_link(__MODULE__, tracker_params)
  end

  # Server Callbacks

  @impl true
  def init(tracker_params) do
    Logger.info("Started tracker #{tracker_params.tracker_url}.")

    {:ok, _value} = Registry.register(HiveTorrent.TrackerRegistry, :udp_trackers, tracker_params)

    state = %{
      tracker_params: tracker_params,
      tracker_data: nil,
      error: nil,
      transaction_id: nil,
      connection_id: nil,
      action: @connect_action,
      target_action: nil,
      event: Tracker.started().key,
      key: :rand.uniform(0xFFFFFFFF)
    }

    {:ok, state, {:continue, :announce}}
  end

  @impl true
  def handle_continue(:announce, %{tracker_params: tracker_params} = state) do
    Logger.info("Init tracker #{tracker_params.tracker_url}")

    handle_info(:schedule_announce, %{state | event: Tracker.started().key})
  end

  @impl true
  def handle_info(:schedule_announce, %{tracker_params: tracker_params} = state) do
    case url_to_inet_address(tracker_params.tracker_url) do
      {:ok, ip, port} ->
        transaction_id = send_message(ip, port, state)

        Logger.info("Sent message with transaction id #{format_transaction_id(transaction_id)}.")

        {:noreply,
         %{
           state
           | transaction_id: transaction_id
         }}

      {:fatal_error, message} ->
        Logger.error(message)
        {:stop, {:shutdown, message}, state}

      {:error, message} ->
        Logger.error(message)
        schedule_fetch(nil)

        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(
        {:broadcast, message},
        %{
          transaction_id: transaction_id,
          action: action
        } = state
      ) do
    <<msg_action::32, msg_transaction_id::32, rest::binary>> = message

    cond do
      transaction_id !== msg_transaction_id ->
        Logger.debug("Transaction ids do not match, skipping message processing.")
        {:noreply, state}

      action !== msg_action and msg_action !== @error_action ->
        Logger.error(
          "Received message with correct transaction id #{format_transaction_id(transaction_id)} but invalid actions. Expected action #{action}, received action #{msg_action}."
        )

        {:noreply, state}

      true ->
        Logger.info(
          "Start processing of the message received with transaction id #{transaction_id}."
        )

        {:noreply, process_message(msg_action, rest, state)}
    end
  end

  defp process_message(@connect_action, <<connection_id::64, _rest::binary>>, state) do
    Process.send(self(), :schedule_announce, [:noconnect])

    %{
      state
      | connection_id: connection_id,
        action: @announce_action,
        error: nil,
        transaction_id: nil
    }
  end

  defp process_message(
         @announce_action,
         <<interval::32, leechers::32, seeders::32, address_list::binary>>,
         %{tracker_params: tracker_params} = state
       ) do
    peers = Tracker.parse_peers(address_list)

    tracker_data =
      %Tracker{
        info_hash: tracker_params.info_hash,
        tracker_url: tracker_params.tracker_url,
        complete: seeders,
        downloaded: nil,
        incomplete: leechers,
        interval: interval,
        min_interval: nil,
        peers: peers,
        updated_at: DateTime.utc_now()
      }

    TrackerStorage.put(tracker_data)
    schedule_fetch(tracker_data)

    %{
      state
      | tracker_data: tracker_data,
        connection_id: nil,
        action: @connect_action,
        error: nil,
        transaction_id: nil,
        event: Tracker.none().key
    }
  end

  defp process_message(@error_action, message, state) do
    Logger.error("Received error action with the message #{message}.")

    schedule_fetch(state.tracker_data)

    %{
      state
      | connection_id: nil,
        action: @connect_action,
        error: message,
        transaction_id: nil
    }
  end

  defp send_message(ip, port, %{action: action, tracker_params: tracker_params} = state) do
    case action do
      @connect_action ->
        Logger.info("Sent connect message from tracker #{tracker_params.tracker_url}.")
        send_connect_message(ip, port)

      @announce_action ->
        Logger.info("Sent announce message from tracker #{tracker_params.tracker_url}.")
        send_announce_message(ip, port, state)
    end
  end

  defp send_connect_message(ip, port) do
    transaction_id = :rand.uniform(0xFFFFFFFF)

    connect_message =
      <<@udp_protocol_id::64, @connect_action::32, transaction_id::32>>

    HiveTorrent.UDPServer.send_message(connect_message, ip, port)
    transaction_id
  end

  defp send_announce_message(
         ip,
         port,
         %{tracker_params: tracker_params, event: event, connection_id: connection_id, key: key}
       ) do
    %{info_hash: info_hash, tracker_url: tracker_url} = tracker_params

    {:ok, stats} = StatsStorage.get(info_hash)

    %StatsStorage{
      peer_id: peer_id,
      ip: peer_ip,
      port: peer_port,
      uploaded: uploaded,
      downloaded: downloaded,
      left: left
    } = stats

    has_completed_sent = StatsStorage.has_completed?(stats, tracker_url)

    next_event =
      cond do
        event === Tracker.started().key -> Tracker.started().key
        has_completed_sent -> Tracker.none().key
        stats.left == 0 -> Tracker.completed().key
        true -> Tracker.none().key
      end

    Logger.info(
      "Sending announce message with event status #{Tracker.formatted_event_name(next_event)}."
    )

    # if nil set 0 as default value
    peer_ip = peer_ip || 0
    # TODO move to config of tracker
    num_want = -1
    transaction_id = :rand.uniform(0xFFFFFFFF)

    announce_message =
      <<connection_id::64, @announce_action::32, transaction_id::32, info_hash::binary,
        peer_id::binary, downloaded::64, left::64, uploaded::64, next_event::32, peer_ip::32,
        key::32, num_want::32, peer_port::16>>

    HiveTorrent.UDPServer.send_message(announce_message, ip, port)
    transaction_id
  end

  defp schedule_fetch(nil) do
    Process.send_after(self(), :schedule_announce, @default_error_interval * 1_000)
  end

  defp schedule_fetch(tracker_data) do
    interval =
      Map.get(tracker_data, :min_interval) ||
        Map.get(tracker_data, :interval, @default_interval)

    Process.send_after(self(), :schedule_announce, interval * 1_000)
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
    # TODO handle IPv6
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
