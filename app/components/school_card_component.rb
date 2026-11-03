# A ranked result card: illustration + save, name and type, GreatSchools-style
# x/10 rating (or "No rating yet" when the field is null), reviews, the agent's
# "Good fit if..." line, the per-criterion evidence checklist, and actions.
class SchoolCardComponent < ViewComponent::Base
  ENTITY_LABELS = { "public" => "Public", "charter" => "Charter", "private" => "Private" }.freeze

  def initialize(school:, selected: false)
    @school = school
    @selected = selected
  end

  def meta
    [ ENTITY_LABELS.fetch(@school.entity_type, @school.entity_type.to_s.titleize),
      "Grades #{@school.grades}",
      "#{@school.distance_mi} mi" ].join(" · ")
  end

  def stars
    full = @school.avg_review_rating.to_f.round
    ("★" * full) + ("☆" * (5 - full))
  end

  def card_classes
    base = "flex gap-[18px] rounded-2xl bg-white p-4"
    @selected ? "#{base} border-2 border-navy shadow-[0_2px_10px_rgba(31,59,87,0.12)]" : "#{base} border border-line"
  end

  def rating_classes
    @selected ? "bg-navy" : "bg-pin"
  end

  def data_date
    dates = @school.criteria.filter_map(&:as_of)
    return "No dated data" if dates.empty?
    min, max = dates.minmax
    min.year == max.year ? "Data from #{max.strftime('%b %Y')}" : "Data from #{min.year} to #{max.year}"
  end
end
