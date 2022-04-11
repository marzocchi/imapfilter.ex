defmodule ImapFilter.Stages.NewMessagesProducerTest do
  defmodule TestConsumer do
    use GenStage

    @initial_state %{forward_to: nil, name: nil, producers: nil}

    def start_link(%{name: name} = state) do
      GenStage.start_link(__MODULE__, Map.merge(@initial_state, state), name: name)
    end

    def init(%{producers: producers} = state) do
      {:consumer, state, subscribe_to: producers}
    end

    def handle_events(events, _from, %{forward_to: forward_to} = state) do
      send(forward_to, {:received, events})
      {:noreply, [], state}
    end
  end

  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias ImapFilter.Imap.MessageQueue
  alias ImapFilter.Stages.NewMessagesProducer
  alias ImapFilter.Imap.Session

  setup %{case: case, test: test} do
    mailbox = "ProducerTest"

    queue_name = {:global, {:test_message_queue, case, test}}
    session_name = {:global, {:test_session, case, test}}
    producer_name = {:global, {:test_producer, case, test}}
    consumer_name = {:global, {:test_consumer, case, test}}

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
        {NewMessagesProducer,
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
      producer_name: producer_name,
      consumer_name: consumer_name,
      mailbox: mailbox
    }
  end

  test "enqueues new messages on notify", %{producer_pid: producer_pid, queue_pid: queue_pid} do
    MessageQueue.notify(self(), queue_pid)
    send(producer_pid, {:mailbox_activity, "hello"})

    assert_receive {:enqueued, 2}, 1_000
  end

  test "satisfies consumer's demand", %{
    producer_name: producer_name,
    consumer_name: consumer_name,
    mailbox: mailbox
  } do
    start_supervised!(
      {TestConsumer,
       %{
         name: consumer_name,
         forward_to: self(),
         producers: [
           {producer_name, min_demand: 1, max_demand: 5}
         ]
       }}
    )

    assert_receive {:received, list}, 1_000
    assert {"uid_validity", mailbox, "1"} in list
    assert {"uid_validity", mailbox, "2"} in list
  end
end
