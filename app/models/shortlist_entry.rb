class ShortlistEntry < ApplicationRecord
  SCHOOL_ID = /\A(?=.{1,100}\z)[a-zA-Z0-9_-]+(?: [a-zA-Z0-9_-]+)*\z/

  belongs_to :search_session
  validates :school_id, format: { with: SCHOOL_ID }
end
