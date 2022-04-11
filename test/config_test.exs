defmodule ImapFilter.ConfigTest do
  use ExUnit.Case, async: true

  alias ImapFilter.Config
  alias ImapFilter.Config.Account
  alias ImapFilter.Config.Rule
  alias ImapFilter.Config.Action

  test "parse_text" do
    text = """
    accounts:
      - host: "example.invalid"
        port: 993
        user: "hello@example.invalid"
        pass: "secret"
        mailbox: "INBOX"
        type: ssl
        verify: true
        rules:
          -
            label: "Trash"
            impl: header_regex
            args: [To, ".*"]
            actions:
              - {impl: move_to_folder, args: [Trash]}
    """

    assert [account] = Config.parse_text!(text)

    assert %Account{
             host: "example.invalid",
             port: 993,
             user: "hello@example.invalid",
             pass: "secret",
             mailbox: "INBOX",
             type: :ssl,
             verify: true,
             rules: [%Rule{} = rule]
           } = account

    assert %Rule{
             label: "Trash",
             impl: "header_regex",
             args: ["To", ".*"],
             actions: [%Action{} = action]
           } = rule

    assert %Action{impl: "move_to_folder", args: ["Trash"]} = action
  end
end
