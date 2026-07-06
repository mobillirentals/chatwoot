# frozen_string_literal: true

# =============================================================================
# Migração OctaDesk → Chatwoot (somente Chats fechados do WhatsApp)
# Modo: Uma conversa unificada por contato (Option B)
#
# Uso (local):
#   docker compose exec rails bundle exec rails runner scripts/octadesk_import.rb
#
# Opções via ENV:
#   LIMIT=5        Importar apenas os N primeiros chats (para teste)
#   DRY_RUN=true   Imprime o que faria sem gravar nada no banco
#   ACCOUNT_ID=1   ID da conta no Chatwoot (padrão: 1)
#
# Para limpar dados de teste anteriores (formato antigo):
#   docker compose exec rails bundle exec rails runner \
#     "Conversation.where(\"identifier LIKE 'octadesk:%'\").destroy_all; puts 'Limpo.'"
# =============================================================================

require 'rest-client'
require 'json'

# ─── Configuração ────────────────────────────────────────────────────────────

OCTADESK_API_KEY  = ENV.fetch('OCTADESK_API_KEY')  { raise 'Defina OCTADESK_API_KEY no .env' }
OCTADESK_BASE_URL = ENV.fetch('OCTADESK_BASE_URL') { raise 'Defina OCTADESK_BASE_URL no .env' }
ACCOUNT_ID   = (ENV['ACCOUNT_ID'] || 1).to_i
IMPORT_LIMIT = (ENV['LIMIT'] || 0).to_i   # 0 = sem limite
DRY_RUN      = ENV['DRY_RUN'] == 'true'
INBOX_NAME   = 'OctaDesk - WhatsApp (Importado)'
PAGE_SIZE    = 100
SLEEP_BETWEEN_REQUESTS = 0.3
# Campos do OctaDesk que não devem ser mapeados para custom_attributes do Chatwoot
# c_digo = forma normalizada de "código" (caractere especial → _)
OCTA_SKIP_FIELDS = %w[cpf tag company_name nome_empresa empresa c_digo código].freeze

# ─── Estado global (em memória para dedup) ───────────────────────────────────

$account           = nil
$inbox             = nil
$companies_map     = {}  # octadesk_org_id    → Company.id
$contacts_map      = {}  # octadesk_contact_id → Contact (objeto)
$agents_map        = {}  # email              → User.id
$conversations_map = {}  # octadesk_contact_id → Conversation (objeto)
$stats             = { imported: 0, skipped: 0, errors: [] }

# ─── Helpers de log ──────────────────────────────────────────────────────────

def log(msg)
  puts "[#{Time.current.strftime('%H:%M:%S')}] #{msg}"
end

def dry(msg)
  puts "  [DRY_RUN] #{msg}" if DRY_RUN
end

# ─── Cliente OctaDesk ────────────────────────────────────────────────────────

