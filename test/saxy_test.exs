defmodule SaxyTest do
  use ExUnit.Case

  import SaxyTest.Utils

  alias Saxy.ParseError

  alias Saxy.TestHandlers.{
    FastReturnHandler,
    HaltHandler,
    WrongHandler,
    StackHandler
  }

  doctest Saxy

  test "parse_string/3 parses a XML document binary" do
    data = File.read!("./test/support/fixture/food.xml")
    assert {:ok, state} = data |> remove_indents() |> Saxy.parse_string(StackHandler, [])
    assert length(state) == 74

    data = File.read!("./test/support/fixture/complex.xml")
    assert {:ok, state} = data |> remove_indents() |> Saxy.parse_string(StackHandler, [])
    assert length(state) == 79

    data = File.read!("./test/support/fixture/illustrator.svg")
    assert {:ok, state} = data |> remove_indents() |> Saxy.parse_string(StackHandler, [])
    assert length(state) == 12
  end

  test "parse_string/4 parses XML binary with multiple \":expand_entity\" strategy" do
    data = """
    <?xml version="1.0" ?>
    <foo>Something &unknown;</foo>
    """

    assert {:ok, state} = Saxy.parse_string(data, StackHandler, [], expand_entity: :keep)

    assert state == [
             {:end_document, {}},
             {:end_element, "foo"},
             {:characters, "Something &unknown;"},
             {:start_element, {"foo", []}},
             {:start_document, [version: "1.0"]}
           ]

    assert {:ok, state} = Saxy.parse_string(data, StackHandler, [], expand_entity: :skip)

    assert state == [
             {:end_document, {}},
             {:end_element, "foo"},
             {:characters, "Something "},
             {:start_element, {"foo", []}},
             {:start_document, [version: "1.0"]}
           ]

    assert {:ok, state} = Saxy.parse_string(data, StackHandler, [], expand_entity: {__MODULE__, :convert_entity, []})

    assert state == [
             {:end_document, {}},
             {:end_element, "foo"},
             {:characters, "Something known"},
             {:start_element, {"foo", []}},
             {:start_document, [version: "1.0"]}
           ]
  end

  test "parse_stream/3 parses file stream" do
    stream = File.stream!("./test/support/fixture/food.xml", [], 1024)
    assert {:ok, _state} = Saxy.parse_stream(stream, StackHandler, [])

    stream = File.stream!("./test/support/fixture/food.xml", [], 200)
    assert {:ok, state} = Saxy.parse_stream(stream, StackHandler, [])
    assert length(state) == 105

    stream = File.stream!("./test/support/fixture/complex.xml", [], 200)
    assert {:ok, state} = Saxy.parse_stream(stream, StackHandler, [])
    assert length(state) == 120

    stream = File.stream!("./test/support/fixture/illustrator.svg", [], 5)
    assert {:ok, state} = Saxy.parse_stream(stream, StackHandler, [])
    assert length(state) == 18
  end

  test "parse_stream/3 parses normal stream" do
    stream =
      """
      <?xml version='1.0' encoding="UTF-8" ?>
      <!DOCTYPE note [
        <!ELEMENT note (to,from,heading,body)>
        <!ELEMENT to (#PCDATA)>
        <!ELEMENT from (#PCDATA)>
        <!ELEMENT heading (#PCDATA)>
        <!ELEMENT body (#PCDATA)>
      ]>
      <item name="[日本語] Tom &amp; Jerry" category='movie'>
        <author name='William Hanna &#x26; Joseph Barbera' />
        <!--Ignore me please I am just a comment-->
        <?foo Hmm? Then probably ignore me too?>
        <description><![CDATA[<strong>"Tom & Jerry" is a cool movie!</strong>]]></description>
        <actors>
          <actor>Tom</actor>
          <actor>Jerry</actor>
        </actors>
      </item>
      <!--a very bottom comment-->
      <?foo what a instruction ?>
      """
      |> remove_indents()
      |> String.codepoints()
      |> Stream.map(& &1)

    assert {:ok, state} = Saxy.parse_stream(stream, StackHandler, [])
    events = Enum.reverse(state)

    assert [{:start_document, [encoding: "UTF-8", version: "1.0"]} | events] = events

    item_attributes = [{"name", "[日本語] Tom & Jerry"}, {"category", "movie"}]
    assert [{:start_element, {"item", ^item_attributes}} | events] = events

    author_attributes = [{"name", "William Hanna & Joseph Barbera"}]
    assert [{:start_element, {"author", ^author_attributes}} | events] = events
    assert [{:end_element, "author"} | events] = events

    assert [{:start_element, {"description", []}} | events] = events
    assert [{:characters, "<strong>\"Tom & Jerry\" is a cool movie!</strong>"} | events] = events
    assert [{:end_element, "description"} | events] = events

    assert [{:start_element, {"actors", []}} | events] = events
    assert [{:start_element, {"actor", []}} | events] = events
    assert [{:characters, "Tom"} | events] = events
    assert [{:end_element, "actor"} | events] = events
    assert [{:start_element, {"actor", []}} | events] = events
    assert [{:characters, "Jerry"} | events] = events
    assert [{:end_element, "actor"} | events] = events
    assert [{:end_element, "actors"} | events] = events

    assert [{:end_element, "item"} | events] = events
    assert [{:end_document, {}} | events] = events

    assert events == []
  end

  test "parse_stream/3 handles trailing unicode codepoints when buffering" do
    stream = File.stream!("./test/support/fixture/unicode.xml", [], 1)
    assert {:ok, state} = Saxy.parse_stream(stream, StackHandler, [])

    assert state == [
             {:end_document, {}},
             {:end_element, "songs"},
             {:characters, "\n"},
             {:end_element, "song"},
             {:characters, "Eva Braun 𠜎 𠜱 𠝹𠱓"},
             {:start_element, {"song", [{"singer", "Die Ärtze"}]}},
             {:characters, "\n  "},
             {:end_element, "song"},
             {:characters, "Über den Wolken"},
             {:start_element, {"song", [{"singer", "Reinhard Mey"}]}},
             {:characters, "\n  "},
             {:start_element, {"songs", []}},
             {:start_document, [version: "1.0"]}
           ]
  end

  test "parse_stream/3 supports parsing with enum" do
    codepoints =
      String.codepoints("""
      <?xml version='1.0' encoding="UTF-8" ?>
      <item></item>
      """)

    assert {:ok, state} = Saxy.parse_stream(codepoints, StackHandler, [])

    assert Enum.reverse(state) == [
             {:start_document, [encoding: "UTF-8", version: "1.0"]},
             {:start_element, {"item", []}},
             {:end_element, "item"},
             {:end_document, {}}
           ]
  end

  test "parse_stream/3 emits \"characters\" event" do
    character_data_max_length = 32
    first_chunk = String.duplicate("x", character_data_max_length)
    second_chunk = String.duplicate("y", character_data_max_length)

    doc =
      String.codepoints("""
      <?xml version="1.0" encoding="UTF-8"?>
      <foo>#{first_chunk}#{second_chunk}</foo>
      """)

    assert {:ok, state} = Saxy.parse_stream(doc, StackHandler, [], character_data_max_length: character_data_max_length)

    assert state == [
             end_document: {},
             end_element: "foo",
             characters: "",
             characters: second_chunk,
             characters: first_chunk,
             start_element: {"foo", []},
             start_document: [encoding: "UTF-8", version: "1.0"]
           ]

    assert {:ok, state} = Saxy.parse_stream(doc, StackHandler, [])

    assert state == [
             end_document: {},
             end_element: "foo",
             characters: first_chunk <> second_chunk,
             start_element: {"foo", []},
             start_document: [encoding: "UTF-8", version: "1.0"]
           ]
  end

  test "parse_stream/3 supports fast return" do
    codepoints =
      String.codepoints("""
      <?xml version='1.0' encoding="UTF-8" ?>
      <item></item>
      """)

    assert Saxy.parse_stream(codepoints, FastReturnHandler, []) == {:ok, :fast_return}
  end

  test "parse_stream/3 handles error when parsing" do
    stream =
      """
      <?xml version='1.0' encoding="UTF-8" ?>
      <item></hello>
      """
      |> String.codepoints()
      |> Stream.map(& &1)

    assert {:error, exception} = Saxy.parse_stream(stream, StackHandler, [])
    assert ParseError.message(exception) == "unexpected ending tag \"hello\", expected tag: \"item\""
  end

  test "returns parsing errors" do
    data = "<?xml ?><foo/>"

    assert {:error, exception} = Saxy.parse_string(data, StackHandler, [])
    assert ParseError.message(exception) == "unexpected byte \"?\", expected token: :version"

    data = "<?xml"

    assert {:error, exception} = Saxy.parse_string(data, StackHandler, [])

    assert ParseError.message(exception) == "unexpected end of input, expected token: :version"

    data = "<foo><bar></bee></foo>"

    assert {:error, exception} = Saxy.parse_string(data, StackHandler, [])

    assert ParseError.message(exception) == "unexpected ending tag \"bee\", expected tag: \"bar\""
  end

  test "supports controling parsing flow" do
    data = "<?xml version=\"1.0\" ?><foo/>"

    assert Saxy.parse_string(data, FastReturnHandler, []) == {:ok, :fast_return}
  end

  test "handles invalid return in handler" do
    data = "<?xml version=\"1.0\" ?><foo/>"

    assert {:error, error} = Saxy.parse_string(data, WrongHandler, [])
    assert ParseError.message(error) == "unexpected return :something_wrong in :start_document event handler"
  end

  describe "parser halting" do
    test "halts the parsing process and returns the rest of the binary" do
      data = "<?xml version=\"1.0\" ?><foo/>"
      assert parse_halt(data, :start_document) == "<foo/>"

      data = "<?xml version=\"1.0\" ?><foo/>"
      assert parse_halt(data, :start_element) == ""
      assert parse_halt(data, :end_element) == ""
      assert parse_halt(data, :end_document) == ""

      data = "<?xml version=\"1.0\" ?><foo>foo</foo>"
      assert parse_halt(data, :start_element) == "foo</foo>"
      assert parse_halt(data, :characters) == "</foo>"
      assert parse_halt(data, :end_element) == ""

      data = "<?xml version=\"1.0\" ?><foo>foo <bar/></foo>"
      assert parse_halt(data, [:start_element, {"foo", []}]) == "foo <bar/></foo>"
      assert parse_halt(data, [:characters, "foo "]) == "<bar/></foo>"
      assert parse_halt(data, [:start_element, {"bar", []}]) == "</foo>"
      assert parse_halt(data, [:end_element, "bar"]) == "</foo>"
      assert parse_halt(data, [:end_element, "foo"]) == ""
      assert parse_halt(data <> "trailing", [:end_element, "foo"]) == "trailing"

      data = "<?xml version=\"1.0\" ?><foo><![CDATA[foo]]></foo>"
      assert parse_halt(data, [:characters, "foo"]) == "</foo>"
    end
  end

  defp parse_halt(data, halt_event) do
    assert {:halt, :halt_return, rest} = Saxy.parse_string(data, HaltHandler, halt_event)
    assert Saxy.parse_stream([data], HaltHandler, halt_event) == {:halt, :halt_return, rest}

    rest
  end

  describe "encode!/2" do
    import Saxy.XML

    test "encodes XML document into string" do
      root = element("foo", [], "foo")
      assert Saxy.encode!(root, version: "1.0") == ~s(<?xml version="1.0"?><foo>foo</foo>)
    end
  end

  describe "encode_to_iodata!/2" do
    import Saxy.XML

    test "encodes XML document into IO data" do
      root = element("foo", [], "foo")
      assert xml = Saxy.encode_to_iodata!(root, version: "1.0")
      assert is_list(xml)
      assert IO.iodata_to_binary(xml) == ~s(<?xml version="1.0"?><foo>foo</foo>)
    end
  end

  def convert_entity("unknown"), do: "known"
end
