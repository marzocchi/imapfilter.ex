defmodule ImapFilter.Worker do
  use GenServer

  require Logger

  alias ImapFilter.Imap.Session
  alias ImapFilter.Imap.MessageQueue
  alias ImapFilter.Imap.Response
  alias ImapFilter.Rules
  alias ImapFilter.Actions

  @initial_state %{
    name: nil,
    queue_name: nil,
    session_name: nil,
    socket: nil,
    mailbox: nil,
    rules: []
  }

  def start_link(%{name: name} = init_arg) do
    GenServer.start_link(
      __MODULE__,
      Map.merge(@initial_state, init_arg),
      name: name
    )
  end

  def init(state) do
    GenServer.cast(self(), :init_queue)
    {:ok, state}
  end

  def handle_cast(:init_queue, %{} = state), do: enqueue_new_messages(state)

  def handle_cast(
        :dequeue,
        %{
          queue_name: queue_name,
          session_name: session_name,
          rules: rules
        } = state
      ) do
    with {:value, msgid} <- MessageQueue.dequeue(queue_name),
         %Rules.Arg{} = arg <- assemble_rule_arg(session_name, msgid),
         actions <- Rules.find_actions(rules, arg),
         outcomes <- Actions.apply_actions(session_name, actions, arg) do
      outcomes |> log_outcomes
      GenServer.cast(self(), :dequeue)
    else
      :empty ->
        Logger.info("queue is empty")

      {:error, {_, _, uid}, err} ->
        Logger.info("message #{uid} could not be processed due to error #{err}")
    end

    {:noreply, state}
  end

  def handle_info({:idle_started, _mailbox}, %{} = state),
    do: {:noreply, state}

  def handle_info({:idle_stopped, _mailbox}, %{} = state),
    do: {:noreply, state}

  def handle_info({:idle_activity, mailbox, _}, %{} = state) do
    Logger.info("activity on mailbox #{mailbox}")
    enqueue_new_messages(state)
  end

  defp log_outcomes(outcomes) do
    outcomes
    |> Enum.each(fn o ->
      case o do
        {{_, _, uid}, impl, :ok} ->
          Logger.info("successfuly applied #{impl} to #{uid}")

        {{_, _, uid}, impl, {:error, %Response{status: s, status_line: l}}} ->
          Logger.error("applying #{impl} to #{uid} failed with server error: #{s} #{l}")

        {{_, _, uid}, impl, {:error, reason}} ->
          Logger.error("applying #{impl} to #{uid} failed with error: #{reason}")
      end
    end)
  end

  defp assemble_rule_arg(session_name, msgid) do
    with %Response{} = resp <- Session.fetch_headers(session_name, msgid),
         headers when is_list(headers) <- Response.Parser.parse(resp),
         do: Rules.Arg.new(msgid, headers)
  end

  defp enqueue_new_messages(
         %{
           session_name: session_name,
           mailbox: mailbox,
           queue_name: queue_name
         } = state
       ) do
    with msgids <- get_new_message_ids(session_name, mailbox) do
      MessageQueue.enqueue_list(msgids, queue_name)
      Logger.info("there are now #{MessageQueue.size(queue_name)} messages in queue")
    end

    GenServer.cast(self(), :dequeue)
    {:noreply, state}
  end

  defp get_new_message_ids(session_name, mailbox) do
    with %Response{} = resp <- Session.search(session_name, mailbox, [:all]) do
      uids = Response.Parser.parse(resp)
      Logger.info("found #{Enum.count(uids)} messages to enqueue")

      uids
      |> Enum.map(fn uid ->
        {"uid_validity", mailbox, uid}
      end)
    end
  end
end