module Octa
  HEADERS = {
    'X-API-KEY'    => OCTADESK_API_KEY,
    'Content-Type' => 'application/json',
    'Accept'       => 'application/json'
  }.freeze

  MAX_RETRIES = 5

  def self.get(path, params = {})
    retries = 0
    begin
      url      = "#{OCTADESK_BASE_URL}#{path}"
      response = RestClient.get(url, HEADERS.merge(params: params))
      JSON.parse(response.body)
    rescue RestClient::TooManyRequests
      retries += 1
      raise if retries > MAX_RETRIES

      wait = 2**retries
      log("Rate limit OctaDesk — aguardando #{wait}s...")
      sleep wait
      retry
    rescue RestClient::ServerBrokeConnection,
           RestClient::RequestTimeout,
           RestClient::InternalServerError,
           RestClient::BadGateway,
           RestClient::ServiceUnavailable,
           RestClient::GatewayTimeout,
           SocketError,
           Errno::ECONNREFUSED,
           Errno::ETIMEDOUT,
           Net::OpenTimeout,
           Net::ReadTimeout
      retries += 1
      raise if retries > MAX_RETRIES

      wait = 2**retries
      log("Erro de rede/servidor em #{path} (tentativa #{retries}/#{MAX_RETRIES}) — aguardando #{wait}s...")
      sleep wait
      retry
    rescue RestClient::Exception => e
      log("ERRO na requisição #{path}: #{e.message}")
      raise
    end
  end

  def self.fetch_closed_chats
    chats = []
    page  = 1

    loop do
      log("Buscando chats fechados — página #{page}...")
      data = get('/chat', limit: PAGE_SIZE, page: page,
                          'filters[0][property]' => 'status',
                          'filters[0][operator]' => 'eq',
                          'filters[0][value]'    => 'closed')

      batch = data.is_a?(Array) ? data : (data['data'] || data['chats'] || [])
      break if batch.empty?

      chats.concat(batch)
      log("  → #{batch.size} chats recebidos (total acumulado: #{chats.size})")

      break if IMPORT_LIMIT > 0 && chats.size >= IMPORT_LIMIT
      break if batch.size < PAGE_SIZE

      page += 1
      sleep SLEEP_BETWEEN_REQUESTS
    end

    IMPORT_LIMIT > 0 ? chats.first(IMPORT_LIMIT) : chats
  end

  def self.fetch_chat(chat_id)
    sleep SLEEP_BETWEEN_REQUESTS
    get("/chat/#{chat_id}")
  end

  def self.fetch_contact(contact_id)
    sleep SLEEP_BETWEEN_REQUESTS
    get("/contacts/#{contact_id}")
  rescue StandardError
    nil
  end

  def self.fetch_messages(chat_id, page: 1)
    sleep SLEEP_BETWEEN_REQUESTS
    data = get("/chat/#{chat_id}/messages", limit: PAGE_SIZE, page: page)
    data.is_a?(Array) ? data : (data['data'] || data['messages'] || [])
  end
end

# ─── Setup: Inbox e CustomAttributeDefinitions ───────────────────────────────

def setup!
  $account = Account.find(ACCOUNT_ID)
  log("Conta: #{$account.name} (id=#{$account.id})")

  existing_inbox = Inbox.where(
    account_id: $account.id,
    name: INBOX_NAME,
    channel_type: 'Channel::Api'
  ).first

  if existing_inbox
    $inbox = existing_inbox
    # Garante que auto_assignment está desligado (evita mensagens de atribuição automática)
    $inbox.update_columns(enable_auto_assignment: false) if $inbox.enable_auto_assignment?
    log("Inbox já existe: #{$inbox.name} (id=#{$inbox.id})")
  elsif DRY_RUN
    log("[DRY_RUN] Criaria inbox '#{INBOX_NAME}'")
    $inbox = Inbox.new(id: 0, name: INBOX_NAME)
  else
    channel = Channel::Api.create!(account: $account)
    $inbox  = Inbox.create!(
      account_id:            $account.id,
      name:                  INBOX_NAME,
      channel:               channel,
      enable_auto_assignment: false  # sem atribuição automática no inbox de importação
    )
    log("Inbox criado: #{$inbox.name} (id=#{$inbox.id})")
  end

  ensure_contact_attr('cpf_cnpj',     'CPF/CNPJ')
  ensure_contact_attr('source',       'Origem')
  ensure_contact_attr('id_octadesk',  'ID OctaDesk')

  User.joins(:account_users).where(account_users: { account_id: $account.id }).each do |u|
    $agents_map[u.email.downcase] = u.id
  end
  log("Agentes em cache: #{$agents_map.size}")
end

def ensure_contact_attr(key, display_name)
  return if CustomAttributeDefinition.exists?(
    account_id:      $account.id,
    attribute_key:   key,
    attribute_model: CustomAttributeDefinition.attribute_models[:contact_attribute]
  )

  return dry("Criaria CustomAttributeDefinition '#{key}'") if DRY_RUN

  CustomAttributeDefinition.create!(
    account_id:            $account.id,
    attribute_key:         key,
    attribute_display_name: display_name,
    attribute_display_type: CustomAttributeDefinition.attribute_display_types[:text],
    attribute_model:       :contact_attribute
  )
  log("CustomAttribute criado: #{key}")
end

