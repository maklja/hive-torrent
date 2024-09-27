defmodule HiveTorrent.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_args) do
    children = [
      {HiveTorrent.StatsStorage, []},
      {HiveTorrent.TrackerStorage, nil},
      {Registry, keys: :duplicate, name: HiveTorrent.TrackerRegistry},
      {HiveTorrent.UDPServer, port: 6888},
      {HiveTorrent.TrackerSupervisor, nil}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
