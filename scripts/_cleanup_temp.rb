account = Account.find(ENV.fetch('ACCOUNT_ID', 1).to_i)

# Mensagens importadas
Message.where("source_id LIKE 'octadesk_msg:%'").delete_all
Message.where("source_id LIKE 'octadesk_closed:%'").delete_all
Message.where("source_id LIKE 'octadesk_chat_separator:%'").delete_all

# Conversas importadas
Conversation.where("identifier LIKE 'octadesk:%'").destroy_all

# Contatos importados
Contact.where(account_id: account.id).destroy_all

# Inbox de importação
inbox = Inbox.find_by(account_id: account.id, name: 'OctaDesk - WhatsApp (Importado)')
if inbox
  inbox.channel.destroy
  inbox.destroy
  puts 'Inbox removido.'
end

# Atributos personalizados criados pelo import
CustomAttributeDefinition.where(account_id: account.id,
                                attribute_key: %w[cpf_cnpj source external_reference]).destroy_all

puts 'Limpo.'
