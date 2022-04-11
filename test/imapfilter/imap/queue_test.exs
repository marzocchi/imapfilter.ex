

defmodule ImapFilter.Imap.MessageQueueTest do
  use ExUnit.Case, async: true

  alias ImapFilter.Imap.MessageQueue

  setup %{case: case, test: test} do
    {:ok, pid} = start_supervised({MessageQueue, %{name: {:global, {:test_queue, case, test}}}})
    %{queue: pid}
  end

  test "enqueues, dequeues", %{queue: pid} do
    assert 0 == MessageQueue.size(pid)

    assert 1 == MessageQueue.enqueue(1, pid)
    assert 2 == MessageQueue.enqueue(2, pid)

    assert 2 == MessageQueue.size(pid)

    assert {:value, 1} == MessageQueue.dequeue(pid)
    assert {:value, 2} == MessageQueue.dequeue(pid)
    assert :empty == MessageQueue.dequeue(pid)
    assert :empty == MessageQueue.dequeue(pid)
  end

  test "notifies enqueues, dequeues", %{queue: pid} do
    MessageQueue.notify(self(), pid)

    MessageQueue.enqueue(11, pid)
    assert_receive {:enqueued, 1}, 1_000

    MessageQueue.enqueue_list([11, 12, 13], pid)
    assert_receive {:enqueued, 3}, 1_000

    MessageQueue.dequeue(pid)
    assert_receive {:dequeued, 2}, 1_000

    MessageQueue.dequeue(pid)
    assert_receive {:dequeued, 1}, 1_000

    MessageQueue.dequeue(pid)
    assert_receive {:dequeued, 0}, 1_000
  end

  test "enqueues a list", %{queue: pid} do
    assert 3 == MessageQueue.enqueue_list([11, 12, 13], pid)

    assert {:value, 11} == MessageQueue.dequeue(pid)
    assert {:value, 12} == MessageQueue.dequeue(pid)
    assert {:value, 13} == MessageQueue.dequeue(pid)
    assert :empty == MessageQueue.dequeue(pid)
  end

  test "enqueues a value only once", %{queue: pid} do
    assert 1 == MessageQueue.enqueue(1, pid)
    assert 2 == MessageQueue.enqueue(2, pid)
    assert 2 == MessageQueue.enqueue(1, pid)
  end

  test "enqueus list items only once", %{queue: pid} do
    assert 3 == MessageQueue.enqueue_list([1, 2, 1, 3], pid)
    assert 4 == MessageQueue.enqueue_list([3, 4, 2], pid)
  end
end
