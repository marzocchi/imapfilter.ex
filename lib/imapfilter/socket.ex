defmodule ImapFilter.Socket do
  import Logger

  def connect(:tcp, host, port) do
    {:ok, port} = :gen_tcp.connect(to_charlist(host), port, [:binary, active: false])
    {:ok, {:gen_tcp, port}}
  end

  def connect(:ssl, host, port), do: connect(:ssl, host, port, true)

  def connect(:tcp, host, port, _verify), do: connect(:tcp, host, port)

  def connect(:ssl, host, port, true = _verify) do
    opts = [
      :binary,
      active: false,
      verify: :verify_peer,
      cacertfile: CAStore.file_path()
    ]

    :ssl.start()
    :ssl.connect(to_charlist(host), port, opts)
  end

  def connect(:ssl, host, port, false = _verify) do
    opts = [
      :binary,
      active: false,
      verify: :verify_none
    ]

    :ssl.start()
    :ssl.connect(to_charlist(host), port, opts)
  end

  def setopts({:sslsocket, _, _} = socket, opts), do: :ssl.setopts(socket, opts)
  def setopts({:gen_tcp, port}, opts), do: :inet.setopts(port, opts)

  def close({:sslsocket, _, _} = socket), do: :ssl.close(socket)
  def close({:gen_tcp, port}), do: :gen_tcp.close(port)

  def send({:sslsocket, _, _} = socket, msg), do: :ssl.send(socket, log_outgoing(msg))
  def send({:gen_tcp, port}, msg), do: :gen_tcp.send(port, log_outgoing(msg))

  def recv(socket), do: recv(socket, 0)

  def recv({:gen_tcp, port}, length), do: :gen_tcp.recv(port, length) |> log_incoming
  def recv({:sslsocket, _, _} = socket, length), do: :ssl.recv(socket, length) |> log_incoming

  def recv_lines(socket), do: recv_lines(socket, "")

  def recv_lines(socket, acc) do
    case recv(socket, 0) do
      {:error, :closed} = ret ->
        ret

      {:ok, chunk} ->
        acc = acc <> chunk

        if String.ends_with?(chunk, "\r\n") do
          acc
        else
          recv_lines(socket, acc)
        end
    end
  end

  defp log_outgoing(msg) do
    String.split(msg, "\r\n")
    |> Enum.map(fn line -> "-> #{line}" end)
    |> Enum.each(&Logger.debug/1)

    msg
  end

  defp log_incoming({:error, _ = err} = arg) do
    Logger.debug("<- (socket error: #{err})")
    arg
  end

  defp log_incoming({a, msg}) when is_atom(a) do
    log_incoming(msg)
    {a, msg}
  end

  defp log_incoming(msg) do
    String.split(msg, "\r\n")
    |> Enum.map(fn line -> "<- #{line}" end)
    |> Enum.each(&Logger.debug/1)

    msg
  end
end
