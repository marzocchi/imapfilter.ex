defmodule ImapFilter.Imap.Response do
  alias ImapFilter.Imap.Response
  alias ImapFilter.Imap.Request

  defstruct status_line: "", status: nil, responses: [], req: nil

  def empty?(%Response{responses: list}), do: Enum.count(list) == 0

  defmodule Parser do
    def parse(%Response{req: %Request{command: command}, status: :ok, responses: []})
        when command != :append,
        do: :empty

    def parse(
          %Response{
            status: :ok,
            req: %Request{command: :uid_fetch, params: [_uid, :fetch_attributes]}
          } = resp
        ) do
      resp
      |> find_first_untagged_response
      |> case do
        {:untagged, v, {:literal, _size, headers_text}} ->
          {parse_flags(v), parse_as_headers_list(headers_text)}
      end
    end

    def parse(
          %Response{
            status: :ok,
            req: %Request{command: :uid_fetch, params: [_uid, :fetch_rfc822_headers]}
          } = resp
        ) do
      resp
      |> find_first_untagged_response
      |> untagged_response_text
      |> parse_as_headers_list
    end

    def parse(%Response{status: :ok, req: %Request{command: :uid_search, params: _query}} = resp) do
      line =
        resp
        |> find_first_untagged_response
        |> untagged_response_text
        |> String.trim_trailing()

      if String.starts_with?(line, "* SEARCH "),
        do:
          String.slice(line, 8..-1)
          |> String.split(" ")
          |> Enum.filter(fn id -> id != "" end),
        else: []
    end

    def parse(%Response{status: :ok, req: %Request{command: :capability}} = resp) do
      resp
      |> find_first_untagged_response
      |> untagged_response_text
      |> String.split("\r\n")
      |> Enum.filter(fn line -> String.starts_with?(line, "* CAPABILITY ") end)
      |> case do
        [head | _] ->
          String.slice(head, 13..-1)
          |> String.split(" ")
          |> Enum.filter(fn w -> w != "" end)
      end
    end

    def parse(%Response{
          status: :ok,
          status_line: status_line,
          req: %Request{command: :append}
        }) do
      pattern = Regex.compile!("APPENDUID \\d+ (\\d+)")

      case Regex.run(pattern, status_line, capture: :all_but_first) do
        match when is_list(match) -> Enum.at(match, 0)
      end
    end

    defp find_first_untagged_response(%Response{responses: responses}) do
      responses
      |> Enum.filter(fn x ->
        case x do
          {:untagged, _} -> true
          {:untagged, _, {:literal, _size, _v}} -> true
          _ -> false
        end
      end)
      |> Enum.at(0)
    end

    defp untagged_response_text({:untagged, v}), do: v
    defp untagged_response_text({:untagged, _v, {:literal, _size, v}}), do: v

    defp parse_flags(v) do
      Regex.run(~r/FLAGS \(([^\)]+)\)/, v, capture: :all_but_first)
      |> case do
        nil -> []
        [match] -> match |> String.split(" ")
      end
      |> Enum.map(fn f ->
        case f do
          "\\Seen" -> :seen
          "\\Deleted" -> :deleted
          "\\Answered" -> :answered
          "\\Flagged" -> :flagged
          "\\Draft" -> :draft
          "\\Recent" -> :recent
          any -> any
        end
      end)
    end

    defp parse_as_headers_list(msg) when is_binary(msg) do
      case :mimemail.parse_headers(msg) do
        {list, ""} ->
          list

        {list, rest} ->
          # FIXME parse_headers wrongly detects start of body wrongly,
          # so as a workaround, since we don't expect a body, we shave
          # off the first line, and re-parse the rest
          [_trashy_first_line, rest_as_text] = String.split(rest, "\r\n", parts: 2)
          list ++ parse_as_headers_list(rest_as_text)
      end
    end

    defp parse_as_headers_list(_msg), do: []
  end

  # TODO naming
  def append_response(resp, untagged) do
    responses = resp.responses ++ [untagged]
    %Response{resp | responses: responses}
  end

  def with_status(resp, status, status_line),
    do: %Response{resp | status: status, status_line: status_line}
end
