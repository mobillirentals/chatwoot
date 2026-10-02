/**
 * Encerrar a conversa sem mandar a pesquisa de satisfação.
 *
 * Quem decide isso é a regra nativa da caixa (Caixas → CSAT → regras de pesquisa): com o operador
 * `does_not_contain`, o Chatwoot deixa de enviar a pesquisa nas conversas que tiverem uma das
 * etiquetas listadas. A opção "Encerrar" do painel não inventa comportamento novo — ela põe a
 * etiqueta combinada e resolve a conversa.
 *
 * Por isso a etiqueta é lida da própria configuração, e não fixa no código: trocar o nome dela na
 * tela de Caixas basta, sem deploy.
 *
 * @param {Object} inbox caixa da conversa, como vem da API
 * @returns {string} a etiqueta que silencia a pesquisa, ou '' quando a caixa não está preparada
 */
export const etiquetaQueSilenciaOCsat = inbox => {
  if (!inbox?.csat_survey_enabled) return '';

  const regra = inbox.csat_config?.survey_rules;
  // `contains` faz o oposto (só envia QUANDO tem a etiqueta), então marcar a conversa ali
  // mandaria a pesquisa em vez de impedi-la
  if (regra?.operator !== 'does_not_contain') return '';

  return regra.values?.[0] || '';
};
