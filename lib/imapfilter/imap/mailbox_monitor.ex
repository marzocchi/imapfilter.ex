defmodule ImapFilter.Imap.MailboxMonitor do
  use GenServer

  require Logger

  alias ImapFilter.Socket
  alias ImapFilter.Imap.Request
  alias ImapFilter.Imap.Response
  alias ImapFilter.Imap.Client

  @initial_state %{
    notify: nil,
    name: nil,
    socket: nil,
    conn: %{},
    counter: 0,
    reidle_interval: 300_000
  }

  def start_link(%{name: name} = init_arg) do
    GenServer.start_link(
      __MODULE__,
      Map.merge(@initial_state, init_arg),
      name: name
    )
  end

  @impl true
  def init(state) do
    {:ok, state, {:continue, :init_session}}
  end

  @impl true
  def handle_continue(
        :init_session,
        %{
          conn: %{} = conn,
          counter: counter
        } = state
      ) do
    {socket, counter} = connect(conn, counter)
    send(self(), :idle_start)
    {:noreply, %{state | socket: socket, counter: counter}}
  end

  @impl true
  def handle_info(:idle_start, %{socket: nil, counter: counter, conn: conn} = state) do
    {socket, counter} = connect(conn, counter)
    handle_info(:idle_start, %{state | socket: socket, counter: counter})
  end

  @impl true
  def handle_info(
        :idle_start,
        %{
          socket: socket,
          counter: counter,
          reidle_interval: reidle_interval,
          notify: notify_pid,
          conn: %{mailbox: mailbox}
        } = state
      ) do
    :ok =
      Socket.send(
        socket,
        Request.idle() |> Request.tagged(counter = counter + 1) |> Request.raw()
      )

    send(resolve_notification_target(notify_pid), {:idle_started, mailbox})

    Process.send_after(self(), :idle_stop, reidle_interval)
    {:noreply, %{state | counter: counter}}
  end

  @impl true
  def handle_info(
        :idle_stop,
        %{socket: socket, counter: counter, notify: notify_pid, conn: %{mailbox: mailbox}} = state
      ) do
    :ok =
      Socket.send(
        socket,
        Request.done() |> Request.raw()
      )

    send(resolve_notification_target(notify_pid), {:idle_stopped, mailbox})
    send(self(), :idle_start)
    {:noreply, %{state | counter: counter}}
  end

  @impl true
  def handle_info({:tcp, _, data}, %{notify: notify, conn: %{mailbox: mailbox}} = state) do
    process_received_data(data, notify, mailbox)

    {:noreply, state}
  end

  @impl true
  def handle_info({:ssl, _, data}, %{notify: notify, conn: %{mailbox: mailbox}} = state) do
    process_received_data(data, notify, mailbox)

    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_closed, _}, %{} = state) do
    Logger.warning("socket closing, reconnecting...")
    send(self(), :idle_start)
    {:noreply, %{state | socket: nil}}
  end

  @impl true
  def handle_info({:ssl_closed, _}, %{} = state) do
    Logger.warning("socket closing, reconnecting...")
    send(self(), :idle_start)
    {:noreply, %{state | socket: nil}}
  end

  defp process_received_data(data, notify_pid, mailbox) do
    data
    |> String.split("\r\n")
    |> Enum.filter(&is_interesting_line/1)
    |> send_notification(notify_pid, mailbox)
  end

  defp send_notification([], _notify_id, _mailbox), do: nil

  defp send_notification(lines, notify_pid, mailbox),
    do: send(resolve_notification_target(notify_pid), {:idle_activity, mailbox, lines})

  defp resolve_notification_target(pid) when is_pid(pid), do: pid

  defp resolve_notification_target({:via, Registry, {reg, name}}) do
    [{pid, _}] = Registry.lookup(reg, name)
    pid
  end

  defp is_interesting_line(line) do
    Regex.match?(~r/^\* \d+ EXISTS/, line) ||
      Regex.match?(~r/^\* \d+ RECENT/, line)
  end

  defp connect(
         %{
           user: user,
           pass: pass,
           host: host,
           port: port,
           type: type,
           verify: verify,
           mailbox: mailbox
         },
         counter
       ) do
    {:ok, socket} = Client.connect(type, host, port, verify)

    counter =
      with {:ok, counter} <- idle_supported(socket, counter),
           {:ok, counter} <- login(socket, user, pass, counter),
           {:ok, counter} <- select(socket, mailbox, counter) do
        Socket.setopts(socket, active: true)
        counter
      else
        {{:error, msg}, counter} ->
          Logger.error("can't monitor mailbox #{mailbox}: #{msg}")
          counter
      end

    {socket, counter}
  end

  defp idle_supported(socket, counter) do
    counter = counter + 1

    case Client.get_response(
           socket,
           Request.capability() |> Request.tagged(counter)
         ) do
      %Response{status: :ok} = resp ->
        if "IDLE" in Response.Parser.parse(resp),
          do: {:ok, counter},
          else: {{:error, "IDLE not supported"}, counter}

      {:error, %Response{status_line: status_line}} ->
        {{:error, status_line}, counter}

      {:error, _} = err ->
        {err, counter}
    end
  end

  defp login(socket, user, pass, counter) do
    counter = counter + 1

    case Client.get_response(
           socket,
           Request.login(user, pass) |> Request.tagged(counter)
         ) do
      %Response{status: :ok} -> {:ok, counter}
      {:error, %Response{status_line: status_line}} -> {{:error, status_line}, counter}
      {:error, _} = err -> {err, counter}
    end
  end

  defp select(socket, mailbox, counter) do
    counter = counter + 1

    case Client.get_response(
           socket,
           Request.select(mailbox) |> Request.tagged(counter)
         ) do
      %Response{status: :ok} -> {:ok, counter}
      {:error, %Response{status_line: status_line}} -> {{:error, status_line}, counter}
      {:error, _} = err -> {err, counter}
    end
  end
end
