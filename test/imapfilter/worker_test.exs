defmodule ImapFilter.WorkerTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias ImapFilter.Imap.MessageQueue
  alias ImapFilter.Worker
  alias ImapFilter.Imap.Session

  setup %{case: case, test: test} do
    mailbox = "ProducerTest"

    queue_name = {:global, {:test_message_queue, case, test}}
    session_name = {:global, {:test_session, case, test}}
    producer_name = {:global, {:test_producer, case, test}}

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

    queue_pid = start_supervised!({MessageQueue, %{name: queue_name}})
    start_supervised!({Session, session_params})

    producer_pid =
      start_supervised!(
        {Worker,
         %{
           name: producer_name,
           queue_name: queue_name,
           session_name: session_name,
           mailbox: mailbox
         }}
      )

    %{
      queue_pid: queue_pid,
      producer_pid: producer_pid,
      mailbox: mailbox
    }
  end

  test "enqueues new messages on notify", %{producer_pid: producer_pid, queue_pid: queue_pid} do
    MessageQueue.notify(self(), queue_pid)
    send(producer_pid, {:mailbox_activity, "hello"})

    assert_receive {:enqueued, 2}, 1_000
  end
end
