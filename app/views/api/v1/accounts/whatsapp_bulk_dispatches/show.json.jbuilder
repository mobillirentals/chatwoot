json.partial! 'api/v1/models/whatsapp_bulk_dispatch', formats: [:json], resource: @dispatch

# Only the detail view needs the row-by-row breakdown — index stays light since it's what
# renders the whole campaign list.
if @preview_recipients
  # Preview rows (see #show) aren't real Recipient records yet, so total_recipients — normally
  # only set once DispatchService runs — is overridden here so the summary cards above aren't
  # stuck at 0 while the operator is just looking ahead at who's scheduled to receive it.
  json.total_recipients @preview_recipients.size
  json.recipients @preview_recipients.each_with_index.to_a do |(row, index)|
    json.id "preview-#{index}"
    json.phone_number row[:phone_number]
    json.status 'pending'
    json.variables row[:variables]
    json.error_message nil
    json.sent_at nil
  end
else
  json.recipients @dispatch.recipients.order(:id) do |recipient|
    json.id recipient.id
    json.phone_number recipient.phone_number
    json.status recipient.status
    json.variables recipient.variables
    json.error_message recipient.error_message
    json.sent_at recipient.sent_at
  end
end
