defmodule ImapFilter do
  defmodule Rules do
    defmodule Arg do
      defstruct msgid: nil, headers: [], flags: []

      def new({_uidvalidity, _mailbox, _uid} = msgid, headers) do
        %Arg{msgid: msgid, headers: headers}
      end
    end

    def match!(rule_name, args) do
      case apply(Rules, String.to_existing_atom(rule_name), args) do
        true = b -> b
        false = b -> b
        _ -> raise "#{rule_name} did not return a bool"
      end
    end

    def header_regex(%Arg{headers: headers}, header_name, value_pattern) do
      case get_header(headers, header_name) do
        {:ok, header_value} -> Regex.match?(Regex.compile!(value_pattern), header_value)
        :notfound -> false
      end
    end

    defp get_header([], _header_name) do
      :notfound
    end

    defp get_header([head | tail], header_name) do
      case head do
        {^header_name, header_value} -> {:ok, header_value}
        _ -> get_header(tail, header_name)
      end
    end
  end
end
