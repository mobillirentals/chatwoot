import { etiquetaQueSilenciaOCsat } from '../encerrarSemAvaliacao';

const caixaCom = (survey_rules, csat_survey_enabled = true) => ({
  csat_survey_enabled,
  csat_config: survey_rules ? { survey_rules } : {},
});

describe('etiquetaQueSilenciaOCsat', () => {
  it('devolve a etiqueta configurada na regra', () => {
    const caixa = caixaCom({
      operator: 'does_not_contain',
      values: ['sem-avaliacao'],
    });

    expect(etiquetaQueSilenciaOCsat(caixa)).toBe('sem-avaliacao');
  });

  it('não devolve nada quando a pesquisa está desligada na caixa', () => {
    const caixa = caixaCom(
      { operator: 'does_not_contain', values: ['sem-avaliacao'] },
      false
    );

    expect(etiquetaQueSilenciaOCsat(caixa)).toBe('');
  });

  // `contains` faz o oposto: a pesquisa só sai QUANDO a conversa tem a etiqueta. Marcar a
  // conversa nesse caso mandaria a pesquisa — justamente o que se quer evitar.
  it('ignora a regra que manda a pesquisa em vez de impedi-la', () => {
    const caixa = caixaCom({ operator: 'contains', values: ['avaliar'] });

    expect(etiquetaQueSilenciaOCsat(caixa)).toBe('');
  });

  it('não devolve nada quando a caixa não tem regra nenhuma', () => {
    expect(etiquetaQueSilenciaOCsat(caixaCom(null))).toBe('');
  });

  it('não devolve nada quando a regra está sem etiqueta', () => {
    const caixa = caixaCom({ operator: 'does_not_contain', values: [] });

    expect(etiquetaQueSilenciaOCsat(caixa)).toBe('');
  });

  it('aguenta caixa ausente, que é o estado durante o carregamento', () => {
    expect(etiquetaQueSilenciaOCsat(undefined)).toBe('');
    expect(etiquetaQueSilenciaOCsat({})).toBe('');
  });
});
