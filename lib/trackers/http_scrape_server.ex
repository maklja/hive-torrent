defmodule HiveTorrent.HTTPScrapeServer do
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
    tracker_url = Keyword.fetch!(opts, :tracker_url)
    info_hashes = Keyword.fetch!(opts, :info_hashes)
    timeout = Keyword.get(opts, :timeout, @default_timeout_interval)
    auto_fetch = Keyword.get(opts, :auto_fetch, false)

    GenServer.start_link(__MODULE__,
      tracker_url: tracker_url,
      info_hashes: info_hashes,
      timeout: timeout,
      auto_fetch: auto_fetch
    )
  end

  @doc """
  Returns the current information held in the state.

  This includes the parameters sent to the tracker, the last response received, and the last error encountered.
  If the response was not successfully retrieved, the value will be `nil`. Similarly, if no error occurred, `nil` will be returned for the error.
  """
  def get_scrape_response(pid) when is_pid(pid) do
    GenServer.call(pid, :scrape_response)
  end

  def send_scrape_request(pid) when is_pid(pid) do
    GenServer.cast(pid, :send_scrape)
  end

  # Callbacks

  @impl true
  def init(
        tracker_url: tracker_url,
        info_hashes: info_hashes,
        timeout: timeout,
        auto_fetch: auto_fetch
      ) do
    Logger.info("Started scrape server #{tracker_url}, with info hashes #{inspect(info_hashes)}")

    {:ok, _value} =
      Registry.register(HiveTorrent.TrackerRegistry, :http_scrapers, %{
        tracker_url: tracker_url,
        info_hashes: info_hashes
      })

    state = %{
      tracker_url: tracker_url,
      info_hashes: info_hashes,
      scrape_response: nil,
      error: nil,
      timeout_id: nil,
      timeout: timeout,
      auto_fetch: auto_fetch
    }

    if auto_fetch do
      {:ok, state, {:continue, :scrape}}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_continue(:scrape, %{tracker_url: tracker_url} = state) do
    Logger.info("Init scrape server #{tracker_url}")

    handle_info(:send_scrape, state)
  end

  @impl true
  def handle_cast(:send_scrape, %{tracker_url: tracker_url} = state) do
    Logger.info("Send scrape request tracker #{tracker_url}")

    handle_info(:send_scrape, state)
  end

  @impl true
  def handle_info(
        :send_scrape,
        %{
          tracker_url: tracker_url,
          info_hashes: info_hashes,
          timeout: timeout,
          auto_fetch: auto_fetch
        } = state
      ) do
    Logger.info("Send scrape request tracker #{tracker_url}")

    scrape_response =
      HTTPTracker.send_scrape_request(
        %{
          info_hashes: info_hashes,
          tracker_url: tracker_url
        },
        timeout: timeout
      )

    Logger.debug(
      "Received scrape response from tracker #{tracker_url}, for info hashes #{inspect(info_hashes)}, response: #{inspect(scrape_response)}."
    )

    with {:ok, scraped_torrents} <- scrape_response do
      # TorrentInfoStorage.put(scrape_torrent_data)

      # timeout_id = if auto_fetch, do: schedule_fetch(scrape_torrent_data), else: nil

      {:noreply,
       %{
         state
         | error: nil,
           scrape_response: scraped_torrents,
           timeout_id: 1
       }}
    else
      {:error, reason} ->
        Logger.error(reason)
        timeout_id = if auto_fetch, do: schedule_fetch(nil), else: nil

        {:noreply, %{state | error: reason, timeout_id: timeout_id}}
    end
  end

  @impl true
  def handle_call(:scrape_response, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def terminate(_reason, %{
        tracker_url: tracker_url,
        timeout_id: timeout_id
      }) do
    Logger.info("Terminating tracker #{tracker_url}")

    cancel_scheduled_time(timeout_id)

    :ok
  end

  defp schedule_fetch(nil) do
    Process.send_after(self(), :send_scrape, @default_error_interval * 1_000)
  end

  defp schedule_fetch(scrape_response) do
    min_interval = Map.get(scrape_response, :min_interval)

    interval =
      Map.get(scrape_response, :interval, @default_interval)

    interval = min(min_interval, interval) * 1_000

    Process.send_after(self(), :send_scrape, interval)
  end

  defp cancel_scheduled_time(timeout_ref) when is_reference(timeout_ref),
    do: Process.cancel_timer(timeout_ref)

  defp cancel_scheduled_time(nil), do: :ok
end
