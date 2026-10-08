import {
  findVariables,
  variablesAreSequential,
  insertVariable,
  nextVariable,
  validateTemplate,
  previewText,
  fromComponents,
  slugifyName,
  hasDanglingVariable,
  syncExamples,
  unsupportedReason,
  LIMITS,
} from '../composeTemplate';

// A Meta recusa o modelo inteiro por detalhe de formato e devolve mensagem genérica, depois de a
// pessoa ter preenchido tudo. Estas regras existem para o erro aparecer antes do envio.
describe('variáveis', () => {
  it('acha as variáveis em ordem, sem repetir', () => {
    expect(findVariables('Olá {{2}}, seu código é {{1}} — {{2}}')).toEqual([
      1, 2,
    ]);
  });

  it('exige numeração a partir de 1, sem buraco', () => {
    expect(variablesAreSequential('Oi {{1}}, veja {{2}}')).toBe(true);
    expect(variablesAreSequential('Oi {{1}}, veja {{3}}')).toBe(false);
    expect(variablesAreSequential('Oi {{2}}')).toBe(false);
  });

  it('sugere a próxima pelo que já existe', () => {
    expect(nextVariable('Oi {{1}}')).toBe(2);
    expect(nextVariable('')).toBe(1);
  });

  // Digitar a chave na mão erra a numeração com facilidade; inserir no cursor é como a Meta faz.
  it('insere no cursor e devolve onde o cursor fica', () => {
    const { texto, cursor } = insertVariable('Olá , tudo bem?', 4);

    expect(texto).toBe('Olá {{1}}, tudo bem?');
    expect(cursor).toBe(9);
  });
});

describe('validateTemplate', () => {
  const valido = {
    name: 'aviso_pagamento',
    body: 'Olá {{1}}, tudo bem?',
    examples: { 1: 'Ana' },
  };

  it('aceita um modelo bem formado', () => {
    expect(validateTemplate(valido)).toEqual({});
  });

  it('recusa nome com maiúscula ou espaço', () => {
    expect(validateTemplate({ ...valido, name: 'Aviso Pagamento' }).name).toBe(
      'FORMAT'
    );
  });

  it('exige corpo', () => {
    expect(validateTemplate({ ...valido, body: '   ' }).body).toBe('REQUIRED');
  });

  it('recusa variável fora de ordem no corpo', () => {
    expect(validateTemplate({ ...valido, body: 'Oi {{2}}' }).body).toBe(
      'VARIABLE_ORDER'
    );
  });

  // Rodapé com variável a Meta recusa sem dizer onde está o problema.
  it('recusa variável no rodapé', () => {
    expect(validateTemplate({ ...valido, footer: 'Equipe {{1}}' }).footer).toBe(
      'NO_VARIABLES'
    );
  });

  it('aceita no máximo uma variável no cabeçalho', () => {
    expect(
      validateTemplate({ ...valido, header: 'Oi {{1}} {{2}}' }).header
    ).toBe('ONE_VARIABLE');
  });

  it('cobra endereço em botão de link', () => {
    const buttons = [{ type: 'URL', text: 'Acessar' }];

    expect(validateTemplate({ ...valido, buttons }).buttons).toBe(
      'URL_REQUIRED'
    );
  });

  it('cobra texto em qualquer botão', () => {
    const buttons = [{ type: 'QUICK_REPLY', text: '' }];

    expect(validateTemplate({ ...valido, buttons }).buttons).toBe(
      'TEXT_REQUIRED'
    );
  });

  it('respeita o teto de botões', () => {
    const buttons = Array.from({ length: LIMITS.buttons + 1 }, () => ({
      type: 'QUICK_REPLY',
      text: 'Sim',
    }));

    expect(validateTemplate({ ...valido, buttons }).buttons).toBe('TOO_MANY');
  });

  // A Meta não deixa trocar o nome de um modelo existente, então editar não valida esse campo.
  it('não cobra nome ao editar', () => {
    expect(validateTemplate({ body: 'Olá!' }, { editing: true })).toEqual({});
  });
});

describe('previewText', () => {
  it('troca as variáveis por exemplo, para a prévia ser julgável', () => {
    expect(previewText('Olá {{1}}, seu pedido {{2}} chegou')).toBe(
      'Olá exemplo 1, seu pedido exemplo 2 chegou'
    );
  });
});

describe('fromComponents', () => {
  it('desmonta o modelo da Meta nos campos da tela', () => {
    const modelo = fromComponents({
      name: 'aviso_pagamento',
      language: 'pt_BR',
      category: 'utility',
      components: [
        { type: 'HEADER', format: 'TEXT', text: 'Mobilli' },
        {
          type: 'BODY',
          text: 'Ola {{1}}, reserva {{2}}',
          example: { body_text: [['Ana', '4821']] },
        },
        { type: 'FOOTER', text: 'Equipe Mobilli' },
        {
          type: 'BUTTONS',
          buttons: [
            { type: 'QUICK_REPLY', text: 'Sim' },
            { type: 'URL', text: 'Pagar', url: 'https://mobilli' },
          ],
        },
      ],
    });

    expect(modelo).toEqual({
      name: 'aviso_pagamento',
      language: 'pt_BR',
      category: 'UTILITY',
      header: 'Mobilli',
      body: 'Ola {{1}}, reserva {{2}}',
      // Os exemplos voltam indexados pela variável, para a tela preencher os campos ao editar.
      examples: { 1: 'Ana', 2: '4821' },
      footer: 'Equipe Mobilli',
      buttons: [
        { type: 'QUICK_REPLY', text: 'Sim', url: '' },
        { type: 'URL', text: 'Pagar', url: 'https://mobilli' },
      ],
    });
  });
});

