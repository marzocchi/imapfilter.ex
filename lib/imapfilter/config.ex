defmodule ImapFilter.Config do
  defmodule Action do
    defstruct impl: {}, args: []

    def new(%{impl: impl, args: args}), do: %Action{impl: impl, args: args}
  end

  defmodule Rule do
    defstruct label: "", impl: {}, args: [], actions: []

    def new(%{label: label, impl: impl, args: args, actions: actions}),
      do: %Rule{label: label, impl: impl, args: args, actions: Enum.map(actions, &Action.new/1)}
  end

  defmodule Account do
    defstruct host: "",
              port: 0,
              user: "",
              pass: "",
              mailbox: "",
              type: :ssl,
              verify: true,
              rules: []

    def new(%{
          host: host,
          user: user,
          mailbox: mailbox,
          pass: pass,
          port: port,
          type: type,
          verify: verify,
          rules: rules
        })
        when type in ["ssl", "tcp"],
        do: %Account{
          host: host,
          port: port,
          user: user,
          pass: pass,
          mailbox: mailbox,
          type: String.to_existing_atom(type),
          verify: verify,
          rules: Enum.map(rules, &Rule.new/1)
        }
  end

  def parse_text!(text) do
    {:ok, data} = YamlElixir.read_from_string(text)
    data |> assemble_accounts
  end

  defp assemble_accounts(%{"accounts" => accounts}) when is_list(accounts) do
    accounts
    |> Enum.map(&fix_map/1)
    |> Enum.map(&Account.new/1)
  end

  defp fix_map(v) do
    # FIXME works around some atoms not always existing by the time tests are run?!
    atoms = %{
      "label" => :label,
      "impl" => :impl,
      "args" => :args,
      "actions" => :actions,
      "host" => :host,
      "port" => :port,
      "user" => :user,
      "pass" => :pass,
      "mailbox" => :mailbox,
      "type" => :type,
      "verify" => :verify,
      "rules" => :rules
    }

    case v do
      m when is_map(m) ->
        Map.new(m, fn {k, v} ->
          {Map.get(atoms, k), fix_map(v)}
        end)

      l when is_list(l) ->
        Enum.map(l, &fix_map/1)

      _ ->
        v
    end
  end

  defmodule Loader do
    use GenServer

    alias ImapFilter.Config
    alias ImapFilter.DynamicSupervisor

    @initial_state %{config_file: nil, supervisor: nil}

    def start_link(%{config_file: config_file} = init_arg) when config_file != nil do
      GenServer.start_link(
        __MODULE__,
        Map.merge(@initial_state, init_arg),
        name: __MODULE__
      )
    end

    def init(state) do
      {:ok, state, {:continue, :init}}
    end

    def handle_continue(:init, %{config_file: config_file, supervisor: supervisor} = state) do
      data = File.read!(config_file)

      Config.parse_text!(data)
      |> Enum.with_index()
      |> Enum.each(fn {acct, i} ->
        DynamicSupervisor.add_account(supervisor, acct, i)
      end)


      {:noreply, state}
    end
  end
end
