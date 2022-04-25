defmodule ImapFilter.Imap.Response.ParserTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias ImapFilter.Imap.Response
  alias ImapFilter.Imap.Request

  test "parse APPEND response" do
    resp = %Response{
      status: :ok,
      status_line: "[APPENDUID 1649942063 5] Append completed (0.181 + 0.003 + 0.178 secs)",
      req: %Request{tag: "T2", command: :append}
    }

    assert "5" == Response.Parser.parse(resp)
  end

  test "parse SEARCH response" do
    resp = %Response{
      :status => :ok,
      :req => %Request{tag: "FOO", command: :uid_search},
      :responses => [
        {:untagged, "* SEARCH 4 1 2 3"}
      ]
    }

    uids = Response.Parser.parse(resp)
    assert ["4", "1", "2", "3"] == uids
  end

  test "parse FETCH headers" do
    resp = %Response{
      :status => :ok,
      :req => %Request{tag: "FOO", command: :uid_fetch, params: [42, :fetch_rfc822_headers]},
      :responses => [
        {:untagged, "* 42 FETCH (UID 12345 RFC822.HEADER {45})",
         {:literal, 45, "Return-Path: <some-address@example.invalid>\r\n"}}
      ]
    }

    text = Response.Parser.parse(resp)
    assert text == [{"Return-Path", "<some-address@example.invalid>"}]
  end

  test "parse FETCH attributes response" do
    resp = %Response{
      :status => :ok,
      :req => %Request{tag: "FOO", command: :uid_fetch, params: [42, :fetch_attributes]},
      :responses => [
        {:untagged, "* 42 FETCH (UID 42 FLAGS (\\Deleted \\Seen) RFC822.HEADER {45})",
         {:literal, 45, "Return-Path: <some-address@example.invalid>\r\n"}}
      ]
    }

    {flags, headers} = Response.Parser.parse(resp)
    assert flags == [:deleted, :seen]
    assert headers == [{"Return-Path", "<some-address@example.invalid>"}]
  end

  test "parse CAPABILITY response" do
    resp = %Response{
      status: :ok,
      req: %Request{command: :capability},
      responses: [
        {:untagged, "* CAPABILITY IMAP4rev1     ID IDLE SORT=DISPLAY LITERAL+"}
      ]
    }

    caps = Response.Parser.parse(resp)
    assert ["IMAP4rev1", "ID", "IDLE", "SORT=DISPLAY", "LITERAL+"] = caps
  end
end
