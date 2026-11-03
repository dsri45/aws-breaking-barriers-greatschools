module GuidedSearch
  class DemoSearch
    def call(preferences:)
      [{
        id: "demo-woodstock-stem",
        name: "Woodstock STEM Academy (synthetic)",
        latitude: 34.1015,
        longitude: -84.5194,
        evidence: [{ criterion: "STEM", status: "confirmed", source: "Synthetic demo fixture" }]
      }]
    end
  end
end
