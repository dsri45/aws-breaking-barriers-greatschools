# One row of a school card's criteria checklist: an icon for the status
# (confirmed / partial / needs_attention / missing), the criterion, its
# evidence, and the date of the data behind it.
class CriterionRowComponent < ViewComponent::Base
  STATUS_TEXT = {
    "confirmed" => "Confirmed",
    "partial" => "Partly meets",
    "needs_attention" => "Needs your attention",
    "missing" => "No data"
  }.freeze

  def initialize(evidence:)
    @evidence = evidence
  end

  def status = @evidence.status
  def status_text = STATUS_TEXT.fetch(status)
  def stale? = @evidence.as_of.present? && @evidence.as_of < 12.months.ago.to_date
end
