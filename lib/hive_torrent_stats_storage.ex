defmodule HiveTorrent.StatsStorage do
  @moduledoc """
  The torrent downloads stats storage will store stats information about the downloading torrents.
  """

  use Agent

  @type t :: %__MODULE__{
          info_hash: binary(),
          peer_id: String.t(),
          ip: binary() | nil,
          port: pos_integer(),
          uploaded: non_neg_integer(),
          downloaded: non_neg_integer(),
          left: non_neg_integer(),
          completed: [String.t()],
          pieces: %{pos_integer() => {pos_integer(), boolean()}}
        }

  defstruct [:info_hash, :peer_id, :ip, :port, :uploaded, :downloaded, :left, :completed, :pieces]

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

      iex> HiveTorrent.StatsStorage.get("56789")
      {:ok, %HiveTorrent.StatsStorage{
        info_hash: "56789",
        peer_id: "3456",
        downloaded: 100,
        left: 8,
        ip: "192.168.0.23",
        port: 6889,
        uploaded: 1000,
        completed: ["https://local-tracker.com:333/announce"]
      }}
  """
  @spec get(binary()) :: {:ok, t()} | :error
  def get(info_hash) when is_binary(info_hash) do
    Agent.get(__MODULE__, &Map.fetch(&1, info_hash))
  end

  @doc """
  Retrieve latest stats data for all torrents.

  Returns array of the torrent stats.

  ## Examples
      iex> HiveTorrent.StatsStorage.get_all()
      [%HiveTorrent.StatsStorage{
        info_hash: "56789",
        peer_id: "3456",
        downloaded: 100,
        left: 8,
        ip: "192.168.0.23",
        port: 6889,
        uploaded: 1000,
        completed: ["https://local-tracker.com:333/announce"]
      }]
  """
  @spec get_all() :: [t()]
  def get_all() do
    Agent.get(__MODULE__, &Map.values(&1))
  end

  @doc """
  Mark that event completed has been sent to the tracker.

  ## Examples
      iex> HiveTorrent.StatsStorage.completed("56789", "https://tracker.com:333/announce")
      :ok
  """
  @spec completed(binary(), String.t()) :: :ok
  def completed(info_hash, tracker_url) when is_bitstring(tracker_url) do
    update_stats(info_hash, fn torrent_stats ->
      %{
        torrent_stats
        | completed: Enum.uniq([tracker_url | torrent_stats.completed])
      }
    end)
  end

  @doc """
  Check if event completed is already sent to the tracker.

  ## Examples
      iex> {:ok, torrent_stats} = HiveTorrent.StatsStorage.get("56789")
      iex> HiveTorrent.StatsStorage.has_completed?(torrent_stats, "https://local-tracker.com:333/announce")
      true
  """
  @spec has_completed?(t(), String.t()) :: boolean()
  def has_completed?(%HiveTorrent.StatsStorage{completed: completed}, tracker_url) do
    Enum.member?(completed, tracker_url)
  end

  @doc """
  Update uploaded stat for specific torrent.

  ## Examples
      iex> HiveTorrent.StatsStorage.put(%HiveTorrent.StatsStorage{
      ...> info_hash: "12345",
      ...> peer_id: "3456",
      ...> downloaded: 100,
      ...> left: 8,
      ...> ip: "192.168.0.23",
      ...> port: 6889,
      ...> uploaded: 1000,
      ...> completed: []
      ...> })
      :ok
      iex> HiveTorrent.StatsStorage.uploaded("12345", 99)
      :ok
      iex> HiveTorrent.StatsStorage.get("12345")
      {:ok, %HiveTorrent.StatsStorage{
        info_hash: "12345",
        peer_id: "3456",
        downloaded: 100,
        left: 8,
        ip: "192.168.0.23",
        port: 6889,
        uploaded: 1099,
        completed: []
      }}
  """
  @spec uploaded(binary(), non_neg_integer()) :: :ok
  def uploaded(info_hash, amount_bytes)
      when is_binary(info_hash) and is_integer(amount_bytes) and amount_bytes >= 0 do
    update_stats(info_hash, fn torrent_stats ->
      %{torrent_stats | uploaded: torrent_stats.uploaded + amount_bytes}
    end)
  end

  def downloaded(info_hash, piece_idx)
      when is_binary(info_hash) and is_integer(piece_idx) and piece_idx >= 0 do
    update_stats(info_hash, fn torrent_stats ->
      case Map.fetch(torrent_stats.pieces, piece_idx) do
        {:ok, {piece_size, false}} ->
          rem_pieces = Map.put(torrent_stats, piece_idx, {piece_size, true})

          %{
            torrent_stats
            | downloaded: torrent_stats.downloaded + piece_size,
              left: torrent_stats.left - piece_size,
              pieces: rem_pieces
          }

        {:ok, {piece_size, true}} ->
          %{
            torrent_stats
            | downloaded: torrent_stats.downloaded + piece_size
          }

        _ ->
          torrent_stats
      end
    end)
  end

  @doc """
  Add new torrent stats data.

  ## Examples
      iex> HiveTorrent.StatsStorage.put(%HiveTorrent.StatsStorage{
      ...> info_hash: "12345",
      ...> peer_id: "3456",
      ...> downloaded: 100,
      ...> left: 8,
      ...> port: 6889,
      ...> uploaded: 1000,
      ...> completed: []
      ...> })
      :ok
  """
  @spec put(t()) :: :ok
  def put(%HiveTorrent.StatsStorage{info_hash: info_hash} = torrent_stats) do
    Agent.update(__MODULE__, &Map.put_new(&1, info_hash, torrent_stats))
  end

  defp update_stats(info_hash, callback) do
    Agent.update(__MODULE__, fn torrent_stats_map ->
      case Map.fetch(torrent_stats_map, info_hash) do
        {:ok, torrent_stats} ->
          updated_stats = callback.(torrent_stats)
          Map.put(torrent_stats_map, updated_stats.info_hash, updated_stats)

        _ ->
          torrent_stats_map
      end
    end)
  end
end
