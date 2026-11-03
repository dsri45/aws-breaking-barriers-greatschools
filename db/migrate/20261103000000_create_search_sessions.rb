class CreateSearchSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :search_sessions do |t|
      t.json :history, null: false
      t.json :preferences, null: false
      t.json :results, null: false
      t.json :follow_up_questions, null: false
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    create_table :shortlist_entries do |t|
      t.references :search_session, null: false, foreign_key: true, index: false
      t.string :school_id, limit: 100, null: false, collation: "utf8mb4_bin"
      t.json :school, null: false
      t.timestamps
      t.index %i[search_session_id school_id], unique: true
    end
  end
end
