defmodule ImapFilter.Imap.Session do
  use GenServer
  import Logger

  alias ImapFilter.Imap.Request
  alias ImapFilter.Imap.Response
  alias ImapFilter.Imap.Client

  @initial_state %{
    counter: 0,
    name: nil,
    socket: nil,
    conn: %{},
    started: false
  }

  def start_link(%{name: name} = init_arg) do
    GenServer.start_link(
      __MODULE__,
      Map.merge(@initial_state, init_arg),
      name: name
    )
  end

  def init(state) do
    {:ok, state}
  end

  def start(socket, user, pass, counter) do
    %Response{status: :ok} =
      Client.get_response(
        socket,
        Request.login(user, pass) |> Request.tagged(counter = counter + 1)
      )

    {:ok, counter}
  end

  def append(pid, msg, to_mailbox),
    do: GenServer.call(pid, {:perform, Request.append(msg, to_mailbox)})

  def login(pid, user, pass), do: GenServer.call(pid, {:perform, Request.login(user, pass)})

  def logout(pid), do: GenServer.call(pid, {:perform, Request.logout()})

  def select(pid, mailbox), do: GenServer.call(pid, {:perform, Request.select(mailbox)})

  def search(pid, in_mailbox, query),
    do: GenServer.call(pid, {:perform, [Request.select(in_mailbox), Request.search(query)]})

  def fetch_headers(pid, {_, in_mailbox, uid}),
    do: GenServer.call(pid, {:perform, [Request.select(in_mailbox), Request.fetch_headers(uid)]})

  def fetch(pid, {_, in_mailbox, uid}),
    do: GenServer.call(pid, {:perform, [Request.select(in_mailbox), Request.fetch(uid)]})

  def fetch_subject(pid, {_, in_mailbox, uid}),
    do: GenServer.call(pid, {:perform, [Request.select(in_mailbox), Request.fetch_subject(uid)]})

  def copy(pid, {_, in_mailbox, uid}, to_mailbox),
    do:
      GenServer.call(pid, {:perform, [Request.select(in_mailbox), Request.copy(uid, to_mailbox)]})

  def create(pid, path), do: GenServer.call(pid, {:perform, [Request.create(path)]})

  def move(pid, {_, from_mailbox, uid}, to_mailbox),
    do:
      GenServer.call(
        pid,
        {:perform,
         [
           Request.select(from_mailbox),
           Request.copy(uid, to_mailbox),
           Request.flag(uid, [:deleted]),
           Request.expunge()
         ]}
      )

  def flag(pid, {_, in_mailbox, uid}, flags),
    do: GenServer.call(pid, {:perform, [Request.select(in_mailbox), Request.flag(uid, flags)]})

  def close(pid), do: GenServer.call(pid, :close)

  def handle_call({:perform, ops}, _from, %{socket: socket, counter: counter, conn: conn} = state) do
    ops =
      case ops do
        %Request{} = ops -> [ops]
        ops when is_list(ops) -> ops
      end

    {socket, counter} = connect_if_needed(socket, counter, conn)

    {[resp | _], counter} = perform(socket, ops, [], counter, conn)

    {:reply, resp, %{state | socket: socket, conn: conn, counter: counter}}
  end

  def handle_call(:close, _from, %{socket: socket} = state) do
    Client.close(socket)
    {:reply, :ok, %{state | socket: nil}}
  end

  defp perform(_socket, [], responses, counter, _conn), do: {responses, counter}

  defp perform(socket, [%Request{} = head | tail], responses, counter, conn) do
    resp = get_response(socket, head, counter, 1, conn)

    case resp do
      {%Response{status: :ok} = resp, counter} ->
        Logger.info(
          "Request #{resp.req.tag} #{resp.req.command} succeeded: #{resp.status} #{resp.status_line}"
        )

        perform(socket, tail, [resp | responses], counter, conn)

      {%Response{
         req: %Request{tag: tag, command: command},
         status: status,
         status_line: status_line
       } = resp, counter} ->
        Logger.error("Request #{tag} #{command} failed: #{status} #{status_line}")

        {[resp | responses], counter}
    end
  end

  defp get_response(socket, req, counter, 0 = _attempts, _conn) do
    resp = Client.get_response(socket, req |> Request.tagged(counter = counter + 1))
    {resp, counter}
  end

  defp get_response(socket, req, counter, attempts, conn) do
    counter = counter + 1

    case Client.get_response(socket, req |> Request.tagged(counter)) do
      {:error, err} when err in [:closed, :enotconn] ->
        {socket, counter} = connect_if_needed(nil, counter, conn)
        get_response(socket, req, counter, attempts - 1, conn)

      %Response{} = resp ->
        {resp, counter}
    end
  end

  defp connect_if_needed(socket, counter, _conn) when socket != nil, do: {socket, counter}

  defp connect_if_needed(nil, counter, %{
         host: host,
         port: port,
         user: user,
         pass: pass,
         type: type,
         verify: verify
       }) do
    {:ok, socket} = Client.connect(type, host, port, verify)
    {:ok, counter} = start(socket, user, pass, counter)
    {socket, counter}
  end
end
