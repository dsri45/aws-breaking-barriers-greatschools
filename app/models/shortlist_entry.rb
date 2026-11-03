class ShortlistEntry < ApplicationRecord
  SCHOOL_ID = /\A[a-zA-Z0-9_-]{1,100}\z/

  belongs_to :search_session
  validates :school_id, format: { with: SCHOOL_ID }
end
