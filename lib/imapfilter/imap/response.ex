defmodule ImapFilter.Imap.Response do
  alias ImapFilter.Imap.Response
  alias ImapFilter.Imap.Request

  defstruct status_line: "", status: nil, responses: [], req: nil

  # TODO naming
  def append_response(resp, untagged) do
    responses = resp.responses ++ [untagged]
    %Response{resp | responses: responses}
  end

  def with_status(resp, status, status_line),
    do: %Response{resp | status: status, status_line: status_line}

  def parse_capability(%Response{status: :ok} = resp) do
    resp
    |> first_untagged_response_text
    |> String.split("\r\n")
    |> Enum.filter(fn line -> String.starts_with?(line, "* CAPABILITY ") end)
    |> case do
      [head | _] ->
        String.slice(head, 13..-1)
        |> String.split(" ")
        |> Enum.filter(fn w -> w != "" end)
    end
  end

  def parse_appended_message_uid(%Response{
        status: :ok,
        status_line: status_line,
        req: %Request{tag: tag}
      }) do
    pattern = Regex.compile!("^#{tag} OK.*APPENDUID \\d+ (\\d+)")

    case Regex.run(pattern, status_line, capture: :all_but_first) do
      match when is_list(match) -> Enum.at(match, 0)
    end
  end

  def parse_search_results(%Response{status: :ok} = resp, mailbox, uid_validity) do
    line =
      resp
      |> first_untagged_response_text
      |> String.trim_trailing

    if String.starts_with?(line, "* SEARCH ") do
      String.slice(line, 8..-1)
      |> String.split(" ")
      |> Enum.filter(fn id -> id != "" end)
      |> Enum.map(fn id -> {uid_validity, mailbox, id} end)
    else
      []
    end
  end

  def parse_fetch_headers(%Response{status: :ok} = resp) do
    resp
    |> first_untagged_response_text
    |> parse_as_headers_list
  end

  def parse_as_headers_list(msg) do
    with {list, _} <- :mimemail.parse_headers(msg) do
      list
    end
  end

  defp first_untagged_response_text(%Response{responses: responses}) do
    responses
    |> Enum.filter(fn x ->
      case x do
        {:untagged, _} -> true
        {:untagged, _, {:literal, _size, _v}} -> true
        _ -> false
      end
    end)
    |> Enum.at(0)
    |> case do
      {:untagged, v} -> v
      {:untagged, _, {:literal, _size, v}} -> v
    end
  end
end
