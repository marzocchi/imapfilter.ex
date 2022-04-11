defmodule ImapFilter.SupervisorTest do
  use ExUnit.Case, async: true

  alias ImapFilter.DynamicSupervisor
  alias ImapFilter.Config.Account

  setup do
    pid = start_supervised!({DynamicSupervisor, %{name: {:global, :test_supervisor}}})

    %{supervisor_pid: pid}
  end

  test "add_account", %{supervisor_pid: supervisor_pid} do
    acct = %Account{host: "example.invalid", user: "user"}

    assert {:ok, pid} = DynamicSupervisor.add_account(supervisor_pid, acct, 42)
    assert is_pid(pid)
  end

end
