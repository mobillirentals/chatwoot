# Tela de entrada (login) com a cara da casa

**Status:** em produção desde 28/09/2026 (PR #107). Marca da instalação corrigida no banco de
produção no mesmo dia.

## O que existe hoje

`app/javascript/v3/views/login/Index.vue` — a estrutura de login do Chatwoot (Microsoft, MFA,
limite de sessão, SAML) ficou intacta; mudou a moldura.

- **Foto ocupa a tela inteira**, bloco de entrar flutuando por cima: encostado à esquerda em tela
  larga, centralizado abaixo de 1024px. Arquivos em `public/brand/` (servidos pelo Rails, fora do
  build do front — por isso entram como **valor** no `data()`, não como atributo fixo: atributo
  fixo o Vite tenta resolver como import e o módulo quebra com 500).
- **`<picture>` com `<source media="(max-width: 1023px)">`**: o celular baixa só o corte vertical
  (`login-foto-mobile.jpg`, 122 KB) e nunca o horizontal. Com duas camadas de CSS baixaria os dois.
- **Recorte por formato**: `62% 45%` na horizontal (o cartão cobre a mochila, não o rosto) e
  `50% 35%` na vertical (rosto acima do cartão).
- **Véu que muda de direção**: gradiente lateral na tela larga (cartão à esquerda) e vertical no
  celular (cartão no meio). Sem ele o bloco boia sobre o sol estourado e o vermelho da mochila.
- **Cores por token** (`--slate-*`, `--blue-*`), não cor fixa: a tela acompanha o tema claro/escuro
  de quem entra.
- **Rodapé no pé do cartão** — chama da Mobílli + "by Mobílli Rentals | Egnner Bruno"
  (github.com/egnnerbruno). Ficou dentro do cartão porque sobre a foto a legibilidade dependia do
  trecho da imagem que caísse atrás. Os nomes moram no `data()`, não em chave de i18n: nome próprio
  não se traduz, e o lint (`vue/no-bare-strings-in-template`) exige uma das duas coisas.
- **Logo com queda**: usa `globalConfig.logo`; quando a instalação está sem `LOGO` configurado (é o
  caso do banco local), cai para `/brand-assets/logo.svg` (e `logo_dark.svg` no tema escuro).

## Marca da instalação no painel inteiro

`app/javascript/shared/helpers/textosDoPainel.js` (era `marcaDaInstalacao.js` até 01/10/2026),
ligado como `postTranslation` nos dois `createI18n` (`entrypoints/dashboard.js` e
`entrypoints/v3app.js`). O arquivo foi renomeado quando passou a carregar outros dois ajustes de
texto pelo mesmo mecanismo — ver o fim desta seção.

O Chatwoot só troca o próprio nome onde alguém lembrou de chamar `replaceInstallationName` — o
resto seguia dizendo "Chatwoot" (**45 menções** só nos textos em português: "Desenvolvido por
Chatwoot" no widget, "Chatwoot AI" nos rótulos, avisos de integração, descrições de webhook).
Editar os arquivos de tradução resolveria e criaria conflito em toda atualização do upstream; a
troca acontece na saída do i18n.

**O que o filtro não toca, de propósito** (trocar quebraria coisa real):
- endereços: `app.chatwoot.com/hc/...`, `chatwoot.com/terms`;
- código do widget: `window.chatwootSettings`, `chatwoot_website_token`.

Regra: só "Chatwoot" com **C maiúsculo** e **fora de endereço**. Os testes cobrem esses casos em
`app/javascript/shared/helpers/specs/textosDoPainel.spec.js` (9 no total hoje).

## Outros dois ajustes pelo mesmo mecanismo (01/10/2026)

- **"Capitão" volta a ser "Captain"** em qualquer texto. Produto não se traduz — e a tradução
  pt-BR do upstream rebatizou o Captain em **37 lugares** (menu, console, avisos de limite,
  relatório de mensagem da IA), fazendo o nome do produto mudar conforme o idioma de quem olha.
- **O item de menu `SIDEBAR.INBOX` passou de "Caixa de Entrada" para "Notificações"**. Em inglês a
  chave diz "My Inbox"; a tradução perdeu o "My" e passou a colidir com o nome das **caixas** (os
  canais) usado no resto do painel — a tela parecia uma lista de conversas, e é a caixa de
  notificações de quem está usando (rota `/inbox-view`, alimentada pelo store `notifications`).

Essa segunda troca é presa **à chave e ao texto de origem** (`CORRECOES` no helper): em inglês não
casa e nada muda, e se o upstream reescrever a tradução o pior que acontece é voltar ao texto
dele. É o jeito de corrigir uma string específica sem editar arquivo de tradução — o mesmo texto
"Caixa de Entrada" em outras chaves (filtro de chamadas, automações) continua intocado.

⚠️ **O filtro depende da configuração.** Enquanto `INSTALLATION_NAME` for "Chatwoot", ele não faz
nada — substitui "Chatwoot" pelo nome da instalação, e o nome era "Chatwoot".

## Configuração de marca em produção (28/09/2026)

Estava tudo no padrão do upstream; alterado via `rails runner` no container, com
`GlobalConfig.clear_cache` na sequência:

| chave | antes | agora |
|---|---|---|
| `INSTALLATION_NAME` | Chatwoot | **Chatmobilli** (sem acento, decisão do usuário) |
| `BRAND_NAME` | Chatwoot | Chatmobilli |
| `BRAND_URL` | https://www.chatwoot.com | https://chat.mobillirentals.com.br |
| `WIDGET_BRAND_URL` | https://www.chatwoot.com | https://chat.mobillirentals.com.br |

`config/installation_config.yml` foi alinhado para a mesma grafia — mas esse arquivo só vale para
instalação nova ou reseed, não mexe no que já roda.

⚠️ **Essa correção não ficava de pé sozinha.** Um job de madrugada desfazia as quatro chaves, e foi
preciso achá-lo para a marca parar de voltar: `Internal::ReconcilePlanConfigService`, pelo lado da
marca (PR #113, 01/10/2026) — ver [[premium-unlock]]. Se a marca sumir de novo, o primeiro lugar a
olhar é o `updated_at` das chaves: horário de madrugada quer dizer que algo automático mexeu.

`INSTALLATION_NAME` é quem manda no `<title>` da aba (vem do ERB, `vueapp.html.erb`) e na meta
descrição, além de alimentar o filtro acima.

## Imagens

Trocadas três vezes até chegar na atual (vídeo de balões → foto genérica → motoboy com balão de
WhatsApp → motoboy sem balão). As duas em uso vieram como PNG de ~1,7 MB e viraram **JPEG
progressivo**: `login-foto.jpg` (1785×881, 114 KB) e `login-foto-mobile.jpg` (940×1672, 122 KB).
Foto é caso de JPEG; PNG ali só carrega peso.

O host não tem ffmpeg nem o container do Rails — na fase do vídeo, a compressão saiu num container
`linuxserver/ffmpeg` avulso (15 MB → 321 KB). Fica anotado para a próxima vez que precisar mexer em
mídia neste projeto.

## Pendências

- `app/javascript/dashboard/i18n/locale/{pt,pt_BR}/login.json` estão alterados na árvore local do
  usuário ("Entrar no Chatmobilli" fixo) e **ficaram fora do PR**. Com o filtro no lugar eles não
  fazem mais nada; o usuário ainda não decidiu se reverte.
- Nada impede o mesmo tratamento nas telas de cadastro/redefinição de senha — hoje só o login tem a
  moldura nova.
