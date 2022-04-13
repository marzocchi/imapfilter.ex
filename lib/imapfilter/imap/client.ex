defmodule ImapFilter.Imap.Client do
  # works around 'imported Kernel.send/2 conflicts with local function' which happens when aliasing
  import Kernel, except: [send: 2]

  require Logger

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

  def send(socket, %Request{literal: nil, command: command} = req) do
    case Socket.send(socket, Request.raw(req)) do
      {:error, msg} = err ->
        Logger.error("Send of #{command} on socket failed: #{msg}")
        err

      :ok ->
        :ok
    end
  end

  def send(socket, %Request{literal: literal} = req) when literal != nil do
    {command, literal} = Request.raw(req)

    literal_size = byte_size(literal)

    case Socket.send(socket, "#{command} {#{literal_size}}\r\n") do
      {:error, msg} = err ->
        Logger.error("Send of #{command} with literal failed: #{msg}")
        err

      :ok ->
        case ok_to_continue(socket) do
          {:error, msg} = err ->
            Logger.error("Recv of server's continuation failed: #{msg}")
            err

          true ->
            case Socket.send(socket, literal <> "\r\n") do
              {:error, msg} = err ->
                Logger.error("Send of literal text failed: #{msg}")
                err

              :ok ->
                :ok
            end
        end
    end
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
            log_response(resp)
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
         {:untagged, line, {:literal, {collected, size}, _v} = lit},
         %Response{} = resp
       )
       when collected < size do
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

        msg = line <> "\r\n"

        cur = {:untagged, msg, {:literal, {0, size}, ""}}
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

  defp collect_literal(_socket, lines, {:literal, {collected, size}, v})
       when collected == size,
       do: {{:literal, {collected, size}, v}, lines}

  defp collect_literal(socket, [], {:literal, {collected, size}, _v} = lit)
       when collected < size do
    case Socket.recv_lines(socket) do
      {:error, _} = err ->
        err

      lines ->
        collect_literal(socket, lines |> String.split("\r\n"), lit)
    end
  end

  defp collect_literal(socket, [line | tail], {:literal, {collected, size}, v})
       when collected < size do
    # FIXME appending line terminator should be done either here or above
    v = v <> line <> "\r\n"
    collect_literal(socket, tail, {:literal, {byte_size(v), size}, v})
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
    case Socket.recv_lines(socket) do
      {:error, _} = err ->
        err

      line ->
        String.starts_with?(line, "+ OK")
    end
  end

  defp log_response(%Response{
         status: :ok = status,
         status_line: status_line,
         req: %Request{tag: tag, command: command}
       }),
       do: Logger.info("Request #{tag} #{command} succeeded: #{status} #{status_line}")

  defp log_response(%Response{
         status: status,
         status_line: status_line,
         req: %Request{tag: tag, command: command}
       })
       when status != :ok,
       do: Logger.error("Request #{tag} #{command} failed: #{status} #{status_line}")
end
