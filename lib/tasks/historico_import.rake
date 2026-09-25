# Importa o historico antigo (Octadesk e WhatsApp/Underchat) convertido em NDJSON para dentro de
# uma caixa de entrada propria. Ver .ai/features/historico-import/plan.md.
#
#   bundle exec rake 'historico:import[/tmp/historico/octadesk,Histórico Octadesk]'
#
# Variaveis de ambiente:
#   LIMITE=3    importa so as N conversas com mais mensagens (piloto para conferir na tela)
#   ACCOUNT_ID  padrao 1
#   APAGAR=1    em historico:limpar, confirma o apagamento da caixa inteira
#
# Por que SQL direto (insert_all) e nao ActiveRecord: um Message.create dispara evento, webhook,
# job do Captain, notificacao e reporting_event. Novecentas mil vezes isso nao e carga, e
# incidente. O display_id vem do trigger do Postgres e o uuid do default da coluna.
namespace :historico do
  LOTE = 2_000

  desc 'Importa NDJSON convertido (contacts/conversations/messages) para uma caixa de historico'
  task :import, %i[dir inbox] => :environment do |_t, args|
    dir = Pathname.new(args[:dir].to_s)
    raise "pasta nao encontrada: #{dir}" unless dir.directory?

    account = Account.find(ENV.fetch('ACCOUNT_ID', '1'))
    inbox = HistoricoImport.caixa(account, args[:inbox].to_s)
    HistoricoImport.new(dir: dir, account: account, inbox: inbox, limite: ENV['LIMITE']&.to_i).perform
  end

  desc 'Junta atendimentos picotados (mesmo contato, intervalo curto, filas compativeis)'
  task :juntar, %i[inbox] => :environment do |_t, args|
    account = Account.find(ENV.fetch('ACCOUNT_ID', '1'))
    inbox = account.inboxes.find_by!(name: args[:inbox].to_s)
    HistoricoJuncao.new(account: account, inbox: inbox,
                        janela: ENV.fetch('JANELA_HORAS', '6').to_f.hours,
                        por_contato: ENV['POR_CONTATO'] == '1',
                        simular: ENV['SIMULAR'] == '1').perform
  end

  desc 'Move conversas de uma caixa de historico para outra (para consolidar as origens)'
  task :mover, %i[origem destino] => :environment do |_t, args|
    account = Account.find(ENV.fetch('ACCOUNT_ID', '1'))
    origem = account.inboxes.find_by!(name: args[:origem].to_s)
    destino = account.inboxes.find_by!(name: args[:destino].to_s)
    HistoricoMudanca.new(account: account, origem: origem, destino: destino,
                         simular: ENV['SIMULAR'] == '1').perform
  end

  desc 'Liga a midia ja enviada ao Blob nas mensagens do historico (ver manifesto do prepara_midia.py)'
  task :midia, %i[manifesto] => :environment do |_t, args|
    account = Account.find(ENV.fetch('ACCOUNT_ID', '1'))
    caixas = ENV.fetch('CAIXAS', '9,10').split(',').map(&:to_i)
    HistoricoMidia.new(manifesto: Pathname.new(args[:manifesto].to_s), account: account,
                       caixas: caixas).perform
  end

  desc 'Apaga TUDO de uma caixa de historico (conversas, mensagens e a propria caixa)'
  task :limpar, %i[inbox] => :environment do |_t, args|
    account = Account.find(ENV.fetch('ACCOUNT_ID', '1'))
    inbox = account.inboxes.find_by!(name: args[:inbox].to_s)
    conversas = inbox.conversations.count
    mensagens = Message.where(inbox_id: inbox.id).count
    if ENV['APAGAR'] != '1'
      puts "caixa ##{inbox.id} tem #{conversas} conversas e #{mensagens} mensagens."
      puts 'nada foi apagado. rode de novo com APAGAR=1 para confirmar.'
      next
    end

    ids = Conversation.where(inbox_id: inbox.id).pluck(:id)
    Message.where(inbox_id: inbox.id).in_batches(of: 10_000).delete_all
    # delete_all nao dispara callback, entao a etiqueta (taggings) ficaria orfa apontando para
    # conversa que nao existe mais
    ids.each_slice(10_000) do |lote|
      ActsAsTaggableOn::Tagging.where(taggable_type: 'Conversation', taggable_id: lote).delete_all
    end
    Conversation.where(inbox_id: inbox.id).in_batches(of: 10_000).delete_all
    ContactInbox.where(inbox_id: inbox.id).delete_all
    inbox.destroy!
    puts "apagados: #{conversas} conversas e #{mensagens} mensagens; caixa removida."
  end