def ensure_label(title)
  Label.find_or_create_by!(account_id: $account.id, title: title.downcase) do |l|
    l.color          = '#1f93ff'
    l.show_on_sidebar = true
  end
rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
  # já existe
end

# ─── Company ─────────────────────────────────────────────────────────────────

def find_or_create_company(org)
  return nil if org.nil? || org['id'].blank?

  octa_id = org['id'].to_s
  return $companies_map[octa_id] if $companies_map.key?(octa_id)

  company = Company.where(account_id: $account.id)
                   .find_by("custom_attributes->>'octadesk_org_id' = ?", octa_id)

  unless company
    dry("Criaria Company '#{org['name']}'")
    unless DRY_RUN
      company = Company.create!(
        account_id:        $account.id,
        name:              org['name'].presence || 'Sem nome',
        custom_attributes: { 'octadesk_org_id' => octa_id }
      )
    end
  end

  $companies_map[octa_id] = company&.id
  company&.id
end

# ─── Formatação de nome ───────────────────────────────────────────────────────

# Conectivos que ficam em minúsculo no meio do nome (padrão português)
NAME_CONNECTORS = %w[da de do dos das di e em com para por].freeze

# Converte "DAVI RODRIGUES DOS SANTOS" → "Davi Rodrigues dos Santos"
def format_name(full_name)
  return 'Contato OctaDesk' if full_name.blank?

  full_name.strip.split(/\s+/).each_with_index.map do |word, i|
    i > 0 && NAME_CONNECTORS.include?(word.downcase) ? word.downcase : word.capitalize
  end.join(' ')
end

# ─── Contact ─────────────────────────────────────────────────────────────────

def find_or_create_contact(octa_contact, company_id)
  return nil if octa_contact.nil?

  octa_id = octa_contact['id'].to_s
  return $contacts_map[octa_id] if $contacts_map.key?(octa_id)

  phone = build_phone(octa_contact['phoneContacts']&.first)

  full_name = format_name(octa_contact['name'])

  # Busca dados completos do contato (customFields vem só neste endpoint)
  full_contact = Octa.fetch_contact(octa_id) || octa_contact
  raw_fields   = full_contact['customFields'] || []
  # O endpoint /contacts/{id} retorna Array [{key,value}]; o chat embutido pode retornar Hash
  custom_fields = if raw_fields.is_a?(Array)
                    raw_fields.each_with_object({}) { |f, h| h[f['key'].to_s] = f['value'].to_s }
                  else
                    raw_fields.transform_values(&:to_s)
                  end

  cpf_cnpj     = custom_fields['cpf'].to_s.gsub(/\D/, '').presence
  contact_tags = custom_fields['tag'].to_s.split(',').map(&:strip).select(&:present?)

  custom_attrs = { 'source' => 'OctaDesk', 'id_octadesk' => octa_id }
  custom_attrs['cpf_cnpj'] = cpf_cnpj if cpf_cnpj

  # Demais customFields (exceto os mapeados explicitamente ou sem valor no Chatwoot)
  custom_fields.each do |key, value|
    next if value.blank?

    normalized = key.downcase.gsub(/\W+/, '_')
    # Pula campos da lista de exclusao (checagem na chave original E na normalizada)
    next if OCTA_SKIP_FIELDS.include?(key) || OCTA_SKIP_FIELDS.include?(normalized)

    custom_attrs[normalized] = value
  end

  # 1ª tentativa: pelo telefone (contato já existe no Chatwoot)
  contact = nil
  if phone.present?
    contact = Contact.find_by(account_id: $account.id, phone_number: phone)
    if contact
      log("  → Contato por telefone (ja existia): #{contact.name} (#{phone})")
      # rubocop:disable Rails/SkipsModelValidations
      contact.update_columns(
        name:              full_name,
        last_name:         '',
        custom_attributes: contact.custom_attributes.merge(custom_attrs)
      )
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  # 2ª tentativa: pelo e-mail (fallback)
  if contact.nil? && octa_contact['email'].present?
    contact = Contact.find_by(account_id: $account.id, email: octa_contact['email'])
    if contact
      log("  → Contato por e-mail (ja existia): #{contact.name} (#{octa_contact['email']})")
      # rubocop:disable Rails/SkipsModelValidations
      contact.update_columns(
        name:              full_name,
        last_name:         '',
        custom_attributes: contact.custom_attributes.merge(custom_attrs)
      )
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  # Cria novo contato se não encontrou por nenhuma chave
  unless contact
    dry("Criaria Contact '#{full_name}'")
    unless DRY_RUN
      contact = Contact.create!(
        account_id:        $account.id,
        name:              full_name,
        last_name:         '',
        email:             octa_contact['email'].presence,
        phone_number:      phone,
        company_id:        company_id,
        custom_attributes: custom_attrs
      )
    end
  end

  # O Chatwoot preenche additional_attributes['company_name'] automaticamente ao vincular
  # um contato a uma empresa — removemos pois o dado ja esta no company_id
  if contact && (contact.additional_attributes || {}).key?('company_name')
    # rubocop:disable Rails/SkipsModelValidations
    contact.update_columns(additional_attributes: contact.additional_attributes.except('company_name'))
    # rubocop:enable Rails/SkipsModelValidations
  end

  $contacts_map[octa_id] = contact
  [contact, contact_tags]
