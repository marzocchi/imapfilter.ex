defmodule ImapFilter.Stages.FilterMessagesConsumer do
  use GenStage

  import Logger

  alias ImapFilter.Imap.Response
  alias ImapFilter.Imap.Session
  alias ImapFilter.Rules

  @initial_state %{name: nil, producers: nil, rules: [], session: nil}

  def start_link(%{name: name} = init_arg),
    do: GenStage.start_link(__MODULE__, Map.merge(@initial_state, init_arg), name: name)

  def init(%{producers: producers} = init_arg), do: {:consumer, init_arg, subscribe_to: producers}

  def handle_events(messages, _from, %{rules: rules, session: session} = state) do
    messages
    |> Enum.each(fn msgid ->
      rule_arg = assemble_arg(session, msgid)

      case find_matching_rule(rule_arg, rules) do
        %{actions: _actions, label: label} = rule ->
          info("rule matched: #{label}")
          apply_actions(session, rule_arg, rule)

        _ ->
          info("no rule matched")
      end
    end)

    {:noreply, [], state}
  end

  def apply_actions(session, %Rules.Arg{msgid: {_, _, uid} = msgid}, %{
        label: label,
        actions: actions
      }) do
    actions
    |> Enum.each(fn action ->
      case action do
        %{impl: "move_to_folder" = impl, args: [to_folder]} ->
          info("applying rule #{label}'s action '#{impl}' to message #{uid}")

          Session.move(session, msgid, to_folder)
          |> case do
            %Response{status: :bad, status_line: status_line} ->
              error("action failed: BAD #{status_line}")

            %Response{status: :no, status_line: status_line} ->
              error("action failed: NO #{status_line}")

            %Response{status: :ok, status_line: status_line} ->
              info("action succeeded: OK #{status_line}")
          end
      end
    end)
  end

  defp assemble_arg(session, msgid) do
    headers =
      Session.fetch_headers(session, msgid)
      |> case do
        %Response{status: :ok} = resp -> Response.Parser.parse(resp)
      end

    Rules.Arg.new(msgid, headers)
  end

  defp find_matching_rule(%Rules.Arg{}, []), do: nil

  defp find_matching_rule(%Rules.Arg{} = arg, [%{impl: impl, args: args} = head | tail]) do
    case Rules.match!(impl, [arg] ++ args) do
      true -> head
      false -> find_matching_rule(arg, tail)
    end
  end
end