end

# O Octadesk abria um atendimento novo a cada mensagem quando nao havia ticket aberto: um cliente
# que mandou 5 mensagens em 6 minutos virou 5 "conversas" de uma linha cada. Esta tarefa junta o
# que era a mesma conversa, movendo as mensagens para a conversa mais antiga do grupo.
#
# Regra: mesmo contato, menos de JANELA_HORAS entre o fim de uma e o inicio da outra, e filas que
# nao se contradizem (uma das duas sem fila conta como compativel — o fragmento costuma vir sem).
# Disparo automatico de cobranca fica de fora: nao e conversa de gente.
# Consolida o historico numa caixa so: fonte nova que aparecer no futuro entra nela, em vez de
# criar mais uma caixa. Move conversas, mensagens e o elo com o contato.
class HistoricoMudanca
  def initialize(account:, origem:, destino:, simular: false)
    @account = account
    @origem = origem
    @destino = destino
    @simular = simular
  end

  def perform
    conversas = Conversation.where(inbox_id: @origem.id).count
    mensagens = Message.where(inbox_id: @origem.id).count
    puts "de '#{@origem.name}' (##{@origem.id}) para '#{@destino.name}' (##{@destino.id})"
    puts "conversas: #{conversas} | mensagens: #{mensagens}"
    return puts('SIMULACAO: nada foi alterado.') if @simular
    return puts('nada a mover.') if conversas.zero? && mensagens.zero?

    if conversas.positive?
      criar_elos_no_destino
      # o elo contato-caixa tem que acompanhar: conversa apontando para contact_inbox de outra
      # caixa confunde a tela e o envio
      ActiveRecord::Base.connection.execute(<<~SQL.squish)
        update conversations c set inbox_id = #{@destino.id}, contact_inbox_id = ci.id
        from contact_inboxes ci
        where ci.inbox_id = #{@destino.id} and ci.contact_id = c.contact_id
          and c.inbox_id = #{@origem.id}
      SQL
    end

    movidas = move_mensagens_em_lotes
    puts "movidas: #{conversas} conversas e #{movidas} mensagens"
    puts "sobrou na origem: #{Conversation.where(inbox_id: @origem.id).count} conversas, " \
         "#{Message.where(inbox_id: @origem.id).count} mensagens"
  end

  private

  # Um UPDATE em 700 mil linhas estoura o statement_timeout da conexao do app (o banco em si nao
  # tem limite). Em lotes de 20 mil cada passada termina com folga.
  def move_mensagens_em_lotes
    total = 0
    loop do
      movidas = ActiveRecord::Base.connection.update(<<~SQL.squish)
        update messages set inbox_id = #{@destino.id}
        where id in (select id from messages where inbox_id = #{@origem.id} limit 20000)
      SQL
      break if movidas.zero?

      total += movidas
      print '.'
    end
    puts if total.positive?
    total
  end

  def criar_elos_no_destino
    contatos = Conversation.where(inbox_id: @origem.id).distinct.pluck(:contact_id).compact
    ja_tem = ContactInbox.where(inbox_id: @destino.id, contact_id: contatos).pluck(:contact_id)
    faltando = ContactInbox.where(inbox_id: @origem.id, contact_id: contatos - ja_tem)
                           .pluck(:contact_id, :source_id).uniq { |contact_id, _| contact_id }
    return if faltando.empty?

    agora = Time.current
    ContactInbox.insert_all(faltando.map do |contact_id, source_id|
      { contact_id: contact_id, inbox_id: @destino.id, source_id: source_id,
        pubsub_token: SecureRandom.hex(16), created_at: agora, updated_at: agora }
    end)
    puts "elos contato-caixa criados no destino: #{faltando.size}"
  end
end

class HistoricoJuncao
  FORA = 'aviso-de-cobranca'

  def initialize(account:, inbox:, janela:, por_contato: false, simular: false)
    @account = account
    @inbox = inbox
    @janela = janela
    # por_contato: uma conversa por pessoa, com tudo dentro — sem olhar intervalo, fila ou origem
    @por_contato = por_contato
    @simular = simular
    @resumo = Hash.new(0)
  end

  def perform
    grupos = monta_grupos
    juntaveis = grupos.count { |g| g.size > 1 }
    puts "conversas analisadas: #{@total}"
    puts "grupos que viram uma conversa so: #{juntaveis} (de #{grupos.size} grupos)"
    puts "resultado: #{@total} -> #{grupos.size} conversas"
    return puts('SIMULACAO: nada foi alterado.') if @simular

    grupos.each do |grupo|
      junta(grupo) if grupo.size > 1
      print '.' if (@resumo['grupos juntados'] % 500).zero? && grupo.size > 1
    end
    puts "\n== resumo"
    @resumo.each { |k, v| puts "  #{k}: #{v}" }
  end

  private

  def monta_grupos
    escopo = Conversation.where(inbox_id: @inbox.id)
    # no modo por contato entra tudo, inclusive o disparo automatico de cobranca: a decisao foi
    # ter um fio unico por pessoa, com a historia inteira dela em ordem
    escopo = escopo.where("coalesce(cached_label_list, '') not like ?", "%#{FORA}%") unless @por_contato
    linhas = escopo.order(:contact_id, :created_at)
                   .pluck(:id, :contact_id, :created_at, :last_activity_at,
                          Arel.sql("additional_attributes->>'fila'"))
    @total = linhas.size
    grupos = []
    atual = []
    anterior = nil

    linhas.each do |id, contact_id, created_at, last_activity_at, fila|
      mudou_de_pessoa = anterior.nil? || anterior[:contact_id] != contact_id
      comeca_grupo = if @por_contato
                       mudou_de_pessoa
                     else
                       mudou_de_pessoa ||
                         (created_at - anterior[:fim]) > @janela ||
                         (fila.present? && anterior[:fila].present? && fila != anterior[:fila])
                     end
      if comeca_grupo && atual.any?
        grupos << atual
        atual = []
      end
      atual << id
      anterior = { contact_id: contact_id, fim: last_activity_at, fila: fila }
    end
    grupos << atual if atual.any?
    grupos
  end

  def junta(grupo)
    principal, *outros = grupo

    ActiveRecord::Base.transaction do
      Message.where(conversation_id: outros).update_all(conversation_id: principal)

      todas = Conversation.where(id: grupo)
      fim = todas.maximum(:last_activity_at)
      etiquetas = todas.pluck(:cached_label_list).compact
                       .flat_map { |lista| lista.split(',').map(&:strip) }.reject(&:blank?).uniq
      ids_octadesk = todas.pluck(Arel.sql("additional_attributes->>'octadesk_chat_id'")).compact

      ActsAsTaggableOn::Tagging.where(taggable_type: 'Conversation', taggable_id: outros).delete_all
      ja_tem = ActsAsTaggableOn::Tagging.where(taggable_type: 'Conversation', taggable_id: principal)
                                        .pluck(:tag_id).to_set
      tags = ActsAsTaggableOn::Tag.where(name: etiquetas).pluck(:name, :id).to_h
      faltando = etiquetas.filter_map do |nome|
        id = tags[nome]
        next if id.nil? || ja_tem.include?(id)

        { tag_id: id, taggable_type: 'Conversation', taggable_id: principal,
          context: 'labels', created_at: Time.current }
      end
      ActsAsTaggableOn::Tagging.insert_all(faltando) if faltando.any?

      conversa = Conversation.find(principal)
      conversa.update_columns(
        last_activity_at: fim, updated_at: fim,
        agent_last_seen_at: fim, assignee_last_seen_at: fim, contact_last_seen_at: fim,
        cached_label_list: etiquetas.join(', '),
        # guarda de onde veio cada pedaco: sem isso a origem no Octadesk se perde
        additional_attributes: (conversa.additional_attributes || {})
          .merge('octadesk_chat_ids' => ids_octadesk, 'juntado_de' => grupo.size)
      )
      Conversation.where(id: outros).delete_all
    end

    @resumo['grupos juntados'] += 1
    @resumo['conversas absorvidas'] += outros.size
  end
end

# Liga ao historico a midia que ja foi enviada ao Blob pelo PC (scripts/prepara_midia.py +
# sobe_midia.ps1). O arquivo nao passa por aqui: o que entra e so o registro das tres tabelas que
# o ActiveStorage e o Chatwoot esperam.
class HistoricoMidia
  LOTE = 2_000
  SERVICO = 'microsoft' # config/storage.yml

  # marcador de texto que a carga sem midia deixou: "[imagem] IMG-123.jpg", "[documento] x.pdf",
  # "[nome-do-arquivo]" — agora que o anexo existe de verdade, o marcador so atrapalha
  MARCADOR = /\A\[(imagem|áudio|vídeo|documento|figurinha|contato|localização)[^\]]*\]|\A\[[^\]]+\]\z/

  def initialize(manifesto:, account:, caixas:)
    @manifesto = manifesto
    @account = account
    @caixas = caixas
    @resumo = Hash.new(0)
  end

  def perform
    raise "manifesto nao encontrado: #{@manifesto}" unless @manifesto.file?

    File.foreach(@manifesto).each_slice(LOTE) do |linhas|
      processa(linhas.map { |l| JSON.parse(l) })
      print '.'
    end
    puts
    limpa_marcadores

    puts "\n== resumo"
    @resumo.each { |k, v| puts "  #{k}: #{v}" }
  end

  private

  def processa(itens)
    ja_existem = ActiveStorage::Blob.where(key: itens.map { |i| i['key'] }).pluck(:key).to_set
    itens = itens.reject { |i| ja_existem.include?(i['key']) }
    @resumo['anexos ja existentes (pulados)'] += ja_existem.size
    return if itens.empty?

    mensagens = Message.where(inbox_id: @caixas, source_id: itens.map { |i| i['source_id'] })
                       .pluck(:source_id, :id, :account_id)
                       .to_h { |source_id, id, account_id| [source_id, [id, account_id]] }
    sem_mensagem, itens = itens.partition { |i| mensagens[i['source_id']].nil? }
    @resumo['arquivos sem mensagem correspondente'] += sem_mensagem.size
    return if itens.empty?

    agora = Time.current
    ActiveStorage::Blob.insert_all(itens.map do |i|
      { key: i['key'], filename: i['filename'], content_type: i['content_type'], metadata: '{}',
        byte_size: i['byte_size'], service_name: SERVICO, created_at: agora }
    end)
    blobs = ActiveStorage::Blob.where(key: itens.map { |i| i['key'] }).pluck(:key, :id).to_h

    Attachment.insert_all(itens.map do |i|
      message_id, account_id = mensagens[i['source_id']]
      { message_id: message_id, account_id: account_id, file_type: i['file_type'],
        extension: File.extname(i['filename']).delete('.').presence,
        # a chave do blob fica no meta para reencontrar o id do anexo sem depender da ordem em
        # que o banco devolveu as linhas
        meta: { 'import_key' => i['key'] }, created_at: agora, updated_at: agora }
    end)
    anexos = Attachment.where(message_id: mensagens.values.map(&:first))
                       .where("meta->>'import_key' is not null")
                       .pluck(Arel.sql("meta->>'import_key'"), :id).to_h

    vinculos = itens.filter_map do |i|
      record_id = anexos[i['key']]
      next if record_id.nil?

      { name: 'file', record_type: 'Attachment', record_id: record_id,
        blob_id: blobs[i['key']], created_at: agora }
    end
    ActiveStorage::Attachment.insert_all(vinculos) if vinculos.any?
    @resumo['anexos ligados'] += vinculos.size
  end

  def limpa_marcadores
    alvo = Message.where(inbox_id: @caixas)
                  .where('exists (select 1 from attachments a where a.message_id = messages.id)')
    limpos = 0
    alvo.select(:id, :content).find_in_batches(batch_size: 5_000) do |lote|
      ids = lote.select { |m| m.content.to_s.match?(MARCADOR) }.map(&:id)
      next if ids.empty?

      limpos += Message.where(id: ids).update_all(content: '')
    end
    @resumo['marcadores de texto limpos'] = limpos
  end
