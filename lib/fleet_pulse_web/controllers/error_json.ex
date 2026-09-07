defmodule FleetPulseWeb.ErrorJSON do
  @moduledoc """
  The body every failed JSON request gets back.

  Phoenix's default is `%{errors: %{detail: "Internal Server Error"}}` — true, and useless to both
  sides: the customer has nothing to quote and the operator nothing to search. Every response now
  carries `traceId`, the correlation id Kong minted at the edge and `Plug.RequestId` adopted, which
  is the one string that leads from "my delivery failed at 14:02" to the line that says why.

  `errors.detail` stays where it is. It is additive on purpose: the shape is already asserted by
  callers and tests, and a correlation id is not a reason to break them.
  """

  @typedoc "Standard JSON error payload format."
  @type error_response :: %{errors: %{detail: String.t()}, traceId: String.t()}

  @spec render(String.t(), map()) :: error_response()
  def render("500.json", _assigns) do
    return_payload(
      "something went wrong handling this request. No dispatch, assignment or location was " <>
        "changed unless a previous response said so."
    )
  end

  def render(template, _assigns) do
    return_payload(Phoenix.Controller.status_message_from_template(template))
  end

  @spec return_payload(String.t()) :: error_response()
  defp return_payload(detail) do
    %{errors: %{detail: detail}, traceId: trace_id()}
  end

  @spec trace_id() :: String.t()
  defp trace_id do
    case Logger.metadata()[:request_id] do
      id when is_binary(id) and id != "" -> id
      _absent -> "-"
    end
  end
end
