json.id resource.id
json.title resource.title
json.status resource.status
# Deliberately NOT the full inbox partial ('api/v1/models/inbox') — that one serializes
# provider_config as-is, which for a WhatsApp Cloud inbox includes the raw Meta api_key and
# webhook_verify_token in plain text. This feature has no reason to expose channel credentials
# to whoever can call this endpoint, so it only returns what the wizard actually needs.
json.inbox do
  json.id resource.inbox.id
  json.name resource.inbox.name
end
json.sender do
  json.partial! 'api/v1/models/agent', formats: [:json], resource: resource.sender if resource.sender.present?
end
json.message resource.template_body_text
json.template_name resource.template_name
json.template_namespace resource.template_namespace
json.template_language resource.template_language
json.column_mapping resource.column_mapping
json.scheduled_at resource.scheduled_at&.to_i
json.total_recipients resource.total_recipients
json.sent_count resource.sent_count
json.failed_count resource.failed_count
if resource.failed_rows.attached?
  json.failed_rows_url Rails.application.routes.url_helpers.rails_blob_path(resource.failed_rows, only_path: true)
else
  json.failed_rows_url nil
end
json.created_at resource.created_at
json.updated_at resource.updated_at
