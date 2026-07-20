json.partial! 'api/v1/models/whatsapp_bulk_dispatch', formats: [:json], resource: @dispatch

# Only the detail view needs the row-by-row breakdown — index stays light since it's what
# renders the whole campaign list.
json.recipients @dispatch.recipients.order(:id) do |recipient|
  json.id recipient.id
  json.phone_number recipient.phone_number
  json.status recipient.status
  json.variables recipient.variables
  json.error_message recipient.error_message
  json.sent_at recipient.sent_at
end
