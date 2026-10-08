// Regras da Meta para montar um modelo, do lado do navegador.
//
// Elas vivem aqui, puras, por um motivo prático: a Meta recusa o modelo inteiro por um detalhe de
// formato e devolve uma mensagem genérica, depois de o usuário ter preenchido tudo. Validar antes
// de enviar é a diferença entre "corrija o nome" e "algo deu errado".
//
// O servidor valida de novo — isto é conveniência, não segurança.

export const CATEGORIES = ['MARKETING', 'UTILITY'];
export const BUTTON_TYPES = ['QUICK_REPLY', 'URL'];

export const LIMITS = {
  name: 512,
  header: 60,
  body: 1024,
  footer: 60,
  buttonText: 25,
  buttons: 10,
};

export const NAME_FORMAT = /^[a-z0-9_]+$/;

export const findVariables = texto =>
  [...new Set((texto || '').match(/\{\{(\d+)\}\}/g) || [])]
    .map(v => Number(v.replace(/\D/g, '')))
    .sort((a, b) => a - b);

// A Meta exige variáveis numeradas a partir de 1, sem buraco: {{1}} {{3}} é recusado.
export const variablesAreSequential = texto => {
  const numeros = findVariables(texto);
  return numeros.every((n, i) => n === i + 1);
};

export const nextVariable = texto => findVariables(texto).length + 1;

// Insere {{n}} na posição do cursor, que é como a Meta faz — digitar a chave na mão erra a
// numeração com facilidade.
export const insertVariable = (texto, posicao) => {
  const marcador = `{{${nextVariable(texto)}}}`;
  const antes = (texto || '').slice(0, posicao);
  const depois = (texto || '').slice(posicao);
  return {
    texto: `${antes}${marcador}${depois}`,
    cursor: antes.length + marcador.length,
  };
};

// A Meta chama de "dangling parameter" e recusa: o texto não pode começar nem terminar com
// variável. "{{1}}, seu pedido chegou" e "Seu pedido chegou {{1}}" são reprovados; precisa de
// texto fixo dos dois lados.
export const hasDanglingVariable = texto => {
  const limpo = (texto || '').trim();
  return /^\{\{\d+\}\}/.test(limpo) || /\{\{\d+\}\}$/.test(limpo);
};

export const validateTemplate = (modelo, { editing = false } = {}) => {
  const erros = {};

  if (!editing) {
    if (!modelo.name) erros.name = 'REQUIRED';
    else if (!NAME_FORMAT.test(modelo.name)) erros.name = 'FORMAT';
    else if (modelo.name.length > LIMITS.name) erros.name = 'TOO_LONG';
  }

  if (!modelo.body?.trim()) erros.body = 'REQUIRED';
  else if (modelo.body.length > LIMITS.body) erros.body = 'TOO_LONG';
  else if (!variablesAreSequential(modelo.body)) erros.body = 'VARIABLE_ORDER';
  else if (hasDanglingVariable(modelo.body)) erros.body = 'DANGLING';

  // A Meta exige um exemplo para cada variável, e usa esse valor para entender o modelo na
  // análise — por isso cobramos aqui em vez de preencher com algo genérico por baixo.
  const faltandoExemplo = findVariables(modelo.body).some(
    numero => !modelo.examples?.[numero]?.trim()
  );
  if (!erros.body && faltandoExemplo) erros.examples = 'REQUIRED';

  if (modelo.header?.length > LIMITS.header) erros.header = 'TOO_LONG';
  // Cabeçalho aceita no máximo uma variável — a Meta recusa a partir da segunda.
  else if (findVariables(modelo.header).length > 1)
    erros.header = 'ONE_VARIABLE';

  if (modelo.footer?.length > LIMITS.footer) erros.footer = 'TOO_LONG';
  else if (findVariables(modelo.footer).length) erros.footer = 'NO_VARIABLES';

  const botoes = modelo.buttons || [];
  if (botoes.length > LIMITS.buttons) erros.buttons = 'TOO_MANY';
  else if (botoes.some(b => !b.text?.trim())) erros.buttons = 'TEXT_REQUIRED';
  else if (botoes.some(b => b.type === 'URL' && !b.url?.trim()))
    erros.buttons = 'URL_REQUIRED';

  return erros;
};

