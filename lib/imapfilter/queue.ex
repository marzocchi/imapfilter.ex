defmodule ImapFilter.Queue do
  def new(), do: {0, :queue.new()}

  def enqueue(v, {_, q}), do: wrap(:queue.in(v, q))

  def enqueue_list([], q), do: q

  def enqueue_list([head | tail], q), do: enqueue_list(tail, enqueue(head, q))

  def dequeue({_, q}) do
    {v, q} = :queue.out(q)
    {v, wrap(q)}
  end

  def size({_, q}), do: :queue.len(q)

  defp wrap(q), do: {:queue.len(q), q}
end
