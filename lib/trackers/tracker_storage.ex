defmodule HiveTorrent.TrackerStorage do
  use Agent

  alias HiveTorrent.HTTPTracker

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def get(tracker_url) do
    Agent.get(__MODULE__, &Map.fetch(&1, tracker_url))
  end

  def put(%HTTPTracker{tracker_url: tracker_url} = tracker) do
    Agent.update(__MODULE__, &Map.put(&1, tracker_url, tracker))
  end
end
