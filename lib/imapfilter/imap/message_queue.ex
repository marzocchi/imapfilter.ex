defmodule ImapFilter.Imap.MessageQueue do

  alias ImapFilter.Queue

  use GenServer

  @initial_state %{q: Queue.new(), set: %MapSet{}, name: nil, notify: []}

  def start_link(%{name: name} = init_arg),
    do:
      GenServer.start_link(
        __MODULE__,
        Map.merge(@initial_state, init_arg),
        name: name
      )

  def init(state), do: {:ok, state}

  def notify(notify_pid, pid), do: GenServer.call(pid, {:notify, notify_pid})

  def enqueue(v, pid), do: GenServer.call(pid, {:enqueue, v})

  def enqueue_list(v, pid), do: GenServer.call(pid, {:enqueue_list, v})

  def dequeue(pid), do: GenServer.call(pid, :dequeue)

  def size(pid), do: GenServer.call(pid, :size)

  def handle_call({:enqueue, v}, _from, %{q: q, set: set} = state) do
    case enqueue_if_not_present(v, q, set) do
      :skipped ->
        {:reply, Queue.size(q), state}

      {q, set} ->
        {:reply, Queue.size(q), %{state | q: q, set: set},
         {:continue, {:send_notification, :enqueued}}}
    end
  end

  def handle_call({:enqueue_list, []}, _from, %{q: q} = state), do: {:reply, Queue.size(q), state}

  def handle_call({:enqueue_list, [v]}, _from, %{q: q, set: set} = state) do
    case enqueue_if_not_present(v, q, set) do
      :skipped ->
        {:reply, Queue.size(q), state}

      {q, set} ->
        {:reply, Queue.size(q), %{state | q: q, set: set},
         {:continue, {:send_notification, :enqueued}}}
    end
  end

  def handle_call({:enqueue_list, [head | tail]}, from, %{q: q, set: set} = state) do
    case enqueue_if_not_present(head, q, set) do
      :skipped ->
        handle_call({:enqueue_list, tail}, from, state)

      {q, set} ->
        handle_call({:enqueue_list, tail}, from, %{state | q: q, set: set})
    end
  end

  def handle_call(:dequeue, _from, %{q: q} = state) do
    {v, q} = Queue.dequeue(q)

    case v do
      :empty ->
        {:reply, v, %{state | q: q}}

      {:value, _} = v ->
        {:reply, v, %{state | q: q}, {:continue, {:send_notification, :dequeued}}}
    end
  end

  def handle_call(:size, _from, %{q: q} = state) do
    {:reply, Queue.size(q), state}
  end

  def handle_call({:notify, notify_pid}, _from, %{notify: notify_list} = state) do
    {:reply, :ok, %{state | notify: notify_list ++ [notify_pid]}}
  end

  def handle_continue({:send_notification, _}, %{notify: []} = state), do: {:noreply, state}

  def handle_continue({:send_notification, :dequeued}, %{notify: []} = state),
    do: {:noreply, state}

  def handle_continue({:send_notification, msg}, %{notify: notify, q: q} = state) do
    notify
    |> Enum.each(fn pid ->
      send(pid, {msg, Queue.size(q)})
    end)

    {:noreply, state}
  end

  defp enqueue_if_not_present([], q, set), do: {q, set}

  defp enqueue_if_not_present([head | tail], q, set) do
    {q, set} = enqueue_if_not_present(head, q, set)
    enqueue_if_not_present(tail, q, set)
  end

  defp enqueue_if_not_present(v, q, set) do
    case MapSet.member?(set, v) do
      true ->
        :skipped

      false ->
        q = Queue.enqueue(v, q)
        {q, MapSet.put(set, v)}
    end
  end
end