end

def build_phone(phone_obj)
  return nil if phone_obj.nil?

  number  = phone_obj['number'].to_s.gsub(/\D/, '')
  country = phone_obj['countryCode'].to_s.gsub(/\D/, '')
  return nil if number.blank?

  "+#{country}#{number}"
end

# ─── ContactInbox ─────────────────────────────────────────────────────────────

def find_or_create_contact_inbox(contact)
  return nil if contact.nil? || $inbox.id == 0

  ContactInbox.find_or_create_by!(
    contact_id: contact.id,
    inbox_id:   $inbox.id
  ) do |ci|
    ci.source_id = SecureRandom.uuid
  end
end

# ─── Conversa unificada por contato ───────────────────────────────────────────

def find_or_create_unified_conversation(contact, contact_inbox, first_chat_at, agent)
  # Usa o ID do Chatwoot (não do OctaDesk) para que contatos duplicados no OctaDesk
  # (mesmo cliente, dois cadastros) sejam unificados na mesma conversa
  cw_id = contact.id.to_s
  return $conversations_map[cw_id] if $conversations_map.key?(cw_id)

  conv_identifier = "octadesk:contact:#{cw_id}"
  conv = Conversation.find_by(account_id: $account.id, identifier: conv_identifier)

  unless conv
    dry("Criaria Conversation unificada para contato Chatwoot ##{cw_id}")
    unless DRY_RUN
      conv = Conversation.create!(
        account_id:       $account.id,
        inbox_id:         $inbox.id,
        contact_id:       contact&.id,
        contact_inbox_id: contact_inbox&.id,
        status:           :resolved,
        identifier:       conv_identifier,
        created_at:       first_chat_at,
        updated_at:       first_chat_at,
        additional_attributes: { imported_from: 'octadesk' }
      )

      # Remove todas as activity messages geradas automaticamente pelos callbacks
      # (atribuição automática, "marcado como resolvido", etc.)
      # rubocop:disable Rails/SkipsModelValidations
      Message.where(conversation_id: conv.id, message_type: Message.message_types[:activity]).delete_all
      # rubocop:enable Rails/SkipsModelValidations

      assignee_id = resolve_agent(agent)
      conv.update_columns(assignee_id: assignee_id) if assignee_id
    end
  end

  $conversations_map[cw_id] = conv
  conv
end

# ─── Processo principal de cada chat ─────────────────────────────────────────

