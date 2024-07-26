defmodule HiveTorrent.Bencode.SyntaxError do
  defexception [:message]

  @type t(message) :: %HiveTorrent.Bencode.SyntaxError{message: message}

  @type t :: %HiveTorrent.Bencode.SyntaxError{message: String.t()}

  @impl true
  def exception(:eof) do
    msg = "Unexpected end of the input"
    %HiveTorrent.Bencode.SyntaxError{message: msg}
  end

  @impl true
  def exception(invalid_token) do
    msg = "Unexpected token '#{invalid_token}' while parsing"
    %HiveTorrent.Bencode.SyntaxError{message: msg}
  end
end

defmodule HiveTorrent.Bencode.Parser do
  @moduledoc """
  Parser for Bencode format.

  Reference:

  - http://www.bittorrent.org/beps/bep_0003.html#bencoding
  - https://en.wikipedia.org/wiki/Bencode
  """

  require Logger

  alias HiveTorrent.Bencode.SyntaxError

  @type t :: integer() | String.t() | list() | map()
  @type parse_err :: SyntaxError.t()

  @doc """
  Tries to parse Bencode format into Elixir type integer, string, list or map.

  Returns {:ok, result}, otherwise {:error, %HiveTorrent.Bencode.SyntaxError{message}}

  ## Examples
      iex> "i30e" |> IO.iodata_to_binary() |> HiveTorrent.Bencode.Parser.parse()
      {:ok, 30}

      iex> "i30" |> IO.iodata_to_binary() |> HiveTorrent.Bencode.Parser.parse()
      {:error, %HiveTorrent.Bencode.SyntaxError{message: "Unexpected end of the input"}}
  """
  @spec parse(iodata()) :: {:ok, t()} | {:error, parse_err()}
  def parse(bencode_data) when is_binary(bencode_data) do
    {value, rest} = parse_value(bencode_data)

    case rest do
      "" -> {:ok, value}
      other -> syntax_error(other)
    end
  catch
    {:syntax_error, invalid_token} -> {:error, SyntaxError.exception(invalid_token)}
  end

  @doc """
  Same as parse/1, but raises a HiveTorrent.Bencode.SyntaxError exception in case of failure. Otherwise return a value.
  """
  @spec parse!(iodata()) :: t() | no_return()
  def parse!(bencode_data) when is_binary(bencode_data) do
    case parse(bencode_data) do
      {:ok, value} -> value
      {:error, e} -> raise e
    end
  end

  defp parse_value("i" <> rest) do
    Logger.debug("Starting integer parsing")

    value = parse_integer(rest)
    Logger.debug("Successfully parsed integer value #{elem(value, 0)}")
    value
  end

  defp parse_value("l" <> rest) do
    Logger.debug("Starting list parsing")

    value = parse_list(rest, [])
    Logger.debug("Successfully parsed list value #{value |> elem(0) |> inspect()}")
    value
  end

  defp parse_value("d" <> rest) do
    Logger.debug("Starting dict parsing")

    value = parse_dict(rest, [])
    Logger.debug("Successfully parsed dict value #{value |> elem(0) |> inspect()}")
    value
  end

  defp parse_value(<<digit>> <> _rest = data_bytes)
       when digit in ~c"0123456789" do
    Logger.debug("Starting string parsing")

    value = parse_string(data_bytes)
    Logger.debug("Successfully parsed string value #{value |> elem(0) |> inspect()}")
    value
  end

  defp parse_value(other), do: syntax_error(other)

  ## Integer

  defp parse_integer("0e" <> rest), do: {0, rest}

  # Error cases
  defp parse_integer("-e" <> _rest), do: syntax_error("i-e")

  defp parse_integer("-0" <> _rest), do: syntax_error("i-0?e")

  defp parse_integer("e" <> _rest), do: syntax_error("ie")

  defp parse_integer("0" <> _rest), do: syntax_error("i0?e")

  # Integer parse
  defp parse_integer(<<c>> <> rest) when c in ~c"-0123456789",
    do: continue_parse_integer(rest, [c])

  defp continue_parse_integer("e" <> rest, acc),
    do: {acc |> Enum.reverse() |> List.to_integer(), rest}

  defp continue_parse_integer(<<digit>> <> rest, acc) when digit in ~c"0123456789",
    do: continue_parse_integer(rest, [digit | acc])

  defp continue_parse_integer("", _acc),
    do: syntax_error(:eof)

  defp continue_parse_integer(other, _acc),
    do: syntax_error(other)

  ## String

  defp parse_string("0:" <> rest), do: {"", rest}

  defp parse_string(<<digit>> <> rest) when digit in ~c"123456789",
    do: parse_string_len(rest, [digit])

  defp parse_string(other),
    do: syntax_error(other)

  defp parse_string_len(":" <> rest, acc) do
    str_len = acc |> Enum.reverse() |> List.to_integer()
    parse_string_content(str_len, rest)
  end

  defp parse_string_len(<<digit>> <> rest, acc) when digit in ~c"0123456789",
    do: parse_string_len(rest, [digit | acc])

  defp parse_string_len(<<char>> <> _rest, acc) do
    str_len = acc |> Enum.reverse() |> List.to_integer() |> to_string
    syntax_error(str_len <> <<char>> <> "?")
  end

  defp parse_string_content(str_len, str_value) when str_len > byte_size(str_value),
    do: syntax_error(:eof)

  defp parse_string_content(str_len, str_value) do
    <<content::binary-size(str_len)>> <> rest = str_value
    {content, rest}
  end

  ## List

  defp parse_list("e" <> rest, acc), do: {Enum.reverse(acc), rest}

  defp parse_list(list_content, acc) do
    {list_item, rest} = parse_value(list_content)
    acc = [list_item | acc]

    case rest do
      "" -> syntax_error(:eof)
      rest -> parse_list(rest, acc)
    end
  end

  ## Map

  defp parse_dict("e" <> rest, acc), do: {acc |> Enum.reverse() |> Map.new(), rest}

  defp parse_dict(dict_content, acc) do
    {key, rest} = parse_string(dict_content)
    {value, rest} = parse_value(rest)

    acc = [{key, value} | acc]

    case rest do
      "" -> syntax_error(:eof)
      rest -> parse_dict(rest, acc)
    end
  end

  defp syntax_error(token), do: throw({:syntax_error, token})
end
