defmodule HiveTorrent.Bencode.ParserTest do
  use ExUnit.Case
  doctest HiveTorrent.Bencode.Parser

  alias HiveTorrent.Bencode.Parser
  alias HiveTorrent.Bencode.SyntaxError

  describe "Integer parse tests" do
    setup do
      [
        test_numbers: %{
          positive_int: {"i30e", 30},
          negative_int: {"i-999e", -999},
          zero: {"i0e", 0},
          negative_zero: {"i-0e", "Unexpected token 'i-0?e' while parsing"},
          empty: {"ie", "Unexpected token 'ie' while parsing"},
          minus_only: {"i-e", "Unexpected token 'i-e' while parsing"},
          corrupted: {"i1-e", "Unexpected token '-e' while parsing"},
          float: {"i1.2e", "Unexpected token '.2e' while parsing"},
          no_closing_tag: {"i12", "Unexpected end of the input"}
        }
      ]
    end

    test "parse positive integer", fixture do
      {value, expected} = fixture.test_numbers.positive_int
      assert value |> IO.iodata_to_binary() |> Parser.parse() == {:ok, expected}
    end

    test "parse negative integer", fixture do
      {value, expected} = fixture.test_numbers.negative_int
      assert value |> IO.iodata_to_binary() |> Parser.parse() == {:ok, expected}
    end

    test "parse zero integer", fixture do
      {value, expected} = fixture.test_numbers.zero
      assert value |> IO.iodata_to_binary() |> Parser.parse() == {:ok, expected}
    end

    test "parse negative zero integer", fixture do
      {value, expected} = fixture.test_numbers.negative_zero
      result = value |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:error, %SyntaxError{message: expected}}
    end

    test "parse empty integer", fixture do
      {value, expected} = fixture.test_numbers.empty
      result = value |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:error, %SyntaxError{message: expected}}
    end

    test "parse minus only integer", fixture do
      {value, expected} = fixture.test_numbers.minus_only
      result = value |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:error, %SyntaxError{message: expected}}
    end

    test "parse corrupted integer", fixture do
      {value, expected} = fixture.test_numbers.corrupted
      result = value |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:error, %SyntaxError{message: expected}}
    end

    test "parse float", fixture do
      {value, expected} = fixture.test_numbers.float
      result = value |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:error, %SyntaxError{message: expected}}
    end

    test "parse integer without closing token", fixture do
      {value, expected} = fixture.test_numbers.no_closing_tag
      result = value |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:error, %SyntaxError{message: expected}}
    end

    test "parse! positive integer", fixture do
      {value, expected} = fixture.test_numbers.positive_int
      assert value |> IO.iodata_to_binary() |> Parser.parse!() == expected
    end

    test "parse! negative integer", fixture do
      {value, expected} = fixture.test_numbers.negative_int
      assert value |> IO.iodata_to_binary() |> Parser.parse!() == expected
    end

    test "parse! zero integer", fixture do
      {value, expected} = fixture.test_numbers.zero
      assert value |> IO.iodata_to_binary() |> Parser.parse!() == expected
    end

    test "parse! negative zero integer", fixture do
      {value, expected} = fixture.test_numbers.negative_zero
      error = catch_error(value |> IO.iodata_to_binary() |> Parser.parse!())
      assert error == %SyntaxError{message: expected}
    end

    test "parse! empty integer", fixture do
      {value, expected} = fixture.test_numbers.empty
      error = catch_error(value |> IO.iodata_to_binary() |> Parser.parse!())
      assert error == %SyntaxError{message: expected}
    end

    test "parse! minus only integer", fixture do
      {value, expected} = fixture.test_numbers.minus_only
      error = catch_error(value |> IO.iodata_to_binary() |> Parser.parse!())
      assert error == %SyntaxError{message: expected}
    end

    test "parse! corrupted integer", fixture do
      {value, expected} = fixture.test_numbers.corrupted
      result = catch_error(value |> IO.iodata_to_binary() |> Parser.parse!())
      assert result == %SyntaxError{message: expected}
    end

    test "parse! float", fixture do
      {value, expected} = fixture.test_numbers.float
      result = catch_error(value |> IO.iodata_to_binary() |> Parser.parse!())
      assert result == %SyntaxError{message: expected}
    end

    test "parse! integer without closing token", fixture do
      {value, expected} = fixture.test_numbers.no_closing_tag
      result = catch_error(value |> IO.iodata_to_binary() |> Parser.parse!())
      assert result == %SyntaxError{message: expected}
    end
  end

  describe "String parse tests" do
    setup do
      [
        test_strings: %{
          software: {"8:software", "software"},
          empty: {"0:", ""},
          invalid_length: {"8:test", "Unexpected end of the input"},
          short_length: {"2:test", "Unexpected token 'st' while parsing"},
          corrupted: {"x:test", "Unexpected token 'x:test' while parsing"},
          invalid_string: {":test", "Unexpected token ':test' while parsing"}
        }
      ]
    end

    test "parse string", fixture do
      {value, expected} = fixture.test_strings.software
      assert value |> IO.iodata_to_binary() |> Parser.parse() == {:ok, expected}
    end

    test "parse empty string", fixture do
      {value, expected} = fixture.test_strings.empty
      assert value |> IO.iodata_to_binary() |> Parser.parse() == {:ok, expected}
    end

    test "parse string with invalid length", fixture do
      {value, expected} = fixture.test_strings.invalid_length
      result = value |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:error, %SyntaxError{message: expected}}
    end

    test "parse string with short length", fixture do
      {value, expected} = fixture.test_strings.short_length
      result = value |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:error, %SyntaxError{message: expected}}
    end

    test "parse string with corrupted length", fixture do
      {value, expected} = fixture.test_strings.corrupted
      result = value |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:error, %SyntaxError{message: expected}}
    end

    test "parse invalid string", fixture do
      {value, expected} = fixture.test_strings.invalid_string
      result = value |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:error, %SyntaxError{message: expected}}
    end

    test "parse! string", fixture do
      {value, expected} = fixture.test_strings.software
      assert value |> IO.iodata_to_binary() |> Parser.parse!() == expected
    end

    test "parse! empty string", fixture do
      {value, expected} = fixture.test_strings.empty
      assert value |> IO.iodata_to_binary() |> Parser.parse!() == expected
    end

    test "parse! string with invalid length", fixture do
      {value, expected} = fixture.test_strings.invalid_length
      error = catch_error(value |> IO.iodata_to_binary() |> Parser.parse!())
      assert error == %SyntaxError{message: expected}
    end

    test "parse! string with short length", fixture do
      {value, expected} = fixture.test_strings.short_length
      error = catch_error(value |> IO.iodata_to_binary() |> Parser.parse!())
      assert error == %SyntaxError{message: expected}
    end

    test "parse! string with corrupted length", fixture do
      {value, expected} = fixture.test_strings.corrupted
      error = catch_error(value |> IO.iodata_to_binary() |> Parser.parse!())
      assert error == %SyntaxError{message: expected}
    end

    test "parse! invalid string", fixture do
      {value, expected} = fixture.test_strings.invalid_string
      error = catch_error(value |> IO.iodata_to_binary() |> Parser.parse!())
      assert error == %SyntaxError{message: expected}
    end
  end

  describe "List tests parse with tuple" do
    test "parse list of integers" do
      assert "li30ei-15ei0ee" |> IO.iodata_to_binary() |> Parser.parse() == {:ok, [30, -15, 0]}
    end

    test "parse list of strings" do
      assert "l8:software11:developmente" |> IO.iodata_to_binary() |> Parser.parse() ==
               {:ok, ["software", "development"]}
    end

    test "parse empty list" do
      assert "le" |> IO.iodata_to_binary() |> Parser.parse() == {:ok, []}
    end

    test "parse list of the list" do
      assert "lli999eee" |> IO.iodata_to_binary() |> Parser.parse() == {:ok, [[999]]}
    end

    test "parse list of the map" do
      result = "ld3:cati4eedee" |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:ok, [%{"cat" => 4}, %{}]}
    end

    test "parse list without closing token" do
      result = "ld3:cati4eede" |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:error, %SyntaxError{message: "Unexpected end of the input"}}
    end
  end

  describe "List tests parse with exception" do
    test "parse! list of integers" do
      assert "li30ei-15ei0ee" |> IO.iodata_to_binary() |> Parser.parse!() == [30, -15, 0]
    end

    test "parse! list of strings" do
      assert "l8:software11:developmente" |> IO.iodata_to_binary() |> Parser.parse!() == [
               "software",
               "development"
             ]
    end

    test "parse! empty list" do
      assert "le" |> IO.iodata_to_binary() |> Parser.parse!() == []
    end

    test "parse! list of the list" do
      assert "lli999eee" |> IO.iodata_to_binary() |> Parser.parse!() == [[999]]
    end

    test "parse! list of the map" do
      result = "ld3:cati4eedee" |> IO.iodata_to_binary() |> Parser.parse!()
      assert result == [%{"cat" => 4}, %{}]
    end

    test "parse! list without closing token" do
      error = catch_error("ld3:cati4eede" |> IO.iodata_to_binary() |> Parser.parse!())
      assert error == %SyntaxError{message: "Unexpected end of the input"}
    end
  end

  describe "Map test parse with tuple" do
    test "parse map of <string, integer>" do
      result = "d3:keyi30ee" |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:ok, %{"key" => 30}}
    end

    test "parse map of <string, list<integer>>" do
      result = "d3:keyli30ei35eee" |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:ok, %{"key" => [30, 35]}}
    end

    test "parse map of <string, map<string, integer>>" do
      result = "d3:keyd3:dogi5eee" |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:ok, %{"key" => %{"dog" => 5}}}
    end

    test "parse empty map" do
      assert "de" |> IO.iodata_to_binary() |> Parser.parse() == {:ok, %{}}
    end

    test "parse map without closing token" do
      result = "d3:keyd3:dogi5ee" |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:error, %SyntaxError{message: "Unexpected end of the input"}}
    end
  end

  describe "Map test parse with exception" do
    test "parse! map of <string, integer>" do
      result = "d3:keyi30ee" |> IO.iodata_to_binary() |> Parser.parse!()
      assert result == %{"key" => 30}
    end

    test "parse! map of <string, list<integer>>" do
      result = "d3:keyli30ei35eee" |> IO.iodata_to_binary() |> Parser.parse!()
      assert result == %{"key" => [30, 35]}
    end

    test "parse! map of <string, map<string, integer>>" do
      result = "d3:keyd3:dogi5eee" |> IO.iodata_to_binary() |> Parser.parse!()
      assert result == %{"key" => %{"dog" => 5}}
    end

    test "parse! empty map" do
      assert "de" |> IO.iodata_to_binary() |> Parser.parse!() == %{}
    end

    test "parse! map without closing token" do
      error = catch_error("d3:keyd3:dogi5ee" |> IO.iodata_to_binary() |> Parser.parse!())
      assert error == %SyntaxError{message: "Unexpected end of the input"}
    end
  end
end
