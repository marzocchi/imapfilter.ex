defmodule ImapFilter.Stages.FilterMessagesConsumerTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias ImapFilter.Stages.FilterMessagesConsumer
  alias ImapFilter.Imap.Session
  alias ImapFilter.Imap.Response

  setup %{case: case, test: test} do
    session_name = {:global, {:test_session, case, test}}

    session_params = %{
      conn: %{
        host: "127.0.0.1",
        port: 10143,
        user: "user1",
        pass: "password",
        type: :tcp,
        verify: false
      },
      name: session_name
    }

    session_pid = start_supervised!({Session, session_params})

    rules = [
      %{
        label: "Test rule",
        impl: "header_regex",
        args: ["To", ".*"],
        actions: [
          %{impl: "move_to_folder", args: ["ConsumerTestDest"]}
        ]
      }
    ]

    %{
      session_pid: session_pid,
      rules: rules
    }
  end

  test "applies rules with found msg", %{session_pid: session_pid, rules: rules} do
    assert %Response{status: :ok} =
             append_resp =
             Session.append(session_pid, "To: hello@example.invalid\r\n", "ConsumerTestSource")

    uid = Response.Parser.parse(append_resp)

    messages = [{"", "ConsumerTestSource", uid}]

    assert [{"Test rule", "move_to_folder", :ok}] =
             FilterMessagesConsumer.apply_rules(session_pid, rules, messages)
  end

  test "applies rules with missing msg", %{session_pid: session_pid, rules: rules} do
    messages = [{"", "ConsumerTestSource", "42"}]
    assert [] = FilterMessagesConsumer.apply_rules(session_pid, rules, messages)
  end
end
