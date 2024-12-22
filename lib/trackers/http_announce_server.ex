defmodule HiveTorrent.HTTPAnnounceServer do
  @moduledoc """
  This module implements an HTTP/HTTPS BitTorrent tracker client.

  The client periodically contacts the tracker using HTTP/HTTPS to retrieve peer information.
  On success, the response is stored in `HiveTorrent.TorrentInfoStorage` for later use.
  The client also pulls statistics from `HiveTorrent.StatsStorage`, the single source of truth for all ongoing Torrent downloads.

  Internally, the client manages its configuration, the latest tracker response, and any errors encountered during communication.

  Reference:

  - https://wiki.theory.org/BitTorrentSpecification#Tracker_HTTP.2FHTTPS_Protocol
  - https://www.bittorrent.org/beps/bep_0003.html#trackers
  """
  use GenServer, restart: :transient

  require Logger

  alias HiveTorrent.Tracker
  alias HiveTorrent.StatsStorage
  alias HiveTorrent.TorrentInfoStorage
  alias HiveTorrent.HTTPTracker

  @default_interval 30 * 60
  @default_error_interval 30
  @default_timeout_interval 5 * 1_000

  @doc """
  Starts the HTTP/HTTPS tracker client.

  ## Examples
      iex>{:ok, _pid} = HiveTorrent.HTTPTrackerServer.start_link(tracker_params: %{tracker_url: "http://example/announce", info_hash: <<20, 20>>})

  """
  def start_link(opts) do
    tracker_params = Keyword.fetch!(opts, :tracker_params)
    timeout = Keyword.get(opts, :timeout, @default_timeout_interval)
    auto_fetch = Keyword.get(opts, :auto_fetch, false)

    GenServer.start_link(__MODULE__,
      tracker_params: tracker_params,
      timeout: timeout,
      auto_fetch: auto_fetch
    )
  end

  @doc """
  Returns the current information held in the state.

  This includes the parameters sent to the tracker, the last response received, and the last error encountered.
  If the response was not successfully retrieved, the value will be `nil`. Similarly, if no error occurred, `nil` will be returned for the error.
  """
  def get_tracker_info(pid) when is_pid(pid) do
    GenServer.call(pid, :tracker_info)
  end

  def send_announce_request(pid) when is_pid(pid) do
    GenServer.cast(pid, :send_announce)
  end

  # Callbacks

  @impl true
  def init(tracker_params: tracker_params, timeout: timeout, auto_fetch: auto_fetch) do
    Logger.info("Started tracker #{tracker_params.tracker_url}")

    tracker_params = tracker_params |> Map.put_new(:compact, 1) |> Map.put_new(:num_want, nil)

    {:ok, _value} = Registry.register(HiveTorrent.TrackerRegistry, :http_trackers, tracker_params)

    state = %{
      tracker_params: tracker_params,
      tracker_data: nil,
      error: nil,
      timeout_id: nil,
      event: HTTPTracker.started(),
      key: Tracker.create_transaction_id(),
      timeout: timeout,
      auto_fetch: auto_fetch
    }

    if auto_fetch do
      {:ok, state, {:continue, :announce}}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_continue(:announce, %{tracker_params: tracker_params} = state) do
    Logger.info("Init tracker #{tracker_params.tracker_url}")

    handle_info(:send_announce, state)
  end

  @impl true
  def handle_cast(:send_announce, %{tracker_params: tracker_params} = state) do
    Logger.info("Send announce request tracker #{tracker_params.tracker_url}")

    handle_info(:send_announce, state)
  end

  @impl true
  def handle_info(
        :send_announce,
        %{
          tracker_params: tracker_params,
          event: current_event,
          key: key,
          timeout: timeout,
          auto_fetch: auto_fetch
        } =
          state
      ) do
    # Let it crash in case stats for the torrent are not found, this is then some fatal error
    {:ok, stats} = StatsStorage.get(tracker_params.info_hash)
    has_completed_sent = StatsStorage.has_completed?(stats, tracker_params.tracker_url)

    next_event =
      cond do
        current_event === HTTPTracker.started() -> HTTPTracker.started()
        has_completed_sent -> HTTPTracker.none()
        stats.left == 0 -> HTTPTracker.completed()
        true -> HTTPTracker.none()
      end

    fetch_params = %{
      tracker_url: tracker_params.tracker_url,
      info_hash: tracker_params.info_hash,
      compact: tracker_params.compact,
      event: next_event,
      peer_id: stats.peer_id,
      ip: stats.ip,
      key: key,
      port: stats.port,
      uploaded: stats.uploaded,
      downloaded: stats.downloaded,
      left: stats.left,
      num_want: tracker_params.num_want
    }

    tracker_data_response = HTTPTracker.send_announce_request(fetch_params, timeout: timeout)

    case tracker_data_response do
      {:ok, tracker_data} ->
        Logger.debug(
          "Received tracker(#{tracker_params.tracker_url}) data: #{inspect(tracker_data)}"
        )

        if next_event === HTTPTracker.completed(),
          do: StatsStorage.completed(tracker_params.info_hash, tracker_params.tracker_url)

        TorrentInfoStorage.put(tracker_data)
        timeout_id = if auto_fetch, do: schedule_fetch(tracker_data), else: nil

        {:noreply,
         %{
           state
           | tracker_data: tracker_data,
             error: nil,
             event: HTTPTracker.none(),
             timeout_id: timeout_id
         }}

      {:error, reason} ->
        Logger.error(reason)
        timeout_id = if auto_fetch, do: schedule_fetch(nil), else: nil

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

    fetch_params = %{
      tracker_url: tracker_params.tracker_url,
      info_hash: tracker_params.info_hash,
      compact: tracker_params.compact,
      event: HTTPTracker.stopped(),
      peer_id: stats.peer_id,
      ip: stats.ip,
      key: key,
      port: stats.port,
      uploaded: stats.uploaded,
      downloaded: stats.downloaded,
      left: stats.left,
      num_want: tracker_params.num_want
    }

    tracker_data_response = HTTPTracker.send_announce_request(fetch_params, timeout: timeout)

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
    Process.send_after(self(), :send_announce, @default_error_interval * 1_000)
  end

  defp schedule_fetch(tracker_data) do
    min_interval = Map.get(tracker_data, :min_interval)

    interval =
      Map.get(tracker_data, :interval, @default_interval)

    interval = min(min_interval, interval) * 1_000

    Process.send_after(self(), :send_announce, interval)
  end

  defp cancel_scheduled_time(timeout_ref) when is_reference(timeout_ref),
    do: Process.cancel_timer(timeout_ref)

  defp cancel_scheduled_time(nil), do: :ok
end
