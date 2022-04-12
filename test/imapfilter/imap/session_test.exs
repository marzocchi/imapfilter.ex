defmodule ImapFilter.Imap.SessionTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias ImapFilter.Imap.Session
  alias ImapFilter.Imap.Response

  setup %{case: case, test: test} do
    params = %{
      conn: %{
        host: "127.0.0.1",
        port: 10143,
        user: "user1",
        pass: "password",
        type: :tcp,
        verify: false
      },
      name: {:global, {:test_session, case, test}}
    }

    %{params: params}
  end

  test "append", %{params: params} do
    pid = start_supervised!({Session, params})

    mailbox = UUID.uuid4()

    %Response{status: :ok} = Session.create(pid, mailbox)

    assert %Response{status: :ok} = Session.append(pid, "Subject: hello\r\nhello\r\n", mailbox)
  end

  test "close and autoreconnect", %{params: params} do
    pid = start_supervised!({Session, params})

    assert %Response{status: :ok} = Session.select(pid, "INBOX")
    assert :ok = Session.close(pid)
    assert %Response{status: :ok} = Session.select(pid, "INBOX")
  end

  test "logout with implied disconnect and autoreconnect", %{params: params} do
    pid = start_supervised!({Session, params})

    assert %Response{status: :ok} = Session.select(pid, "INBOX")
    assert %Response{status: :ok} = Session.logout(pid)
    assert %Response{status: :ok} = Session.select(pid, "INBOX")
  end

  test "login", %{params: params} do
    pid = start_supervised!({Session, params})
    assert %Response{status: :bad} = Session.login(pid, "foo", "bar")
  end

  test "search", %{params: params} do
    pid = start_supervised!({Session, params})

    assert %Response{status: :ok, responses: [{:untagged, "* SEARCH 2\r\n"}]} =
             Session.search(pid, "INBOX", [:header, "Subject", "RE: Very important message"])
  end

  test "select", %{params: params} do
    pid = start_supervised!({Session, params})

    assert %Response{status: :ok} = Session.select(pid, "INBOX")
    assert %Response{status: :no} = Session.select(pid, UUID.uuid4())
  end

  test "fetch_headers", %{params: params} do
    pid = start_supervised!({Session, params})

    expected_cmd = "* 1 FETCH (UID 1 RFC822.HEADER {498}\r\n)\r\n"

    expected_body =
      [
        "Return-Path: <hello@example.invalid>",
        "Delivered-To: hello@example.invalid",
        "Received: some server",
        "\tfor <hello@example.invalid>; Fri, 01 Apr 2022 11:20:43 +0200",
        "From: Federico Marzocchi <hello@example.invalid>",
        "Content-Type: text/plain;",
        "\tcharset=us-ascii",
        "Content-Transfer-Encoding: 7bit",
        "MIME-Version: 1.0",
        "Subject: Very important message",
        "Message-Id: <48D44CE7-72BE-434A-892D-9421F7E504CE@example.invalid>",
        "Date: Fri, 1 Apr 2022 11:20:41 +0200",
        "To: Federico Marzocchi <hello@example.invalid>",
        "",
        ""
      ]
      |> Enum.join("\r\n")

    assert %Response{status: :ok, responses: responses} =
             Session.fetch_headers(pid, {"", "INBOX", "1"})

    assert [{:untagged, ^expected_cmd, {:literal, 498, ^expected_body}}] = responses
  end

  test "fetch_subject", %{params: params} do
    pid = start_supervised!({Session, params})

    assert %Response{status: :ok, responses: responses} =
             Session.fetch_subject(pid, {"", "INBOX", "1"})

    assert [{:untagged, _, {:literal, 35, "Subject: Very important message\r\n\r\n"}}] = responses
  end

  test "fetch", %{params: params} do
    pid = start_supervised!({Session, params})

    expected_body =
      [
        "Return-Path: <hello@example.invalid>",
        "Delivered-To: hello@example.invalid",
        "Received: some server",
        "\tfor <hello@example.invalid>; Fri, 01 Apr 2022 11:20:43 +0200",
        "From: Federico Marzocchi <hello@example.invalid>",
        "Content-Type: text/plain;",
        "\tcharset=us-ascii",
        "Content-Transfer-Encoding: 7bit",
        "MIME-Version: 1.0",
        "Subject: Very important message",
        "Message-Id: <48D44CE7-72BE-434A-892D-9421F7E504CE@example.invalid>",
        "Date: Fri, 1 Apr 2022 11:20:41 +0200",
        "To: Federico Marzocchi <hello@example.invalid>",
        "",
        "Hello!",
        ""
      ]
      |> Enum.join("\r\n")

    assert %Response{status: :ok, responses: responses} = Session.fetch(pid, {"", "INBOX", "1"})
    assert [{:untagged, _command, {:literal, 506, ^expected_body}}] = responses
  end

  test "copy", %{params: params} do
    pid = start_supervised!({Session, params})

    to_mailbox = UUID.uuid4()

    %Response{status: :ok} = Session.create(pid, to_mailbox)
    assert %Response{status: :ok} = Session.copy(pid, {"", "INBOX", "1"}, to_mailbox)
  end

  test "set flags", %{params: params} do
    pid = start_supervised!({Session, params})

    assert %Response{status: :ok} = Session.flag(pid, {"", "INBOX", "1"}, [:deleted])
  end

  test "move", %{params: params} do
    pid = start_supervised!({Session, params})

    from_mailbox = UUID.uuid4()
    to_mailbox = UUID.uuid4()

    %Response{status: :ok} = Session.create(pid, from_mailbox)
    %Response{status: :ok} = Session.create(pid, to_mailbox)
    %Response{status: :ok} = Session.append(pid, "Subject: .\r\n.\r\n", from_mailbox)

    assert %Response{status: :ok} = Session.move(pid, {"", from_mailbox, "1"}, to_mailbox)
  end

  test "create", %{params: params} do
    pid = start_supervised!({Session, params})

    path = UUID.uuid4()

    %Response{status: :ok} = Session.create(pid, "#{path}/a/b/c")
    %Response{status: :no} = Session.create(pid, "#{path}/a/b/c")
  end

  test "fetch_attributes", %{params: params} do
    pid = start_supervised!({Session, params})

    assert %Response{status: :ok, responses: responses} = Session.fetch_attributes(pid, {"", "INBOX", "1"})
    assert [{:untagged, "* 1 FETCH (UID 1 FLAGS (\\Deleted \\Seen) RFC822.HEADER {498}\r\n)\r\n", {:literal, 498, literal_text}}] = responses
    size = byte_size(literal_text)
    assert ^size = 498
  end
end
