# The agent's clarifying / trade-off question with tap-to-answer options.
# Rendered when the agent calls its `ask_clarifying_question` tool.
class QuestionCardComponent < ViewComponent::Base
  def initialize(text:, options:, hint: nil, selected: nil)
    @text = text
    @options = options
    @hint = hint
    @selected = selected
  end

  def option_classes(option)
    base = "h-9 rounded-full px-3.5 text-sm"
    if option == @selected
      "#{base} border-[1.5px] border-navy bg-navy font-medium text-white"
    else
      "#{base} border border-line-2 bg-white text-ink hover:border-navy"
    end
  end
end
