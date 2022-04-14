defmodule ImapFilter.EndToEndTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias ImapFilter.Application
  alias ImapFilter.Imap.Client
  alias ImapFilter.Imap.Request
  alias ImapFilter.Imap.Response
  alias ImapFilter.Imap.MailboxMonitor

  setup %{case: case, test: test} do
    conn = %{
      host: "127.0.0.1",
      # port: 10993,
      port: 10143,
      user: "user1",
      pass: "password",
      # type: :ssl,
      type: :tcp,
      verify: false,
      mailbox: "EndToEndDest"
    }

    monitor_params = %{
      conn: conn,
      name: {:global, {:e2e_test_changes_monitor, case, test}},
      notify: self()
    }

    %{
      monitor_pid: start_supervised!({MailboxMonitor, monitor_params})
    }
  end

  @tag :e2e
  test "e2e" do
    System.put_env("IMAPFILTER_CONFIG_FILE", "./test/config.test.yaml")

    assert {:ok, pid} = Application.start(nil, nil)
    assert is_pid(pid)

    msgid = UUID.uuid4()
    msg = "To: hello@example.invalid\r\nMessage-Id: #{msgid}\r\nSubject: hello\r\n"

    {:ok, socket} = Client.connect(:tcp, "localhost", 10143)

    assert %Response{status: :ok} =
             Client.get_response(socket, Request.login("user1", "password") |> Request.tagged(1))

    assert %Response{status: :ok} =
             Client.get_response(socket, Request.select("EndToEndSource") |> Request.tagged(2))

    assert_receive :idle_started, 1_000

    assert %Response{status: :ok} =
             Client.get_response(
               socket,
               Request.append(msg, "EndToEndSource") |> Request.tagged(3)
             )

    assert_receive {:mailbox_activity, _lines}, 15_000

    assert %Response{status: :ok} =
             Client.get_response(socket, Request.select("EndToEndDest") |> Request.tagged(3))

    assert %Response{status: :ok} =
             Client.get_response(
               socket,
               Request.search([:header, "Message-Id", msgid]) |> Request.tagged(3)
             )
  end
end
