require "test_helper"

module GuidedSearch
  class BedrockAgentTest < ActiveSupport::TestCase
    test "stated needs become requirements instead of optional recommendations" do
      assert_equal "require", BedrockAgent.criterion_for("Sports programs")["importance"]
      assert_equal "require", BedrockAgent.criterion_for("After-school clubs")["importance"]
    end

    test "accepts any grade after a grade question and searches the existing ZIP" do
      agent = BedrockAgent.new(extractor: NeedsExtractor.new(bedrock: Object.new))
      preferences = {
        "location" => "98031",
        "grade_level" => nil,
        "needs" => ["Sports programs"],
        "query" => "Schools with sports programs in 98031",
        "filters" => { "level_codes" => "m" }
      }
      history = [{ "role" => "assistant", "content" => "What grade level are you looking for?" }]

      ["any", "any grade level"].each do |answer|
        guidance = agent.call(message: answer, history: history, preferences: preferences)

        assert guidance.fetch(:search)
        assert_empty guidance.fetch(:follow_up_questions)
        assert_equal "Any grade", guidance.dig(:preferences, "grade_level")
        assert_equal({ "zipcode" => "98031" }, guidance.dig(:preferences, "filters"))
        assert_equal preferences["query"], guidance.dig(:preferences, "query")
        assert_match(/98031 in the current dataset/, agent.reply(guidance: guidance, results: []))
      end
    end

    test "a reading club request survives an incorrect arts extraction and has a readable grade label" do
      agent = agent_with_extraction("needs" => ["Arts programs", "Strong reading and writing", "After-school clubs"],
        "location" => "FL", "grade_level" => "e", "filters" => { "state" => "FL", "level_codes" => "e" },
        "query" => "Elementary arts programs in Florida")
      guidance = agent.call(message: "give me an elementary school with a reading club in FL", history: [], preferences: {})
      assert guidance[:search]
      assert_equal ["Reading club"], guidance.dig(:preferences, "needs")
      assert_equal "Elementary school", guidance.dig(:preferences, "grade_level")
      assert_equal %w[level reading_club], guidance.dig(:preferences, "criteria").pluck("key")
      assert_equal ["Elementary school", "Reading club"], guidance.dig(:preferences, "criteria").pluck("label")
      assert_match(/reading club/, guidance.dig(:preferences, "query"))
      assert_equal "e", guidance.dig(:preferences, "filters", "level_codes")
    end

    test "explicit arts alongside a book club remain a separate preference after reading" do
      agent = agent_with_extraction("needs" => ["Arts programs"], "location" => "FL", "grade_level" => "e",
        "filters" => { "state" => "FL", "level_codes" => "e" })
      guidance = agent.call(message: "An elementary school with a book club and arts in FL", history: [], preferences: {})
      assert_equal ["Reading club", "Arts programs"], guidance.dig(:preferences, "needs")
    end

    test "a negated reading club mention does not add a reading requirement" do
      agent = agent_with_extraction("needs" => ["Arts programs"], "location" => "FL", "grade_level" => "e",
        "filters" => { "state" => "FL", "level_codes" => "e" })
      guidance = agent.call(message: "I want arts, not a reading club", history: [], preferences: {})
      assert_equal ["Arts programs"], guidance.dig(:preferences, "needs")
    end

    private

    def agent_with_extraction(extraction)
      client = Aws::BedrockRuntime::Client.new(region: "us-east-1", stub_responses: {
        converse: {
          output: { message: { role: "assistant", content: [{ text: extraction.to_json }] } },
          stop_reason: "end_turn", usage: { input_tokens: 10, output_tokens: 10, total_tokens: 20 }, metrics: { latency_ms: 1 }
        }
      })
      BedrockAgent.new(extractor: NeedsExtractor.new(bedrock: Bedrock.new(client: client)))
    end
  end
end
