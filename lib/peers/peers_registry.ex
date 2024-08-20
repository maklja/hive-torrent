defmodule HiveTorrent.Bencode.PeersRegistry do
  use Agent

  @moduledoc """
  Registry that will contain the ip and the ports for the peers retrieved from a trackers.
  """

  def start_link() do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def stop() do
    Agent.stop(__MODULE__)
  end

  def get_peers() do
    Agent.get(__MODULE__, & &1)
  end

  def register_peer({_ip, _ports} = peer) do
    Agent.update(__MODULE__, &update_peer(&1, peer))
  end

  def unregister_peer(ip) when is_bitstring(ip) do
    Agent.update(__MODULE__, fn peers_map -> Map.delete(peers_map, ip) end)
  end

  defp update_peer(peers_map, {ip, ports}), do: Map.put(peers_map, ip, ports)
end
