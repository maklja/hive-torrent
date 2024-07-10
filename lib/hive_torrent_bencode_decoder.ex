defmodule HiveTorrent.Bencode.Decoder do
  def decode(bencode_data, opts \\ []) do
  end

  defp transform(value, into: into) when is_map(value) do
    transform_map(value, into)
  end

  defp transform(value, _opts), do: value

  defp transform_map(value, into) when is_struct(into) do
    value
    |> transform_map(Map.from_struct(into))
    |> Map.put(:__struct__, into.__struct__)
  end

  defp transform_map(value, into) when is_map(into) do
    Enum.reduce(into, %{}, fn {key, default}, acc ->
      item = Map.get(value, to_string(key), default)

      Map.put(acc, key, transform(item, as: default))
    end)
  end

  defp transform_map(value, _as), do: value
end
