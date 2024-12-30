defmodule HiveTorrent.TorrentInfoStorage do
  @moduledoc """
  The tracker storage will store the most recently received data from the torrent tracker.
  """

  use Agent

  alias HiveTorrent.Tracker
  alias HiveTorrent.ScrapeResponse

  @spec start_link(any()) :: {:error, {any(), any()}} | {:ok, pid()}
  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Retrieve latest torrent data by torrent url.

  Returns {:ok, result}, otherwise :error if entry is not found.

  ## Examples
      iex> HiveTorrent.TorrentInfoStorage.get_torrent("http://example.com:333/announce", <<1>>)
      :error

      iex> HiveTorrent.TorrentInfoStorage.get_torrent("https://local-tracker.com:333/announce", <<179, 113, 122, 146, 100, 7, 66, 32, 44, 230, 243, 244, 233, 164, 177, 130, 46, 138, 145, 40>>)
      {:ok, %HiveTorrent.Tracker{
        info_hash: <<179, 113, 122, 146, 100, 7, 66, 32, 44, 230, 243, 244, 233, 164, 177, 130, 46, 138, 145, 40>>,
        tracker_url: "https://local-tracker.com:333/announce",
        complete: 100,
        incomplete: 3,
        downloaded: 300,
        interval: 60_000,
        min_interval: 30_000,
        peers: <<192, 168, 0, 1, 6345>>,
        updated_at: ~U[2024-09-10 15:20:30Z]
      }}
  """
  @spec get_torrent(String.t(), binary()) :: :error | {:ok, Tracker.t()}
  def get_torrent(tracker_url, info_hash)
      when is_bitstring(tracker_url) and is_binary(info_hash) do
    Agent.get(__MODULE__, fn trackers ->
      with {:ok, tracker_torrents} <- Map.fetch(trackers, tracker_url),
           {:ok, torrent_data} <- Map.fetch(tracker_torrents, info_hash) do
        {:ok, torrent_data}
      else
        _ -> :error
      end
    end)
  end

  @doc """
  Retrieve all torrents data by torrent url.

  ## Examples
      iex> HiveTorrent.TorrentInfoStorage.get_torrents("http://example.com:333/announce")
      []

      iex> HiveTorrent.TorrentInfoStorage.get_torrents("https://local-tracker.com:333/announce")
      [%HiveTorrent.Tracker{
        info_hash: <<179, 113, 122, 146, 100, 7, 66, 32, 44, 230, 243, 244, 233, 164, 177, 130, 46, 138, 145, 40>>,
        tracker_url: "https://local-tracker.com:333/announce",
        complete: 100,
        incomplete: 3,
        downloaded: 300,
        interval: 60_000,
        min_interval: 30_000,
        peers: <<192, 168, 0, 1, 6345>>,
        updated_at: ~U[2024-09-10 15:20:30Z]
      }]
  """
  @spec get_torrents(String.t()) :: [Tracker.t()]
  def get_torrents(tracker_url) when is_bitstring(tracker_url) do
    Agent.get(__MODULE__, fn trackers ->
      trackers |> Map.get(tracker_url, %{}) |> Map.values()
    end)
  end

  @doc """
  Returns all trackers torrent data.

  ## Examples
      iex> HiveTorrent.TorrentInfoStorage.get_all_torrents()
      [%HiveTorrent.Tracker{
        info_hash: <<179, 113, 122, 146, 100, 7, 66, 32, 44, 230, 243, 244, 233, 164, 177, 130, 46, 138, 145, 40>>,
        tracker_url: "https://local-tracker.com:333/announce",
        complete: 100,
        incomplete: 3,
        downloaded: 300,
        interval: 60_000,
        min_interval: 30_000,
        peers: <<192, 168, 0, 1, 6345>>,
        updated_at: ~U[2024-09-10 15:20:30Z]
      }]
  """
  @spec get_all_torrents() :: [Tracker.t()]
  def get_all_torrents() do
    Agent.get(__MODULE__, fn trackers ->
      trackers |> Map.values() |> Enum.flat_map(&Map.values/1)
    end)
  end

  @doc """
  Add new latest torrent data.

  ## Examples
      iex> HiveTorrent.TorrentInfoStorage.put(%HiveTorrent.Tracker{
      ...> info_hash: <<179, 113, 122, 146, 100, 7, 66, 32, 44, 230, 243, 244, 233, 164, 177, 130, 46, 138, 145, 40>>,
      ...> tracker_url: "https://local-tracker.com:333/announce",
      ...> complete: 100,
      ...> incomplete: 3,
      ...> downloaded: 300,
      ...> interval: 60_000,
      ...> min_interval: 30_000,
      ...> peers: <<1234>>
      ...> })
      %HiveTorrent.Tracker{
        info_hash: <<179, 113, 122, 146, 100, 7, 66, 32, 44, 230, 243, 244, 233, 164, 177, 130, 46, 138, 145, 40>>,
        tracker_url: "https://local-tracker.com:333/announce",
        complete: 100,
        incomplete: 3,
        downloaded: 300,
        interval: 60_000,
        min_interval: 30_000,
        peers: <<1234>>
      }
  """
  @spec put(Tracker.t()) :: Tracker.t()
  def put(%Tracker{tracker_url: tracker_url, info_hash: info_hash} = tracker) do
    :ok =
      Agent.update(
        __MODULE__,
        &Map.update(&1, tracker_url, %{info_hash => tracker}, fn tracker_torrents ->
          Map.put(tracker_torrents, info_hash, tracker)
        end)
      )

    tracker
  end

  def put(%ScrapeResponse{tracker_url: tracker_url, info_hash: info_hash} = scrape_response) do
    tracker = Tracker.scrape_response_to_torrent(scrape_response)

    :ok =
      Agent.update(
        __MODULE__,
        &Map.update(&1, tracker_url, %{info_hash => tracker}, fn tracker_torrents ->
          current_torrent = Map.get(tracker_torrents, info_hash)
          tracker = Map.put(tracker, :peers, tracker.peers || current_torrent.peers || %{})
          Map.put(tracker_torrents, info_hash, tracker)
        end)
      )

    tracker
  end
end
