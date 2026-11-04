class SearchSession < ApplicationRecord
  attribute :history, :json, default: -> { [] }
  attribute :preferences, :json, default: -> { {} }
  attribute :results, :json, default: -> { [] }
  attribute :follow_up_questions, :json, default: -> { [] }

  has_many :shortlist_entries, dependent: :delete_all

  scope :with_history, -> { where("JSON_LENGTH(history) > 0") }

  def matching_results
    results.select do |school|
      GuidedSearch::EvidenceScorer.matches?(criteria: preferences["criteria"], evidence: school["criteria"] || school["evidence"])
    end
  end

  def title
    history.find { |message| message["role"] == "user" }&.fetch("content", nil).presence || "New school search"
  end
end
