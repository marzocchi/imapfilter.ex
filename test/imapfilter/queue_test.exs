defmodule ImapFilter.QueueTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log

  alias ImapFilter.Queue

  test "enqueue" do
    assert {0, _} = q = Queue.new()
    assert {1, _} = q = Queue.enqueue(1, q)
    assert {2, _} = Queue.enqueue(2, q)
  end

  test "enqueue_list" do
    assert {0, _} = q = Queue.new()
    assert {3, _} = Queue.enqueue_list([1, 2, 3], q)
  end

  test "dequeue" do
    assert {0, _} = q = Queue.new()
    assert {2, _} = q = Queue.enqueue_list([1, 2], q)

    assert {{:value, 1}, {1, _} = q} = Queue.dequeue(q)
    assert {{:value, 2}, {0, _} = q} = Queue.dequeue(q)
    assert {:empty, {0, _}} = Queue.dequeue(q)
  end

  test "size" do
    assert {0, _} = q = Queue.new()

    assert 0 == Queue.size(q)

    assert {1, _} = q = Queue.enqueue(1, q)

    assert 1 == Queue.size(q)
  end
end