// Editar reenvia o modelo inteiro, entao o que a tela nao sabe remontar seria apagado no caminho.
describe('unsupportedReason', () => {
  const corpo = [{ type: 'BODY', text: 'Ola' }];

  it('libera o que a tela sabe remontar', () => {
    expect(
      unsupportedReason({ category: 'UTILITY', components: corpo })
    ).toBeNull();
  });

  it('barra cabecalho de midia', () => {
    const components = [{ type: 'HEADER', format: 'IMAGE' }, ...corpo];

    expect(unsupportedReason({ components })).toBe('MEDIA_HEADER');
  });

  it('barra componente que nao montamos', () => {
    const components = [...corpo, { type: 'CAROUSEL' }];

    expect(unsupportedReason({ components })).toBe('EXTRA_COMPONENT');
  });

  it('barra botao fora de resposta rapida e link', () => {
    const components = [
      ...corpo,
      { type: 'BUTTONS', buttons: [{ type: 'PHONE_NUMBER', text: 'Ligar' }] },
    ];

    expect(unsupportedReason({ components })).toBe('BUTTON_TYPE');
  });

  it('barra categoria legada, que a Meta nao aceita mais', () => {
    expect(
      unsupportedReason({ category: 'TRANSACTIONAL', components: corpo })
    ).toBe('CATEGORY');
  });

  it('barra autenticacao, que tem formato proprio na Meta', () => {
    expect(
      unsupportedReason({ category: 'AUTHENTICATION', components: corpo })
    ).toBe('AUTHENTICATION');
  });
});

// A Meta so aceita [a-z0-9_] no nome e normaliza sozinha no painel dela.
describe('slugifyName', () => {
  it('troca espaco por sublinhado e tira acento', () => {
    expect(slugifyName('Aviso de Pagamento Atrasado')).toBe(
      'aviso_de_pagamento_atrasado'
    );
    expect(slugifyName('Confirmacao de Reserva')).toBe(
      'confirmacao_de_reserva'
    );
  });

  it('remove caractere especial e nao acumula sublinhado', () => {
    expect(slugifyName('promo!! 50% -- off')).toBe('promo_50_off');
  });

  it('nao comeca com sublinhado', () => {
    expect(slugifyName('  aviso')).toBe('aviso');
  });

  // Tirar o sublinhado do fim atrapalharia quem ainda esta digitando a proxima palavra.
  it('mantem o sublinhado do fim enquanto digita', () => {
    expect(slugifyName('aviso ')).toBe('aviso_');
  });
});

describe('unsupportedReason com status', () => {
  const corpo = [{ type: 'BODY', text: 'Ola' }];

  it('barra modelo ainda em analise', () => {
    expect(unsupportedReason({ status: 'PENDING', components: corpo })).toBe(
      'STATUS'
    );
  });

  it('libera aprovado, reprovado e pausado', () => {
    ['APPROVED', 'REJECTED', 'PAUSED'].forEach(status => {
      expect(unsupportedReason({ status, components: corpo })).toBeNull();
    });
  });
});

// A Meta chama de "dangling parameter" e recusa o modelo.
describe('hasDanglingVariable', () => {
  it('acusa variavel no comeco e no fim', () => {
    expect(hasDanglingVariable('{{1}}, seu pedido chegou')).toBe(true);
    expect(hasDanglingVariable('Seu pedido chegou {{1}}')).toBe(true);
    expect(hasDanglingVariable('  Teste {{2}}  ')).toBe(true);
  });

  it('libera variavel cercada de texto', () => {
    expect(hasDanglingVariable('Ola {{1}}, tudo bem?')).toBe(false);
  });
});

describe('exemplos das variaveis', () => {
  it('cobra um exemplo por variavel', () => {
    const modelo = {
      name: 'aviso',
      body: 'Ola {{1}}, sua reserva {{2}} esta ok.',
      examples: { 1: 'Ana' },
    };

    expect(validateTemplate(modelo).examples).toBe('REQUIRED');
  });

  it('aceita quando todas tem exemplo', () => {
    const modelo = {
      name: 'aviso',
      body: 'Ola {{1}}, sua reserva {{2}} esta ok.',
      examples: { 1: 'Ana', 2: '4821' },
    };

    expect(validateTemplate(modelo)).toEqual({});
  });

  it('nao cobra exemplo quando nao ha variavel', () => {
    expect(validateTemplate({ name: 'aviso', body: 'Tudo certo!' })).toEqual(
      {}
    );
  });

  // Apagar uma variavel nao pode deixar o exemplo orfao viajando para a Meta.
  it('sincroniza os campos com as variaveis do corpo', () => {
    expect(syncExamples('Ola {{1}} e {{2}}', { 1: 'Ana', 2: 'Bruno' })).toEqual(
      {
        1: 'Ana',
        2: 'Bruno',
      }
    );
    expect(syncExamples('Ola {{1}}', { 1: 'Ana', 2: 'Bruno' })).toEqual({
      1: 'Ana',
    });
    expect(syncExamples('Ola {{1}} e {{2}}', { 1: 'Ana' })).toEqual({
      1: 'Ana',
      2: '',
    });
  });

  it('usa o exemplo real na previa', () => {
    expect(previewText('Ola {{1}}, reserva {{2}}', { 1: 'Ana' })).toBe(
      'Ola Ana, reserva exemplo 2'
    );
  });
});
