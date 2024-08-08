defmodule HiveTorrent.HTTPTracker do
  use GenServer

  alias HiveTorrent.Bencode.Parser

  def start_link(tracker_params) when is_map(tracker_params) do
    GenServer.start_link(__MODULE__, tracker_params)
  end

  def fetch(pid) do
    GenServer.call(pid, :fetch)
  end

  # Callbacks

  @impl true
  def init(tracker_params) do
    {:ok, %{tracker_params: tracker_params, tracker_data: nil}}
  end

  @impl true
  def handle_call(:fetch, _from, state) do
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
    } = state.tracker_params

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

    case response do
      %HTTPoison.Response{status_code: 200, body: body} -> IO.inspect(response)
      _ -> IO.inspect("error")
    end

    # Parser.parse(response.body)
    # File.write("temp.txt", response.body)

    {:reply, url, state}
  end

  # @impl true
  # def handle_cast({:push, element}, state) do
  #   new_state = [element | state]
  #   {:noreply, new_state}
  # end
end
