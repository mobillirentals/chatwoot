class Crm::ClientProfileService
  BITRIX_BASE = ENV.fetch('BITRIX24_WEBHOOK_URL', '').freeze
  ASAAS_BASE  = 'https://api.asaas.com/v3'.freeze
  ASAAS_TOKEN = ENV.fetch('ASAAS_ACCESS_TOKEN', '').freeze

  STAGE_ALUGADA    = 'DT1072_28:UC_S400BR'.freeze
  STAGE_MANUTENCAO = 'DT1072_28:UC_IK83H1'.freeze

  def initialize(phone)
    @phone = normalize_phone(phone)
  end

  def perform
    contact = find_contact
    return { found: false, welcome_text: 'Olá!', intro_message: generic_intro, payment_message: nil } unless contact

    deal         = find_active_deal(contact['ID'])
    motorcycles  = deal ? find_motorcycles(deal['ID']) : []
    current_moto, contract_moto = resolve_motorcycles(motorcycles)
    asaas_id     = contact['UF_CRM_1773336918635']
    overdue_data = asaas_id.present? ? fetch_overdue(asaas_id) : { count: 0, total: 0.0, payments: [] }
    next_payment = asaas_id.present? ? fetch_next_pending(asaas_id) : nil

    first_name = contact['NAME']

    {
      found:                     true,
      welcome_text:              "Olá, **#{first_name}**!",
      name:                      "#{first_name} #{contact['LAST_NAME']}".strip,
      first_name:                first_name,
      cpf:                       contact['UF_CRM_1721609323'],
      asaas_id:                  asaas_id,
      active_contract:           deal.present?,
      deal_id:                   deal&.dig('ID'),
      deal_start:                br_date(deal&.dig('UF_CRM_1743092456783')),
      current_motorcycle_plate:  current_moto&.dig('ufCrm_68BB19F1AD8FD'),
      current_motorcycle_model:  current_moto&.dig('ufCrm16_1758898469346'),
      contract_motorcycle_plate: contract_moto&.dig('ufCrm_68BB19F1AD8FD'),
      contract_motorcycle_model: contract_moto&.dig('ufCrm16_1758898469346'),
      overdue_count:             overdue_data[:count],
      overdue_total:             overdue_data[:total],
      overdue_payments:          overdue_data[:payments].first(3).map { |p| payment_summary(p) },
      next_payment:              next_payment ? payment_summary(next_payment) : nil,
      intro_message:             build_intro_message(first_name, current_moto, overdue_data, next_payment),
      payment_message:           build_payment_message(overdue_data, next_payment)
    }
  rescue StandardError => e
    Rails.logger.error("[Crm::ClientProfileService] #{e.message}")
    { found: false, welcome_text: 'Olá!', error: 'Erro ao consultar dados do cliente', intro_message: generic_intro, payment_message: nil }
  end

  private

  def find_contact
    body = {
      FILTER: { PHONE: @phone },
      SELECT: %w[ID NAME LAST_NAME UF_CRM_1721609323 UF_CRM_1773336933605 UF_CRM_1773336918635]
    }
    contacts = bitrix_post('crm.contact.list.json', body)['result'] || []
    contacts.find { |c| c['UF_CRM_1721609323'].present? } || contacts.first
  end

  def find_active_deal(contact_id)
    body = {
      FILTER: { CONTACT_ID: contact_id, CATEGORY_ID: 0 },
      SELECT: %w[ID STAGE_ID UF_CRM_1743092456783 UF_CRM_1732714351]
    }
    deals = bitrix_post('crm.deal.list.json', body)['result'] || []
    deals.find do |d|
      d['STAGE_ID'] == 'WON' &&
        d['UF_CRM_1743092456783'].present? &&
        d['UF_CRM_1732714351'].blank?
    end
  end

  def find_motorcycles(deal_id)
    body = {
      entityTypeId: 1072,
      filter: { parentId2: deal_id },
      select: %w[id title stageId ufCrm_68BB19F1AD8FD ufCrm16_1758898469346 parentId2]
    }
    bitrix_post('crm.item.list.json', body).dig('result', 'items') || []
  end

  def resolve_motorcycles(motorcycles)
    return [nil, nil] if motorcycles.empty?
    return [motorcycles.first, motorcycles.first] if motorcycles.size == 1

    current  = motorcycles.find { |m| m['stageId'] == STAGE_ALUGADA }
    contract = motorcycles.find { |m| m['stageId'] == STAGE_MANUTENCAO }

    current  ||= motorcycles.first
    contract ||= motorcycles.first

    [current, contract]
  end

  def fetch_overdue(asaas_customer_id)
    response = Faraday.get("#{ASAAS_BASE}/payments") do |req|
      req.headers['access_token'] = ASAAS_TOKEN
      req.params['customer'] = asaas_customer_id
      req.params['status']   = 'OVERDUE'
      req.params['limit']    = 100
      req.params['offset']   = 0
    end
    body     = JSON.parse(response.body)
    payments = body['data'] || []
    {
      count:    body['totalCount'].to_i,
      total:    payments.sum { |p| p['value'].to_f }.round(2),
      payments: payments
    }
  rescue StandardError => e
    Rails.logger.error("[Crm::ClientProfileService] Asaas OVERDUE falhou: #{e.message}")
    { count: 0, total: 0.0, payments: [] }
  end

  def fetch_next_pending(asaas_customer_id)
    response = Faraday.get("#{ASAAS_BASE}/payments") do |req|
      req.headers['access_token'] = ASAAS_TOKEN
      req.params['customer'] = asaas_customer_id
      req.params['status']   = 'PENDING'
      req.params['limit']    = 100
      req.params['offset']   = 0
    end
    payments = JSON.parse(response.body)['data'] || []
    payments.min_by { |p| p['dueDate'] }
  rescue StandardError => e
    Rails.logger.error("[Crm::ClientProfileService] Asaas PENDING falhou: #{e.message}")
    nil
  end

  def bitrix_post(endpoint, body)
    response = Faraday.post("#{BITRIX_BASE}/#{endpoint}") do |req|
      req.headers['Content-Type'] = 'application/json'
      req.body = body.to_json
    end
    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.error("[Crm::ClientProfileService] Bitrix #{endpoint} falhou: #{e.message}")
    {}
  end

  def payment_summary(p)
    {
      value:       p['value'].to_f,
      due_date:    br_date(p['dueDate']),
      status:      p['status'],
      invoice_url: p['invoiceUrl'],
      description: p['description']
    }
  end

  def br_date(date_str)
    return nil if date_str.blank?
    Date.parse(date_str).strftime('%d/%m/%Y')
  rescue ArgumentError
    nil
  end

  def normalize_phone(phone)
    phone = phone.to_s.gsub(/\D/, '')
    phone = "55#{phone}" unless phone.start_with?('55')
    "+#{phone}"
  end

  def generic_intro
    "Olá! 👋 Sou o assistente da Mobílli.\n\nComo posso te ajudar hoje?"
  end

  def build_intro_message(first_name, current_moto, overdue_data, next_payment)
    if overdue_data[:count] > 0
      total_str = format('%.2f', overdue_data[:total])
      types = overdue_data[:payments].map { |p| detect_charge_type(p['description']) }.uniq
      label = label_for_types(types, overdue_data[:count])
      "**#{first_name}**, identifiquei que você possui **#{overdue_data[:count]} #{label}** em atraso no total de **R$ #{total_str}**. Quer que eu envie o link para regularizar?"
    elsif next_payment
      value_str = format('%.2f', next_payment['value'].to_f)
      date_str  = br_date(next_payment['dueDate'])
      next_word = case detect_charge_type(next_payment['description'])
                  when 'multa' then 'próxima multa'
                  when 'parcela' then 'próxima parcela'
                  else 'próxima cobrança'
                  end
      "**#{first_name}**, identifiquei que sua **#{next_word}** vence em **#{date_str}** no valor de **R$ #{value_str}**. Quer que eu envie o link para pagamento?"
    else
      "**#{first_name}**, não identifiquei cobranças em aberto. Como posso te ajudar hoje?"
    end
  end

  def build_payment_message(overdue_data, next_payment)
    if overdue_data[:count] > 0 && overdue_data[:payments].any?
      p    = overdue_data[:payments].first
      url  = p['invoiceUrl']
      date = br_date(p['dueDate'])
      type_word = detect_charge_type(p['description'])
      type_label = type_word == 'multa' ? 'multa vencida' : (type_word == 'parcela' ? 'parcela vencida' : 'cobrança vencida')
      "📋 Clique no link abaixo para acessar a #{type_label} em *#{date}:*\n\n#{url}"
    elsif next_payment
      url   = next_payment['invoiceUrl']
      date  = br_date(next_payment['dueDate'])
      type_word = detect_charge_type(next_payment['description'])
      type_label = type_word == 'multa' ? 'multa com vencimento em' : (type_word == 'parcela' ? 'parcela com vencimento em' : 'cobrança com vencimento em')
      "📋 Clique no link abaixo para acessar a #{type_label} *#{date}:*\n\n#{url}"
    else
      "Não encontrei cobranças em aberto para seu número. Nosso time pode te ajudar com mais detalhes!"
    end
  end

  def detect_charge_type(description)
    desc = description.to_s.upcase
    if desc.include?('MULTA') || desc.include?('REEMBOLSO')
      'multa'
    elsif desc.include?('PARCELA') || desc.include?('LOCACAO') || desc.include?('LOCAÇÃO')
      'parcela'
    else
      'cobrança'
    end
  end

  def label_for_types(types, count)
    word = types.size == 1 ? types.first : 'cobrança'
    case word
    when 'multa'
      count > 1 ? 'multas' : 'multa'
    when 'parcela'
      count > 1 ? 'parcelas' : 'parcela'
    else
      count > 1 ? 'cobranças' : 'cobrança'
    end
  end
end
