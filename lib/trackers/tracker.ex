defmodule HiveTorrent.Tracker do
  @type t :: %__MODULE__{
          tracker_url: String.t(),
          complete: pos_integer(),
          downloaded: pos_integer(),
          incomplete: pos_integer(),
          interval: pos_integer(),
          min_interval: pos_integer(),
          peers: %{String.t() => [pos_integer()]}
        }

  defstruct [
    :tracker_url,
    :complete,
    :downloaded,
    :incomplete,
    :interval,
    :min_interval,
    :peers,
    :updated_at
  ]

  @none %{key: 0, value: ""}

  @started %{key: 1, value: "started"}

  @stopped %{key: 2, value: "stopped"}

  @completed %{key: 3, value: "completed"}

  def none(), do: @none

  def started(), do: @started

  def stopped(), do: @stopped

  def completed(), do: @completed

  def get_status_code(%{key: key}), do: key

  def get_status_value(%{value: value}), do: value
end
