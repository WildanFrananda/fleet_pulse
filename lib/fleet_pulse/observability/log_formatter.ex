defmodule FleetPulse.Observability.LogFormatter do
  @moduledoc """
  One line per event, one JSON object, on stdout.
  """

  @dropped [
    :request_id,
    :time,
    :mfa,
    :module,
    :function,
    :gl,
    :report_cb,
    :erl_level,
    :ansi_color
  ]
  @unknown_source "unknown"

  @spec format(Logger.level(), IO.chardata(), Logger.Formatter.date_time_ms(), keyword()) ::
          IO.chardata()
  def format(level, message, _timestamp, metadata) do
    [Jason.encode_to_iodata!(event(level, message, metadata)), ?\n]
  rescue
    error -> fallback(level, message, error)
  end

  @spec event(Logger.level(), IO.chardata(), keyword()) :: %{optional(String.t()) => term()}
  defp event(level, message, metadata) do
    metadata
    |> Keyword.drop(@dropped)
    |> Map.new(fn {key, value} -> {encodable_key(key), encodable(value)} end)
    |> Map.merge(%{
      "timestamp" => timestamp(metadata),
      "level" => Atom.to_string(level),
      "message" => IO.chardata_to_string(message),
      "logger" => source(metadata),
      "request_id" => request_id(metadata)
    })
  end

  @spec fallback(Logger.level(), IO.chardata(), Exception.t()) :: IO.chardata()
  defp fallback(level, message, error) do
    body = %{
      "timestamp" => DateTime.to_iso8601(DateTime.utc_now()),
      "level" => Atom.to_string(level),
      "message" => inspect(message, limit: 50, printable_limit: 4096),
      "logger" => inspect(__MODULE__),
      "request_id" => nil,
      "formatter_error" => inspect(error)
    }

    [Jason.encode_to_iodata!(body), ?\n]
  end

  @spec timestamp(keyword()) :: String.t()
  defp timestamp(metadata), do: metadata |> Keyword.get(:time) |> to_iso8601()

  @spec to_iso8601(integer() | nil) :: String.t()
  defp to_iso8601(microseconds) when is_integer(microseconds) do
    microseconds |> DateTime.from_unix!(:microsecond) |> DateTime.to_iso8601()
  end

  defp to_iso8601(_absent), do: DateTime.to_iso8601(DateTime.utc_now())

  @spec request_id(keyword()) :: String.t() | nil
  defp request_id(metadata), do: metadata |> Keyword.get(:request_id) |> to_id()

  @spec to_id(term()) :: String.t() | nil
  defp to_id(id) when is_binary(id), do: id
  defp to_id(nil), do: nil
  defp to_id(other), do: inspect(other)

  @spec source(keyword()) :: String.t()
  defp source(metadata) do
    source(
      Keyword.get(metadata, :mfa),
      Keyword.get(metadata, :module),
      Keyword.get(metadata, :application)
    )
  end

  @spec source(mfa() | nil, module() | nil, atom() | nil) :: String.t()
  defp source({module, function, arity}, _module, _application),
    do: "#{inspect(module)}.#{function}/#{arity}"

  defp source(_mfa, module, _application) when is_atom(module) and not is_nil(module),
    do: inspect(module)

  defp source(_mfa, _module, application) when is_atom(application) and not is_nil(application),
    do: Atom.to_string(application)

  defp source(_mfa, _module, _application), do: @unknown_source

  @spec encodable(term()) :: term()
  defp encodable(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
       do: value

  defp encodable(value) when is_atom(value), do: Atom.to_string(value)
  defp encodable([]), do: []

  defp encodable(value) when is_list(value),
    do: encodable_list(value, :io_lib.printable_unicode_list(value))

  defp encodable(value) when is_map(value) and not is_struct(value),
    do: Map.new(value, fn {key, inner} -> {encodable_key(key), encodable(inner)} end)

  defp encodable(value), do: inspect(value, limit: 25, printable_limit: 1024)

  @spec encodable_list(list(), boolean()) :: String.t() | list()
  defp encodable_list(value, true), do: List.to_string(value)
  defp encodable_list(value, false), do: Enum.map(value, &encodable/1)

  @spec encodable_key(term()) :: String.t()
  defp encodable_key(key) when is_binary(key), do: key
  defp encodable_key(key) when is_atom(key), do: Atom.to_string(key)
  defp encodable_key(key), do: inspect(key)
end
