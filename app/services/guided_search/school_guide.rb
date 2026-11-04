module GuidedSearch
  class SchoolGuide
    VISIT_QUESTIONS = {
      "rating" => "How do teachers support students in the subjects behind this rating?",
      "reviews" => "How does the school gather family feedback and respond to concerns?",
      "sports_programs" => "Which sports are offered for this grade, and when do practices take place?",
      "ib" => "Which IB programme is offered for this grade, and how can families verify availability?",
      "ib_offered" => "Which IB programme is offered for this grade, and how can families verify availability?",
      "class_size" => "What is a typical class size in this grade, and how is extra support provided?",
      "after_school" => "What time does after-school care finish, and how do families enroll?",
      "after_school_clubs" => "Which clubs run after school for this grade, and how can students join?",
      "reading_club" => "Which books does the reading club explore, which grades can join, and when does it meet?",
      "transportation" => "Which transportation options serve our neighborhood?"
    }.freeze
    CONCERN_DESCRIPTIONS = {
      "missing" => "there is no published confirmation yet",
      "partial" => "the published evidence is a partial match",
      "needs_attention" => "the published evidence falls short of this priority"
    }.freeze

    def self.recommendations(preferences:, results:)
      location = preferences["location"].presence
      if results.empty?
        opening = "I couldn’t find matching schools for #{location || 'this search'} in the current dataset."
        keys = EvidenceScorer.required_keys(preferences["criteria"])
        required = Array(preferences["criteria"]).select { |criterion| keys.include?(criterion["key"]) }.pluck("label")
        next_step = if required.any?
          "I need published evidence for #{required.to_sentence} before I can include a school. Missing information does not mean a program is unavailable, but I won't recommend it without confirmation. We can try another location or change the requested priorities."
        else
          "Let's try another city or ZIP, or widen the grade range. The current demo dataset covers a small set of schools."
        end
        return [opening, next_step].join("\n\n")
      end

      count = results.one? ? "one school" : "#{results.size} schools"
      opening = "I found #{count} to explore#{location ? " in #{location}" : ''}. Let's look at what fits your learner and what is worth asking about."
      priorities = Array(preferences["criteria"]).pluck("label").compact_blank
      opening += " I used your priorities of #{priorities.to_sentence}." if priorities.any?
      spotlights = results.first(3).map do |school|
        guide = new(school)
        [school["name"], guide.short_reason, guide.caution, "On a visit, I'd ask “#{guide.visit_questions.first}”"].compact.join("\n")
      end
      closing = "You can open a school's evidence, ask me to explain it in more detail, or select two schools to compare."
      [opening, *spotlights, closing].join("\n\n")
    end

    def initialize(school)
      @school = school
      @evidence = Array(school["criteria"] || school["evidence"])
    end

    def short_reason
      match = confirmed.first
      return "This is an option from your search. Its published evidence does not yet confirm your stated priorities." unless match

      "I'd start with its match for #{label(match).downcase}. #{detail(match)}"
    end

    def caution
      row = concerns.first
      return unless row

      concern_text(row)
    end

    def explanation
      sections = ["Let's take a closer look at #{@school['name']}."]
      facts = [
        ("The record lists grades #{@school['grades']}." if @school["grades"].present?),
        ("Its GreatSchools summary rating is #{@school['summary_rating']}/10." unless @school["summary_rating"].nil?),
        ("Its average community review rating is #{@school['avg_review_rating']}/5." unless @school["avg_review_rating"].nil?)
      ].compact
      sections << facts.join(" ") if facts.any?
      sections << if confirmed.any?
        "Why it made your shortlist\n" + confirmed.first(3).map { |row| "• #{label(row)}. #{detail(row)}" }.join("\n")
      else
        "Its available records do not yet confirm a match to your priorities. I'd use this as a starting point for questions."
      end
      if concerns.any?
        sections << "What I'd check with the school\n" + concerns.first(3).map { |row| "• #{concern_text(row)}" }.join("\n")
      end
      sections << "A question to take on a visit\n#{visit_questions.first}"
      sections.join("\n\n")
    end

    def visit_reply
      ["For a visit to #{@school['name']}, I'd bring a few questions tied to your priorities.",
       visit_questions.map { |question| "• #{question}" }.join("\n"),
       "Ask the school for current examples and availability. The answers can help you decide how this school fits your child's day."].join("\n\n")
    end

    def visit_questions
      questions = (concerns + confirmed).filter_map { |row| VISIT_QUESTIONS[row["key"] || row["criterion"]] }.uniq
      questions.concat([
        "What does a typical day look like for a student in my child's grade?",
        "How do teachers share progress with families and adapt support when a child needs help?"
      ])
      questions.uniq.first(3)
    end

    private

    def confirmed
      @evidence.select { |row| row["status"] == "confirmed" }.sort_by do |row|
        key = row["key"] || row["criterion"]
        key == "reading_club" ? 0 : (%w[level location].include?(key) ? 2 : 1)
      end
    end

    def concerns
      @evidence.select { |row| row["status"].in?(%w[needs_attention partial missing]) }.sort_by do |row|
        %w[needs_attention partial missing].index(row["status"])
      end
    end

    def label(row)
      row["label"] || row["criterion"] || row["key"].to_s.humanize
    end

    def concern_text(row)
      "For #{label(row).downcase}, #{CONCERN_DESCRIPTIONS.fetch(row['status'])}. #{detail(row)}"
    end

    def detail(row)
      text = (row["evidence"] || row["source"]).to_s.strip
      text = "The record provides no further detail" if text.empty?
      text.end_with?(".", "?", "!") ? text : "#{text}."
    end
  end
end
