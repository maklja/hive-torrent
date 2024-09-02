defmodule HiveTorrent.HTTPTracker do
  use GenServer, restart: :transient

  require Logger

  alias HiveTorrent.HTTPTracker
  alias HiveTorrent.Bencode.Parser
  alias HiveTorrent.StatsStorage

  @default_interval 30 * 60
  @default_error_interval 30

  @type t :: %__MODULE__{
          tracker_url: String.t(),
          complete: pos_integer(),
          downloaded: pos_integer(),
          incomplete: pos_integer(),
          interval: pos_integer(),
          min_interval: pos_integer(),
          peers: binary()
        }

  defstruct [:tracker_url, :complete, :downloaded, :incomplete, :interval, :min_interval, :peers]

  def start_link(tracker_params) when is_map(tracker_params) do
    GenServer.start_link(__MODULE__, %{tracker_params | compact: 1})
  end

  # Callbacks

  @impl true
  def init(tracker_params) do
    Logger.info("Started tracker #{tracker_params.tracker_url}")
    {:ok, tracker_params, {:continue, :fetch_tracker_data}}
  end

  @impl true
  def handle_continue(:fetch_tracker_data, tracker_params) do
    Logger.info("Init tracker #{tracker_params.tracker_url}")
    tracker_data_response = fetch_tracker_data(tracker_params)

    case tracker_data_response do
      {:ok, tracker_data} ->
        Logger.debug(
          "Received tracker(#{tracker_params.tracker_url}) data: #{inspect(tracker_data_response)}"
        )

        HiveTorrent.TrackerStorage.put(tracker_data)
        schedule_fetch(tracker_data)

        {:noreply, tracker_params}

      {:error, reason} ->
        Logger.error(reason)
        schedule_error_fetch()
        {:noreply, tracker_params}
    end
  end

  @impl true
  def handle_info(:work, state) do
    tracker_data_response = fetch_tracker_data(state)

    case tracker_data_response do
      {:ok, tracker_data} ->
        Logger.debug(
          "Received tracker(#{state.tracker_url}) data: #{inspect(tracker_data_response)}"
        )

        HiveTorrent.TrackerStorage.put(tracker_data)
        schedule_fetch(tracker_data)
        {:noreply, state}

      {:error, reason} ->
        Logger.error(reason)
        schedule_error_fetch()
        {:noreply, state}
    end
  end

  defp schedule_error_fetch() do
    Process.send_after(self(), :work, @default_error_interval * 1_000)
  end

  defp schedule_fetch(tracker_data) do
    interval =
      Map.get(tracker_data, :min_interval) ||
        Map.get(tracker_data, :interval) ||
        @default_interval

    Process.send_after(self(), :work, interval * 1_000)
  end

  @spec fetch_tracker_data(map()) :: {:ok, HTTPTracker.t()} | {:error, String.t()}
  defp fetch_tracker_data(%{
         tracker_url: tracker_url,
         info_hash: info_hash,
         compact: compact
       }) do
    {:ok,
     %StatsStorage{
       peer_id: peer_id,
       port: port,
       uploaded: uploaded,
       downloaded: downloaded,
       left: left,
       event: event
     }} = StatsStorage.get(info_hash)

    Logger.debug("Fetching tracker data #{tracker_url}.")

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

      %HTTPoison.Response{status_code: status_code} ->
        {:error, "Received status code #{status_code} from tracker #{tracker_url}."}
    end
  end

  defp handle_tracker_response({:error, %HTTPoison.Error{reason: reason}}, tracker_url) do
    {:error, "Error #{reason} encountered during communication with tracker #{tracker_url}."}
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
    else
      {:error, _} -> {:error, "Invalid tracker response body"}
      :error -> {:error, "Invalid tracker response body"}
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
