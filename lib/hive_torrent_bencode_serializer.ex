defmodule HiveTorrent.Bencode.SerializeError do
  @moduledoc """
  Raised when unsupported type is passed to the serializer.
  """

  defexception [:value, :message]

  @type t(value, message) :: %HiveTorrent.Bencode.SerializeError{value: value, message: message}

  @type t :: %HiveTorrent.Bencode.SerializeError{value: String.t()}

  @impl true
  def message(%{message: message}), do: message
end

defmodule HiveTorrent.Bencode.Serializer do
  @moduledoc """
  Serialize Elixir types to Bencode.
  Supported types are atoms, integers, strings, lists and maps.
  Structs are also supported and will be serialized as map.
  Serialization of the custom types can be expanded using protocol HiveTorrent.Bencode.SerializerProtocol.

  Reference:

  - http://www.bittorrent.org/beps/bep_0003.html#bencoding
  - https://en.wikipedia.org/wiki/Bencode
  """

  alias HiveTorrent.Bencode.SerializerProtocol

  @type serializable :: SerializerProtocol.serializable()

  @doc """
  Serialize Elixir types into the Bencode format.

  Returns Bencode string value, otherwise raises HiveTorrent.Bencode.SerializeError

  ## Examples
      iex> HiveTorrent.Bencode.Serializer.encode(1)
      "i1e"

      iex> HiveTorrent.Bencode.Serializer.encode(%{test: 999})
      "d4:testi999ee"

      iex> HiveTorrent.Bencode.Serializer.encode(9.99)
      ** (HiveTorrent.Bencode.SerializeError) Unsupported types: Float
  """
  @spec encode(serializable()) :: binary() | no_return()
  def encode(value) do
    value |> SerializerProtocol.encode() |> IO.iodata_to_binary()
  end
end

defprotocol HiveTorrent.Bencode.SerializerProtocol do
  @fallback_to_any true

  @type serializable :: atom() | HiveTorrent.Bencode.Parser.t() | Enumerable.t()

  @doc """
  Encode an Elixir value into its Bencoded form.
  """
  @spec encode(serializable()) :: iodata() | no_return()
  def encode(value)
end

defimpl HiveTorrent.Bencode.SerializerProtocol, for: Atom do
  alias HiveTorrent.Bencode.SerializerProtocol

  def encode(nil), do: "4:null"

  def encode(atom), do: atom |> Atom.to_string() |> SerializerProtocol.encode()
end

defimpl HiveTorrent.Bencode.SerializerProtocol, for: Integer do
  def encode(int), do: [?i, Integer.to_string(int), ?e]
end

defimpl HiveTorrent.Bencode.SerializerProtocol, for: BitString do
  def encode(str), do: [str |> byte_size() |> Integer.to_string(), ?:, str]
end

defimpl HiveTorrent.Bencode.SerializerProtocol, for: Map do
  alias HiveTorrent.Bencode.SerializerProtocol
  alias HiveTorrent.Bencode.SerializeError

  def encode(map) when map_size(map) == 0, do: "de"

  def encode(map) do
    dict =
      map
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map(fn
        key when is_bitstring(key) ->
          [
            SerializerProtocol.BitString.encode(key),
            SerializerProtocol.encode(Map.get(map, key))
          ]

        key when is_atom(key) ->
          [
            SerializerProtocol.Atom.encode(key),
            SerializerProtocol.encode(Map.get(map, key))
          ]

        key ->
          raise SerializeError,
            value: key,
            message: "Supported map key types are only Atoms and Strings"
      end)

    [?d, dict, ?e]
  end
end

defimpl HiveTorrent.Bencode.SerializerProtocol, for: [List, Range, Stream] do
  alias HiveTorrent.Bencode.SerializerProtocol

  def encode([]), do: "le"

  def encode(list) do
    [?l, list |> Enum.map(&SerializerProtocol.encode/1), ?e]
  end
end

defimpl HiveTorrent.Bencode.SerializerProtocol, for: Any do
  alias HiveTorrent.Bencode.SerializeError
  alias HiveTorrent.Bencode.SerializerProtocol

  def encode(struct) when is_struct(struct) do
    struct |> Map.from_struct() |> SerializerProtocol.encode()
  end

  # Types that do not conform to the bencoding specification.
  # See: http://www.bittorrent.org/beps/bep_0003.html#bencoding
  def encode(value) do
    raise SerializeError,
      value: value,
      message: "Unsupported types: #{value_type(value)}"
  end

  defp value_type(value) when is_float(value), do: "Float"
  defp value_type(value) when is_function(value), do: "Function"
  defp value_type(value) when is_pid(value), do: "PID"
  defp value_type(value) when is_port(value), do: "Port"
  defp value_type(value) when is_reference(value), do: "Reference"
  defp value_type(value) when is_tuple(value), do: "Tuple"
end
