class SearchSession < ApplicationRecord
  attribute :history, :json, default: -> { [] }
  attribute :preferences, :json, default: -> { {} }
  attribute :results, :json, default: -> { [] }
  attribute :follow_up_questions, :json, default: -> { [] }

  has_many :shortlist_entries, dependent: :delete_all
end