end

class HistoricoImport
  ESTADO_MENSAGEM = { 'sent' => 0, 'delivered' => 1, 'read' => 2, 'failed' => 3 }.freeze

  def self.caixa(account, nome)
    account.inboxes.find_by(name: nome) || begin
      # historico_importado: a tela usa essa marca para abrir a caixa com status "Todos" — sem
      # ela o atendente ve lista vazia, porque conversa importada nasce resolvida
      canal = Channel::Api.create!(account: account, webhook_url: nil,
                                   additional_attributes: { 'historico_importado' => true })
      account.inboxes.create!(name: nome, channel: canal, enable_auto_assignment: false)
    end
  end

  def initialize(dir:, account:, inbox:, limite: nil)
    @dir = dir
    @account = account
    @inbox = inbox
    @limite = limite
    @resumo = Hash.new(0)
  end

  def perform
    conversas = escolhe_conversas
    puts "conversas a importar: #{conversas.size}#{@limite ? " (piloto: as #{@limite} maiores)" : ''}"
    return puts('nada novo a importar.') if conversas.empty?

    identificadores = conversas.map { |c| c['identifier'] }.to_set
    contatos = resolve_contatos(conversas)
    ids_por_identificador = grava_conversas(conversas, contatos)
    grava_mensagens(identificadores, ids_por_identificador)
    grava_etiquetas(conversas, ids_por_identificador)

    puts "\n== resumo"
    @resumo.each { |k, v| puts "  #{k}: #{v}" }
    puts "\ncaixa ##{@inbox.id} (#{@inbox.name}) — ver em /app/accounts/#{@account.id}/inbox/#{@inbox.id}"
  end

  private

  # No piloto vale mostrar conversa cheia, nao a primeira que aparecer: escolhe as que tem mais
  # mensagens. Sem limite, importa tudo que ainda nao entrou.
  def escolhe_conversas
    ja_existem = Conversation.where(account_id: @account.id, inbox_id: @inbox.id)
                             .where.not(identifier: nil).pluck(:identifier).to_set
    todas = []
    File.foreach(@dir.join('conversations.ndjson')) do |linha|
      c = JSON.parse(linha)
      next if ja_existem.include?(c['identifier'])

      todas << c
    end
    @resumo['conversas ja existentes (puladas)'] = ja_existem.size
    return todas unless @limite

    contagem = Hash.new(0)
    File.foreach(@dir.join('messages.ndjson')) { |l| contagem[JSON.parse(l)['conversa']] += 1 }
    todas.sort_by { |c| -contagem[c['identifier']] }.first(@limite)
  end

  def resolve_contatos(conversas)
    desejados = conversas.map { |c| c['contato'] }.to_set
    fichas = {}
    File.foreach(@dir.join('contacts.ndjson')) do |linha|
      f = JSON.parse(linha)
      fichas[f['telefone']] = f if desejados.include?(f['telefone'])
    end

    # Contato que ja existe na base manda: reaproveita como esta e nao atualiza nome, e-mail nem
    # atributos. O historico e dado antigo; quem esta na base hoje foi cadastrado pela operacao e
    # vale mais. O telefone e procurado tambem na variante sem o nono digito (numero de 2023 pode
    # estar gravado sem ele), e so quando nao existe em nenhuma forma e que um contato e criado.
    todos_fones = fichas.values.flat_map { |f| [f['telefone']] + Array(f['telefones_alternativos']) }
    achados = @account.contacts.where(phone_number: todos_fones).pluck(:phone_number, :id).to_h

    novos = fichas.values.reject { |f| ([f['telefone']] + Array(f['telefones_alternativos'])).any? { |t| achados[t] } }
    if novos.any?
      agora = Time.current
      Contact.insert_all(novos.map do |f|
        { name: f['nome'].presence || f['telefone'], phone_number: f['telefone'],
          account_id: @account.id, created_at: agora, updated_at: agora,
          custom_attributes: f['custom_attributes'] || {},
          additional_attributes: { 'import_source' => 'historico' } }
      end)
      achados.merge!(@account.contacts.where(phone_number: novos.map { |f| f['telefone'] })
                             .pluck(:phone_number, :id).to_h)
      @resumo['contatos criados'] = novos.size
    end
    @resumo['contatos casados com a base'] = fichas.size - novos.size

    # contact_inbox: o elo entre o contato e esta caixa; source_id e o telefone
    por_contato = {}
    fichas.each_value do |f|
      id = ([f['telefone']] + Array(f['telefones_alternativos'])).filter_map { |t| achados[t] }.first
      por_contato[f['telefone']] = id if id
    end
    existentes = ContactInbox.where(inbox_id: @inbox.id, source_id: por_contato.keys)
                             .pluck(:source_id, :id, :contact_id)
    elo = existentes.to_h { |source_id, id, contact_id| [source_id, [id, contact_id]] }
    faltando = por_contato.reject { |fone, _| elo[fone] }
    if faltando.any?
      agora = Time.current
      ContactInbox.insert_all(faltando.map do |fone, contact_id|
        { contact_id: contact_id, inbox_id: @inbox.id, source_id: fone,
          pubsub_token: SecureRandom.hex(16), created_at: agora, updated_at: agora }
      end)
      ContactInbox.where(inbox_id: @inbox.id, source_id: faltando.keys)
                  .pluck(:source_id, :id, :contact_id)
                  .each { |source_id, id, contact_id| elo[source_id] = [id, contact_id] }
    end
    elo
  end

  def grava_conversas(conversas, elo)
    agora = Time.current
    linhas = conversas.filter_map do |c|
      contact_inbox_id, contact_id = elo[c['contato']]
      unless contact_id
        @resumo['conversas sem contato (puladas)'] += 1
        next # sem valor: o filter_map descarta a linha em vez de guardar o retorno
      end

      { account_id: @account.id, inbox_id: @inbox.id, contact_id: contact_id,
        contact_inbox_id: contact_inbox_id, status: 1, # resolvida: fica fora da fila viva
        created_at: c['created_at'], updated_at: c['last_activity_at'],
        last_activity_at: c['last_activity_at'], identifier: c['identifier'],
        # historico nao pode chegar como "nao lido": sem isso, 61 mil conversas antigas caem no
        # contador da equipe como se fossem mensagem nova esperando resposta
        agent_last_seen_at: c['last_activity_at'],
        assignee_last_seen_at: c['last_activity_at'],
        contact_last_seen_at: c['last_activity_at'],
        additional_attributes: c['additional_attributes'] || {},
        cached_label_list: Array(c['labels']).join(', ') }
    end

    mapa = {}
    linhas.each_slice(LOTE) do |lote|
      Conversation.insert_all(lote, returning: %w[id identifier]).each do |r|
        mapa[r['identifier']] = r['id']
      end
      @resumo['conversas criadas'] += lote.size
      print '.'
    end
    puts
    mapa
  end

  def grava_mensagens(identificadores, ids_por_identificador)
    usuarios = User.joins(:account_users).where(account_users: { account_id: @account.id })
                   .pluck(:email, :id).to_h
    ja_existem = Message.where(inbox_id: @inbox.id).where.not(source_id: nil).pluck(:source_id).to_set
    # de uma vez so: descobrir o contato de cada conversa aqui evita uma consulta por mensagem
    contato_da_conversa = Conversation.where(id: ids_por_identificador.values).pluck(:id, :contact_id).to_h
    lote = []

    File.foreach(@dir.join('messages.ndjson')) do |linha|
      m = JSON.parse(linha)
      next unless identificadores.include?(m['conversa'])
      next if ja_existem.include?(m['source_id'])

      conversation_id = ids_por_identificador[m['conversa']]
      next unless conversation_id

      entrada = m['direcao'] == 'incoming'
      remetente = m['remetente'] || {}
      user_id = usuarios[remetente['email']] if remetente['email']
      contact_id = contato_da_conversa[conversation_id] if entrada

      lote << {
        account_id: @account.id, inbox_id: @inbox.id, conversation_id: conversation_id,
        message_type: entrada ? 0 : 1, content: m['content'], private: m['privada'] || false,
        status: ESTADO_MENSAGEM.fetch(m['status'], 0), source_id: m['source_id'], content_type: 0,
        content_attributes: m['responde_a'] ? { 'in_reply_to_external_id' => m['responde_a'] } : {},
        sender_type: entrada ? 'Contact' : (user_id ? 'User' : nil),
        sender_id: entrada ? contact_id : user_id,
        created_at: m['created_at'], updated_at: m['created_at'],
        additional_attributes: {
          'import_source' => 'historico',
          # quem atendeu e nao existe mais como usuario do Chatwoot fica registrado pelo nome
          'agent_name' => (remetente['nome'] if !entrada && user_id.nil?)
        }.compact
      }
      @resumo['mensagens com anexo (texto por enquanto)'] += 1 if m['anexos'].present?

      if lote.size >= LOTE
        Message.insert_all(lote)
        @resumo['mensagens criadas'] += lote.size
        lote = []
        print '.'
      end
    end

    if lote.any?
      Message.insert_all(lote)
      @resumo['mensagens criadas'] += lote.size
    end
    puts
  end

  # Etiqueta no Chatwoot e acts_as_taggable (tags + taggings) mais uma linha em labels para
  # aparecer na barra lateral. cached_label_list ja foi gravado junto da conversa.
  def grava_etiquetas(conversas, ids_por_identificador)
    titulos = conversas.flat_map { |c| Array(c['labels']) }.uniq
    return if titulos.empty?

    agora = Time.current
    existentes = Label.where(account_id: @account.id, title: titulos).pluck(:title).to_set
    faltando = titulos - existentes.to_a
    if faltando.any?
      Label.insert_all(faltando.map do |t|
        { title: t, account_id: @account.id, color: '#6c757d', show_on_sidebar: true,
          created_at: agora, updated_at: agora }
      end)
    end

    tags = titulos.to_h { |t| [t, ActsAsTaggableOn::Tag.find_or_create_by!(name: t).id] }
    vinculos = conversas.flat_map do |c|
      id = ids_por_identificador[c['identifier']]
      next [] unless id

      Array(c['labels']).map do |t|
        { tag_id: tags[t], taggable_type: 'Conversation', taggable_id: id,
          context: 'labels', created_at: agora }
      end
    end
    vinculos.each_slice(LOTE) { |l| ActsAsTaggableOn::Tagging.insert_all(l) }
    @resumo['etiquetas aplicadas'] = vinculos.size
  end
end
