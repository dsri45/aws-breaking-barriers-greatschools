module GuidedSearchHelper
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