def process_chat(chat_data)
  chat_id    = chat_data['id'].to_s
  created_at = parse_time(chat_data['createdAt']) || Time.current

  octa_contact    = chat_data['contact']
  octa_contact_id = octa_contact&.fetch('id', nil).to_s
  org             = octa_contact&.dig('organization')

  company_id    = find_or_create_company(org)
  contact, contact_tags = find_or_create_contact(octa_contact, company_id)
  contact_inbox         = find_or_create_contact_inbox(contact)

  # Idempotência: activity de encerramento é a chave de dedup (inserida no fim da transação)
  closed_source_id = "octadesk_closed:#{chat_id}"

  if !DRY_RUN && Message.joins(:conversation).exists?(source_id: closed_source_id)
    log("  → SKIP (já importado): chat #{chat_id}")
    $stats[:skipped] += 1
    return
  end

  log("  → Importando chat #{chat_id} (#{octa_contact&.fetch('name', '?')})...")
  dry("Processaria chat #{chat_id}")

  unless DRY_RUN
    ActiveRecord::Base.transaction do
      conv = find_or_create_unified_conversation(
        contact, contact_inbox, created_at, chat_data['agent']
      )

      # Se este chat é mais antigo que a conversa existente, ajusta o created_at
      conv.update_columns(created_at: created_at) if conv.created_at > created_at

      messages = collect_messages(chat_data, chat_id)
      import_messages(conv, messages, contact&.id)

      # Activity de encerramento no final de cada atendimento OctaDesk
      closed_source_id = "octadesk_closed:#{chat_id}"
      unless Message.joins(:conversation).exists?(source_id: closed_source_id)
        last_msg_time = messages.map { |m| parse_time(m['time']) }.compact.max || created_at
        agent_name    = chat_data.dig('agent', 'name').presence || 'OctaDesk'
        # rubocop:disable Rails/SkipsModelValidations
        Message.insert_all!([{
          account_id:      $account.id,
          inbox_id:        conv.inbox_id,
          conversation_id: conv.id,
          source_id:       closed_source_id,
          message_type:    Message.message_types[:activity],
          content:         "Conversa foi marcada como resolvida por #{agent_name}",
          private:         false,
          status:          'sent',
          content_type:    'text',
          created_at:      last_msg_time + 1.second,
          updated_at:      last_msg_time + 1.second,
          sender_type:     nil,
          sender_id:       nil
        }])
        # rubocop:enable Rails/SkipsModelValidations
      end

      # Labels: tags do chat + tags do contato (OctaDesk) → etiquetas da conversa
      chat_tag_names = (chat_data['tags'] || []).map { |t| t['name'].to_s.downcase.strip }.select(&:present?)
      tag_names      = (chat_tag_names + (contact_tags || [])).map(&:downcase).uniq
      if tag_names.any?
        # Garante que cada etiqueta existe na conta antes de associar à conversa
        tag_names.each { |name| ensure_label(name) }
        merged = (conv.label_list.to_a + tag_names).uniq
        # update! passa pelo ORM do acts_as_taggable_on (atualiza taggings + cached_label_list)
        # update_columns não funciona aqui porque label_list é atributo virtual
        conv.update!(label_list: merged)
      end

      last_time = messages.map { |m| parse_time(m['time']) }.compact.max
      if last_time
        # rubocop:disable Rails/SkipsModelValidations
        # Só atualiza se este chat for mais recente que o último já registrado
        # (chats são processados do mais antigo ao mais novo, mas defensivo por segurança)
        conv.reload
        if conv.last_activity_at.nil? || last_time > conv.last_activity_at
          conv.update_columns(last_activity_at: last_time + 1.second, updated_at: last_time + 1.second)
        end
        # rubocop:enable Rails/SkipsModelValidations
      end
    end
  end

  $stats[:imported] += 1
end

# ─── Mensagens ───────────────────────────────────────────────────────────────

def collect_messages(chat_data, chat_id)
  embedded       = chat_data['messages'] || []
  messages_count = chat_data['messagesCount'].to_i
  return embedded if messages_count <= embedded.size

  all  = embedded.dup
  page = 2
  loop do
    batch = Octa.fetch_messages(chat_id, page: page)
    break if batch.empty?

    all.concat(batch)
    break if all.size >= messages_count || batch.size < PAGE_SIZE

    page += 1
  end
  all
end

