defmodule ImapFilter.Imap.Client do
  # works around 'imported Kernel.send/2 conflicts with local function' which happens when aliasing
  import Kernel, except: [send: 2]

  alias ImapFilter.Imap.Request
  alias ImapFilter.Imap.Response
  alias ImapFilter.Socket

  def connect(:tcp, host, port) do
    with {:ok, socket} <- Socket.connect(:tcp, host, port),
         {:ok, _} <- Socket.recv(socket) do
      {:ok, socket}
    else
      {:error, _} = err -> err
    end
  end

  def connect(:tcp, host, port, _verify) do
    connect(:tcp, host, port)
  end

  def connect(:ssl, host, port, verify) do
    with {:ok, socket} <- Socket.connect(:ssl, host, port, verify),
         {:ok, _} = Socket.recv(socket) do
      {:ok, socket}
    else
      {:error, _} = err -> err
    end
  end

  def close(socket), do: Socket.close(socket)

  def send(socket, %Request{literal: nil} = req),
    do: Socket.send(socket, Request.raw(req))

  def send(socket, %Request{literal: literal} = req) when literal != nil do
    {command, literal} = Request.raw(req)

    literal_size = byte_size(literal)

    with :ok <- Socket.send(socket, "#{command} {#{literal_size}}\r\n"),
         :ok <- continue(socket),
         :ok <- Socket.send(socket, literal <> "\r\n") do
      :ok
    end
  end

  def get_response(socket, %Request{tag: tag} = req) when tag != nil do
    with :ok <- send(socket, req),
         %Response{status: :ok} = resp <-
           receive_response_lines(socket, "", nil, %Response{req: req}) do
      resp
    else
      %Response{} = resp -> {:error, resp}
      {:error, _} = err -> err
    end
  end

  defp receive_response_lines(socket, nil, cur, %Response{} = resp) do
    case Socket.recv_lines(socket) do
      {:error, _} = err ->
        err

      lines ->
        receive_response_lines(socket, lines, cur, resp)
    end
  end

  defp receive_response_lines(
         socket,
         lines,
         {:untagged, msg, {:literal, {collected, size}, _v} = lit},
         %Response{} = resp
       )
       when collected < size do
    {lit, rest} = collect_literal(socket, lines, lit)

    receive_response_lines(socket, rest, {:untagged, msg, lit}, resp)
  end

  defp receive_response_lines(socket, lines, cur, %Response{req: req} = resp) do
    {line, rest} = split(lines)

    cond do
      # status line
      matches = is_status_line(req, line) ->
        resp = append_response(resp, cur)

        {status, status_line} = matches
        Response.with_status(resp, status, status_line)

      # untagged resp with literal
      size = is_untagged_response_with_literal(line) ->
        resp = append_response(resp, cur)

        msg = line
        cur = {:untagged, msg, {:literal, {0, size}, ""}}

        receive_response_lines(socket, rest, cur, resp)

      # untagged resp
      String.starts_with?(line, "* ") ->
        resp = append_response(resp, cur)

        cur = {:untagged, line}
        receive_response_lines(socket, rest, cur, resp)

      # continuation
      String.starts_with?(line, "+ ") ->
        resp = append_response(resp, cur)

        cur = {:continuation, line}
        receive_response_lines(socket, rest, cur, resp)

      # CRLF is interesting only inside a literal
      line == "\r\n" ->
        receive_response_lines(socket, rest, cur, resp)

      true ->
        cur =
          case cur do
            {:untagged, msg} ->
              {:untagged, msg <> line}

            {:untagged, msg, {:literal, _, _} = lit} ->
              {:untagged, msg <> line, lit}
          end

        receive_response_lines(socket, rest, cur, resp)
    end
  end

  defp collect_literal(_socket, lines, {:literal, {collected, size}, v})
       when collected == size,
       do: {{:literal, {collected, size}, v}, lines}

  defp collect_literal(socket, "", {:literal, {collected, size}, _v} = lit)
       when collected < size do
    case Socket.recv_lines(socket) do
      {:error, _} = err ->
        err

      lines ->
        collect_literal(socket, lines, lit)
    end
  end

  defp collect_literal(socket, lines, {:literal, {collected, size}, v})
       when collected < size do
    {line, rest} = split(lines)
    v = v <> line
    collect_literal(socket, rest, {:literal, {byte_size(v), size}, v})
  end

  defp split(lines) do
    case String.split(lines, "\r\n", parts: 2) do
      [a, b] -> {"#{a}\r\n", b}
      [a] -> {"#{a}\r\n", nil}
      [""] -> {nil, nil}
    end
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
    case Regex.run(~r/^\* \d+ [^\s]+.* \{(\d+)\}\r$/, line, capture: :all_but_first) do
      [size] ->
        {size, _} = Integer.parse(size)
        size

      nil ->
        nil
    end
  end

  defp continue(socket) do
    with line <- Socket.recv_lines(socket),
         true <- String.starts_with?(line, "+ OK") do
      :ok
    else
      {:error, _} = err -> err
      false -> {:error, :server_reply_not_ok}
    end
  end
end
