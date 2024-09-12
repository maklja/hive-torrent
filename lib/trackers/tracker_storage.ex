defmodule HiveTorrent.TrackerStorage do
  @moduledoc """
  The tracker storage will store the most recently received data from the torrent tracker.
  """

  use Agent

  alias HiveTorrent.Tracker

  @spec start_link(any()) :: {:error, {any(), any()}} | {:ok, pid()}
  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Retrieve latest torrent data by torrent url.

  Returns {:ok, result}, otherwise :error if entry is not found.

  ## Examples
      iex> HiveTorrent.TrackerStorage.get("http://example.com:333/announce")
      :error

      iex> HiveTorrent.TrackerStorage.put(%HiveTorrent.Tracker{
      ...> tracker_url: "https://local-tracker.com:333/announce",
      ...> complete: 100,
      ...> incomplete: 3,
      ...> downloaded: 300,
      ...> interval: 60_000,
      ...> min_interval: 30_000,
      ...> peers: <<1234>>
      ...> })
      :ok
      iex> HiveTorrent.TrackerStorage.get("https://local-tracker.com:333/announce")
      {:ok, %HiveTorrent.Tracker{
        tracker_url: "https://local-tracker.com:333/announce",
        complete: 100,
        incomplete: 3,
        downloaded: 300,
        interval: 60_000,
        min_interval: 30_000,
        peers: <<1234>>
      }}
  """
  @spec get(String.t()) :: :error | {:ok, Tracker.t()}
  def get(tracker_url) do
    # TODO this should be pair tracker id + info hash?
    # Because one tracker can be used for multiple torrent files
    # Fix it later...
    Agent.get(__MODULE__, &Map.fetch(&1, tracker_url))
  end

  @doc """
  Returns all trackers torrent data.

  ## Examples
      iex> HiveTorrent.TrackerStorage.get_all()
      [%HiveTorrent.Tracker{
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
  @spec get_all() :: [Tracker.t()]
  def get_all() do
    Agent.get(__MODULE__, &Map.values(&1))
  end

  @doc """
  Add new latest torrent data.

  ## Examples
      iex> HiveTorrent.TrackerStorage.put(%HiveTorrent.Tracker{
      ...> tracker_url: "https://local-tracker.com:333/announce",
      ...> complete: 100,
      ...> incomplete: 3,
      ...> downloaded: 300,
      ...> interval: 60_000,
      ...> min_interval: 30_000,
      ...> peers: <<1234>>
      ...> })
      :ok
  """
  @spec put(Tracker.t()) :: :ok
  def put(%Tracker{tracker_url: tracker_url} = tracker) do
    Agent.update(__MODULE__, &Map.put(&1, tracker_url, tracker))
  end
end
