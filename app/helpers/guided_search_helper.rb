module GuidedSearchHelper
  def google_maps_location(location)
    "https://www.google.com/maps/search/?#{ { api: 1, query: "#{location.lat},#{location.lon}" }.to_query }"
  end

  def school_review_summary(school)
    [("#{school.avg_review_rating}/5" if school.avg_review_rating),
     (pluralize(school.review_count, "review") if school.review_count)].compact.join(" · ").presence || "No data"
  end

  # Wraps the phrases the agent extracted from the parent's question in a
  # green highlight, so the parent can see what was understood.
  def highlight_phrases(text, phrases)
    return text if phrases.blank?
    pattern = Regexp.union(phrases)
    safe_join(text.split(/(#{pattern})/).map do |part|
      phrases.include?(part) ? tag.mark(part, class: "rounded bg-highlight px-1 py-px text-ink") : part
    end)
  end
end
