defmodule ImapFilter.Imap.Client do
  # works around 'imported Kernel.send/2 conflicts with local function' which happens when aliasing
  import Kernel, except: [send: 2]

  alias ImapFilter.Imap.Request
  alias ImapFilter.Imap.Response
  alias ImapFilter.Socket

  def connect(:tcp, host, port) do
    {:ok, socket} = Socket.connect(:tcp, host, port)
    {:ok, _} = Socket.recv(socket)
    {:ok, socket}
  end

  def connect(:tcp, host, port, _verify) do
    connect(:tcp, host, port)
  end

  def connect(:ssl, host, port, true = _verify) do
    {:ok, socket} = Socket.connect(:ssl, host, port, true)
    {:ok, _} = Socket.recv(socket)
    {:ok, socket}
  end

  def connect(:ssl, host, port, false = _verify) do
    {:ok, socket} = Socket.connect(:ssl, host, port, false)
    {:ok, _} = Socket.recv(socket)
    {:ok, socket}
  end

  def close(socket), do: Socket.close(socket)

  def send(socket, %Request{literal: nil} = req), do: Socket.send(socket, Request.raw(req))

  def send(socket, %Request{literal: literal} = req) when literal != nil do
    {command, literal} = Request.raw(req)

    literal_size = byte_size(literal)
    Socket.send(socket, "#{command} {#{literal_size}}\r\n")

    true = ok_to_continue(socket)
    Socket.send(socket, literal <> "\r\n")
  end

  def get_response(socket, %Request{tag: tag} = req) when tag != nil do
    case send(socket, req) do
      {:error, _} = err ->
        err

      :ok ->
        case process_lines(socket, [], nil, %Response{req: req}) do
          {:error, _} = err ->
            err

          %Response{status: status} = resp when status != nil ->
            resp
        end
    end
  end

  defp process_lines(socket, [], cur, %Response{} = resp) do
    case Socket.recv_lines(socket) do
      {:error, _} = err ->
        err

      lines ->
        process_lines(socket, lines |> String.split("\r\n"), cur, resp)
    end
  end

  defp process_lines(
         socket,
         lines,
         {:untagged, line, {:literal, size, v} = lit},
         %Response{} = resp
       )
       when byte_size(v) < size do

    {lit, rest} = collect_literal(socket, lines, lit)
    process_lines(socket, rest, {:untagged, line, lit}, resp)
  end

  defp process_lines(socket, [line | tail], cur, %Response{req: req} = resp) do
    cond do
      # status line
      matches = is_status_line(req, line) ->
        resp = append_response(resp, cur)

        {status, status_line} = matches
        Response.with_status(resp, status, status_line)

      # untagged resp with literal
      size = is_untagged_response_with_literal(line) ->
        resp = append_response(resp, cur)

        cur = {:untagged, line <> "\r\n", {:literal, size, ""}}
        process_lines(socket, tail, cur, resp)

      # untagged resp
      String.starts_with?(line, "* ") ->
        resp = append_response(resp, cur)

        cur = {:untagged, line <> "\r\n"}
        process_lines(socket, tail, cur, resp)

      # continuation
      String.starts_with?(line, "+ ") ->
        resp = append_response(resp, cur)

        cur = {:continuation, line <> "\r\n"}
        process_lines(socket, tail, cur, resp)

      true ->
        cur =
          case cur do
            nil ->
              raise "cur=nil is unexpected here (line=#{line})"

            {:untagged, msg} ->
              {:untagged, msg <> line <> "\r\n"}

            {:untagged, msg, {:literal, _, _} = lit} ->
              {:untagged, msg <> line <> "\r\n", lit}
          end

        process_lines(socket, tail, cur, resp)
    end
  end

  defp collect_literal(_socket, lines, {:literal, size, v} = lit)
       when byte_size(v) == size,
       do: {lit, lines}

  defp collect_literal(socket, [], {:literal, size, v} = lit) when byte_size(v) < size do
    case Socket.recv_lines(socket) do
      {:error, _} = err ->
        err

      lines ->
        collect_literal(socket, lines |> String.split("\r\n"), lit)
    end
  end

  defp collect_literal(socket, [line | tail], {:literal, size, v}) when byte_size(v) < size do
    # FIXME appending line terminator should be done either here or above
    v = v <> line <> "\r\n"
    collect_literal(socket, tail, {:literal, size, v})
  end

  defp append_response(%Response{} = resp, _cur = nil), do: resp

  defp append_response(%Response{} = resp, cur), do: Response.append_response(resp, cur)

  defp is_status_line(%Request{tag: tag}, line) do
    case Regex.run(Regex.compile!("^#{tag} (OK|BAD|NO) (.*)$"), line, capture: :all_but_first) do
      [status, status_line] ->
        {Map.get(%{"OK" => :ok, "BAD" => :bad, "NO" => :no}, status), status_line}

      nil ->
        nil
    end
  end

  defp is_untagged_response_with_literal(line) do
    case Regex.run(~r/^\* \d+ [^\s]+.* \{(\d+)\}$/, line, capture: :all_but_first) do
      [size] ->
        {size, _} = Integer.parse(size)
        size

      nil ->
        nil
    end
  end

  defp ok_to_continue(socket) do
    line = Socket.recv_lines(socket)
    String.starts_with?(line, "+ OK")
  end
end
