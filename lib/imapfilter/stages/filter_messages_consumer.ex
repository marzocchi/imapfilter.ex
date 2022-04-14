defmodule ImapFilter.Stages.FilterMessagesConsumer do
  use GenStage

  require Logger

  alias ImapFilter.Imap.Response
  alias ImapFilter.Imap.Session
  alias ImapFilter.Rules

  @initial_state %{name: nil, producers: nil, rules: [], session: nil}

  def start_link(%{name: name} = init_arg),
    do: GenStage.start_link(__MODULE__, Map.merge(@initial_state, init_arg), name: name)

  def init(%{producers: producers} = init_arg), do: {:consumer, init_arg, subscribe_to: producers}

  def handle_events(messages, _from, %{rules: rules, session: session} = state) do
    apply_rules(session, rules, messages)
    {:noreply, [], state}
  end

  def apply_rules(session, rules, messages) do
    {successful, failures} =
      messages
      |> Enum.map(fn msgid -> assemble_arg(session, msgid) end)
      |> Enum.split_with(fn a ->
        case a do
          %Rules.Arg{} ->
            true

          _ ->
            false
        end
      end)

    failures
    |> Enum.each(fn {:error, msgid, msg} ->
      {_, mailbox, uid} = msgid

      msg =
        case msg do
          {:error, err} ->
            err

          text ->
            text
        end

      Logger.error("can't process #{uid} in #{mailbox}, got #{msg} while retrieving attributes")
    end)

    rules_outcomes =
      successful
      |> Enum.map(fn arg ->
        case find_matching_rule(arg, rules) do
          %{actions: _actions} = rule ->
            {arg, rule}

          nil ->
            {arg, nil}
        end
      end)
      |> Enum.filter(fn {_arg, rule} -> rule != nil end)
      |> Enum.flat_map(fn {arg, %{actions: actions, label: label}} ->
        Enum.map(actions, fn %{impl: impl, args: args} ->
          result = apply(__MODULE__, String.to_existing_atom(impl), [session, arg] ++ args)
          {label, impl, result}
        end)
      end)

    rules_outcomes
    |> Enum.each(fn {label, impl, result} ->
      case result do
        :ok ->
          Logger.info("#{label} #{impl} -> :ok")

        {:error, msg} ->
          Logger.error("#{label} #{impl} -> error: #{msg}")
      end
    end)

    rules_outcomes
  end

  def move_to_folder(session, %Rules.Arg{msgid: msgid}, to_folder) do
    case Session.move(session, msgid, to_folder) do
      {:error, msg} ->
        {:error, "socket error: #{msg}"}

      %Response{status: status, status_line: status_line} when status in [:bad, :no] ->
        {:error, status_line}

      %Response{status: :ok} ->
        :ok
    end
  end

  defp assemble_arg(session, msgid) do
    Session.fetch_headers(session, msgid)
    |> case do
      {:error, _} = err ->
        {:error, msgid, err}

      %Response{status: :ok} = resp ->
        if Response.empty?(resp),
          do: {:error, msgid, "message not found"},
          else: Rules.Arg.new(msgid, Response.Parser.parse(resp))
    end
  end

  defp find_matching_rule(%Rules.Arg{}, []), do: nil

  defp find_matching_rule(%Rules.Arg{} = arg, [%{impl: impl, args: args} = head | tail]) do
    case Rules.match!(impl, [arg] ++ args) do
      true -> head
      false -> find_matching_rule(arg, tail)
    end
  end
end
