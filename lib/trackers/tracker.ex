defmodule HiveTorrent.ScrapeResponse do
  @type t :: %__MODULE__{
          info_hash: binary(),
          tracker_url: String.t(),
          complete: pos_integer(),
          downloaded: pos_integer() | nil,
          incomplete: pos_integer(),
          interval: pos_integer(),
          min_interval: pos_integer() | nil,
          updated_at: DateTime.t()
        }

  defstruct [
    :info_hash,
    :tracker_url,
    :complete,
    :downloaded,
    :incomplete,
    :interval,
    :min_interval,
    :updated_at
  ]
end

defmodule HiveTorrent.Tracker do
  alias HiveTorrent.ScrapeResponse

  @type t :: %__MODULE__{
          info_hash: binary(),
          tracker_url: String.t(),
          complete: pos_integer(),
          downloaded: pos_integer() | nil,
          incomplete: pos_integer(),
          interval: pos_integer(),
          min_interval: pos_integer() | nil,
          peers: %{String.t() => [pos_integer()]},
          updated_at: DateTime.t()
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

  def create_transaction_id(), do: :rand.uniform(0xFFFFFFFF)

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

  def udp_url_to_inet_address("udp://" <> _rest = url) do
    case URI.parse(url) do
      %URI{host: nil} ->
        {:fatal_error, "Invalid URL: Host not found with tracker #{url}."}

      %URI{port: nil} ->
        {:fatal_error, "Invalid URL: Port not found with tracker #{url}."}

      %URI{host: host, port: port} ->
        host_to_inet_address(host, port)
    end
  end

  def udp_url_to_inet_address(invalid_url),
    do: {:fatal_error, "Invalid URL: Port not found with tracker #{inspect(invalid_url)}."}

  defp host_to_inet_address(host, port) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip_address} ->
        {:ok, ip_address, port}

      {:error, :einval} ->
        resolve_hostname_to_inet_address(host, port)
    end
  end

  defp resolve_hostname_to_inet_address(hostname, port) do
    # TODO handle IPv6
    case :inet.getaddr(String.to_charlist(hostname), :inet) do
      {:ok, ip_address} ->
        {:ok, ip_address, port}

      {:error, reason} ->
        {:error, "Failed to resolve hostname, reason #{reason} with tracker #{hostname}."}
    end
  end

  def scrape_response_to_torrent(%ScrapeResponse{} = scrape_response) do
    %HiveTorrent.Tracker{
      info_hash: scrape_response.info_hash,
      tracker_url: scrape_response.tracker_url,
      complete: scrape_response.complete,
      downloaded: scrape_response.downloaded,
      incomplete: scrape_response.incomplete,
      interval: scrape_response.interval,
      min_interval: scrape_response.min_interval,
      peers: nil,
      updated_at: scrape_response.updated_at
    }
  end
end
