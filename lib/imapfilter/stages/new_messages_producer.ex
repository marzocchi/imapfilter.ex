defmodule ImapFilter.Stages.NewMessagesProducer do
  use GenStage

  import Logger

  alias ImapFilter.Imap.Session
  alias ImapFilter.Imap.MessageQueue
  alias ImapFilter.Imap.Response

  @initial_state %{
    name: nil,
    queue_name: nil,
    pending_demand: 0,
    session_name: nil,
    socket: nil,
    mailbox: nil
  }

  def start_link(%{name: name} = init_arg) do
    GenStage.start_link(
      __MODULE__,
      Map.merge(@initial_state, init_arg),
      name: name
    )
  end

  def init(state) do
    {:producer, state}
  end

  def handle_info(
        {:mailbox_activity, activity},
        %{
          queue_name: queue_name,
          session_name: session_name,
          mailbox: mailbox,
          pending_demand: pending_demand
        } = state
      ) do
    info("mailbox activity: #{activity}")

    enqueue_new_messages(session_name, mailbox, queue_name)

    messages = get_demanded_messages(pending_demand, [], queue_name)
    pending_demand = pending_demand - length(messages)

    info(
      "queue size=#{MessageQueue.size(queue_name)}, sending #{length(messages)} pending messages, pending_demand=#{pending_demand}"
    )

    {:noreply, messages, %{state | pending_demand: pending_demand}}
  end

  def handle_demand(
        demand,
        %{queue_name: queue_name, session_name: session_name, mailbox: mailbox} = state
      ) do
    enqueue_new_messages(session_name, mailbox, queue_name)

    messages = get_demanded_messages(demand, [], queue_name)
    pending_demand = demand - length(messages)

    info(
      "demand=#{demand}, satisfied=#{length(messages)}, pending_demand=#{pending_demand}, queued=#{MessageQueue.size(queue_name)}"
    )

    {:noreply, messages, %{state | pending_demand: pending_demand}}
  end

  defp enqueue_new_messages(session_name, mailbox, queue_name) do
    %Response{status: :ok} = resp = Session.search(session_name, mailbox, [:all])

    found_messages = Response.parse_search_results(resp, mailbox, "uid_validity")
    found_messages |> MessageQueue.enqueue_list(queue_name)
  end

  defp get_demanded_messages(0, messages, _queue), do: messages

  defp get_demanded_messages(count, messages, queue) do
    case MessageQueue.dequeue(queue) do
      {:value, msg} -> get_demanded_messages(count - 1, [msg | messages], queue)
      :empty -> messages
    end
  end
end
