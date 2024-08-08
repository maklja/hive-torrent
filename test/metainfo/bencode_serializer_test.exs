defmodule HiveTorrent.Bencode.SerializerExampleStruct do
  defstruct [:message, :value]
end

defmodule HiveTorrent.Bencode.SerializerTest do
  use ExUnit.Case
  doctest HiveTorrent.Bencode.Serializer

  alias HiveTorrent.Bencode.Serializer
  alias HiveTorrent.Bencode.SerializeError
  alias HiveTorrent.Bencode.SerializerExampleStruct

  describe "Integer tests" do
    test "encode! positive integer" do
      assert Serializer.encode!(30) == "i30e"
    end

    test "encode positive integer" do
      assert Serializer.encode(30) == {:ok, "i30e"}
    end

    test "encode! negative integer" do
      assert Serializer.encode!(-999) == "i-999e"
    end

    test "encode negative integer" do
      assert Serializer.encode(-999) == {:ok, "i-999e"}
    end

    test "encode! zero integer" do
      assert Serializer.encode!(0) == "i0e"
    end

    test "encode zero integer" do
      assert Serializer.encode(0) == {:ok, "i0e"}
    end
  end

  describe "String tests" do
    test "encode! string" do
      assert Serializer.encode!("software") == "8:software"
    end

    test "encode string" do
      assert Serializer.encode("software") == {:ok, "8:software"}
    end

    test "encode! empty string" do
      assert Serializer.encode!("") == "0:"
    end

    test "encode empty string" do
      assert Serializer.encode("") == {:ok, "0:"}
    end
  end

  describe "nil test" do
    test "encode! nil" do
      assert Serializer.encode!(nil) == "4:null"
    end

    test "encode nil" do
      assert Serializer.encode(nil) == {:ok, "4:null"}
    end
  end

  describe "atom tests" do
    test "encode! true" do
      assert Serializer.encode!(true) == "4:true"
    end

    test "encode true" do
      assert Serializer.encode(true) == {:ok, "4:true"}
    end

    test "encode! :tests" do
      assert Serializer.encode!(:tests) == "5:tests"
    end

    test "encode :tests" do
      assert Serializer.encode(:tests) == {:ok, "5:tests"}
    end
  end

  describe "list tests" do
    test "encode! empty list" do
      assert Serializer.encode!([]) == "le"
    end

    test "encode empty list" do
      assert Serializer.encode([]) == {:ok, "le"}
    end

    test "encode! integer list" do
      assert Serializer.encode!([1, 2, 3]) == "li1ei2ei3ee"
    end

    test "encode integer list" do
      assert Serializer.encode([1, 2, 3]) == {:ok, "li1ei2ei3ee"}
    end

    test "encode! list of lists" do
      assert Serializer.encode!([[1]]) == "lli1eee"
    end

    test "encode list of lists" do
      assert Serializer.encode([[1]]) == {:ok, "lli1eee"}
    end

    test "encode! list of maps" do
      assert Serializer.encode!([%{"test" => 1}]) == "ld4:testi1eee"
    end

    test "encode list of maps" do
      assert Serializer.encode([%{"test" => 1}]) == {:ok, "ld4:testi1eee"}
    end
  end

  describe "map tests" do
    test "encode! empty map" do
      assert Serializer.encode!(%{}) == "de"
    end

    test "encode empty map" do
      assert Serializer.encode(%{}) == {:ok, "de"}
    end

    test "encode! integer map" do
      assert Serializer.encode!(%{"test" => 23}) == "d4:testi23ee"
    end

    test "encode integer map" do
      assert Serializer.encode(%{"test" => 23}) == {:ok, "d4:testi23ee"}
    end

    test "encode! map of lists" do
      assert Serializer.encode!(%{"test" => [1]}) == "d4:testli1eee"
    end

    test "encode map of lists" do
      assert Serializer.encode(%{"test" => [1]}) == {:ok, "d4:testli1eee"}
    end

    test "encode! map of maps" do
      assert Serializer.encode!(%{"test" => %{test: 999}}) == "d4:testd4:testi999eee"
    end

    test "encode map of maps" do
      assert Serializer.encode(%{"test" => %{test: 999}}) == {:ok, "d4:testd4:testi999eee"}
    end

    test "encode! map ensure keys are sorted" do
      assert Serializer.encode!(%{"c" => 1, "a" => 2}) == "d1:ai2e1:ci1ee"
    end

    test "encode map ensure keys are sorted" do
      assert Serializer.encode(%{"c" => 1, "a" => 2}) == {:ok, "d1:ai2e1:ci1ee"}
    end
  end

  describe "map struct" do
    test "encode! SerializerExampleStruct" do
      assert Serializer.encode!(%SerializerExampleStruct{message: "test", value: 100}) ==
               "d7:message4:test5:valuei100ee"
    end

    test "encode SerializerExampleStruct" do
      assert Serializer.encode(%SerializerExampleStruct{message: "test", value: 100}) ==
               {:ok, "d7:message4:test5:valuei100ee"}
    end

    test "encode! unsupported float type" do
      error = catch_error(Serializer.encode!(1.1))
      assert error == %SerializeError{value: 1.1, message: "Unsupported types: Float"}
    end

    test "encode unsupported float type" do
      {:error, error} = Serializer.encode(1.1)
      assert error == %SerializeError{value: 1.1, message: "Unsupported types: Float"}
    end

    test "encode! unsupported tuple type" do
      error = catch_error(Serializer.encode!({13, "test"}))
      assert error == %SerializeError{value: {13, "test"}, message: "Unsupported types: Tuple"}
    end

    test "encode unsupported tuple type" do
      {:error, error} = Serializer.encode({13, "test"})
      assert error == %SerializeError{value: {13, "test"}, message: "Unsupported types: Tuple"}
    end

    test "encode! unsupported function type" do
      func = fn x -> IO.inspect(x) end
      error = catch_error(Serializer.encode!(func))
      assert error == %SerializeError{value: func, message: "Unsupported types: Function"}
    end

    test "encode unsupported function type" do
      func = fn x -> IO.inspect(x) end
      {:error, error} = Serializer.encode(func)
      assert error == %SerializeError{value: func, message: "Unsupported types: Function"}
    end

    test "encode! unsupported map key type" do
      error = catch_error(Serializer.encode!(%{{1} => "test"}))

      assert error == %SerializeError{
               value: {1},
               message: "Supported map key types are only Atoms and Strings"
             }
    end

    test "encode unsupported map key type" do
      {:error, error} = Serializer.encode(%{{1} => "test"})

      assert error == %SerializeError{
               value: {1},
               message: "Supported map key types are only Atoms and Strings"
             }
    end
  end
end
