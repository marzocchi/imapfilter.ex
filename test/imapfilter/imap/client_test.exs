defmodule ImapFilter.Imap.ClientTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias ImapFilter.Imap.Client
  alias ImapFilter.Imap.Request
  alias ImapFilter.Imap.Response

  setup do
    {:ok, socket} = Client.connect(:tcp, "localhost", 10143)

    Client.get_response(socket, Request.login("user1", "password") |> Request.tagged(0))
    Client.get_response(socket, Request.select("INBOX") |> Request.tagged(0))

    %{socket: socket}
  end

  test "connect and close type=:ssl, verify=false" do
    {:ok, _} = Client.connect(:ssl, "localhost", 10993, false)
  end

  test "connect and close type=:tcp" do
    {:ok, _} = Client.connect(:tcp, "localhost", 10143)
  end

  test "get_response with FETCH", %{socket: socket} do
    resp = Client.get_response(socket, Request.fetch("1") |> Request.tagged(2))

    assert %Response{status: :ok} = resp
    assert String.starts_with?(resp.status_line, "Fetch completed")
    assert %Response{responses: responses} = resp

    fetch_resp =
      responses
      |> Enum.filter(fn resp ->
        case resp do
          {:untagged, _, {:literal, _, _}} -> true
          _ -> false
        end
      end)
      |> Enum.at(0)

    assert {:untagged, line, {:literal, {506, 506}, literal}} = fetch_resp
    assert String.starts_with?(line, "* 1 FETCH (UID 1 ")
    assert 506 = byte_size(literal)
  end

  test "get_response with SELECT", %{socket: socket} do
    resp = Client.get_response(socket, Request.select("INBOX") |> Request.tagged(1))

    assert %Response{status: :ok, status_line: status_line, responses: responses} = resp
    assert String.contains?(status_line, "Select completed")
    assert Enum.count(responses) > 1
  end

  test "get_response with SEARCH", %{socket: socket} do
    resp = Client.get_response(socket, Request.search(:all) |> Request.tagged(1))

    assert %Response{status: :ok, status_line: status_line, responses: responses} = resp
    assert String.contains?(status_line, "Search completed")
    assert Enum.count(responses) == 1

    assert [{:untagged, line}] = resp.responses
    assert String.starts_with?(line, "* SEARCH ")
    assert String.ends_with?(line, "\r\n")
  end
end
