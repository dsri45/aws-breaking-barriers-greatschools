# A ranked result card: illustration + save, name and type, GreatSchools-style
# x/10 rating (or "No rating yet" when the field is null), reviews, the agent's
# "Good fit if..." line, the per-criterion evidence checklist, and actions.
class SchoolCardComponent < ViewComponent::Base
  ENTITY_LABELS = { "public" => "Public", "charter" => "Charter", "private" => "Private" }.freeze

  def initialize(school:, selected: false, allow_saving: false, show_shortlist: false, allow_comparison: false)
    @school = school
    @selected = selected
    @allow_saving = allow_saving
    @show_shortlist = show_shortlist
    @allow_comparison = allow_comparison
  end

  def meta
    [
      ENTITY_LABELS.fetch(@school.entity_type, @school.entity_type.to_s.titleize).presence,
      ("Grades #{@school.grades}" if @school.grades.present?),
      ("#{@school.distance_mi} mi" if @school.distance_mi)
    ].compact.join(" · ")
  end

  def card_classes
    base = "search-school-card flex flex-wrap gap-[18px] rounded-2xl border border-line bg-white p-4"
    @selected ? "#{base} search-school-card-selected" : base
  end

  def data_date
    dates = @school.criteria.filter_map(&:as_of)
    return "No dated data" if dates.empty?
    min, max = dates.minmax
    min.year == max.year ? "Data from #{max.strftime('%b %Y')}" : "Data from #{min.year} to #{max.year}"
  end
end
