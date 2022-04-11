defmodule ImapFilter.Imap.MailboxMonitor do
  use GenServer

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
    mailbox: "",
    reidle_interval: 600_000
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
          conn: %{
            user: user,
            pass: pass,
            host: host,
            port: port,
            type: type,
            verify: verify,
            mailbox: mailbox
          },
          counter: counter
        } = state
      ) do
    {:ok, socket} = Client.connect(type, host, port, verify)

    %Response{status: :ok} =
      caps =
      Client.get_response(
        socket,
        Request.capability() |> Request.tagged(counter = counter + 1)
      )

    idle_supported!(caps)

    %Response{status: :ok} =
      Client.get_response(
        socket,
        Request.login(user, pass) |> Request.tagged(counter = counter + 1)
      )

    %Response{status: :ok} =
      Client.get_response(
        socket,
        Request.select(mailbox) |> Request.tagged(counter = counter + 1)
      )

    Socket.setopts(socket, active: true)

    send(self(), :idle_start)
    {:noreply, %{state | socket: socket, counter: counter}}
  end

  @impl true
  def handle_info(
        :idle_start,
        %{socket: socket, counter: counter, reidle_interval: reidle_interval, notify: notify} = state
      ) do
    :ok =
      Socket.send(
        socket,
        Request.idle() |> Request.tagged(counter = counter + 1) |> Request.raw()
      )

    send(notify, :idle_started)

    Process.send_after(self(), :idle_stop, reidle_interval)
    {:noreply, %{state | counter: counter}}
  end

  @impl true
  def handle_info(:idle_stop, %{socket: socket, counter: counter, notify: notify} = state) do
    :ok =
      Socket.send(
        socket,
        Request.done() |> Request.raw()
      )

    send(notify, :idle_stopped)
    send(self(), :idle_start)
    {:noreply, %{state | counter: counter}}
  end

  @impl true
  def handle_info({:tcp, _, data}, %{notify: notify} = state) do
    process_received_data(data, notify)

    {:noreply, state}
  end

  @impl true
  def handle_info({:ssl, _, data}, %{notify: notify} = state) do
    process_received_data(data, notify)

    {:noreply, state}
  end

  defp idle_supported!(%Response{} = resp), do: true = "IDLE" in Response.parse_capability(resp)

  defp process_received_data(data, notify_pid) do
    data
    |> String.split("\r\n")
    |> Enum.filter(&is_interesting_line/1)
    |> send_notification(notify_pid)
  end

  defp send_notification([], _notify_id), do: nil

  defp send_notification(lines, {:via, Registry, {reg, name}}) do
    [{pid, _}] = Registry.lookup(reg, name)
    send_notification(lines, pid)
  end

  defp send_notification(lines, notify_pid) when is_pid(notify_pid),
    do: send(notify_pid, {:mailbox_activity, lines})

  defp is_interesting_line(line) do
    Regex.match?(~r/^\* \d+ EXISTS/, line) ||
      Regex.match?(~r/^\* \d+ RECENT/, line)
  end
end
