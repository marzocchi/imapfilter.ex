defmodule ImapFilter.RulesTest do
  use ExUnit.Case, async: true

  alias ImapFilter.Rules

  test "header_regex returns true for first matching header value" do
    headers_list = [
      {"Subject", "test"},
      {"To", "hello@example.invalid"},
      {"To", "hello@test.invalid"}
    ]

    matches = Rules.header_regex(%Rules.Arg{headers: headers_list}, "To", "^hello@.*$")
    assert matches == true
  end

  test "header_regex returns false if header does not match" do
    headers_list = [
      {"Subject", "test"},
      {"To", "not-matching@example.invalid"},
      {"To", "hello@test.invalid"}
    ]

    matches = Rules.header_regex(%Rules.Arg{headers: headers_list}, "To", "^hello@.*$")
    assert matches == false
  end

  test "header_regex returns false if header not found by name" do
    headers_list = [
      {"Subject", "test"},
      {"Cc", "hello@example.invalid"},
      {"Bcc", "hello@test.invalid"}
    ]

    matches = Rules.header_regex(%Rules.Arg{headers: headers_list}, "To", "^hello@.*$")
    assert matches == false
  end
end
