json.conversations do
  json.array! @conversations do |conversation|
    json.id conversation.id
    json.display_id conversation.display_id
    json.deleted_at conversation.deleted_at
    json.inbox do
      json.id conversation.inbox.id
      json.name conversation.inbox.name
    end
    json.contact do
      json.id conversation.contact.id
      json.name conversation.contact.name
    end
  end
end

json.meta do
  json.current_page @conversations.current_page
  json.total_entries @conversations.total_count
  json.per_page @conversations.limit_value
end
