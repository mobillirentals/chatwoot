# Business hours live in the inbox settings and nowhere else. Tools read them from there rather
# than from a FAQ: an FAQ would freeze the schedule at the moment it was written, and the day
# someone changes the hours in the settings the bot would go on quoting the old ones, silently.
module Captain::Tools::Concerns::BusinessHoursReadable
  DAY_NAMES = %w[domingo segunda terça quarta quinta sexta sábado].freeze

  private

  def hours_configured?(inbox)
    inbox.present? && inbox.working_hours_enabled?
  end

  def open_now?(inbox)
    inbox.working_now?
  end

  # Reads as "segunda a sexta, 08:00–18:00" when the week is uniform, and falls back to listing
  # each day when it is not.
  def schedule_text(inbox)
    days = inbox.weekly_schedule.map { |day| [day['day_of_week'], day_text(day)] }
    open_days = days.reject { |_, text| text.nil? }
    return 'fechado todos os dias' if open_days.empty?

    grouped = group_consecutive(open_days)
    grouped.map { |range, text| "#{range}: #{text}" }.join(' · ')
  end

  def day_text(day)
    return nil if day['closed_all_day']
    return 'aberto 24h' if day['open_all_day']

    "#{clock(day['open_hour'], day['open_minutes'])}–#{clock(day['close_hour'], day['close_minutes'])}"
  end

  def clock(hour, minutes)
    format('%<h>02d:%<m>02d', h: hour.to_i, m: minutes.to_i)
  end

  # Collapses runs of consecutive days that share the same hours, so the model gets
  # "segunda a sexta" instead of five near-identical lines it might garble.
  def group_consecutive(open_days)
    open_days.slice_when { |(day_a, text_a), (day_b, text_b)| day_b != day_a + 1 || text_a != text_b }
             .map { |run| [day_range(run), run.first.last] }
  end

  def day_range(run)
    first = DAY_NAMES[run.first.first]
    return first if run.one?

    "#{first} a #{DAY_NAMES[run.last.first]}"
  end
end