// O que o cliente vê: as variáveis viram o exemplo que a pessoa escreveu, senão a prévia mostra
// {{1}} e ninguém consegue julgar se a mensagem ficou boa.
export const previewText = (texto, exemplos = {}) =>
  (texto || '').replace(
    /\{\{(\d+)\}\}/g,
    (_, n) => exemplos?.[n]?.trim() || `exemplo ${n}`
  );

// Mantém um campo de exemplo por variável do corpo, preservando o que já foi escrito. Sem isso,
// apagar uma variável deixaria o exemplo órfão viajando para a Meta.
export const syncExamples = (body, exemplos = {}) =>
  Object.fromEntries(
    findVariables(body).map(numero => [numero, exemplos?.[numero] || ''])
  );

// Desmonta o modelo que a Meta devolve de volta nos campos da tela, para editar.
export const fromComponents = (template = {}) => {
  const componentes = template.components || [];
  const achar = tipo => componentes.find(c => c.type?.toUpperCase() === tipo);

  const corpo = achar('BODY');
  // A Meta devolve os exemplos do corpo como uma lista dentro de outra, uma posição por variável.
  const exemplos = corpo?.example?.body_text?.[0] || [];

  return {
    name: template.name || '',
    language: template.language || 'pt_BR',
    category: (template.category || 'UTILITY').toUpperCase(),
    header: achar('HEADER')?.text || '',
    body: corpo?.text || '',
    examples: Object.fromEntries(
      exemplos.map((valor, indice) => [indice + 1, valor || ''])
    ),
    footer: achar('FOOTER')?.text || '',
    buttons: (achar('BUTTONS')?.buttons || []).map(botao => ({
      type: botao.type?.toUpperCase(),
      text: botao.text || '',
      url: botao.url || '',
    })),
  };
};

// A Meta só deixa editar modelo nestes estados. Um PENDING ainda está em análise, e a tentativa
// de salvar volta como erro depois de a pessoa ter reescrito tudo.
export const EDITABLE_STATUSES = ['APPROVED', 'REJECTED', 'PAUSED'];

// Editar na nossa tela reenvia o modelo inteiro: o que ela não sabe remontar seria APAGADO no
// caminho. Então o que está fora do nosso alcance continua sendo editado no painel da Meta.
export const unsupportedReason = (template = {}) => {
  const componentes = template.components || [];
  const tipos = componentes.map(c => c.type?.toUpperCase());

  const status = (template.status || '').toUpperCase();
  if (status && !EDITABLE_STATUSES.includes(status)) return 'STATUS';

  const categoria = (template.category || '').toUpperCase();
  if (categoria === 'AUTHENTICATION') return 'AUTHENTICATION';
  // Categoria legada (TRANSACTIONAL, OTP) a Meta ainda devolve em modelo antigo, e salvar
  // mandaria ela de volta num envio que a Meta recusa.
  if (categoria && !CATEGORIES.includes(categoria)) return 'CATEGORY';

  const cabecalho = componentes.find(c => c.type?.toUpperCase() === 'HEADER');
  if (cabecalho && (cabecalho.format || 'TEXT').toUpperCase() !== 'TEXT')
    return 'MEDIA_HEADER';

  if (
    tipos.some(tipo => !['HEADER', 'BODY', 'FOOTER', 'BUTTONS'].includes(tipo))
  )
    return 'EXTRA_COMPONENT';

  const botoes =
    componentes.find(c => c.type?.toUpperCase() === 'BUTTONS')?.buttons || [];
  if (botoes.some(botao => !BUTTON_TYPES.includes(botao.type?.toUpperCase())))
    return 'BUTTON_TYPE';

  return null;
};

// A Meta normaliza o nome sozinha no painel dela, e so aceita [a-z0-9_]. Fazer isso enquanto a
// pessoa digita evita o unico erro que ela nao tem como adivinhar: acento e espaco sao naturais
// de escrever e seriam recusados.
export const slugifyName = texto =>
  (texto || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/_{2,}/g, '_')
    .replace(/^_+/, '');
