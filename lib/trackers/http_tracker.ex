defmodule HiveTorrent.HTTPTracker do
  require Logger

  alias HiveTorrent.Tracker
  alias HiveTorrent.ScrapeResponse
  alias HiveTorrent.Bencode.Parser
  alias HiveTorrent.Bencode.SyntaxError

  @default_timeout_interval 5 * 1_000

  @type tracer_params :: %{
          tracker_url: String.t(),
          info_hash: binary(),
          compact: non_neg_integer(),
          event: String.t(),
          peer_id: binary(),
          ip: {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()} | nil,
          port: non_neg_integer(),
          uploaded: non_neg_integer(),
          downloaded: non_neg_integer(),
          left: non_neg_integer(),
          num_want: integer() | nil,
          key: binary()
        }

  @type scrape_params :: %{
          tracker_url: String.t(),
          info_hashes: [binary()]
        }

  def none(), do: "none"

  def started(), do: "started"

  def stopped(), do: "stopped"

  def completed(), do: "completed"

  @spec send_announce_request(tracer_params(), keyword(timeout: pos_integer())) ::
          {:ok, Tracker.t()} | {:error, String.t()}
  def send_announce_request(
        %{
          tracker_url: tracker_url,
          info_hash: info_hash,
          compact: compact,
          event: event,
          peer_id: peer_id,
          ip: ip,
          key: key,
          port: port,
          uploaded: uploaded,
          downloaded: downloaded,
          left: left,
          num_want: num_want
        },
        opts \\ Keyword.new()
      ) do
    Logger.debug("Sending announce request for tracker #{tracker_url}.")

    timeout = Keyword.get(opts, :timeout, @default_timeout_interval)

    query_params = %{
      info_hash: info_hash,
      peer_id: peer_id,
      port: port,
      uploaded: uploaded,
      downloaded: downloaded,
      left: left,
      compact: compact,
      event: event,
      key: key
    }

    query_params = if ip, do: Map.put(query_params, :ip, ip), else: query_params

    query_params = if num_want, do: Map.put(query_params, :numwant, num_want), else: query_params

    url = "#{tracker_url}?#{URI.encode_query(query_params)}"

    response =
      HTTPoison.get(url, [{"Accept", "text/plain"}], timeout: timeout)

    handle_announce_response(response, tracker_url, info_hash)
  end

  defp handle_announce_response({:ok, response}, tracker_url, info_hash) do
    case response do
      %HTTPoison.Response{status_code: 200, body: body} ->
        parse_announce_response(tracker_url, info_hash, body)

      %HTTPoison.Response{status_code: status_code, body: body} ->
        {:error,
         "Received status code #{status_code} from tracker #{tracker_url}. Response: #{inspect(body)}."}
    end
  end

  defp handle_announce_response(
         {:error, %HTTPoison.Error{reason: reason}},
         tracker_url,
         info_hash
       ),
       do:
         {:error,
          "Error '#{reason}' encountered during announce request with tracker #{tracker_url} with info hash #{inspect(info_hash)}."}

  defp parse_announce_response(tracker_url, info_hash, response_body) do
    with {:ok, announce_response} <- parse_bencoded(response_body),
         {:ok, peers} <- extract_torrent_announce_data(announce_response),
         {:ok, interval} <- fetch_interval(announce_response),
         complete <- Map.get(announce_response, "complete", 0),
         downloaded <- Map.get(announce_response, "downloaded", 0),
         incomplete <- Map.get(announce_response, "incomplete", 0),
         min_interval <- Map.get(announce_response, "min interval") do
      # TODO handle not compact

      min_interval = if min_interval > 0, do: min_interval, else: nil

      {:ok,
       %Tracker{
         info_hash: info_hash,
         tracker_url: tracker_url,
         complete: complete,
         downloaded: downloaded,
         incomplete: incomplete,
         interval: interval,
         min_interval: min_interval,
         peers: peers,
         updated_at: DateTime.utc_now()
       }}
    end
  end

  defp extract_torrent_announce_data(announce_response) do
    case Map.fetch(announce_response, "peers") do
      {:ok, peers_payload} -> Tracker.parse_peers(peers_payload)
      _ -> extract_failure_reason(announce_response)
    end
  end

  @spec send_scrape_request(scrape_params(), timeout: pos_integer()) ::
          {:ok, %{binary() => ScrapeResponse.t()}} | {:error, String.t()}
  def send_scrape_request(
        %{
          tracker_url: tracker_url
        } = params,
        opts \\ Keyword.new()
      ) do
    Logger.debug("Sending scrape request for tracker #{tracker_url}.")

    timeout = Keyword.get(opts, :timeout, @default_timeout_interval)
    info_hashes = Map.get(params, :info_hashes, [])

    query_params =
      info_hashes
      |> Enum.reduce([], fn info_hash, qp -> [{:info_hash, info_hash} | qp] end)
      |> Enum.reverse()

    {:ok, scrape_url} = create_scrape_url(tracker_url)

    url = "#{scrape_url}?#{URI.encode_query(query_params)}"
    response = HTTPoison.get(url, [{"Accept", "text/plain"}], timeout: timeout)
    handle_scrape_response(response, tracker_url, info_hashes)
  end

  defp handle_scrape_response({:ok, response}, tracker_url, info_hashes) do
    case response do
      %HTTPoison.Response{status_code: 200, body: body} ->
        parse_scrape_response(tracker_url, info_hashes, body)

      %HTTPoison.Response{status_code: status_code, body: body} ->
        {:error,
         "Received status code #{status_code} from tracker #{tracker_url}. Response: #{inspect(body)}."}
    end
  end

  defp handle_scrape_response(
         {:error, %HTTPoison.Error{reason: reason}},
         tracker_url,
         info_hashes
       ),
       do:
         {:error,
          "Error #{reason} encountered during scrape request with tracker #{tracker_url} with info hash #{inspect(info_hashes)}."}

  defp parse_scrape_response(tracker_url, info_hashes, response_body) do
    with {:ok, scrape_response} <- parse_bencoded(response_body),
         {:ok, scrape_payload} <- extract_torrent_scrape_data(scrape_response, info_hashes),
         {:ok, interval} <- fetch_interval(scrape_response),
         min_interval <- Map.get(scrape_response, "min interval") do
      min_interval = if min_interval > 0, do: min_interval, else: nil

      torrent_scrape_data =
        Enum.reduce(scrape_payload, Map.new(), fn {info_hash, tracker_scrape_data}, torrents ->
          complete = Map.get(tracker_scrape_data, "complete", 0)
          downloaded = Map.get(tracker_scrape_data, "downloaded", 0)
          incomplete = Map.get(tracker_scrape_data, "incomplete", 0)

          scrape_response = %ScrapeResponse{
            info_hash: info_hash,
            tracker_url: tracker_url,
            complete: complete,
            downloaded: downloaded,
            incomplete: incomplete,
            interval: interval,
            min_interval: min_interval,
            updated_at: DateTime.utc_now()
          }

          Map.put(torrents, info_hash, scrape_response)
        end)

      {:ok, torrent_scrape_data}
    end
  end

  defp extract_torrent_scrape_data(scrape_response, info_hashes) do
    case Map.fetch(scrape_response, "files") do
      {:ok, files} ->
        scrape_data = Enum.map(info_hashes, &{&1, Map.get(files, &1, Map.new())})

        {:ok, scrape_data}

      _ ->
        extract_failure_reason(scrape_response)
    end
  end

  defp extract_failure_reason(tracker_response) do
    case Map.fetch(tracker_response, "failure reason") do
      {:ok, failure_reason} -> {:error, failure_reason}
      _ -> {:error, "Unknown failure reason in the tracker response."}
    end
  end

  defp parse_bencoded(bencoded_data) do
    case Parser.parse(bencoded_data) do
      {:ok, parsed_data} ->
        {:ok, parsed_data}

      {:error, %SyntaxError{message: message}} ->
        {:error, "Failed to parse bencoded data: #{message}."}
    end
  end

  defp fetch_interval(tracker_response) do
    case Map.fetch(tracker_response, "interval") do
      {:ok, interval} when interval > 0 -> {:ok, interval}
      {:ok, interval} -> {:error, "Negative interval received with value #{interval}."}
      :error -> {:error, "Interval value missing in response."}
    end
  end

  @spec create_scrape_url(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def create_scrape_url(announce_url) when is_binary(announce_url) do
    url_parts = announce_url |> String.trim() |> String.split("/", trim: false)
    last_part = Enum.at(url_parts, -1)

    if String.starts_with?(last_part, "announce") do
      url_parts = Enum.drop(url_parts, -1)
      scrape_part = String.replace_prefix(last_part, "announce", "scrape")

      {:ok, "#{Enum.join(url_parts, "/")}/#{scrape_part}"}
    else
      {:error, "Scrape is not supported for tracker #{announce_url}."}
    end
  end

  def create_scrape_url(invalid_announce_url),
    do: {:error, "Invalid tracker url #{invalid_announce_url}."}
end
