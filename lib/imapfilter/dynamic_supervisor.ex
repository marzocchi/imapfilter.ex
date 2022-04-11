defmodule ImapFilter.DynamicSupervisor do
  use DynamicSupervisor

  alias ImapFilter.Config.Account

  def start_link(%{name: name} = init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: name)
  end

  @impl true
  def init(_init_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def add_account(pid, %Account{} = acct, i) when is_integer(i) do
    tree = create_supervision_tree(acct, i)
    DynamicSupervisor.start_child(pid, tree)
  end

  defp create_supervision_tree(%Account{host: host, user: user, rules: rules} = conn_params, i) do
    registry_name = String.to_atom("imap_registry_#{i}")
    registry_spec = {Registry, keys: :unique, name: registry_name}

    children =
      [registry_spec] ++
        create_monitor_processes(registry_name, conn_params) ++
        create_producer_processes(registry_name, conn_params) ++
        create_consumer_processes(registry_name, conn_params, rules)

    %{
      id: String.to_atom("supervisor_#{i}"),
      start: {
        Supervisor,
        :start_link,
        [children, [strategy: :one_for_one, name: {:global, {:account_root, host, user}}]]
      }
    }
  end

  defp create_monitor_processes(registry_name, %{} = conn_params) do
    [
      %{
        :id => :changes_monitor,
        :start =>
          {ImapFilter.Imap.MailboxMonitor, :start_link,
           [
             %{
               notify: unique_name(registry_name, :producer),
               name: unique_name(registry_name, :monitor),
               conn: conn_params
             }
           ]}
      }
    ]
  end

  defp create_producer_processes(registry_name, %{mailbox: mailbox} = conn_params) do
    [
      %{
        :id => :producer_queue,
        :start =>
          {ImapFilter.Imap.MessageQueue, :start_link,
           [%{name: unique_name(registry_name, :producer_queue)}]}
      },
      %{
        :id => :producer_client,
        :start =>
          {ImapFilter.Imap.Session, :start_link,
           [%{name: unique_name(registry_name, :producer_session), conn: conn_params}]}
      },
      %{
        :id => :producer,
        :start =>
          {ImapFilter.Stages.NewMessagesProducer, :start_link,
           [
             %{
               name: unique_name(registry_name, :producer),
               session_name: unique_name(registry_name, :producer_session),
               conn: conn_params,
               queue_name: unique_name(registry_name, :producer_queue),
               mailbox: mailbox
             }
           ]}
      }
    ]
  end

  defp create_consumer_processes(registry_name, %{} = conn_params, rules) do
    [
      %{
        :id => :consumer_session,
        :start => {
          ImapFilter.Imap.Session,
          :start_link,
          [%{name: unique_name(registry_name, :consumer_session), conn: conn_params}]
        }
      },
      %{
        :id => :consumer,
        :start => {
          ImapFilter.Stages.FilterMessagesConsumer,
          :start_link,
          [
            %{
              producers: [{unique_name(registry_name, :producer), min_demand: 1, max_demand: 100}],
              name: unique_name(registry_name, :consumer),
              rules: rules,
              session: unique_name(registry_name, :consumer_session)
            }
          ]
        }
      }
    ]
  end

  defp unique_name(registry_name, label) do
    {:via, Registry, {registry_name, label}}
  end
end
