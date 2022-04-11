defmodule ImapFilter.Imap.MailboxMonitorTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log

  alias ImapFilter.Imap.MailboxMonitor
  alias ImapFilter.Imap.Session

  setup %{case: case, test: test} do
    mailbox =  "MailboxMonitorTest"
    conn = %{
      host: "127.0.0.1",
      # port: 10993,
      port: 10143,
      user: "user1",
      pass: "password",
      # type: :ssl,
      type: :tcp,
      verify: false,
      mailbox: mailbox
    }

    monitor_params = %{
      conn: conn,
      name: {:global, {:test_changes_monitor, case, test}},
      notify: self()
    }

    session_params = %{conn: conn, name: {:global, {:test_session, case, test}}}

    %{
      monitor_pid: start_supervised!({MailboxMonitor, monitor_params}),
      session_pid: start_supervised!({Session, session_params}),
      mailbox: mailbox
    }
  end

  test "monitor changes", %{session_pid: session_pid, mailbox: mailbox} do
    assert_receive :idle_started, 1_000

    Session.append(session_pid, "Subject: .\r\n.\r\n", mailbox)
    assert_receive {:mailbox_activity, lines} when is_list(lines), 15_000
  end
end
