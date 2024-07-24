defmodule HiveTorrent.Bencode.SerializerExampleStruct do
  defstruct [:message, :value]
end

defmodule HiveTorrent.Bencode.SerializerTest do
  use ExUnit.Case
  doctest HiveTorrent.Bencode.Serializer

  alias HiveTorrent.Bencode.Serializer
  alias HiveTorrent.Bencode.SerializeError
  alias HiveTorrent.Bencode.SerializerExampleStruct

  ## Integer tests

  test "serialize positive integer" do
    assert Serializer.encode(30) == "i30e"
  end

  test "serialize negative integer" do
    assert Serializer.encode(-999) == "i-999e"
  end

  test "serialize zero integer" do
    assert Serializer.encode(0) == "i0e"
  end

  ## String tests

  test "serialize string" do
    assert Serializer.encode("software") == "8:software"
  end

  test "serialize empty string" do
    assert Serializer.encode("") == "0:"
  end

  ## nil test

  test "serialize nil" do
    assert Serializer.encode(nil) == "4:null"
  end

  ## atom tests

  test "serialize true" do
    assert Serializer.encode(true) == "4:true"
  end

  test "serialize :tests" do
    assert Serializer.encode(:tests) == "5:tests"
  end

  ## list tests

  test "serialize empty list" do
    assert Serializer.encode([]) == "le"
  end

  test "serialize integer list" do
    assert Serializer.encode([1, 2, 3]) == "li1ei2ei3ee"
  end

  test "serialize list of lists" do
    assert Serializer.encode([[1]]) == "lli1eee"
  end

  test "serialize list of maps" do
    assert Serializer.encode([%{"test" => 1}]) == "ld4:testi1eee"
  end

  ## map tests

  test "serialize empty map" do
    assert Serializer.encode(%{}) == "de"
  end

  test "serialize integer map" do
    assert Serializer.encode(%{"test" => 23}) == "d4:testi23ee"
  end

  test "serialize map of lists" do
    assert Serializer.encode(%{"test" => [1]}) == "d4:testli1eee"
  end

  test "serialize map of maps" do
    assert Serializer.encode(%{"test" => %{test: 999}}) == "d4:testd4:testi999eee"
  end

  test "serialize map ensure keys are sorted" do
    assert Serializer.encode(%{"c" => 1, "a" => 2}) == "d1:ai2e1:ci1ee"
  end

  ## map struct

  test "serialize SerializerExampleStruct" do
    assert Serializer.encode(%SerializerExampleStruct{message: "test", value: 100}) ==
             "d7:message4:test5:valuei100ee"
  end

  test "serialize unsupported float type" do
    error = catch_error(Serializer.encode(1.1))
    assert error == %SerializeError{value: 1.1, message: "Unsupported types: Float"}
  end

  test "serialize unsupported tuple type" do
    error = catch_error(Serializer.encode({13, "test"}))
    assert error == %SerializeError{value: {13, "test"}, message: "Unsupported types: Tuple"}
  end

  test "serialize unsupported function type" do
    func = fn x -> IO.inspect(x) end
    error = catch_error(Serializer.encode(func))
    assert error == %SerializeError{value: func, message: "Unsupported types: Function"}
  end
end
