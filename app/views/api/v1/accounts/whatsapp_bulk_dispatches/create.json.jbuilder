json.partial! 'api/v1/models/whatsapp_bulk_dispatch', formats: [:json], resource: @dispatch
json.headers @headers
json.suggested_mapping @suggested_mapping
json.suggested_phone_column @suggested_phone_column
