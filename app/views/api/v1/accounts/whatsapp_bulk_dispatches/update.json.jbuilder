json.partial! 'api/v1/models/whatsapp_bulk_dispatch', formats: [:json], resource: @dispatch
json.valid_count @validation[:valid_rows].size
json.rejected_rows @validation[:rejected_rows]
json.preview @preview
json.whatsapp_check @whatsapp_check
