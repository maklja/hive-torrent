defmodule HiveTorrent.HTTPTracker do
  use GenServer, restart: :transient, shutdown: 5_000

  require Logger

  alias HiveTorrent.Bencode.Parser

  @default_interval 30 * 60

  defstruct [:tracker_url, :complete, :downloaded, :incomplete, :interval, :min_interval, :peers]

  def start_link(tracker_params) when is_map(tracker_params) do
    GenServer.start_link(__MODULE__, tracker_params)
  end

  # Callbacks

  @impl true
  def init(tracker_params) do
    {:ok, tracker_params, {:continue, :fetch_tracker_data}}
  end

  @impl true
  def handle_continue(:fetch_tracker_data, tracker_params) do
    tracker_data_response = fetch_tracker_data(tracker_params)

    case tracker_data_response do
      {:ok, tracker_data} ->
        HiveTorrent.TrackerStorage.put(tracker_data)
        schedule_fetch(tracker_data)

        {:noreply, tracker_params}

      :error ->
        schedule_fetch(nil)

        {:noreply, tracker_params}

      :fatal_error ->
        {:stop, :fatal_error, nil}
    end
  end

  @impl true
  def handle_info(:work, state) do
    tracker_data_response = fetch_tracker_data(state)

    case tracker_data_response do
      {:ok, tracker_data} ->
        HiveTorrent.TrackerStorage.put(tracker_data)
        schedule_fetch(tracker_data)
        {:noreply, state}

      :error ->
        schedule_fetch(HiveTorrent.TrackerStorage.get(state.tracker_url))
        {:noreply, state}

      :fatal_error ->
        {:stop, :fatal_error, state}
    end
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
    response = HTTPoison.get(url, [{"Accept", "text/plain"}])

    handle_tracker_response(response, tracker_url)
  end

  defp handle_tracker_response({:ok, response}, tracker_url) do
    case response do
      %HTTPoison.Response{status_code: 200, body: body} ->
        process_tracker_response(tracker_url, body)

      %HTTPoison.Response{status_code: status_code}
      when status_code in [408, 429, 500, 502, 503, 504] ->
        Logger.warning(
          "Received status code #{status_code} from tracker #{tracker_url} that could be retried."
        )

        :error

      %HTTPoison.Response{status_code: status_code} ->
        Logger.error(
          "Received status code #{status_code} from tracker #{tracker_url} that is fatal."
        )

        :fatal_error
    end
  end

  defp handle_tracker_response({:error, %HTTPoison.Error{reason: reason}}, tracker_url) do
    case reason do
      fatal_error when fatal_error in [:nxdomain, :bad_request, :unknown_error] ->
        Logger.error(
          "Fatal error #{fatal_error} encountered during communication with tracker #{tracker_url}."
        )

        :fatal_error

      error ->
        Logger.warning(
          "Non fatal error #{error} encountered during communication with tracker #{tracker_url}."
        )

        :error
    end
  end

  defp process_tracker_response(tracker_url, response_body) do
    with {:ok, tracker_state} <- Parser.parse(response_body),
         {:ok, peers_payload} <- Map.fetch(tracker_state, "peers"),
         {:ok, interval} <- Map.fetch(tracker_state, "interval"),
         complete <- Map.get(tracker_state, "complete"),
         downloaded <- Map.get(tracker_state, "downloaded"),
         incomplete <- Map.get(tracker_state, "incomplete"),
         min_interval = Map.get(tracker_state, "min interval") do
      # TODO handle not compact
      peers = parse_peers(peers_payload)

      {:ok,
       %__MODULE__{
         tracker_url: tracker_url,
         complete: complete,
         downloaded: downloaded,
         incomplete: incomplete,
         interval: interval,
         min_interval: min_interval,
         peers: peers
       }}
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
