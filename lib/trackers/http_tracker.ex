defmodule HiveTorrent.HTTPTracker do
  use GenServer

  alias HiveTorrent.Bencode.Parser

  @default_interval 30 * 60

  defstruct [:complete, :downloaded, :incomplete, :interval, :min_interval, :peers]

  def start_link(tracker_params) when is_map(tracker_params) do
    GenServer.start_link(__MODULE__, tracker_params)
  end

  def fetch(pid) do
    GenServer.call(pid, :fetch)
  end

  # Callbacks

  @impl true
  def init(tracker_params) do
    state = %{tracker_params: tracker_params, tracker_data: nil}

    {:ok, state, {:continue, :fetch_tracker_data}}
  end

  @impl true
  def handle_continue(:fetch_tracker_data, %{tracker_params: tracker_params}) do
    tracker_data = fetch_tracker_data(tracker_params)

    schedule_fetch(tracker_data)

    state = %{
      tracker_params: tracker_params,
      tracker_data: tracker_data
    }

    {:noreply, state}
  end

  @impl true
  def handle_call(:fetch, _from, state) do
    %{tracker_data: tracker_data} = state
    {:reply, tracker_data, state}
  end

  @impl true
  def handle_info(:work, state) do
    %{tracker_params: tracker_params} = state
    tracker_data = fetch_tracker_data(tracker_params)

    schedule_fetch(tracker_data)

    {:noreply, Map.put(state, :tracker_data, tracker_data)}
  end

  defp schedule_fetch(%{min_interval: min_interval}) do
    Process.send_after(self(), :work, min_interval * 1_000)
  end

  defp schedule_fetch(%{interval: interval}) do
    Process.send_after(self(), :work, interval * 1_000)
  end

  defp schedule_fetch(_) do
    Process.send_after(self(), :work, @default_interval * 1_000)
  end

  defp fetch_tracker_data(tracker_params) do
    %{
      tracker_url: tracker_url,
      info_hash: info_hash,
      peer_id: peer_id,
      port: port,
      uploaded: uploaded,
      downloaded: downloaded,
      left: left,
      compact: compact,
      event: event
    } = tracker_params

    query_params =
      URI.encode_query(%{
        info_hash: info_hash,
        peer_id: peer_id,
        port: port,
        uploaded: uploaded,
        downloaded: downloaded,
        left: left,
        compact: compact,
        event: event
      })

    url = "#{tracker_url}?#{query_params}"
    {:ok, response} = HTTPoison.get(url, [{"Accept", "text/plain"}])
    %HTTPoison.Response{status_code: 200, body: body} = response

    with {:ok, tracker_state} <- Parser.parse(body),
         {:ok, peers_payload} <- Map.fetch(tracker_state, "peers"),
         {:ok, interval} <- Map.fetch(tracker_state, "interval"),
         complete <- Map.get(tracker_state, "complete"),
         downloaded <- Map.get(tracker_state, "downloaded"),
         incomplete <- Map.get(tracker_state, "incomplete"),
         min_interval = Map.get(tracker_state, "min interval") do
      # TODO handle not compact
      peers = parse_peers(peers_payload)

      %__MODULE__{
        complete: complete,
        downloaded: downloaded,
        incomplete: incomplete,
        interval: interval,
        min_interval: min_interval,
        peers: peers
      }
    end
  end

  defp parse_peers(
         peers_binary_payload,
         peers \\ []
       )

  defp parse_peers(
         <<>>,
         peers
       ),
       do: Enum.group_by(peers, &elem(&1, 0), &elem(&1, 1))

  defp parse_peers(
         <<ip_bin::binary-size(4), port_bin::binary-size(2), other_peers::binary>>,
         peers
       ) do
    ip = ip_bin |> :binary.bin_to_list() |> Enum.join(".")
    port = :binary.decode_unsigned(port_bin, :big)

    parse_peers(other_peers, [{ip, port} | peers])
  end
end
