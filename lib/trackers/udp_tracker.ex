defmodule HiveTorrent.UDPTracker do
  use GenServer, restart: :transient

  require Logger

  # TODO closed callback
  # TODO scrape

  alias HiveTorrent.StatsStorage
  alias HiveTorrent.Tracker
  alias HiveTorrent.TrackerStorage

  @default_interval 30 * 60
  @default_error_interval 30
  @default_timeout_interval 30

  def broadcast_announce_message(pid, transaction_id, message) do
    GenServer.cast(pid, {:broadcast_announce, transaction_id, message})
  end

  def broadcast_scrape_message(_pid, _transaction_id, _message) do
    # GenServer.cast(pid, {:broadcast_announce, transaction_id, message})
    :ok
  end

  def start_link(tracker_params) when is_map(tracker_params) do
    GenServer.start_link(__MODULE__, tracker_params)
  end

  # Server Callbacks

  @impl true
  def init(tracker_params) do
    Logger.info("Started tracker #{tracker_params.tracker_url}.")

    tracker_params = tracker_params |> Map.put_new(:num_want, -1)

    {:ok, _value} = Registry.register(HiveTorrent.TrackerRegistry, :udp_trackers, tracker_params)

    state = %{
      tracker_params: tracker_params,
      tracker_data: nil,
      transaction_id: nil,
      error: nil,
      timeout_id: nil,
      event: Tracker.started().key,
      key: :rand.uniform(0xFFFFFFFF)
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
        transaction_id = send_announce_message(ip, port, state)
        timeout_id = schedule_timeout()

        Logger.info(
          "Sent message with transaction id #{Tracker.format_transaction_id(transaction_id)}."
        )

        {:noreply,
         %{
           state
           | transaction_id: transaction_id,
             timeout_id: timeout_id
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
  def handle_info(
        :timeout,
        %{transaction_id: transaction_id, tracker_params: tracker_params} = state
      ) do
    Logger.warning(
      "Connection timeout #{tracker_params.tracker_url} for transaction #{Tracker.format_transaction_id(transaction_id)}."
    )

    Process.send(self(), :schedule_announce, [:noconnect])

    {:noreply,
     %{
       state
       | transaction_id: nil,
         error: nil,
         timeout_id: nil
     }}
  end

  @impl true
  def handle_cast(
        {:broadcast_announce, msg_transaction_id, message},
        %{
          transaction_id: transaction_id
        } = state
      ) do
    if transaction_id !== msg_transaction_id do
      Logger.debug("Transaction ids do not match, skipping message processing.")
      {:noreply, state}
    else
      Logger.info(
        "Start processing of the message received with transaction id #{transaction_id}."
      )

      {:noreply, process_announce_message(message, state)}
    end
  end

  defp process_announce_message(
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

    tracker_data =
      case TrackerStorage.get(tracker_params.info_hash) do
        {:ok, %Tracker{peers: old_peers}} ->
          TrackerStorage.put(%{tracker_data | peers: Map.merge(old_peers, peers)})

        :error ->
          TrackerStorage.put(tracker_data)
      end

    cancel_scheduled_time(state.timeout_id)
    schedule_fetch(tracker_data)

    %{
      state
      | tracker_data: tracker_data,
        event: Tracker.none().key,
        error: nil,
        transaction_id: nil,
        timeout_id: nil
    }
  end

  defp send_announce_message(
         ip,
         port,
         %{
           tracker_params: tracker_params,
           event: event,
           key: key
         }
       ) do
    Logger.info("Sent announce message from tracker #{tracker_params.tracker_url}.")
    %{info_hash: info_hash, tracker_url: tracker_url, num_want: num_want} = tracker_params

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
        event in [Tracker.started().key, Tracker.stopped().key] -> event
        has_completed_sent -> Tracker.none().key
        stats.left == 0 -> Tracker.completed().key
        true -> Tracker.none().key
      end

    Logger.info(
      "Sending announce message with event status #{Tracker.formatted_event_name(next_event)}."
    )

    # if nil set 0 as default value
    peer_ip = peer_ip || 0

    announce_message =
      <<info_hash::binary, peer_id::binary, downloaded::64, left::64, uploaded::64,
        next_event::32, peer_ip::32, key::32, num_want::32, peer_port::16>>

    HiveTorrent.UDPServer.send_announce_message(announce_message, ip, port)
  end

  defp schedule_timeout() do
    Process.send_after(self(), :timeout, @default_timeout_interval * 1_000)
  end

  defp cancel_scheduled_time(timeout_ref) when is_reference(timeout_ref) do
    Process.cancel_timer(timeout_ref)
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
end
