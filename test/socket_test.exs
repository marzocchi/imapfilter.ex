defmodule ImapFilter.SocketTest do
  use ExUnit.Case, async: true

  @moduletag :capturelog

  alias ImapFilter.Socket

  test "connect" do
    assert {:ok, socket} = Socket.connect(:tcp, "localhost", 10143)
    assert {:ok, text} = Socket.recv(socket)
    assert 0 < String.length(text)
  end

  test "send and recv" do
    {:ok, socket} = Socket.connect(:tcp, "localhost", 10143)
    {:ok, _} = Socket.recv(socket)

    assert :ok = Socket.send(socket, "T1 GARBAGE\r\n")

    {:ok, text} = Socket.recv(socket)
    assert String.starts_with?(text, "T1 BAD ")
  end

  test "send and recv_lines" do
    {:ok, socket} = Socket.connect(:tcp, "localhost", 10143)
    {:ok, _} = Socket.recv(socket)

    assert :ok = Socket.send(socket, "T1 GARBAGE\r\n")

    text = Socket.recv_lines(socket)
    assert String.starts_with?(text, "T1 BAD ")
  end
end
