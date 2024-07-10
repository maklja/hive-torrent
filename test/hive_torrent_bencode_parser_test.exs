defmodule HiveTorrent.Bencode.ParserTest do
  use ExUnit.Case
  doctest HiveTorrent.Bencode.Parser

  alias HiveTorrent.Bencode.Parser
  alias HiveTorrent.Bencode.SyntaxError

  ## Integer tests parse with tuple

  test "parse positive integer" do
    assert "i30e" |> IO.iodata_to_binary() |> Parser.parse() == {:ok, 30}
  end

  test "parse negative integer" do
    assert "i-999e" |> IO.iodata_to_binary() |> Parser.parse() == {:ok, -999}
  end

  test "parse zero integer" do
    assert "i0e" |> IO.iodata_to_binary() |> Parser.parse() == {:ok, 0}
  end

  test "parse negative zero integer" do
    result = "i-0e" |> IO.iodata_to_binary() |> Parser.parse()
    assert result == {:error, %SyntaxError{message: "Unexpected token 'i-0?e' while parsing"}}
  end

  test "parse empty integer" do
    result = "ie" |> IO.iodata_to_binary() |> Parser.parse()
    assert result == {:error, %SyntaxError{message: "Unexpected token 'ie' while parsing"}}
  end

  test "parse minus only integer" do
    result = "i-e" |> IO.iodata_to_binary() |> Parser.parse()
    assert result == {:error, %SyntaxError{message: "Unexpected token 'i-e' while parsing"}}
  end

  test "parse corrupted integer" do
    result = "i1-e" |> IO.iodata_to_binary() |> Parser.parse()
    assert result == {:error, %SyntaxError{message: "Unexpected token '-e' while parsing"}}
  end

  test "parse float" do
    result = "i1.2e" |> IO.iodata_to_binary() |> Parser.parse()
    assert result == {:error, %SyntaxError{message: "Unexpected token '.2e' while parsing"}}
  end

  test "parse integer without closing token" do
    result = "i12" |> IO.iodata_to_binary() |> Parser.parse()
    assert result == {:error, %SyntaxError{message: "Unexpected end of the input"}}
  end

  ## Integer tests parse with exception

  test "parse! positive integer" do
    assert "i30e" |> IO.iodata_to_binary() |> Parser.parse!() == 30
  end

  test "parse! negative integer" do
    assert "i-999e" |> IO.iodata_to_binary() |> Parser.parse!() == -999
  end

  test "parse! zero integer" do
    assert "i0e" |> IO.iodata_to_binary() |> Parser.parse!() == 0
  end

  test "parse! negative zero integer" do
    error = catch_error("i-0e" |> IO.iodata_to_binary() |> Parser.parse!())
    assert error == %SyntaxError{message: "Unexpected token 'i-0?e' while parsing"}
  end

  test "parse! empty integer" do
    error = catch_error("ie" |> IO.iodata_to_binary() |> Parser.parse!())
    assert error == %SyntaxError{message: "Unexpected token 'ie' while parsing"}
  end

  test "parse! minus only integer" do
    error = catch_error("i-e" |> IO.iodata_to_binary() |> Parser.parse!())
    assert error == %SyntaxError{message: "Unexpected token 'i-e' while parsing"}
  end

  test "parse! corrupted integer" do
    result = catch_error("i1-e" |> IO.iodata_to_binary() |> Parser.parse!())
    assert result == %SyntaxError{message: "Unexpected token '-e' while parsing"}
  end

  test "parse! float" do
    result = catch_error("i1.2e" |> IO.iodata_to_binary() |> Parser.parse!())
    assert result == %SyntaxError{message: "Unexpected token '.2e' while parsing"}
  end

  test "parse! integer without closing token" do
    result = catch_error("i12" |> IO.iodata_to_binary() |> Parser.parse!())
    assert result == %SyntaxError{message: "Unexpected end of the input"}
  end

  ## String tests parse with tuple

  test "parse string" do
    assert "8:software" |> IO.iodata_to_binary() |> Parser.parse() == {:ok, "software"}
  end

  test "parse empty string" do
    assert "0:" |> IO.iodata_to_binary() |> Parser.parse() == {:ok, ""}
  end

  test "parse string with invalid length" do
    result = "8:test" |> IO.iodata_to_binary() |> Parser.parse()
    assert result == {:error, %SyntaxError{message: "Unexpected end of the input"}}
  end

  test "parse string with short length" do
    result = "2:test" |> IO.iodata_to_binary() |> Parser.parse()
    assert result == {:error, %SyntaxError{message: "Unexpected token 'st' while parsing"}}
  end

  test "parse string with corrupted length" do
    result = "x:test" |> IO.iodata_to_binary() |> Parser.parse()
    assert result == {:error, %SyntaxError{message: "Unexpected token 'x:test' while parsing"}}
  end

  test "parse invalid string" do
    result = ":test" |> IO.iodata_to_binary() |> Parser.parse()
    assert result == {:error, %SyntaxError{message: "Unexpected token ':test' while parsing"}}
  end

  ## String tests parse with exception

  test "parse! string" do
    assert "8:software" |> IO.iodata_to_binary() |> Parser.parse!() == "software"
  end

  test "parse! empty string" do
    assert "0:" |> IO.iodata_to_binary() |> Parser.parse!() == ""
  end

  test "parse! string with invalid length" do
    error = catch_error("8:test" |> IO.iodata_to_binary() |> Parser.parse!())
    assert error == %SyntaxError{message: "Unexpected end of the input"}
  end

  test "parse! string with short length" do
    error = catch_error("2:test" |> IO.iodata_to_binary() |> Parser.parse!())
    assert error == %SyntaxError{message: "Unexpected token 'st' while parsing"}
  end

  test "parse! string with corrupted length" do
    error = catch_error("x:test" |> IO.iodata_to_binary() |> Parser.parse!())
    assert error == %SyntaxError{message: "Unexpected token 'x:test' while parsing"}
  end

  test "parse! invalid string" do
    error = catch_error(":test" |> IO.iodata_to_binary() |> Parser.parse!())
    assert error == %SyntaxError{message: "Unexpected token ':test' while parsing"}
  end

  ## List tests parse with tuple

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

  ## List tests parse with exception

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

  ## Map test parse with tuple

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

  ## Map test parse with exception

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
