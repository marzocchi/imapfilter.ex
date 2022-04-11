defmodule ImapFilter.Imap.ResponseTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias ImapFilter.Imap.Response
  alias ImapFilter.Imap.Request

  test "parse_appended_message_uid" do
    resp = %Response{
      status: :ok,
      status_line:
        "T2 OK [APPENDUID 1648852787 219] Append completed (0.181 + 0.003 + 0.178 secs)",
      req: %Request{tag: "T2"}
    }

    assert "219" == Response.parse_appended_message_uid(resp)
  end

  test "parse_search_results" do
    resp = %Response{
      :status => :ok,
      :req => %Request{tag: "FOO"},
      :responses => [
        {:untagged, "* SEARCH 4 1 2 3"}
      ]
    }

    msgids = Response.parse_search_results(resp, "INBOX", "QUUX")

    assert 4 == Enum.count(msgids)
    assert Enum.member?(msgids, {"QUUX", "INBOX", "4"})
    assert Enum.member?(msgids, {"QUUX", "INBOX", "2"})
    assert Enum.member?(msgids, {"QUUX", "INBOX", "3"})
    assert Enum.member?(msgids, {"QUUX", "INBOX", "1"})
  end

  test "parse_fetch_headers" do
    resp = %Response{
      :status => :ok,
      :req => %Request{tag: "FOO"},
      :responses => [
        {:untagged, "* 42 FETCH (UID 12345 RFC822.HEADER {45})",
         {:literal, 45, "Return-Path: <some-address@example.invalid>\r\n"}}
      ]
    }

    text = Response.parse_fetch_headers(resp)
    assert text == [{"Return-Path", "<some-address@example.invalid>"}]
  end

  test "parse_capability" do
    resp = %Response{
      status: :ok,
      responses: [
        {:untagged, "* CAPABILITY IMAP4rev1     ID IDLE SORT=DISPLAY LITERAL+"}
      ]
    }

    caps = Response.parse_capability(resp)
    assert ["IMAP4rev1", "ID", "IDLE", "SORT=DISPLAY", "LITERAL+"] = caps
  end
end
