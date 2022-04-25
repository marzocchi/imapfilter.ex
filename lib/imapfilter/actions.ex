defmodule ImapFilter.Actions do
  alias ImapFilter.Imap.Response
  alias ImapFilter.Imap.Session
  alias ImapFilter.Rules
  alias ImapFilter.Config

  def apply_actions(session, actions, %Rules.Arg{} = arg) do
    Enum.map(actions, fn %Config.Action{impl: impl, args: args} ->
      result = apply(__MODULE__, String.to_existing_atom(impl), [session, arg] ++ args)
      {arg.msgid, impl, result}
    end)
  end

  def move_to_folder(session, %Rules.Arg{msgid: msgid}, to_folder) do
    with %Response{} <- Session.move(session, msgid, to_folder), do: :ok
  end
end
