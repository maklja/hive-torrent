defmodule HiveTorrent.HTTPTrackerTest do
  use ExUnit.Case, async: true

  import Mock

  doctest HiveTorrent.HTTPTracker

  alias HiveTorrent.Tracker
  alias HiveTorrent.ScrapeResponse
  alias HiveTorrent.HTTPTracker
  alias HiveTorrent.Bencode.Serializer

  import HiveTorrent.TrackerMocks

  @mock_updated_date DateTime.now!("Etc/UTC")

  setup_with_mocks([
    {DateTime, [:passthrough],
     [
       utc_now: fn -> @mock_updated_date end,
       utc_now: fn _ -> @mock_updated_date end
     ]}
  ]) do
    stats = create_stats()

    {:ok,
     %{
       tracker_url: create_http_tracker_announce_url(),
       info_hash: stats.info_hash,
       stats: stats
     }}
  end

  describe "Announce message" do
    defp random_announce_event(),
      do:
        Enum.random([
          HTTPTracker.started(),
          HTTPTracker.stopped(),
          HTTPTracker.completed(),
          HTTPTracker.none()
        ])

    test "ensure HTTPTracker announce successfully fetch the tracker data", %{
      tracker_url: tracker_url,
      info_hash: info_hash,
      stats: stats
    } do
      {tracker_resp, expected_peers} = http_tracker_announce_response()

      expected_torrent_data = %Tracker{
        info_hash: info_hash,
        tracker_url: tracker_url,
        complete: Map.fetch!(tracker_resp, "complete"),
        downloaded: Map.fetch!(tracker_resp, "downloaded"),
        incomplete: Map.fetch!(tracker_resp, "incomplete"),
        interval: Map.fetch!(tracker_resp, "interval"),
        min_interval: Map.fetch!(tracker_resp, "min interval"),
        peers: expected_peers,
        updated_at: @mock_updated_date
      }

      with_mock HTTPoison,
        get: fn _tracker_url, _headers, _opts ->
          {:ok, mock_response} = Serializer.encode(tracker_resp)
          {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}
        end do
        compact = 1
        key = :rand.uniform(1_000)
        ip = create_ip() |> ip_to_string()
        num_want = -1..1_000 |> Enum.random()
        event = random_announce_event()

        {:ok, torrent_data} =
          HTTPTracker.send_announce_request(%{
            tracker_url: tracker_url,
            info_hash: info_hash,
            compact: compact,
            event: event,
            peer_id: stats.peer_id,
            ip: ip,
            key: key,
            port: stats.port,
            uploaded: stats.uploaded,
            downloaded: stats.downloaded,
            left: stats.left,
            num_want: num_want
          })

        assert torrent_data == expected_torrent_data

        expected_query_params = %{
          info_hash: info_hash,
          peer_id: stats.peer_id,
          port: stats.port,
          uploaded: stats.uploaded,
          downloaded: stats.downloaded,
          left: stats.left,
          compact: compact,
          key: key,
          event: event,
          ip: ip,
          numwant: num_want
        }

        qp = URI.encode_query(expected_query_params)

        assert_called_exactly(HTTPoison.get("#{tracker_url}?#{qp}", :_, :_), 1)
      end
    end

    test "ensure HTTPTracker announce returns error when peers payload is invalid", %{
      tracker_url: tracker_url,
      info_hash: info_hash,
      stats: stats
    } do
      {tracker_resp, _expected_peers} = http_tracker_announce_response()

      with_mock HTTPoison,
        get: fn _tracker_url, _headers, _opts ->
          # corrupt the payload peers format in order to force parse to fail
          invalid_tracker_resp =
            Map.update!(tracker_resp, "peers", fn valid_peers ->
              valid_peers <> <<:rand.uniform(255)::8>>
            end)

          {:ok, mock_response} = Serializer.encode(invalid_tracker_resp)
          {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}
        end do
        compact = 1
        key = :rand.uniform(1_000)
        ip = create_ip() |> ip_to_string()
        num_want = -1..1_000 |> Enum.random()
        event = random_announce_event()

        response =
          HTTPTracker.send_announce_request(%{
            tracker_url: tracker_url,
            info_hash: info_hash,
            compact: compact,
            event: event,
            peer_id: stats.peer_id,
            ip: ip,
            key: key,
            port: stats.port,
            uploaded: stats.uploaded,
            downloaded: stats.downloaded,
            left: stats.left,
            num_want: num_want
          })

        assert response == {:error, "Failed to parse IPv4 peers."}
      end
    end

    test "ensure HTTPTracker announce returns error on not 200 status code", %{
      tracker_url: tracker_url,
      info_hash: info_hash,
      stats: stats
    } do
      with_mock HTTPoison,
        get: fn _tracker_url, _headers, _opts ->
          {:ok, %HTTPoison.Response{status_code: 400, body: "Invalid payload received."}}
        end do
        compact = 1
        key = :rand.uniform(1_000)
        ip = create_ip() |> ip_to_string()
        num_want = -1..1_000 |> Enum.random()
        event = random_announce_event()

        response =
          HTTPTracker.send_announce_request(%{
            tracker_url: tracker_url,
            info_hash: info_hash,
            compact: compact,
            event: event,
            peer_id: stats.peer_id,
            ip: ip,
            key: key,
            port: stats.port,
            uploaded: stats.uploaded,
            downloaded: stats.downloaded,
            left: stats.left,
            num_want: num_want
          })

        assert response ==
                 {:error,
                  "Received status code 400 from tracker #{tracker_url}. Response: \"Invalid payload received.\"."}
      end
    end

    test "ensure HTTPTracker announce returns error on network errors", %{
      tracker_url: tracker_url,
      info_hash: info_hash,
      stats: stats
    } do
      with_mock HTTPoison,
        get: fn _tracker_url, _headers, _opts ->
          {:error, %HTTPoison.Error{id: nil, reason: :timeout}}
        end do
        compact = 1
        key = :rand.uniform(1_000)
        ip = create_ip() |> ip_to_string()
        num_want = -1..1_000 |> Enum.random()
        event = random_announce_event()

        response =
          HTTPTracker.send_announce_request(%{
            tracker_url: tracker_url,
            info_hash: info_hash,
            compact: compact,
            event: event,
            peer_id: stats.peer_id,
            ip: ip,
            key: key,
            port: stats.port,
            uploaded: stats.uploaded,
            downloaded: stats.downloaded,
            left: stats.left,
            num_want: num_want
          })

        assert response ==
                 {:error,
                  "Error 'timeout' encountered during announce request with tracker #{tracker_url} with info hash #{inspect(info_hash)}."}
      end
    end

    test "ensure HTTPTracker announce returns error on the invalid payload response", %{
      tracker_url: tracker_url,
      info_hash: info_hash,
      stats: stats
    } do
      with_mock HTTPoison,
        get: fn _tracker_url, _headers, _opts ->
          {:ok, %HTTPoison.Response{status_code: 200, body: "<invalid_payload>"}}
        end do
        compact = 1
        key = :rand.uniform(1_000)
        ip = create_ip() |> ip_to_string()
        num_want = -1..1_000 |> Enum.random()
        event = random_announce_event()

        response =
          HTTPTracker.send_announce_request(%{
            tracker_url: tracker_url,
            info_hash: info_hash,
            compact: compact,
            event: event,
            peer_id: stats.peer_id,
            ip: ip,
            key: key,
            port: stats.port,
            uploaded: stats.uploaded,
            downloaded: stats.downloaded,
            left: stats.left,
            num_want: num_want
          })

        assert response ==
                 {:error,
                  "Failed to parse bencoded data: Unexpected token '<invalid_payload>' while parsing."}
      end
    end

    test "ensure HTTPTracker announce returns error on the missing peers data", %{
      tracker_url: tracker_url,
      info_hash: info_hash,
      stats: stats
    } do
      with_mock HTTPoison,
        get: fn _tracker_url, _headers, _opts ->
          {:ok, mock_response} =
            http_tracker_announce_response()
            |> elem(0)
            |> Map.delete("peers")
            |> Serializer.encode()

          {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}
        end do
        compact = 1
        key = :rand.uniform(1_000)
        ip = create_ip() |> ip_to_string()
        num_want = -1..1_000 |> Enum.random()
        event = random_announce_event()

        response =
          HTTPTracker.send_announce_request(%{
            tracker_url: tracker_url,
            info_hash: info_hash,
            compact: compact,
            event: event,
            peer_id: stats.peer_id,
            ip: ip,
            key: key,
            port: stats.port,
            uploaded: stats.uploaded,
            downloaded: stats.downloaded,
            left: stats.left,
            num_want: num_want
          })

        assert response ==
                 {:error, "Unknown failure reason in the tracker response."}
      end
    end

    test "ensure HTTPTracker announce returns error on the missing interval value", %{
      tracker_url: tracker_url,
      info_hash: info_hash,
      stats: stats
    } do
      with_mock HTTPoison,
        get: fn _tracker_url, _headers, _opts ->
          {:ok, mock_response} =
            http_tracker_announce_response()
            |> elem(0)
            |> Map.delete("interval")
            |> Serializer.encode()

          {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}
        end do
        compact = 1
        key = :rand.uniform(1_000)
        ip = create_ip() |> ip_to_string()
        num_want = -1..1_000 |> Enum.random()
        event = random_announce_event()

        response =
          HTTPTracker.send_announce_request(%{
            tracker_url: tracker_url,
            info_hash: info_hash,
            compact: compact,
            event: event,
            peer_id: stats.peer_id,
            ip: ip,
            key: key,
            port: stats.port,
            uploaded: stats.uploaded,
            downloaded: stats.downloaded,
            left: stats.left,
            num_want: num_want
          })

        assert response ==
                 {:error, "Interval value missing in response."}
      end
    end

    test "ensure HTTPTracker announce returns error on the negative interval value", %{
      tracker_url: tracker_url,
      info_hash: info_hash,
      stats: stats
    } do
      interval = :rand.uniform(100) * -1

      with_mock HTTPoison,
        get: fn _tracker_url, _headers, _opts ->
          {:ok, mock_response} =
            http_tracker_announce_response()
            |> elem(0)
            |> Map.put("interval", interval)
            |> Serializer.encode()

          {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}
        end do
        compact = 1
        key = :rand.uniform(1_000)
        ip = create_ip() |> ip_to_string()
        num_want = -1..1_000 |> Enum.random()
        event = random_announce_event()

        response =
          HTTPTracker.send_announce_request(%{
            tracker_url: tracker_url,
            info_hash: info_hash,
            compact: compact,
            event: event,
            peer_id: stats.peer_id,
            ip: ip,
            key: key,
            port: stats.port,
            uploaded: stats.uploaded,
            downloaded: stats.downloaded,
            left: stats.left,
            num_want: num_want
          })

        assert response ==
                 {:error, "Negative interval received with value #{interval}."}
      end
    end

    test "ensure HTTPTracker announce negative min interval value is converted to nil", %{
      tracker_url: tracker_url,
      info_hash: info_hash,
      stats: stats
    } do
      {tracker_resp, expected_peers} = http_tracker_announce_response()

      expected_tracker_data = %Tracker{
        info_hash: info_hash,
        tracker_url: tracker_url,
        complete: Map.fetch!(tracker_resp, "complete"),
        downloaded: Map.fetch!(tracker_resp, "downloaded"),
        incomplete: Map.fetch!(tracker_resp, "incomplete"),
        interval: Map.fetch!(tracker_resp, "interval"),
        min_interval: nil,
        peers: expected_peers,
        updated_at: @mock_updated_date
      }

      with_mock HTTPoison,
        get: fn _tracker_url, _headers, _opts ->
          {:ok, mock_response} =
            tracker_resp
            |> Map.put("min interval", :rand.uniform(100) * -1)
            |> Serializer.encode()

          {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}
        end do
        compact = 1
        key = :rand.uniform(1_000)
        ip = create_ip() |> ip_to_string()
        num_want = -1..1_000 |> Enum.random()
        event = random_announce_event()

        announce_response =
          HTTPTracker.send_announce_request(%{
            tracker_url: tracker_url,
            info_hash: info_hash,
            compact: compact,
            event: event,
            peer_id: stats.peer_id,
            ip: ip,
            key: key,
            port: stats.port,
            uploaded: stats.uploaded,
            downloaded: stats.downloaded,
            left: stats.left,
            num_want: num_want
          })

        assert announce_response == {:ok, expected_tracker_data}
      end
    end

    test "ensure HTTPTracker announce returns error reason response", %{
      tracker_url: tracker_url,
      info_hash: info_hash,
      stats: stats
    } do
      failure_reason = Faker.Lorem.sentence()

      with_mock HTTPoison,
        get: fn _tracker_url, _headers, _opts ->
          {:ok, tracker_resp} = Serializer.encode(%{"failure reason" => failure_reason})
          {:ok, %HTTPoison.Response{status_code: 200, body: tracker_resp}}
        end do
        compact = 1
        key = :rand.uniform(1_000)
        ip = create_ip() |> ip_to_string()
        num_want = -1..1_000 |> Enum.random()
        event = random_announce_event()

        response =
          HTTPTracker.send_announce_request(%{
            tracker_url: tracker_url,
            info_hash: info_hash,
            compact: compact,
            event: event,
            peer_id: stats.peer_id,
            ip: ip,
            key: key,
            port: stats.port,
            uploaded: stats.uploaded,
            downloaded: stats.downloaded,
            left: stats.left,
            num_want: num_want
          })

        assert response == {:error, failure_reason}
      end
    end
  end

  describe "Scrape message" do
    test "ensure HTTPTracker scrape successfully fetch the tracker data", %{
      tracker_url: tracker_url,
      info_hash: info_hash
    } do
      {tracker_resp, _expected_files} = http_tracker_scrape_response(info_hash)

      torrent_scrape_data = tracker_resp |> Map.fetch!("files") |> Map.fetch!(info_hash)

      expected_scrape_data = %ScrapeResponse{
        info_hash: info_hash,
        tracker_url: tracker_url,
        complete: Map.fetch!(torrent_scrape_data, "complete"),
        downloaded: Map.fetch!(torrent_scrape_data, "downloaded"),
        incomplete: Map.fetch!(torrent_scrape_data, "incomplete"),
        interval: Map.fetch!(tracker_resp, "interval"),
        min_interval: Map.fetch!(tracker_resp, "min interval"),
        updated_at: @mock_updated_date
      }

      with_mock HTTPoison,
        get: fn _tracker_url, _headers, _opts ->
          {:ok, mock_response} = Serializer.encode(tracker_resp)
          {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}
        end do
        {:ok, scrape_data} =
          HTTPTracker.send_scrape_request(%{
            tracker_url: tracker_url,
            info_hashes: [info_hash]
          })

        torrent_scrape_data = Map.fetch!(scrape_data, info_hash)
        assert torrent_scrape_data == expected_scrape_data

        expected_query_params = [
          {
            :info_hash,
            info_hash
          }
        ]

        {:ok, scrape_url} = HTTPTracker.create_scrape_url(tracker_url)
        qp = URI.encode_query(expected_query_params)
        assert_called_exactly(HTTPoison.get("#{scrape_url}?#{qp}", :_, :_), 1)
      end
    end

    test "ensure HTTPTracker scrape returns error when files payload is invalid", %{
      tracker_url: tracker_url,
      info_hash: info_hash
    } do
      {tracker_resp, _expected_files} = http_tracker_scrape_response(info_hash)

      with_mock HTTPoison,
        get: fn _tracker_url, _headers, _opts ->
          # corrupt the payload files format in order to force parse to fail
          invalid_tracker_resp = Map.delete(tracker_resp, "files")

          {:ok, mock_response} = Serializer.encode(invalid_tracker_resp)
          {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}
        end do
        response =
          HTTPTracker.send_scrape_request(%{
            tracker_url: tracker_url,
            info_hashes: [info_hash]
          })

        assert response == {:error, "Unknown failure reason in the tracker response."}
      end
    end

    test "ensure HTTPTracker scrape returns error on not 200 status code", %{
      tracker_url: tracker_url,
      info_hash: info_hash
    } do
      with_mock HTTPoison,
        get: fn _tracker_url, _headers, _opts ->
          {:ok, %HTTPoison.Response{status_code: 400, body: "Invalid payload received."}}
        end do
        response =
          HTTPTracker.send_scrape_request(%{
            tracker_url: tracker_url,
            info_hashes: [info_hash]
          })

        assert response ==
                 {:error,
                  "Received status code 400 from tracker #{tracker_url}. Response: \"Invalid payload received.\"."}
      end
    end

    test "ensure HTTPTracker scrape returns error on network errors", %{
      tracker_url: tracker_url,
      info_hash: info_hash
    } do
      with_mock HTTPoison,
        get: fn _tracker_url, _headers, _opts ->
          {:error, %HTTPoison.Error{id: nil, reason: :timeout}}
        end do
        info_hashes = [info_hash]

        response =
          HTTPTracker.send_scrape_request(%{
            tracker_url: tracker_url,
            info_hashes: info_hashes
          })

        assert response ==
                 {:error,
                  "Error timeout encountered during scrape request with tracker #{tracker_url} with info hash #{inspect(info_hashes)}."}
      end
    end

    test "ensure HTTPTracker scrape returns error on the invalid payload response", %{
      tracker_url: tracker_url,
      info_hash: info_hash
    } do
      with_mock HTTPoison,
        get: fn _tracker_url, _headers, _opts ->
          {:ok, %HTTPoison.Response{status_code: 200, body: "<invalid_payload>"}}
        end do
        response =
          HTTPTracker.send_scrape_request(%{
            tracker_url: tracker_url,
            info_hashes: [info_hash]
          })

        assert response ==
                 {:error,
                  "Failed to parse bencoded data: Unexpected token '<invalid_payload>' while parsing."}
      end
    end

    test "ensure HTTPTracker scrape returns default values on the missing info_data data", %{
      tracker_url: tracker_url,
      info_hash: info_hash
    } do
      {tracker_resp, _expected_files} = http_tracker_scrape_response(create_info_hash())

      expected_scrape_data = %ScrapeResponse{
        info_hash: info_hash,
        tracker_url: tracker_url,
        complete: 0,
        downloaded: 0,
        incomplete: 0,
        interval: Map.fetch!(tracker_resp, "interval"),
        min_interval: Map.fetch!(tracker_resp, "min interval"),
        updated_at: @mock_updated_date
      }

      with_mock HTTPoison,
        get: fn _tracker_url, _headers, _opts ->
          {:ok, mock_response} = Serializer.encode(tracker_resp)

          {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}
        end do
        {:ok, scrape_data} =
          HTTPTracker.send_scrape_request(%{
            tracker_url: tracker_url,
            info_hashes: [info_hash]
          })

        torrent_scrape_data = Map.fetch!(scrape_data, info_hash)

        assert torrent_scrape_data == expected_scrape_data
      end
    end

    test "ensure HTTPTracker scrape returns error on the missing interval value", %{
      tracker_url: tracker_url,
      info_hash: info_hash
    } do
      with_mock HTTPoison,
        get: fn _tracker_url, _headers, _opts ->
          {:ok, mock_response} =
            http_tracker_scrape_response(info_hash)
            |> elem(0)
            |> Map.delete("interval")
            |> Serializer.encode()

          {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}
        end do
        response =
          HTTPTracker.send_scrape_request(%{
            tracker_url: tracker_url,
            info_hashes: [info_hash]
          })

        assert response ==
                 {:error, "Interval value missing in response."}
      end
    end

    test "ensure HTTPTracker scrape returns error on the negative interval value", %{
      tracker_url: tracker_url,
      info_hash: info_hash
    } do
      interval = :rand.uniform(100) * -1

      with_mock HTTPoison,
        get: fn _tracker_url, _headers, _opts ->
          {:ok, mock_response} =
            http_tracker_scrape_response(info_hash)
            |> elem(0)
            |> Map.put("interval", interval)
            |> Serializer.encode()

          {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}
        end do
        response =
          HTTPTracker.send_scrape_request(%{
            tracker_url: tracker_url,
            info_hashes: [info_hash]
          })

        assert response ==
                 {:error, "Negative interval received with value #{interval}."}
      end
    end

    test "ensure HTTPTracker scrape negative min interval value is converted to nil", %{
      tracker_url: tracker_url,
      info_hash: info_hash
    } do
      {tracker_resp, _expected_files} = http_tracker_scrape_response(info_hash)
      torrent_scrape_data = tracker_resp |> Map.fetch!("files") |> Map.fetch!(info_hash)

      expected_scrape_data = %ScrapeResponse{
        info_hash: info_hash,
        tracker_url: tracker_url,
        complete: Map.fetch!(torrent_scrape_data, "complete"),
        downloaded: Map.fetch!(torrent_scrape_data, "downloaded"),
        incomplete: Map.fetch!(torrent_scrape_data, "incomplete"),
        interval: Map.fetch!(tracker_resp, "interval"),
        min_interval: nil,
        updated_at: @mock_updated_date
      }

      with_mock HTTPoison,
        get: fn _tracker_url, _headers, _opts ->
          {:ok, mock_response} =
            tracker_resp
            |> Map.put("min interval", :rand.uniform(100) * -1)
            |> Serializer.encode()

          {:ok, %HTTPoison.Response{status_code: 200, body: mock_response}}
        end do
        {:ok, scrape_response} =
          HTTPTracker.send_scrape_request(%{
            tracker_url: tracker_url,
            info_hashes: [info_hash]
          })

        torrent_scrape_data = Map.fetch!(scrape_response, info_hash)
        assert torrent_scrape_data == expected_scrape_data
      end
    end

    test "ensure HTTPTracker scrape returns error reason response", %{
      tracker_url: tracker_url,
      info_hash: info_hash
    } do
      failure_reason = Faker.Lorem.sentence()

      with_mock HTTPoison,
        get: fn _tracker_url, _headers, _opts ->
          {:ok, tracker_resp} = Serializer.encode(%{"failure reason" => failure_reason})
          {:ok, %HTTPoison.Response{status_code: 200, body: tracker_resp}}
        end do
        response =
          HTTPTracker.send_scrape_request(%{
            tracker_url: tracker_url,
            info_hashes: [info_hash]
          })

        assert response == {:error, failure_reason}
      end
    end
  end

  describe "Scrape URL convert" do
    test "Supported conversion announce URL to scrape URL" do
      url = Faker.Internet.url()

      assert HTTPTracker.create_scrape_url("#{url}/announce") == {:ok, "#{url}/scrape"}
      assert HTTPTracker.create_scrape_url("#{url}/announce.php") == {:ok, "#{url}/scrape.php"}
      assert HTTPTracker.create_scrape_url("#{url}/x/announce") == {:ok, "#{url}/x/scrape"}

      url_query_params = Faker.Lorem.sentence()

      assert HTTPTracker.create_scrape_url("#{url}/announce?#{url_query_params}") ==
               {:ok, "#{url}/scrape?#{url_query_params}"}
    end

    test "Not suported conversion announce URL to scrape URL" do
      url = Faker.Internet.url()

      assert HTTPTracker.create_scrape_url("#{url}/a") ==
               {:error, "Scrape is not supported for tracker #{url}/a."}

      url_slug = Faker.Internet.slug()

      assert HTTPTracker.create_scrape_url("#{url}/#{url_slug}announce") ==
               {:error, "Scrape is not supported for tracker #{url}/#{url_slug}announce."}

      url_query_params = Faker.Lorem.word() <> "/" <> Faker.Lorem.word()

      assert HTTPTracker.create_scrape_url("#{url}/announce?#{url_query_params}") ==
               {:error,
                "Scrape is not supported for tracker #{url}/announce?#{url_query_params}."}
    end
  end
end