def import_messages(conv, messages, contact_id)
  return if messages.empty?

  messages_data           = []
  attachments_per_message = {}
  quoted_refs             = {}  # source_id → octa_id da mensagem citada

  messages.each do |msg|
    next if msg['status'] == 'error'   # mensagem que falhou ao enviar — nunca chegou ao cliente

    body_raw = msg['body']
    body_raw = body_raw.is_a?(Array) ? body_raw.flatten.map(&:to_s).join("\n") : body_raw.to_s
    next if body_raw.blank? && msg['attachments'].blank?

    source_id = "octadesk_msg:#{msg['id']}"
    next if Message.exists?(conversation_id: conv.id, source_id: source_id)

    msg_type = resolve_message_type(msg)
    private  = msg['type'] == 'internal'
    created  = parse_time(msg['time']) || conv.created_at

    messages_data << {
      account_id:      $account.id,
      inbox_id:        conv.inbox_id,
      conversation_id: conv.id,
      source_id:       source_id,
      message_type:    Message.message_types[msg_type],
      content:         strip_html(body_raw).presence,
      private:         private,
      status:          'sent',
      content_type:    'text',
      created_at:      created,
      updated_at:      created,
      sender_type:     (msg_type == :incoming ? 'Contact' : 'User'),
      sender_id:       (msg_type == :incoming ? contact_id : resolve_agent(msg['sentBy']))
    }

    attachments_per_message[source_id] = msg['attachments'] if msg['attachments'].present?

    # Guarda referência de quote para resolver após o insert_all
    quoted = msg['quoted']
    if quoted.is_a?(Hash)
      quoted_id = quoted['id'] || quoted['messageId']
      quoted_refs[source_id] = quoted_id.to_s if quoted_id.present?
    end
  end

  # Garante que nenhum campo escalar receba um Array (alguns tipos de mensagem
  # do OctaDesk retornam campos inesperadamente como Array)
  messages_data.each do |row|
    row.each do |key, value|
      next unless value.is_a?(Array)

      log("    AVISO: campo '#{key}' veio como Array — convertendo para string")
      row[key] = value.flatten.map(&:to_s).join("\n")
    end
  end

  # rubocop:disable Rails/SkipsModelValidations
  Message.insert_all!(messages_data) if messages_data.any?
  # rubocop:enable Rails/SkipsModelValidations

  # Vincula mensagens que são reply de outra (WhatsApp quote)
  quoted_refs.each do |src_id, quoted_octa_id|
    msg_record    = Message.find_by(conversation_id: conv.id, source_id: src_id)
    quoted_record = Message.find_by(conversation_id: conv.id,
                                    source_id: "octadesk_msg:#{quoted_octa_id}")
    next unless msg_record && quoted_record

    new_attrs = msg_record.content_attributes.merge(
      'in_reply_to'             => quoted_record.id,
      'in_reply_to_external_id' => quoted_record.source_id
    )
    # rubocop:disable Rails/SkipsModelValidations
    msg_record.update_columns(content_attributes: new_attrs)
    # rubocop:enable Rails/SkipsModelValidations
  end

  attachments_per_message.each do |src_id, attachments|
    msg_record = Message.find_by(conversation_id: conv.id, source_id: src_id)
    next unless msg_record

    attachments.each do |att|
      next if att['url'].blank?

      # ── Opção A (atual): referência externa — arquivo fica no storage do OctaDesk.
      # Quebra quando o contrato com o OctaDesk for encerrado.
      Attachment.create!(
        message_id:     msg_record.id,
        account_id:     $account.id,
        file_type:      infer_file_type(att['name'], att['url']),
        external_url:   att['url'],
        fallback_title: att['name']
      )

      # ── Opção B (produção): download + re-upload para o storage do Chatwoot (S3/disco).
      # Descomentar quando pronto para migração definitiva. Remover o bloco da Opção A acima.
      #
      # require 'open-uri'
      # begin
      #   attachment = Attachment.new(
      #     message_id:     msg_record.id,
      #     account_id:     $account.id,
      #     file_type:      infer_file_type(att['name'], att['url']),
      #     fallback_title: att['name']
      #   )
      #   attachment.file.attach(
      #     io:       URI.open(att['url'], read_timeout: 30),
      #     filename: att['name'].presence || File.basename(URI.parse(att['url']).path)
      #   )
      #   attachment.save!
      # rescue StandardError => e
      #   log("    AVISO: falha ao baixar anexo #{att['url']}: #{e.message} — usando external_url como fallback")
      #   Attachment.create!(
      #     message_id:     msg_record.id,
      #     account_id:     $account.id,
      #     file_type:      infer_file_type(att['name']),
      #     external_url:   att['url'],
      #     fallback_title: att['name']
      #   )
      # end
    end
  end
