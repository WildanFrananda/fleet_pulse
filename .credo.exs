%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      strict: true,
      checks: %{
        extra: [
          # PAKSA @spec di tiap fungsi publik
          {Credo.Check.Readability.Specs, []}
        ]
      }
    }
  ]
}
