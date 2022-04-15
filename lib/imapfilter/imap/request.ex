defmodule ImapFilter.Imap.Request do
  alias ImapFilter.Imap.Request

  defstruct tag: nil, command: nil, params: [], literal: nil

  def tagged(req, counter), do: %Request{req | tag: "T#{counter}"}

  def login(user, pass, counter), do: login(user, pass) |> tagged(counter)
  def login(user, pass), do: %Request{command: :login, params: ["#{user}", "#{pass}"]}

  def logout(counter), do: logout() |> Request.tagged(counter)
  def logout(), do: %Request{command: :logout}

  def capability(counter), do: capability() |> Request.tagged(counter)
  def capability(), do: %Request{command: :capability}

  def select(mailbox, counter), do: select(mailbox) |> Request.tagged(counter)
  def select(mailbox), do: %Request{command: :select, params: ["#{mailbox}"]}

  def create(path, counter), do: create(path) |> Request.tagged(counter)
  def create(path), do: %Request{command: :create, params: [path]}

  def expunge(counter), do: expunge() |> Request.tagged(counter)
  def expunge(), do: %Request{command: :expunge}

  def flag(uid, flags, counter), do: flag(uid, flags) |> Request.tagged(counter)
  def flag(uid, flags), do: %Request{command: :store, params: [uid, {:plus_flags, flags}]}

  def idle(counter), do: idle() |> Request.tagged(counter)
  def idle(), do: %Request{command: :idle}

  def done(counter), do: done() |> Request.tagged(counter)
  def done(), do: %Request{command: :done}

  def search(query, counter), do: search(query) |> Request.tagged(counter)

  def search(query) when is_list(query),
    do: %Request{
      command: :uid_search,
      params: query
    }

  def search(query), do: search([query])

  def copy(uid, mailbox, counter), do: copy(uid, mailbox) |> Request.tagged(counter)
  def copy(uid, mailbox), do: %Request{command: :uid_copy, params: [uid, mailbox]}

  def fetch_headers(uid, counter), do: fetch_headers(uid) |> Request.tagged(counter)
  def fetch_headers(uid), do: %Request{command: :uid_fetch, params: [uid, :fetch_rfc822_headers]}

  def fetch_attributes(uid, counter), do: fetch_attributes(uid) |> Request.tagged(counter)
  def fetch_attributes(uid), do: %Request{command: :uid_fetch, params: [uid, :fetch_attributes]}

  def fetch(uid, counter), do: fetch(uid) |> Request.tagged(counter)
  def fetch(uid), do: %Request{command: :uid_fetch, params: [uid, :fetch_rfc822]}

  def fetch_subject(uid, counter), do: fetch_subject(uid) |> Request.tagged(counter)
  def fetch_subject(uid), do: %Request{command: :uid_fetch, params: [uid, :fetch_subject]}

  def append(msg, to_mailbox, counter), do: append(msg, to_mailbox) |> Request.tagged(counter)
  def append(msg, to_mailbox), do: %Request{command: :append, params: [to_mailbox], literal: msg}

  def raw(%Request{literal: nil} = req), do: assemble_command(req) <> "\r\n"

  def raw(%Request{literal: literal} = req), do: {assemble_command(req), literal}

  defp assemble_command(%Request{} = req) do
    command = get_command(req)
    params = req |> map_params()

    if req.tag == nil do
      [command | params]
    else
      [req.tag, command] ++ params
    end
    |> Enum.filter(& &1)
    |> Enum.map(&to_string(&1))
    |> Enum.join(" ")
  end

  defp get_command(%Request{command: command}) do
    Map.get(
      %{
        :login => "LOGIN",
        :logout => "LOGOUT",
        :select => "SELECT",
        :idle => "IDLE",
        :done => "DONE",
        :uid_search => "UID SEARCH",
        :uid_fetch => "UID FETCH",
        :append => "APPEND",
        :header => "HEADER",
        :uid_copy => "UID COPY",
        :expunge => "EXPUNGE",
        :capability => "CAPABILITY",
        :store => "UID STORE"
      },
      command,
      command
    )
  end

  defp map_params(%Request{params: params}) do
    Enum.map(params, &map_param/1)
  end

  defp map_param(p) do
    case p do
      :fetch_attributes ->
        "(RFC822.HEADER FLAGS)"

      :fetch_rfc822_headers ->
        "RFC822.HEADER"

      :fetch_rfc822 ->
        "RFC822"

      :fetch_subject ->
        "BODY[HEADER.FIELDS (SUBJECT)]"

      :all ->
        "ALL"

      :header ->
        "HEADER"

      {:plus_flags, flags} ->
        flags = Enum.map(flags, &map_flag/1)
        "+FLAGS (" <> Enum.join(flags, " ") <> ")"

      p ->
        case Integer.parse(p) do
          :error -> '"#{p}"'
          {_, _} -> p
        end
    end
  end

  defp map_flag(flag) do
    Map.get(
      %{
        :seen => "\\Seen",
        :deleted => "\\Deleted",
        :answered => "\\Answered",
        :flagged => "\\Flagged",
        :draft => "\\Draft",
        :recent => "\\Recent"
      },
      flag,
      flag
    )
  end
end
