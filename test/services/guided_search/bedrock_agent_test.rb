require "test_helper"

module GuidedSearch
  class BedrockAgentTest < ActiveSupport::TestCase
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
  end
end
