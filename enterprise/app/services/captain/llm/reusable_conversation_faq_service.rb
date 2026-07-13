# Upstream's FAQ generator has no rule against generalising facts that were only ever true for
# one customer. On a real resolved conversation it turned "when do I return my bike?" into "next
# month, on the 17th" — one contract's date, one approval away from becoming the answer given to
# everyone. The pending queue would catch it, but a queue that fills with noise stops being read.
#
# The rules go in front of the parent prompt so that its output-format instructions stay last.
class Captain::Llm::ReusableConversationFaqService < Captain::Llm::ConversationFaqService
  private

  def system_prompt
    "#{reusability_rules}\n#{super}"
  end

  def reusability_rules
    <<~PROMPT
      An FAQ is only worth keeping if its answer holds true for ANY customer who asks the same question.
      Never turn account-specific facts into FAQs: dates, amounts, contract terms, order numbers,
      addresses, or anything else that was only true for this particular customer. If the agent's answer
      would be wrong for the next customer asking the same question, skip it entirely.
      Prefer reusable knowledge: troubleshooting steps, policies, and how things work.
    PROMPT
  end
end
