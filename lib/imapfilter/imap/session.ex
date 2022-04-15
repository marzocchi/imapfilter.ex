defmodule ImapFilter.Imap.Session do
  use GenServer
  require Logger

  alias ImapFilter.Imap.Request
  alias ImapFilter.Imap.Response
  alias ImapFilter.Imap.Client

  @initial_state %{
    counter: 0,
    name: nil,
    socket: nil,
    conn: %{},
    logger_metadata: nil
  }

  def append(pid, msg, to_mailbox),
    do: GenServer.call(pid, {:perform, Request.append(msg, to_mailbox)})

  def login(pid, user, pass), do: GenServer.call(pid, {:perform, Request.login(user, pass)})

  def logout(pid), do: GenServer.call(pid, {:perform, Request.logout()})

  def select(pid, mailbox), do: GenServer.call(pid, {:perform, Request.select(mailbox)})

  def search(pid, in_mailbox, query),
    do: GenServer.call(pid, {:perform, [Request.select(in_mailbox), Request.search(query)]})

  def fetch_headers(pid, {_, in_mailbox, uid}),
    do: GenServer.call(pid, {:perform, [Request.select(in_mailbox), Request.fetch_headers(uid)]})

  def fetch_attributes(pid, {_, in_mailbox, uid}),
    do:
      GenServer.call(pid, {:perform, [Request.select(in_mailbox), Request.fetch_attributes(uid)]})

  def fetch(pid, {_, in_mailbox, uid}),
    do: GenServer.call(pid, {:perform, [Request.select(in_mailbox), Request.fetch(uid)]})

  def fetch_subject(pid, {_, in_mailbox, uid}),
    do: GenServer.call(pid, {:perform, [Request.select(in_mailbox), Request.fetch_subject(uid)]})

  def copy(pid, {_, in_mailbox, uid}, to_mailbox),
    do:
      GenServer.call(pid, {:perform, [Request.select(in_mailbox), Request.copy(uid, to_mailbox)]})

  def create(pid, path), do: GenServer.call(pid, {:perform, Request.create(path)})

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

  def start_link(%{name: name} = init_arg) do
    GenServer.start_link(
      __MODULE__,
      Map.merge(@initial_state, init_arg),
      name: name
    )
  end

  @impl true
  def init(%{logger_metadata: md} = state) when md != nil do
    Logger.metadata(md)
    {:ok, state}
  end

  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:close, _from, %{socket: socket} = state) do
    Client.close(socket)
    {:reply, :ok, %{state | socket: nil}}
  end

  @impl true
  def handle_call({:perform, %Request{} = req}, from, %{} = state),
    do: handle_call({:perform, [req]}, from, state)

  @impl true
  def handle_call({:perform, ops}, _from, %{socket: socket, counter: counter, conn: conn} = state) do
    {socket, counter} = connect_if_needed(socket, counter, conn)
    perform(ops, [], %{state | socket: socket, counter: counter})
  end

  defp perform([], [resp | _], %{} = state), do: {:reply, resp, state}

  defp perform([%Request{} = head | tail], responses, %{socket: socket, counter: counter} = state) do
    counter = counter + 1

    with %Response{} = resp <-
           Client.get_response(socket, head |> Request.tagged(counter)) do
      perform(tail, [resp | responses], %{state | counter: counter})
    else
      {:error, %Response{}} = err ->
        {:reply, err, %{state | counter: counter}}

      {:error, _} = err ->
        {:reply, err, %{state | counter: counter, socket: nil}}
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
    counter = counter + 1

    with {:ok, socket} <- Client.connect(type, host, port, verify),
         %Response{} <- login(socket, user, pass, counter) do
      {socket, counter}
    else
      {:error, _} = err ->
        {err, counter}
    end
  end

  defp login(socket, user, pass, counter) do
    with %Response{} = resp <- Client.get_response(socket, Request.login(user, pass, counter)) do
      resp
    else
      {:error, _} = err -> err
    end
  end
end
