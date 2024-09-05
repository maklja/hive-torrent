defmodule HiveTorrent.StatsStorage do
  @moduledoc """
  The torrent downloads stats storage will store stats information about the downloading torrents.
  """

  use Agent

  @type t :: %__MODULE__{
          info_hash: binary(),
          peer_id: String.t(),
          port: pos_integer(),
          uploaded: non_neg_integer(),
          downloaded: non_neg_integer(),
          left: non_neg_integer(),
          event: String.t()
        }

  defstruct [:info_hash, :peer_id, :port, :uploaded, :downloaded, :left, :event]

  def start_link(stats_list \\ []) do
    stats_map =
      Enum.reduce(stats_list, %{}, fn torrent_stats, map ->
        Map.put(map, torrent_stats.info_hash, torrent_stats)
      end)

    Agent.start_link(fn -> stats_map end, name: __MODULE__)
  end

  @doc """
  Retrieve latest stats data by info hash of the torrent.

  Returns {:ok, result}, otherwise :error if entry is not found.

  ## Examples
      iex> HiveTorrent.StatsStorage.get("info_hash")
      :error

      iex> HiveTorrent.StatsStorage.put(%HiveTorrent.StatsStorage{
      ...> info_hash: "12345",
      ...> event: "started",
      ...> peer_id: "3456",
      ...> downloaded: 100,
      ...> left: 8,
      ...> port: 6889,
      ...> uploaded: 1000
      ...> })
      :ok
      iex> HiveTorrent.StatsStorage.get("12345")
      {:ok, %HiveTorrent.StatsStorage{
        info_hash: "12345",
        event: "started",
        peer_id: "3456",
        downloaded: 100,
        left: 8,
        port: 6889,
        uploaded: 1000
      }}
  """
  @spec get(String.t()) :: {:ok, t()} | :error
  def get(info_hash) do
    Agent.get(__MODULE__, &Map.fetch(&1, info_hash))
  end

  @doc """
  Update uploaded stat for specific torrent.

  ## Examples
      iex> HiveTorrent.StatsStorage.put(%HiveTorrent.StatsStorage{
      ...> info_hash: "12345",
      ...> event: "started",
      ...> peer_id: "3456",
      ...> downloaded: 100,
      ...> left: 8,
      ...> port: 6889,
      ...> uploaded: 1000
      ...> })
      :ok
      iex> HiveTorrent.StatsStorage.uploaded("12345", 99)
      :ok
      iex> HiveTorrent.StatsStorage.get("12345")
      {:ok, %HiveTorrent.StatsStorage{
        info_hash: "12345",
        event: "started",
        peer_id: "3456",
        downloaded: 100,
        left: 8,
        port: 6889,
        uploaded: 1099
      }}
  """
  @spec uploaded(String.t(), non_neg_integer()) :: :ok
  def uploaded(info_hash, amount_bytes) when is_integer(amount_bytes) and amount_bytes >= 0 do
    Agent.update(__MODULE__, fn torrent_stats_map ->
      case Map.fetch(torrent_stats_map, info_hash) do
        {:ok, torrent_stats} ->
          updated_stats = %{torrent_stats | uploaded: torrent_stats.uploaded + amount_bytes}
          Map.put(torrent_stats_map, updated_stats.info_hash, updated_stats)

        _ ->
          torrent_stats_map
      end
    end)
  end

  @doc """
  Add new torrent stats data.

  ## Examples
      iex> HiveTorrent.StatsStorage.put(%HiveTorrent.StatsTracker{
      ...> info_hash: "12345",
      ...> event: "started",
      ...> peer_id: "3456",
      ...> downloaded: 100,
      ...> left: 8,
      ...> port: 6889,
      ...> uploaded: 1000
      ...> })
      :ok
  """
  @spec put(t()) :: :ok
  def put(%HiveTorrent.StatsStorage{info_hash: info_hash} = torrent_stats) do
    Agent.update(__MODULE__, &Map.put_new(&1, info_hash, torrent_stats))
  end
end
