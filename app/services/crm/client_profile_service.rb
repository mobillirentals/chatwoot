class Crm::ClientProfileService
  BITRIX_BASE = ENV.fetch('BITRIX24_WEBHOOK_URL', '').freeze
  ASAAS_BASE  = 'https://api.asaas.com/v3'.freeze
  ASAAS_TOKEN = ENV.fetch('ASAAS_ACCESS_TOKEN', '').freeze

  def initialize(phone)
    @phone = normalize_phone(phone)
  end

  def perform
    contact = find_contact
    return { found: false } unless contact

    deal       = find_active_deal(contact['ID'])
    motorcycle = deal ? find_motorcycle(deal['ID']) : nil
    asaas_id   = contact['UF_CRM_1773336918635']
    overdue    = asaas_id.present? ? fetch_payments(asaas_id, 'OVERDUE') : []
    pending    = asaas_id.present? ? fetch_payments(asaas_id, 'PENDING') : []

    next_payment = pending
      .reject { |p| p['deleted'] }
      .min_by { |p| p['dueDate'] }

    {
      found:            true,
      name:             "#{contact['NAME']} #{contact['LAST_NAME']}".strip,
      first_name:       contact['NAME'],
      cpf:              contact['UF_CRM_1721609323'],
      asaas_id:         asaas_id,
      active_contract:  deal.present?,
      deal_id:          deal&.dig('ID'),
      deal_start:       br_date(deal&.dig('UF_CRM_1743092456783')),
      motorcycle_plate: motorcycle&.dig('ufCrm_68BB19F1AD8FD'),
      motorcycle_model: motorcycle&.dig('ufCrm16_1758898469346'),
      overdue_count:    overdue.size,
      overdue_total:    overdue.sum { |p| p['value'].to_f }.round(2),
      overdue_payments: overdue.first(3).map { |p| payment_summary(p) },
      next_payment:     next_payment ? payment_summary(next_payment) : nil
    }
  rescue StandardError => e
    Rails.logger.error("[Crm::ClientProfileService] #{e.message}")
    { found: false, error: 'Erro ao consultar dados do cliente' }
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

  def find_motorcycle(deal_id)
    body = {
      entityTypeId: 1072,
      filter: { parentId2: deal_id },
      select: %w[id title ufCrm_68BB19F1AD8FD ufCrm16_1758898469346 parentId2]
    }
    bitrix_post('crm.item.list.json', body).dig('result', 'items')&.first
  end

  def fetch_payments(asaas_customer_id, status)
    response = asaas_client.get('/payments') do |req|
      req.params['customer'] = asaas_customer_id
      req.params['status']   = status
      req.params['limit']    = 20
    end
    JSON.parse(response.body)['data'] || []
  rescue StandardError => e
    Rails.logger.error("[Crm::ClientProfileService] Asaas #{status} falhou: #{e.message}")
    []
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

  def bitrix_client
    @bitrix_client ||= Faraday.new(url: BITRIX_BASE) do |f|
      f.request  :json
      f.adapter  Faraday.default_adapter
    end
  end

  def asaas_client
    @asaas_client ||= Faraday.new(url: ASAAS_BASE) do |f|
      f.headers['access_token'] = ASAAS_TOKEN
      f.adapter Faraday.default_adapter
    end
  end
end
