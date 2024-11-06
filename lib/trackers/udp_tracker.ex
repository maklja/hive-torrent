defmodule HiveTorrent.UDPTracker do
  use GenServer, restart: :transient

  require Logger

  # TODO scrape

  alias HiveTorrent.StatsStorage
  alias HiveTorrent.Tracker
  alias HiveTorrent.TrackerStorage

  @default_interval 30 * 60
  @default_error_interval 30
  @default_timeout_interval 30

  def broadcast_announce_message(pid, transaction_id, message)
      when is_pid(pid) and is_integer(transaction_id) and is_binary(message) do
    GenServer.cast(pid, {:broadcast_announce, transaction_id, message})
  end

  def broadcast_scrape_message(_pid, _transaction_id, _message) do
    # GenServer.cast(pid, {:broadcast_announce, transaction_id, message})
    :ok
  end

  def broadcast_error_message(pid, transaction_id, error_message) do
    GenServer.cast(pid, {:broadcast_error, transaction_id, error_message})
  end

  @doc """
  Returns the current information held in the state.

  This includes the parameters sent to the tracker, the last response received, and the last error encountered.
  If the response was not successfully retrieved, the value will be `nil`. Similarly, if no error occurred, `nil` will be returned for the error.
  """
  def get_tracker_info(pid) when is_pid(pid) do
    GenServer.call(pid, :tracker_info)
  end

  def start_link(opts) do
    tracker_params = Keyword.fetch!(opts, :tracker_params)
    client = Keyword.fetch!(opts, :client)
    timeout = Keyword.get(opts, :timeout, @default_timeout_interval)

    GenServer.start_link(__MODULE__,
      tracker_params: tracker_params,
      client: client,
      timeout: timeout
    )
  end

  # Server Callbacks

  @impl true
  def init(
        tracker_params: tracker_params,
        client: client,
        timeout: timeout
      ) do
    Logger.info("Started tracker #{tracker_params.tracker_url}.")

    tracker_params = tracker_params |> Map.put_new(:num_want, -1)

    {:ok, _value} = Registry.register(HiveTorrent.TrackerRegistry, :udp_trackers, tracker_params)

    state = %{
      tracker_params: tracker_params,
      tracker_data: nil,
      transaction_id: nil,
      error: nil,
      timeout_id: nil,
      timeout: timeout * 1_000,
      event: Tracker.started().key,
      key: Tracker.create_transaction_id(),
      client: client
    }

    {:ok, state, {:continue, :announce}}
  end

  @impl true
  def handle_continue(:announce, %{tracker_params: tracker_params} = state) do
    Logger.info("Init tracker #{tracker_params.tracker_url}")

    handle_info(:schedule_announce, state)
  end

  @impl true
  def handle_info(:schedule_announce, %{tracker_params: tracker_params, timeout: timeout} = state) do
    case Tracker.udp_url_to_inet_address(tracker_params.tracker_url) do
      {:ok, ip, port} ->
        transaction_id = send_announce_message(ip, port, state)
        timeout_id = schedule_timeout(timeout)

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

        {:noreply, %{state | error: message}}
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
  def handle_call(:tracker_info, _from, state) do
    {:reply, state, state}
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

  @impl true
  def handle_cast(
        {:broadcast_error, msg_transaction_id, error_message},
        %{
          tracker_data: tracker_data,
          transaction_id: transaction_id,
          timeout_id: timeout_id
        } = state
      ) do
    if transaction_id !== msg_transaction_id do
      Logger.debug("Transaction ids do not match, skipping error message processing.")
      {:noreply, state}
    else
      Logger.error(
        "Received error message from transaction #{Tracker.format_transaction_id(msg_transaction_id)}, reason #{error_message}"
      )

      cancel_schedule_timeout(timeout_id)
      schedule_fetch(tracker_data)

      {:noreply, %{state | error: error_message, timeout_id: nil, transaction_id: nil}}
    end
  end

  @impl true
  def terminate(_reason, %{tracker_params: tracker_params, timeout_id: timeout_id} = state) do
    Logger.info("Terminating tracker #{tracker_params.tracker_url}")

    cancel_schedule_timeout(timeout_id)

    case Tracker.udp_url_to_inet_address(tracker_params.tracker_url) do
      {:ok, ip, port} ->
        transaction_id = send_announce_message(ip, port, %{state | event: Tracker.stopped().key})

        Logger.info(
          "Sent stopped message with transaction id #{Tracker.format_transaction_id(transaction_id)}."
        )

        :ok

      _ ->
        :ok
    end
  end

  defp process_announce_message(
         <<interval::unsigned-integer-size(32), leechers::unsigned-integer-size(32),
           seeders::unsigned-integer-size(32), address_list::binary>>,
         %{tracker_params: tracker_params} = state
       )
       when interval > 0 do
    cancel_schedule_timeout(state.timeout_id)

    with {:ok, peers} <- Tracker.parse_peers(address_list),
         tracker_data <-
           TrackerStorage.put(%Tracker{
             info_hash: tracker_params.info_hash,
             tracker_url: tracker_params.tracker_url,
             complete: seeders,
             downloaded: nil,
             incomplete: leechers,
             interval: interval,
             min_interval: nil,
             peers: peers,
             updated_at: DateTime.utc_now()
           }) do
      schedule_fetch(tracker_data)

      %{
        state
        | tracker_data: tracker_data,
          event: Tracker.none().key,
          error: nil,
          transaction_id: nil,
          timeout_id: nil
      }
    else
      {:error, reason} ->
        Logger.error(reason)
        schedule_fetch(state.tracker_data)

        %{
          state
          | error: reason,
            transaction_id: nil,
            timeout_id: nil
        }
    end
  end

  defp process_announce_message(
         invalid_message,
         state
       ) do
    Logger.error(
      "Invalid message format for announce response, message #{inspect(invalid_message)}."
    )

    cancel_schedule_timeout(state.timeout_id)
    schedule_fetch(state.tracker_data)

    %{
      state
      | error: "Invalid message format for announce response.",
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
           key: key,
           client: client
         }
       ) do
    %{info_hash: info_hash, tracker_url: tracker_url, num_want: num_want} = tracker_params
    Logger.info("Sent announce message from tracker #{tracker_url}.")

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
      <<info_hash::binary-size(20), peer_id::binary-size(20), downloaded::64, left::64,
        uploaded::64, next_event::32, peer_ip::32, key::32, num_want::32, peer_port::16>>

    transaction_id = client.send_announce_message(announce_message, ip, port)

    if next_event === Tracker.completed().key,
      do: StatsStorage.completed(tracker_params.info_hash, tracker_params.tracker_url)

    transaction_id
  end

  defp schedule_timeout(timeout) do
    Process.send_after(self(), :timeout, timeout)
  end

  defp cancel_schedule_timeout(nil), do: :ok

  defp cancel_schedule_timeout(timeout_ref) when is_reference(timeout_ref) do
    Process.cancel_timer(timeout_ref)
  end

  defp schedule_fetch(nil) do
    Process.send_after(self(), :schedule_announce, @default_error_interval * 1_000)
  end

  defp schedule_fetch(tracker_data) do
    interval = Map.get(tracker_data, :interval, @default_interval)

    Process.send_after(self(), :schedule_announce, interval * 1_000)
  end
end
