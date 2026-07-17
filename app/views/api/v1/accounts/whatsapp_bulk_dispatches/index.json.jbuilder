json.array! @dispatches do |dispatch|
  json.partial! 'api/v1/models/whatsapp_bulk_dispatch', formats: [:json], resource: dispatch
end
