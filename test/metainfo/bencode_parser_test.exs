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

  describe "List parse tests" do
    setup do
      [
        test_lists: %{
          list_of_integers: {"li30ei-15ei0ee", [30, -15, 0]},
          list_of_strings: {"l8:software11:developmente", ["software", "development"]},
          empty: {"le", []},
          list_of_lists: {"lli999eee", [[999]]},
          list_of_maps: {"ld3:cati4eedee", [%{"cat" => 4}, %{}]},
          corrupted: {"ld3:cati4eede", "Unexpected end of the input"}
        }
      ]
    end

    test "parse list of integers", fixture do
      {value, expected} = fixture.test_lists.list_of_integers
      assert value |> IO.iodata_to_binary() |> Parser.parse() == {:ok, expected}
    end

    test "parse list of strings", fixture do
      {value, expected} = fixture.test_lists.list_of_strings

      assert value |> IO.iodata_to_binary() |> Parser.parse() ==
               {:ok, expected}
    end

    test "parse empty list", fixture do
      {value, expected} = fixture.test_lists.empty
      assert value |> IO.iodata_to_binary() |> Parser.parse() == {:ok, expected}
    end

    test "parse list of the list", fixture do
      {value, expected} = fixture.test_lists.list_of_lists
      assert value |> IO.iodata_to_binary() |> Parser.parse() == {:ok, expected}
    end

    test "parse list of the map", fixture do
      {value, expected} = fixture.test_lists.list_of_maps
      result = value |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:ok, expected}
    end

    test "parse list without closing token", fixture do
      {value, expected} = fixture.test_lists.corrupted
      result = value |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:error, %SyntaxError{message: expected}}
    end

    test "parse! list of integers", fixture do
      {value, expected} = fixture.test_lists.list_of_integers
      assert value |> IO.iodata_to_binary() |> Parser.parse!() == expected
    end

    test "parse! list of strings", fixture do
      {value, expected} = fixture.test_lists.list_of_strings
      assert value |> IO.iodata_to_binary() |> Parser.parse!() == expected
    end

    test "parse! empty list", fixture do
      {value, expected} = fixture.test_lists.empty
      assert value |> IO.iodata_to_binary() |> Parser.parse!() == expected
    end

    test "parse! list of the list", fixture do
      {value, expected} = fixture.test_lists.list_of_lists
      assert value |> IO.iodata_to_binary() |> Parser.parse!() == expected
    end

    test "parse! list of the map", fixture do
      {value, expected} = fixture.test_lists.list_of_maps
      result = value |> IO.iodata_to_binary() |> Parser.parse!()
      assert result == expected
    end

    test "parse! list without closing token", fixture do
      {value, expected} = fixture.test_lists.corrupted
      error = catch_error(value |> IO.iodata_to_binary() |> Parser.parse!())
      assert error == %SyntaxError{message: expected}
    end
  end

  describe "Map parse tests" do
    setup do
      [
        test_maps: %{
          map_of_integers: {"d3:keyi30ee", %{"key" => 30}},
          map_of_lists: {"d3:keyli30ei35eee", %{"key" => [30, 35]}},
          map_of_maps: {"d3:keyd3:dogi5eee", %{"key" => %{"dog" => 5}}},
          empty: {"de", %{}},
          corrupted: {"d3:keyd3:dogi5ee", "Unexpected end of the input"}
        }
      ]
    end

    test "parse map of <string, integer>", fixture do
      {value, expected} = fixture.test_maps.map_of_integers
      result = value |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:ok, expected}
    end

    test "parse map of <string, list<integer>>", fixture do
      {value, expected} = fixture.test_maps.map_of_lists
      result = value |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:ok, expected}
    end

    test "parse map of <string, map<string, integer>>", fixture do
      {value, expected} = fixture.test_maps.map_of_maps
      result = value |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:ok, expected}
    end

    test "parse empty map", fixture do
      {value, expected} = fixture.test_maps.empty
      assert value |> IO.iodata_to_binary() |> Parser.parse() == {:ok, expected}
    end

    test "parse map without closing token", fixture do
      {value, expected} = fixture.test_maps.corrupted
      result = value |> IO.iodata_to_binary() |> Parser.parse()
      assert result == {:error, %SyntaxError{message: expected}}
    end

    test "parse! map of <string, integer>", fixture do
      {value, expected} = fixture.test_maps.map_of_integers
      result = value |> IO.iodata_to_binary() |> Parser.parse!()
      assert result == expected
    end

    test "parse! map of <string, list<integer>>", fixture do
      {value, expected} = fixture.test_maps.map_of_lists
      result = value |> IO.iodata_to_binary() |> Parser.parse!()
      assert result == expected
    end

    test "parse! map of <string, map<string, integer>>", fixture do
      {value, expected} = fixture.test_maps.map_of_maps
      result = value |> IO.iodata_to_binary() |> Parser.parse!()
      assert result == expected
    end

    test "parse! empty map", fixture do
      {value, expected} = fixture.test_maps.empty
      assert value |> IO.iodata_to_binary() |> Parser.parse!() == expected
    end

    test "parse! map without closing token", fixture do
      {value, expected} = fixture.test_maps.corrupted
      error = catch_error(value |> IO.iodata_to_binary() |> Parser.parse!())
      assert error == %SyntaxError{message: expected}
    end
  end
end
