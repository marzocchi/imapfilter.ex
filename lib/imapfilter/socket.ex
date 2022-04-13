defmodule ImapFilter.Socket do
  import Logger

  @default_timeout 1_000

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

  def recv(socket, timeout \\ @default_timeout)

  def recv({:gen_tcp, port}, timeout),
    do: :gen_tcp.recv(port, 0, timeout) |> log_incoming

  def recv({:sslsocket, _, _} = socket, timeout),
    do: :ssl.recv(socket, 0, timeout) |> log_incoming

  def recv_lines(socket, timeout \\ @default_timeout), do: accumulate_lines(socket, "", timeout)

  defp accumulate_lines(socket, acc, timeout) do
    case recv(socket) do
      {:error, _} = ret ->
        ret

      {:ok, chunk} ->
        acc = acc <> chunk

        if String.ends_with?(chunk, "\r\n") do
          acc
        else
          accumulate_lines(socket, acc, timeout)
        end
    end
  end

  defp log_outgoing(msg) do
    String.split(msg, "\r\n")
    |> Enum.map(fn line -> "-> #{line}" end)
    |> Enum.each(&debug/1)

    msg
  end

  defp log_incoming({:error, _ = err} = arg) do
    debug("<- (socket error: #{err})")
    arg
  end

  defp log_incoming({a, msg}) when is_atom(a) do
    log_incoming(msg)
    {a, msg}
  end

  defp log_incoming(msg) do
    String.split(msg, "\r\n")
    |> Enum.map(fn line -> "<- #{line}" end)
    |> Enum.each(&debug/1)

    msg
  end
end