end

def resolve_message_type(msg)
  sent_by = msg['sentBy']
  return :incoming if sent_by.nil?

  sent_by['type'].to_s.downcase == 'contact' ? :incoming : :outgoing
end

def strip_html(html)
  html
    .gsub(/<br\s*\/?>/, "\n")          # <br> → newline
    .gsub(%r{</p>|</div>|</li>}, "\n") # tags de bloco → newline
    .then { |h| ActionController::Base.helpers.strip_tags(h) }
    .gsub(/&nbsp;/, ' ')
    .gsub(/&amp;/, '&')
    .gsub(/&lt;/, '<')
    .gsub(/&gt;/, '>')
    .gsub(/&quot;/, '"')
    .gsub(/[ \t]+/, ' ')               # colapsa só espaços horizontais (não newlines)
    .gsub(/\n{3,}/, "\n\n")            # máx 2 quebras consecutivas
    .strip
end

def infer_file_type(filename, url = nil)
  # name do OctaDesk às vezes vem sem extensão — usa a URL como fallback
  source = filename.to_s
  source = File.basename(URI.parse(url.to_s).path) if source.exclude?('.') && url.present?

  return :image if source.match?(/\.(jpg|jpeg|png|gif|webp|svg)$/i)
  return :audio if source.match?(/\.(mp3|ogg|wav|m4a|opus|mpeg)$/i)
  return :video if source.match?(/\.(mp4|mov|avi|webm)$/i)

  :file
end

# ─── Helpers ─────────────────────────────────────────────────────────────────

def resolve_agent(agent_obj)
  return nil if agent_obj.nil?

  email = agent_obj['email'].to_s.downcase.strip
  $agents_map[email]
end

def parse_time(value)
  return nil if value.blank?

  Time.parse(value.to_s)
rescue ArgumentError
  nil
end

# ─── Runner principal ─────────────────────────────────────────────────────────

log('=' * 60)
log("Iniciando migração OctaDesk → Chatwoot (Conversa unificada por contato)")
log("DRY_RUN: #{DRY_RUN} | LIMIT: #{IMPORT_LIMIT.zero? ? 'ilimitado' : IMPORT_LIMIT}")
log('=' * 60)

setup!

chats = Octa.fetch_closed_chats
log("Total de chats fechados a processar: #{chats.size}")

# Ordena do mais antigo para o mais novo: garante que mensagens de chats mais antigos
# recebam IDs menores no banco. O Chatwoot pagina por ID decrescente (before=<id>),
# então IDs precisam crescer com o tempo para que a paginação carregue tudo.
chats.sort_by! { |c| c['createdAt'].to_s }

chats.each_with_index do |chat_summary, idx|
  log("Chat #{idx + 1}/#{chats.size} — id: #{chat_summary['id']}")

  begin
    chat_data = Octa.fetch_chat(chat_summary['id'])
    process_chat(chat_data)
  rescue StandardError => e
    log("  ERRO no chat #{chat_summary['id']}: #{e.message}")
    script_frames = e.backtrace.select { |f| f.include?('scripts/') || f.include?('octadesk') }
    gem_frames    = e.backtrace.first(3)
    shown = (script_frames + gem_frames).uniq.first(6)
    log("  #{shown.join("\n  ")}")
    $stats[:errors] << { chat_id: chat_summary['id'], error: e.message }
  end
end

log('=' * 60)
log("Concluído!")
log("  Importados: #{$stats[:imported]}")
log("  Pulados (já existiam): #{$stats[:skipped]}")
log("  Erros: #{$stats[:errors].size}")
$stats[:errors].each { |e| log("    ✗ chat #{e[:chat_id]}: #{e[:error]}") }
log('=' * 60)
