defmodule HiveTorrent.StatsStorage do
  use Agent

  defstruct [:info_hash, :peer_id, :port, :uploaded, :downloaded, :left, :event]

  def start_link(stats_list \\ []) do
    stats_map =
      Enum.reduce(stats_list, %{}, fn torrent_stats, map ->
        Map.put(map, torrent_stats.info_hash, torrent_stats)
      end)

    Agent.start_link(fn -> stats_map end, name: __MODULE__)
  end

  def get(info_hash) do
    Agent.get(__MODULE__, &Map.fetch(&1, info_hash))
  end

  def uploaded(info_hash, amount_bytes) when is_integer(amount_bytes) and amount_bytes >= 0 do
    Agent.get(__MODULE__, fn torrent_stats ->
      case Map.fetch(torrent_stats, info_hash) do
        {:ok, torrent_stats} ->
          %HiveTorrent.StatsStorage{uploaded: uploaded} = torrent_stats
          %{torrent_stats | uploaded: uploaded + amount_bytes}

        :error ->
          torrent_stats
      end
    end)
  end

  def put(%HiveTorrent.StatsStorage{info_hash: info_hash} = torrent_stats) do
    Agent.update(__MODULE__, &Map.put_new(&1, info_hash, torrent_stats))
  end
end
