defmodule FleetPulse.Observability.LogFormatterTest do
  use ExUnit.Case, async: true

  alias FleetPulse.Observability.LogFormatter

  @kong_id "8f3a1c2e-4b5d-6e7f-8a9b-0c1d2e3f4a5b"
  @plug_id "GDzZ0nlWt5aVQwsAAAKB"
  @midnight 1_757_400_000_123_456

  defp line(level, message, metadata) do
    level
    |> LogFormatter.format(message, nil, metadata)
    |> IO.iodata_to_binary()
  end

  describe "the correlation id" do
    test "survives a plain grep as a bare substring, which trace_test.sh depends on" do
      for id <- [@kong_id, @plug_id] do
        text =
          line(:info, "gRPC shipping.v1.ShippingService/EstimateShippingOptions",
            time: @midnight,
            request_id: id
          )

        assert String.contains?(text, id)
        assert Jason.decode!(text)["request_id"] == id
      end
    end

    test "is null, not absent, when the caller carried none" do
      body = :warning |> line("no id here", time: @midnight) |> Jason.decode!()

      assert Map.has_key?(body, "request_id")
      assert body["request_id"] == nil
    end
  end

  describe "the line" do
    test "is one JSON object, newline terminated" do
      text = line(:info, "hello", time: @midnight, request_id: @kong_id)

      assert String.ends_with?(text, "\n")
      assert text |> String.trim_trailing("\n") |> String.split("\n") |> length() == 1
    end

    test "stays one line when the message itself carries newlines and quotes" do
      text = line(:error, ~s(said "hello"\nand then stopped), time: @midnight)

      assert text |> String.trim_trailing("\n") |> String.split("\n") |> length() == 1
      assert Jason.decode!(text)["message"] == ~s(said "hello"\nand then stopped)
    end

    test "carries a timestamp, a level, a message and the source" do
      body =
        :info
        |> line("assigned", time: @midnight, mfa: {FleetPulse.Dispatch, :assign, 2})
        |> Jason.decode!()

      assert body["timestamp"] == "2025-09-09T06:40:00.123456Z"
      assert body["level"] == "info"
      assert body["message"] == "assigned"
      assert body["logger"] == "FleetPulse.Dispatch.assign/2"
    end

    test "names the module, then the application, when there is no mfa" do
      assert Jason.decode!(line(:info, "x", module: FleetPulse.Repo))["logger"] ==
               "FleetPulse.Repo"

      assert Jason.decode!(line(:info, "x", application: :fleet_pulse))["logger"] ==
               "fleet_pulse"

      assert Jason.decode!(line(:info, "x", []))["logger"] == "unknown"
    end
  end

  describe "the structured context" do
    test "is kept, one JSON key per metadata key" do
      body =
        :info
        |> line("dispatched", time: @midnight, order_number: "ORD-888", attempt: 2, ok: true)
        |> Jason.decode!()

      assert body["order_number"] == "ORD-888"
      assert body["attempt"] == 2
      assert body["ok"] == true
    end

    test "renders terms JSON cannot carry rather than dropping them" do
      body =
        :error
        |> line("boom", time: @midnight, pid: self(), file: ~c"lib/x.ex", domain: [:elixir])
        |> Jason.decode!()

      assert body["pid"] == inspect(self())
      assert body["file"] == "lib/x.ex"
      assert body["domain"] == ["elixir"]
    end

    test "cannot shadow a required field" do
      body = :info |> line("real", time: @midnight, message: "impostor") |> Jason.decode!()

      assert body["message"] == "real"
    end
  end

  test "a message nothing can encode still produces a line" do
    body = :info |> line({:not, :chardata}, []) |> Jason.decode!()

    assert body["level"] == "info"
    assert body["formatter_error"] =~ "FunctionClauseError"
  end

  test "is the formatter Logger is actually configured with" do
    assert Application.fetch_env!(:logger, :default_formatter)[:format] ==
             {LogFormatter, :format}
  end
end
