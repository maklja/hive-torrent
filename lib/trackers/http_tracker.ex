defmodule HiveTorrent.HTTPTracker do
  @moduledoc """
  This module implements an HTTP/HTTPS BitTorrent tracker client.

  The client periodically contacts the tracker using HTTP/HTTPS to retrieve peer information.
  On success, the response is stored in `HiveTorrent.TrackerStorage` for later use.
  The client also pulls statistics from `HiveTorrent.StatsStorage`, the single source of truth for all ongoing Torrent downloads.

  Internally, the client manages its configuration, the latest tracker response, and any errors encountered during communication.

  Reference:

  - https://wiki.theory.org/BitTorrentSpecification#Tracker_HTTP.2FHTTPS_Protocol
  - https://www.bittorrent.org/beps/bep_0003.html#trackers
  """
  use GenServer, restart: :transient

  require Logger

  alias HiveTorrent.Tracker
  alias HiveTorrent.Bencode.Parser
  alias HiveTorrent.StatsStorage
  alias HiveTorrent.TrackerStorage

  @default_interval 30 * 60
  @default_error_interval 30
  @default_timeout_interval 5 * 1_000

  @doc """
  Starts the HTTP/HTTPS tracker client.

  ## Examples
      iex>{:ok, _pid} = HiveTorrent.HTTPTracker.start_link(tracker_params: %{tracker_url: "http://example/announce", info_hash: <<20, 20>>})

  """
  def start_link(opts) do
    tracker_params = Keyword.fetch!(opts, :tracker_params)
    timeout = Keyword.get(opts, :timeout, @default_timeout_interval)

    GenServer.start_link(__MODULE__, tracker_params: tracker_params, timeout: timeout)
  end

  @doc """
  Returns the current information held in the state.

  This includes the parameters sent to the tracker, the last response received, and the last error encountered.
  If the response was not successfully retrieved, the value will be `nil`. Similarly, if no error occurred, `nil` will be returned for the error.
  """
  def get_tracker_info(pid) when is_pid(pid) do
    GenServer.call(pid, :tracker_info)
  end

  # Callbacks

  @impl true
  def init(tracker_params: tracker_params, timeout: timeout) do
    Logger.info("Started tracker #{tracker_params.tracker_url}")

    tracker_params = tracker_params |> Map.put_new(:compact, 1) |> Map.put_new(:num_want, nil)

    {:ok, _value} = Registry.register(HiveTorrent.TrackerRegistry, :http_trackers, tracker_params)

    state = %{
      tracker_params: tracker_params,
      tracker_data: nil,
      error: nil,
      timeout_id: nil,
      event: Tracker.started().value,
      key: :rand.uniform(0xFFFFFFFF),
      timeout: timeout
    }

    {:ok, state, {:continue, :announce}}
  end

  @impl true
  def handle_continue(:announce, %{tracker_params: tracker_params} = state) do
    Logger.info("Init tracker #{tracker_params.tracker_url}")

    handle_info(:schedule_announce, state)
  end

  @impl true
  def handle_info(
        :schedule_announce,
        %{tracker_params: tracker_params, event: current_event, key: key, timeout: timeout} =
          state
      ) do
    # Let it crash in case stats for the torrent are not found, this is then some fatal error
    {:ok, stats} = StatsStorage.get(tracker_params.info_hash)
    has_completed_sent = StatsStorage.has_completed?(stats, tracker_params.tracker_url)

    next_event =
      cond do
        current_event === Tracker.started().value -> Tracker.started().value
        has_completed_sent -> Tracker.none().value
        stats.left == 0 -> Tracker.completed().value
        true -> Tracker.none().value
      end

    fetch_params =
      stats
      |> Map.from_struct()
      |> Map.merge(tracker_params)
      |> Map.put(:event, next_event)
      |> Map.put(:key, key)
      |> Map.put(:timeout, timeout)

    tracker_data_response = fetch_tracker_data(fetch_params)

    case tracker_data_response do
      {:ok, tracker_data} ->
        Logger.debug(
          "Received tracker(#{tracker_params.tracker_url}) data: #{inspect(tracker_data)}"
        )

        if next_event === Tracker.completed().value,
          do: StatsStorage.completed(tracker_params.info_hash, tracker_params.tracker_url)

        TrackerStorage.put(tracker_data)
        timeout_id = schedule_fetch(tracker_data)

        {:noreply,
         %{
           state
           | tracker_data: tracker_data,
             error: nil,
             event: Tracker.none().value,
             timeout_id: timeout_id
         }}

      {:error, reason} ->
        Logger.error(reason)
        timeout_id = schedule_fetch(nil)
        {:noreply, %{state | error: reason, timeout_id: timeout_id}}
    end
  end

  @impl true
  def handle_call(:tracker_info, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def terminate(_reason, %{
        tracker_params: tracker_params,
        key: key,
        timeout_id: timeout_id,
        timeout: timeout
      }) do
    Logger.info("Terminating tracker #{tracker_params.tracker_url}")

    cancel_scheduled_time(timeout_id)

    # Let it crash in case stats for the torrent are not found, this is then some fatal error
    {:ok, stats} = StatsStorage.get(tracker_params.info_hash)

    fetch_params =
      stats
      |> Map.from_struct()
      |> Map.merge(tracker_params)
      |> Map.put(:event, Tracker.stopped().value)
      |> Map.put(:key, key)
      |> Map.put(:timeout, timeout)

    tracker_data_response = fetch_tracker_data(fetch_params)

    case tracker_data_response do
      {:ok, tracker_data} ->
        Logger.debug(
          "Received tracker(#{tracker_params.tracker_url}) data: #{inspect(tracker_data)}"
        )

      {:error, reason} ->
        Logger.error(reason)
    end

    :ok
  end

  defp schedule_fetch(nil) do
    Process.send_after(self(), :schedule_announce, @default_error_interval * 1_000)
  end

  defp schedule_fetch(tracker_data) do
    min_interval = Map.get(tracker_data, :min_interval)

    interval =
      Map.get(tracker_data, :interval, @default_interval)

    interval = min(min_interval, interval) * 1_000

    Process.send_after(self(), :schedule_announce, interval)
  end

  defp cancel_scheduled_time(timeout_ref) when is_reference(timeout_ref),
    do: Process.cancel_timer(timeout_ref)

  defp cancel_scheduled_time(nil), do: :ok

  @spec fetch_tracker_data(map()) :: {:ok, Tracker.t()} | {:error, String.t()}
  defp fetch_tracker_data(%{
         tracker_url: tracker_url,
         info_hash: info_hash,
         compact: compact,
         event: event,
         peer_id: peer_id,
         ip: ip,
         key: key,
         port: port,
         uploaded: uploaded,
         downloaded: downloaded,
         left: left,
         num_want: num_want,
         timeout: timeout
       }) do
    Logger.debug("Fetching tracker data #{tracker_url}.")

    query_params = %{
      info_hash: info_hash,
      peer_id: peer_id,
      port: port,
      uploaded: uploaded,
      downloaded: downloaded,
      left: left,
      compact: compact,
      event: event,
      key: key
    }

    query_params = if ip, do: Map.put(query_params, :ip, ip), else: query_params

    query_params = if num_want, do: Map.put(query_params, :numwant, num_want), else: query_params

    url = "#{tracker_url}?#{URI.encode_query(query_params)}"
    response = HTTPoison.get(url, [{"Accept", "text/plain"}], timeout: timeout)
    handle_tracker_response(response, tracker_url, info_hash)
  end

  defp handle_tracker_response({:ok, response}, tracker_url, info_hash) do
    case response do
      %HTTPoison.Response{status_code: 200, body: body} ->
        process_tracker_response(tracker_url, info_hash, body)

      %HTTPoison.Response{status_code: status_code, body: body} ->
        {:error,
         "Received status code #{status_code} from tracker #{tracker_url}. Response: #{inspect(body)}"}
    end
  end

  defp handle_tracker_response({:error, %HTTPoison.Error{reason: reason}}, tracker_url, info_hash) do
    {:error,
     "Error #{reason} encountered during communication with tracker #{tracker_url} with info hash #{inspect(info_hash)}."}
  end

  defp process_tracker_response(tracker_url, info_hash, response_body) do
    with {:ok, tracker_state} <- Parser.parse(response_body),
         {:ok, peers_payload} <- Map.fetch(tracker_state, "peers"),
         {:ok, peers} <- Tracker.parse_peers(peers_payload),
         {:ok, interval} when interval > 0 <- Map.fetch(tracker_state, "interval"),
         complete <- Map.get(tracker_state, "complete"),
         downloaded <- Map.get(tracker_state, "downloaded"),
         incomplete <- Map.get(tracker_state, "incomplete"),
         min_interval <- Map.get(tracker_state, "min interval") do
      # TODO handle not compact

      min_interval = if min_interval > 0, do: min_interval, else: nil

      {:ok,
       %Tracker{
         info_hash: info_hash,
         tracker_url: tracker_url,
         complete: complete,
         downloaded: downloaded,
         incomplete: incomplete,
         interval: interval,
         min_interval: min_interval,
         peers: peers,
         updated_at: DateTime.utc_now()
       }}
    else
      {:error, %HiveTorrent.Bencode.SyntaxError{message: message}} ->
        {:error, "Failed to parse tracker response: #{message}."}

      _unknown_error ->
        {:error, "Invalid tracker response body."}
    end
  end
end
