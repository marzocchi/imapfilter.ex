defmodule ImapFilter.Socket do
  import Logger

  @default_timeout 3_000

  def connect(type, host, port, verify \\ true)

  def connect(:tcp, host, port, _verify) do
    case :gen_tcp.connect(to_charlist(host), port, [:binary, active: false]) do
      {:ok, port} ->
        socket = {:gen_tcp, port}
        setopts(socket, send_timeout: @default_timeout)
        {:ok, socket}

      anything ->
        anything
    end
  end

  def connect(:ssl, host, port, verify) do
    opts = [
      :binary,
      active: false,
      verify: :verify_none
    ]

    opts =
      if verify,
        do:
          opts
          |> Keyword.put(:verify, :verify_peer)
          |> Keyword.put(:cacertfile, CAStore.file_path()),
        else: opts

    :ssl.start()
    :ssl.connect(to_charlist(host), port, opts)

    case :ssl.connect(to_charlist(host), port, opts) do
      {:ok, socket} = result ->
        setopts(socket, send_timeout: @default_timeout)
        result

      anything ->
        anything
    end
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
      {:error, _} = err ->
        err

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
