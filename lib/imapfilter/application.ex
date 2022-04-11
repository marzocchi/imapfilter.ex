defmodule ImapFilter.Application do
  use Application

  alias ImapFilter.DynamicSupervisor
  alias ImapFilter.Config.Loader

  def start(_type, _args) do
    config_file = System.get_env("IMAPFILTER_CONFIG_FILE")

    children = [
      %{
        id: :config_loader,
        start: {Loader, :start_link, [%{config_file: config_file, supervisor: :main_supervisor}]}
      },
      %{
        id: :main_supervisor,
        start: {
          DynamicSupervisor,
          :start_link,
          [%{name: :main_supervisor}]
        }
      }
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
