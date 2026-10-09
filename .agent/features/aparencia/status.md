# Aparência: cores do painel e imagem de fundo da conversa

**Status:** em produção desde 01/10/2026 (PR #111). Sem migration.

## O que existe hoje

O item **Aparência** do menu do perfil abria a barra de comandos (`ninja-keys`), que só oferece
claro, escuro e seguir o sistema. Agora abre um diálogo próprio com três escolhas que convivem:
tema, cor e imagem de fundo da conversa.

Arquivos:

- `app/javascript/dashboard/helper/aparencia.js` — toda a regra: paletas, derivação da escala,
  contraste, compressão de imagem, limite de envios.
- `app/javascript/dashboard/composables/useAparencia.js` — leitura/gravação nas `ui_settings` e o
  acompanhamento que aplica o visual quando o perfil chega.
- `app/javascript/dashboard/components-next/aparencia/DialogoAparencia.vue` — a tela.
- `app/javascript/dashboard/i18n/locale/{pt_BR,en}/appearance.json` — textos (chave `APPEARANCE`).
- `public/brand/chat-backgrounds/` — 13 imagens prontas (3,3 MB no total, servidas pelo Rails).
- `app/controllers/api/v1/accounts/upload_controller.rb` + `config/routes.rb` — o `destroy`.
- `app/javascript/dashboard/components/widgets/conversation/MessagesView.vue` — o CSS do fundo.

## Tema e cor são coisas separadas

Como no Windows: o tema (claro/escuro/sistema) decide se o fundo é claro ou escuro, a cor tinge a
interface por cima dele. Dá para ter tema escuro com cor rosa ou tema claro com a mesma cor.

Cada cor define só **matiz** e **saturação** (`TEMAS_PERSONALIZADOS`). Os doze tons saem da
progressão de claridade da escala em uso (`LUZ_ESCURA` / `LUZ_CLARA`, espelhando
`_next-colors.scss`) — é isso que mantém o texto legível nos dois temas, em vez de calibrar 12
valores por cor. Seis cores: rosa, laranja (matiz do logo da Mobílli, #DB7F2B), vermelho, roxo,
azul e amarelo.

Duas regras que não são óbvias e foram achadas na tela, iterando com o usuário:

- **No tema claro a mesma saturação pesa mais.** As superfícies levam menos cor que no escuro
  (`base = s * 0,57`) e o texto leva **mais** (`s * 0,81`): com pouca luz ele vira um vinho do
  mesmo matiz. Texto cinza no meio de uma interface colorida parece peça de outro jogo.
- **O realce desce até alcançar contraste 4,5 com o branco** (`luzDoRealce`). Cores quentes são
  claras por natureza: o valor que funciona num rosa deixa o amarelo com texto branco ilegível.
  Assim qualquer cor nova entra sem ajuste manual.

`matizDoBot` fica longe do matiz principal de propósito: é o que separa a bolha do bot da do
agente sem precisar ler. No laranja ele puxa para o vermelho, para não se confundir com o âmbar
das notas privadas.

## Armadilhas do CSS (todas custaram tempo)

- **As variáveis vão no `<body>`, não no `<html>`.** O tema escuro do Chatwoot define as mesmas
  variáveis na classe `.dark`, que o `themeHelper` põe no body — escrever no html deixa o valor ser
  sobrescrito logo abaixo e a cor simplesmente não aparece.
- **`n-brand` é cor fixa compilada pelo Tailwind, não variável CSS.** As variáveis não o alcançam:
  sem o `<style id="cor-da-marca-propria">` que `aplicaCorDaMarca` injeta, a interface fica rosa
  com os botões principais azuis.
- **No boot a cor é aplicada antes de o claro/escuro ser decidido.** A escala sai calculada para o
  tema errado e fica presa inline no body: recarregar com cor ativa dava tela misturada (escala
  clara sob painel escuro). Resolvido com um `MutationObserver` na classe do body
  (`vigiaTrocaDeTema`), que também cobre a troca pela barra de comandos e a mudança de preferência
  do sistema — essa última nem passava pelo nosso código antes.
- **O Chrome não repinta troca de cor de borda dentro de elemento com `backdrop-blur`.** A seleção
  da miniatura só aparecia quando outro evento forçava o repaint (apertar Ctrl, por exemplo). A
  saída foi camada própria (`translateZ(0)`) e um sinal que muda de geometria: anel + marca de
  confirmado.
- **Tudo o que o fundo muda na conversa está preso a `body[data-fundo-na-conversa]`.** Quem não
  escolher imagem vê a conversa exatamente como era — sem a camada do véu, sem caixa de resposta
  translúcida. Isso foi corrigido na revisão final, antes de subir: o véu estava sendo pintado em
  toda conversa.

## Fundo da conversa

A imagem entra no container que **não** rola, não no painel de mensagens: preso ao painel ela
subiria junto com a conversa. Por cima vai um véu com a cor do próprio tema, o que faz funcionar no
claro e no escuro.

A **claridade** (0–100, padrão 35) não mexe na imagem: regula quanto do véu fica por cima dela. O
véu nunca chega a zero de propósito — sem nenhuma camada, texto claro sobre foto clara fica
ilegível. O pé da tela fica um pouco mais fechado que o topo, porque é onde ficam a caixa de
resposta e as últimas mensagens.

A caixa de resposta cortava a imagem numa linha reta. Foram **três** fundos opacos empilhados até
a imagem passar: a própria `.reply-box`, o degradê da alça de redimensionar o editor e o rodapé que
abriga o editor. Com fundo escolhido, a caixa passa a flutuar (margem, borda arredondada, sombra) e
a foto aparece nas bordas.

## Envio da própria imagem

Reduzida no navegador **antes** de subir (`comprimirImagem`), alvo 1920 px de largura: a tela nunca
mostra mais que isso e o excedente seria só peso no carregamento de todo dia. Arquivo já pequeno e
dentro da medida volta intacto — reprocessar só tiraria qualidade. O desenho vai sobre fundo branco
porque a saída é JPEG: PNG com transparência viraria preto.

**Limite de 3 por pessoa** (`LIMITE_DE_ENVIOS`). Ao enviar a quarta, a mais antiga sai da lista e o
arquivo é apagado no servidor. Sem teto, cada troca deixaria um arquivo solto para sempre — o
Chatwoot não tem rotina de limpeza para blob sem vínculo.

⚠️ **O `POST /upload` cria um blob solto, sem dono no banco.** Por isso o `destroy` novo não tem
como descobrir o dono por associação: a prova de posse é a lista `chat_background_uploads` no
perfil de quem está pedindo. Sem essa checagem, qualquer pessoa apagaria anexo de conversa alheia
passando o id.

## Experimentar antes de salvar

Nada é gravado enquanto a pessoa testa: a tela muda na hora, o **Salvar** confirma e o **Cancelar**
devolve o que estava. Uma ida à API por escolha testada seria desperdício e deixaria salvo o que a
pessoa só estava olhando.

⚠️ **`<button>` sem `type` dentro de `<form>` é `type="submit"`.** O `Dialog` do Chatwoot usa
`<form @submit.prevent="confirm">`, então cada clique numa cor disparava o `PUT /api/v1/profile` —
o rascunho existia e era ignorado. Levou três idas e voltas até aparecer; quem apontou o caminho
foi o próprio usuário, capturando o PUT na aba Network. Todos os `<button>` e `<Button>` do diálogo
levam `type="button"` explícito.

A cada escolha o diálogo some por 1 s para a conversa aparecer, e o botão **Espiar** faz o mesmo
sob demanda (clicar mostra por 1 s, segurar mantém pressionado). Detalhes que vieram de bug real:

- **Some o `<dialog>` inteiro, não a moldura de dentro**: o próprio elemento tem fundo e sombra, e
  era ele que continuava desenhando um retângulo escuro sobre a conversa.
- **Durante a prévia, um escudo transparente engole os cliques.** A primeira tentativa foi
  `pointer-events: none`, e aí o clique virava "clicou fora" e fechava o diálogo de vez.
- **Ajustar a claridade não esconde o diálogo**, esconde tudo o que há nele menos o controle: a
  pessoa precisa ver a régua e o número enquanto mexe.
- **Fora de uma conversa a prévia não acontece** (`.conversation-panel` ausente). Em Configurações
  não há onde o fundo aparecer; piscar à toa só atrapalha. A ideia anterior — navegar sozinho até
  uma conversa — foi tentada e descartada pelo usuário.
- **Clique rápido parecia botão morto.** A mecânica original do Espiar era só "segurar": no clique
  comum o diálogo sumia e voltava em menos de 150 ms. Hoje é um `pointerdown` só (serve a mouse e
  toque) e o retorno nunca vem antes de 1 s.

## Onde a preferência mora

Nas `ui_settings` do perfil (`custom_theme`, `chat_background`, `chat_background_brightness`,
`chat_background_uploads`), não no `localStorage` onde vive o claro/escuro: assim a escolha
acompanha a pessoa em qualquer computador. O claro/escuro continua no `localStorage`, pelo caminho
oficial (`setColorTheme`), porque é assim que o resto do Chatwoot o lê.

A lista de envios é estado do servidor (arquivos que existem), não preferência visual: é gravada na
hora do envio e não espera o botão Salvar.

## Pendências

- **Sem testes do helper de cor.** É o arquivo com mais regra do pacote (escala por tema, contraste
  mínimo do realce, limite de envios) e subiu sem spec — o usuário optou por subir e deixar para
  depois.
- **O item do menu ainda se chama "Alterar Tema"** em pt_BR (`SIDEBAR_ITEMS.APPEARANCE`, string do
  upstream). O nome ficou menor que a tela faz. Trocar é uma linha, mas é tradução nativa: vira
  conflito em cada upgrade.
- Mais cores entram só mexendo em `TEMAS_PERSONALIZADOS` — matiz, saturação e `matizDoBot`. O
  contraste se ajusta sozinho.
