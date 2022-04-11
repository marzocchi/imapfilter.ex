defmodule ImapFilter.Imap.RequestTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias ImapFilter.Imap.Request

  test "tagged" do
    assert %Request{command: "FOO", params: ["BAR"], tag: "T1"} =
             Request.tagged(%Request{command: "FOO", params: ["BAR"]}, 1)
  end

  test "raw" do
    assert "FOO\r\n" = Request.raw(%Request{command: "FOO"})
    assert "T42 FOO\r\n" = Request.raw(%Request{command: "FOO"} |> Request.tagged(42))

    assert "FOO \"BAR\" \"BAZ\"\r\n" =
             Request.raw(%Request{command: "FOO", params: ["BAR", "BAZ"]})

    assert "T42 FOO \"BAR\" \"BAZ\"\r\n" =
             Request.raw(%Request{command: "FOO", params: ["BAR", "BAZ"]} |> Request.tagged(42))
  end

  test "raw with literal" do
    assert {"APPEND \"INBOX\"", "hello"} = Request.raw(Request.append("hello", "INBOX"))
  end

  test "raw with flags" do
    assert "UID STORE 1 +FLAGS (\\Deleted \\Draft \\Seen \\Answered \\Flagged \\Recent arbitrary-flag)\r\n" =
             Request.raw(
               Request.flag("1", [
                 :deleted,
                 :draft,
                 :seen,
                 :answered,
                 :flagged,
                 :recent,
                 "arbitrary-flag"
               ])
             )
  end

  test "raw with tagged" do
    assert "T42 UID SEARCH ALL\r\n" = Request.raw(Request.search(:all) |> Request.tagged(42))
  end
end
