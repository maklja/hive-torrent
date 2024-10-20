defmodule HiveTorrent.Tracker do
  @type t :: %__MODULE__{
          info_hash: binary(),
          tracker_url: String.t(),
          complete: pos_integer(),
          downloaded: pos_integer() | nil,
          incomplete: pos_integer(),
          interval: pos_integer(),
          min_interval: pos_integer() | nil,
          peers: %{String.t() => [pos_integer()]}
        }

  defstruct [
    :info_hash,
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

  def formatted_event_name(key) when is_integer(key) do
    events =
      [@none, @started, @started, @completed]
      |> Enum.into(%{}, fn %{key: key, value: value} -> {key, value} end)

    case Map.fetch!(events, key) do
      "" -> "none"
      event -> event
    end
  end

  def parse_peers(peers_binary_payload) when is_binary(peers_binary_payload) do
    parse_IPv4_peers(peers_binary_payload)
  end

  def format_transaction_id(transaction_id) when is_integer(transaction_id),
    do: Integer.to_string(transaction_id, 16)

  defp parse_IPv4_peers(
         peers_binary_payload,
         peers \\ []
       )

  defp parse_IPv4_peers(
         <<>>,
         peers
       ),
       do: {:ok, Enum.group_by(peers, &elem(&1, 0), &elem(&1, 1))}

  defp parse_IPv4_peers(
         <<ip_bin::binary-size(4), port_bin::binary-size(2), other_peers::binary>>,
         peers
       ) do
    ip = ip_bin |> :binary.bin_to_list() |> Enum.join(".")
    port = :binary.decode_unsigned(port_bin, :big)

    parse_IPv4_peers(other_peers, [{ip, port} | peers])
  end

  defp parse_IPv4_peers(_invalid_peers_resp, _peers), do: {:error, "Failed to parse IPv4 peers."}
end
