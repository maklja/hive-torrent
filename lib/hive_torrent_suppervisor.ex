defmodule HiveTorrent.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_args) do
    children = [
      {HiveTorrent.TrackerStorage, nil},
      {HiveTorrent.TrackerSupervisor, nil}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
