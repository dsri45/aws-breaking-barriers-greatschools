class SchoolCardComponent < ViewComponent::Base
  ENTITY_LABELS = { "public" => "Public district", "charter" => "Public charter", "private" => "Private school" }.freeze
  LEVEL_LABELS = { "p" => "Pre-K", "e" => "Elementary school", "m" => "Middle school", "h" => "High school" }.freeze
  GRADE_LABELS = { "PK" => "Pre-K", "K-5" => "Elementary school", "6-8" => "Middle school", "9-12" => "High school" }.freeze

  def initialize(school:, selected: false, allow_saving: false, show_shortlist: false, allow_comparison: false)
    @school = school
    @allow_saving = allow_saving
    @show_shortlist = show_shortlist
    @allow_comparison = allow_comparison
  end

  def profile
    @profile ||= SchoolProfile.new(@school, @school.profile.presence || SchoolProfile.seed_schools[@school.school_id] || {})
  end

  def grade_labels
    levels = Array(profile.source["level_codes"])
    return levels.map { |level| LEVEL_LABELS.fetch(level, level) } if levels.any?

    @school.grades.to_s.tr("–", "-").split(",").map do |grades|
      GRADE_LABELS.fetch(grades.strip, "Grades #{grades.strip}")
    end
  end

  def rating_factors
    {
      "student_progress_rating" => "Student Progress",
      "test_scores_rating" => "Test Score",
      "college_readiness_rating" => "College Readiness"
    }.filter_map do |key, label|
      rating = profile.source[key]
      [label, rating] unless rating.nil?
    end
  end

  def data_date
    dates = @school.criteria.filter_map(&:as_of)
    return "No dated data" if dates.empty?

    min, max = dates.minmax
    min.year == max.year ? "Data from #{max.strftime('%b %Y')}" : "Data from #{min.year} to #{max.year}"
  end
end
