class BotFlow::Engine
  STATES = %w[
    start
    menu
    financeiro
    atendimento
    atendimento_veiculo
    atendimento_documentos
    documentos_duvida
    atendimento_ouvidoria
    pos_atendimento
    emergencia_menu
    emergencia
    atendente
    despedida
  ].freeze

  AGENDAMENTO_URL = ENV.fetch('AGENDAMENTO_URL', 'https://mobillirentals.com.br/agendamento').freeze

  def initialize(conversation, user_input)
    @conversation = conversation
    @user_input   = user_input.to_s.strip
  end

  def self.step(conversation, user_input)
    new(conversation, user_input).process
  end

  def process
    state = attrs['bot_state'] || 'start'

    # Comando global: "Voltar" (ou "Menu"/"Início") retorna ao menu principal em
    # qualquer estado, exceto no início e durante o atendimento humano ('atendente').
    if back_command?(@user_input) && !%w[start atendente].include?(state)
      result = back_to_menu('Voltando ao menu principal 👇')
      save_state(result[:next_state])
      return result
    end

    # Atalho pra migração da plataforma de cobranças (Moto Fácil, ago/2026): pula o menu
    # inteiro e cai direto no time de suporte, inclusive vindo de 'start' (é exatamente o
    # estado de quem clica no link do app antigo com esse texto pré-preenchido). Só não
    # interrompe quem já está em atendimento humano.
    if moto_facil_keyword?(@user_input) && state != 'atendente'
      result = transfer_to('suporte app',
                           'Vou te encaminhar para o nosso time de suporte da nova plataforma **Moto Fácil**. Um instante! 📱')
      save_state(result[:next_state])
      return result
    end

    result = case state
    when 'start'                   then handle_start
    when 'menu'                    then handle_menu
    when 'financeiro'              then handle_financeiro
    when 'atendimento'             then handle_atendimento
    when 'atendimento_veiculo'     then handle_atendimento_veiculo
    when 'atendimento_documentos'  then handle_atendimento_documentos
    when 'documentos_duvida'       then handle_documentos_duvida
    when 'atendimento_ouvidoria'   then handle_atendimento_ouvidoria
    when 'pos_atendimento'         then handle_more_help('pos_atendimento')
    when 'emergencia_menu'         then handle_emergencia_menu
    when 'emergencia'              then handle_emergencia
    when 'atendente'               then handle_atendente
    when 'despedida'               then farewell
    else handle_start
    end

    return nil unless result

    save_state(result[:next_state]) if result[:next_state]
    result
  end

  private

  # ── start / menu ────────────────────────────────────────────────────────────

  def handle_start
    # Nome nativo do WhatsApp: a saudação não depende de nenhuma chamada de rede.
    name     = contact_first_name
    greeting = name.present? ? "Olá, **#{name}**! 👋" : 'Olá! 👋'
    messages = [
      "#{greeting} Bem-vindo à **Mobílli Rentals**.",
      'Sou o assistente virtual. Como posso te ajudar?'
    ]

    { messages: messages, buttons: menu_buttons, next_state: 'menu' }
  end

  def handle_menu
    case normalize(@user_input)
    when match_any('financeiro', '1')   then enter_financeiro
    when match_any('atendimento', '2')  then enter_atendimento
    when match_any('emergencia', '3')   then enter_emergencia_menu
    else
      { messages: ['Por favor, escolha uma das opções:'], buttons: menu_buttons, next_state: 'menu' }
    end
  end

  # ── Financeiro (autoatendimento CRM) ─────────────────────────────────────────

  # Sem autoatendimento de cobrança aqui: nem valor, nem tipo, nem link — o tipo
  # (multa x parcela x cobrança) é adivinhado por texto livre e já errou uma vez
  # (ver crm_lookup no Captain). Dinheiro é sempre assunto do time financeiro.
  def enter_financeiro
    { messages: ['Vamos ao seu financeiro. Como posso te ajudar?' + voltar_hint],
      buttons: financeiro_buttons, next_state: 'financeiro' }
  end

  def handle_financeiro
    case normalize(@user_input)
    when match_any('atendente', 'falar com financeiro', 'financeiro', 'link', 'quero o link', 'pagar', 'fatura', 'boleto', '1')
      transfer_to('financeiro',
                  'Vou te encaminhar para a nossa equipe **financeira**. Um instante! 💬')
    when match_any('menu', 'voltar')
      back_to_menu
    else
      enter_financeiro
    end
  end

  # ── Atendimento (sub-setores) ────────────────────────────────────────────────

  def enter_atendimento
    { messages: ['Certo! Com qual setor você precisa falar?' + voltar_hint],
      buttons: atendimento_buttons, next_state: 'atendimento' }
  end

  def handle_atendimento
    case normalize(@user_input)
    when match_any('veiculo', 'oficina', 'moto', '1')   then enter_atendimento_veiculo
    when match_any('documentos', 'documento', '2')      then enter_atendimento_documentos
    when match_any('ouvidoria', '3')                    then enter_atendimento_ouvidoria
    when match_any('menu', 'voltar')                    then back_to_menu
    else
      { messages: ['Escolha um dos setores:'], buttons: atendimento_buttons, next_state: 'atendimento' }
    end
  end

  # Veículo / Oficina
  def enter_atendimento_veiculo
    { messages: ['🔧 **Veículo / Oficina** — o que você precisa?' + voltar_hint],
      buttons: veiculo_buttons, next_state: 'atendimento_veiculo' }
  end

  def handle_atendimento_veiculo
    case normalize(@user_input)
    when match_any('agendar', 'revisao', 'agendamento', '1')
      {
        messages: [agendamento_message, 'Posso te ajudar em mais alguma coisa?'],
        buttons: sim_nao_buttons,
        next_state: 'pos_atendimento'
      }
    when match_any('atendente', 'falar com atendente', 'falar', '2')
      transfer_to('manutenção',
                  'Vou te encaminhar para a nossa equipe de **manutenção**. Um instante! 🔧')
    when match_any('menu', 'voltar')
      back_to_menu
    else
      enter_atendimento_veiculo
    end
  end

  # Documentos
  def enter_atendimento_documentos
    { messages: ['📋 **Documentos** — sobre qual assunto?' + voltar_hint],
      buttons: documentos_buttons, next_state: 'atendimento_documentos' }
  end

  def handle_atendimento_documentos
    case normalize(@user_input)
    when match_any('docs para locar', 'locar', 'locacao', '1')
      {
        messages: [documentos_locacao_message, 'Ficou alguma dúvida sobre a documentação?'],
        buttons: sim_nao_buttons,
        next_state: 'documentos_duvida'
      }
    when match_any('multas', 'multa', 'transito', '2')
      transfer_to('documentação e multas',
                  'Vou te encaminhar para **Documentação e Multas**. Um instante! 🚦')
    when match_any('contrato', 'contratual', '3')
      transfer_to('pós-venda',
                  'Vou te encaminhar para o nosso **Pós-Venda** para dúvidas contratuais. Um instante! 📝')
    when match_any('menu', 'voltar')
      back_to_menu
    else
      enter_atendimento_documentos
    end
  end

  def handle_documentos_duvida
    case normalize(@user_input)
    when match_any('sim', '1')
      transfer_to('documentação e multas',
                  'Sem problema! Vou te encaminhar para **Documentação e Multas** para tirar sua dúvida. 📄')
    when match_any('nao', '2')
      farewell
    else
      { messages: ['Ficou alguma dúvida sobre a documentação?'],
        buttons: sim_nao_buttons, next_state: 'documentos_duvida' }
    end
  end

  # Ouvidoria (texto livre)
  def enter_atendimento_ouvidoria
    { messages: ['📣 **Ouvidoria** — descreva sua mensagem (elogio, reclamação ou sugestão) e vamos encaminhar para o time responsável.' + voltar_hint],
      buttons: nil, next_state: 'atendimento_ouvidoria' }
  end

  def handle_atendimento_ouvidoria
    if @user_input.blank?
      return { messages: ['Pode escrever sua mensagem que eu encaminho para a Ouvidoria.'],
               buttons: nil, next_state: 'atendimento_ouvidoria' }
    end

    transfer_to('ouvidoria',
                'Recebido! Sua mensagem foi registrada e encaminhada para a nossa **Ouvidoria**. Em breve retornaremos. 📣')
  end

  # ── Emergência (submenu e triagem) ──────────────────────────────────────────

  def enter_emergencia_menu
    {
      messages: ['🚨 **Emergência** — Escolha uma das opções abaixo para que eu possa direcionar para a equipe correta:' + voltar_hint],
      buttons: [
        { title: '🚨 Roubo/Furto', value: 'roubo furto' },
        { title: '🆘 Socorro',     value: 'socorro' }
      ],
      next_state: 'emergencia_menu'
    }
  end

  def handle_emergencia_menu
    case normalize(@user_input)
    when match_any('roubo', 'furto', '1')
      transfer_to('monitoramento e sinistros',
                  "🚨 Sinto muito por isso! Vou te encaminhar para a equipe de **Monitoramento e Sinistros** agora mesmo.\n\n⚠️ Importante: se puder, já vá elaborando o **Boletim de Ocorrência (B.O.)**, pois precisaremos dele para dar andamento ao caso. Um instante!")
    when match_any('socorro', '2')
      enter_emergencia
    when match_any('menu', 'voltar')
      back_to_menu
    else
      enter_emergencia_menu
    end
  end

  def enter_emergencia
    { messages: ["🆘 **Socorro**\n\nPara acionarmos o socorro o mais rápido possível, **me informe a sua localização** — endereço com um ponto de referência, ou compartilhe o pin de localização aqui pelo WhatsApp."],
      buttons: nil, next_state: 'emergencia' }
  end

  def handle_emergencia
    if @user_input.blank?
      return { messages: ['Preciso da sua **localização** para acionar o socorro. Pode enviar o endereço ou o pin de localização.'],
               buttons: nil, next_state: 'emergencia' }
    end

    transfer_to('socorro',
                "🚨 Localização recebida! Nossa equipe de **socorro** já foi acionada e vai entrar em contato com você agora mesmo.\n\nSe estiver em local de risco, procure um ponto seguro e mantenha o telefone por perto.")
  end

  # ── "Posso ajudar em mais algo?" (pós self-service) ──────────────────────────

  def handle_more_help(current_state)
    case normalize(@user_input)
    when match_any('sim', '1')
      back_to_menu('Claro! Como posso te ajudar?')
    when match_any('nao', '2')
      farewell
    else
      { messages: ['Posso te ajudar em mais alguma coisa?'], buttons: sim_nao_buttons, next_state: current_state }
    end
  end

  # ── Handoff / encerramento ───────────────────────────────────────────────────

  def handle_atendente
    # Conversa em atendimento humano — o bot permanece em silêncio.
    nil
  end

  def transfer_to(team_name, message)
    hand_off_to_human(team_name)
    { messages: [message], buttons: nil, next_state: 'atendente' }
  end

  def hand_off_to_human(team_name)
    team = @conversation.account.teams.find_by('LOWER(name) = ?', team_name.to_s.downcase)
    Rails.logger.warn("[BotFlow] time '#{team_name}' não encontrado — conversa aberta sem atribuição") if team.nil?

    updates = { status: :open }
    updates[:team_id] = team.id if team
    # update! (não update_columns) para disparar os callbacks de atribuição do Chatwoot:
    # round-robin de agente, atividade de mudança de time e broadcast pro dashboard.
    @conversation.update!(updates)
  rescue StandardError => e
    Rails.logger.error("[BotFlow] handoff(#{team_name}) falhou: #{e.message}")
  end

  def back_to_menu(message = 'Voltando ao menu principal:')
    { messages: [message], buttons: menu_buttons, next_state: 'menu' }
  end

  def farewell
    { messages: ['Perfeito! Se precisar de algo é só chamar. Até logo! 👋'],
      buttons: nil, next_state: nil, end_session: true }
  end

  # ── Botões (títulos ≤ 20 caracteres — limite do WhatsApp) ─────────────────────

  def menu_buttons
    [
      { title: '💰 Financeiro',  value: 'financeiro' },
      { title: '🎧 Atendimento', value: 'atendimento' },
      { title: '🚨 Emergência',  value: 'emergencia' }
    ]
  end

  def financeiro_buttons
    [{ title: '🎧 Atendente', value: 'atendente' }]
  end

  def atendimento_buttons
    [
      { title: '🔧 Veículo',   value: 'veiculo' },
      { title: '📋 Documentos', value: 'documentos' },
      { title: '📣 Ouvidoria',  value: 'ouvidoria' }
    ]
  end

  def veiculo_buttons
    [
      { title: '📅 Agendar revisão', value: 'agendar revisao' },
      { title: '🎧 Atendente',       value: 'atendente' }
    ]
  end

  def documentos_buttons
    [
      { title: '📄 Docs para locar', value: 'docs para locar' },
      { title: '🚦 Multas',          value: 'multas' },
      { title: '📝 Contrato',        value: 'contrato' }
    ]
  end

  def sim_nao_buttons
    [
      { title: '✅ Sim', value: 'sim' },
      { title: '❌ Não', value: 'nao' }
    ]
  end

  # ── Mensagens self-service ───────────────────────────────────────────────────

  def agendamento_message
    "📅 Para agendar a revisão da sua moto, é só escolher o melhor horário por aqui:\n#{AGENDAMENTO_URL}\n\nLeva menos de 1 minuto!"
  end

  def documentos_locacao_message
    "📄 Para locar uma moto na Mobílli você precisa de:\n\n" \
    "• **CNH** válida (categoria A)\n" \
    "• **CPF**\n" \
    "• **Comprovante de residência** (dos últimos 90 dias)\n\n" \
    'Com esses documentos em mãos a locação é rápida!'
  end

  # ── Nome do contato ──────────────────────────────────────────────────────────

  # Nome do contato no WhatsApp/Chatwoot (ignora quando o "nome" é apenas o número de telefone).
  def contact_first_name
    raw = @conversation.contact&.name.to_s.strip
    return nil if raw.blank?
    return nil if raw.match?(/\A\+?[\d\s()-]+\z/) # parece um número de telefone

    raw.split(/\s+/).first
  end

  # ── Estado ────────────────────────────────────────────────────────────────────

  def attrs
    @conversation.additional_attributes || {}
  end

  def save_state(state)
    update_attrs('bot_state' => state)
  end

  def update_attrs(hash)
    @conversation.update_columns(additional_attributes: attrs.merge(hash))
  end

  # ── Helpers de matching ──────────────────────────────────────────────────────

  # Remove acentos E emojis/símbolos de forma uniforme, evitando o bug em que
  # "🚨 Emergência" não casava com "emergencia".
  def normalize(text)
    text.to_s
        .downcase
        .unicode_normalize(:nfkd)
        .chars.reject { |c| c.match?(/\p{Mn}/) } # remove acentos (marcas combinantes)
        .join
        .gsub(/[^\p{Alnum}\s]/, ' ')             # remove emojis/pontuação
        .gsub(/\s+/, ' ')
        .strip
  end

  # Dígitos isolados exigem match exato (evita "10" casar com "1");
  # texto usa substring. Termos vazios são descartados.
  def match_any(*options)
    normalized = options.map { |o| normalize(o.to_s) }.reject(&:blank?)
    lambda do |input|
      normalized.any? do |opt|
        opt.length == 1 && opt.match?(/\d/) ? input == opt : input.include?(opt)
      end
    end
  end

  # Comando global de navegação: qualquer um destes retorna ao menu principal.
  def back_command?(input)
    ['voltar', 'menu', 'inicio', 'voltar ao menu', 'menu principal', 'voltar ao inicio'].include?(normalize(input))
  end

  # Detecta a menção ao Moto Fácil em texto livre (substring, não precisa ser exato) —
  # cobre tanto "Moto Fácil" (com espaço, texto pré-preenchido do botão no app antigo)
  # quanto "motofacil.club"/"motofacil" grudado (normalize vira "motofacil club"/"motofacil").
  def moto_facil_keyword?(input)
    normalized = normalize(input)
    normalized.include?('moto facil') || normalized.include?('motofacil')
  end

  # Dica textual de navegação (substitui o antigo botão "Voltar" — libera slot de botão).
  def voltar_hint
    "\n\n_↩️ Digite Voltar a qualquer momento para retornar ao menu._"
  end
end
