<p align="center">
  <img src="Assets/logo.png" width="340" alt="NotchUser">
</p>

<h3 align="center">Transforme o notch do seu MacBook num player de música e numa prateleira de arquivos.</h3>

<p align="center">
  Nativo, levíssimo, gratuito e de código aberto. Sem conta, sem rastreamento, sem assinatura.
</p>

<p align="center">
  <a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/Magnumja/NotchUser?style=flat-square&label=vers%C3%A3o&color=8A5CF6" alt="Versão mais recente"></a>
  <a href="../../releases"><img src="https://img.shields.io/github/downloads/Magnumja/NotchUser/total?style=flat-square&label=downloads&color=EA7A4E" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-111111?style=flat-square&logo=apple" alt="macOS 14 ou mais novo">
  <img src="https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-3A7BF0?style=flat-square" alt="Universal">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Magnumja/NotchUser?style=flat-square&label=licen%C3%A7a&color=2EA043" alt="Licença MIT"></a>
  <a href="../../stargazers"><img src="https://img.shields.io/github/stars/Magnumja/NotchUser?style=flat-square&label=estrelas&color=F5C542" alt="Estrelas"></a>
</p>

<p align="center">
  <a href="../../releases/latest/download/NotchUser.zip"><b>⬇ Baixar o NotchUser para Mac</b></a>
  &nbsp;·&nbsp;
  <a href="README.md">Read in English</a>
</p>

<p align="center">
  <img src="Assets/screens/hero.png" width="820" alt="NotchUser aberto sob o notch, tocando uma música do Spotify">
</p>

---

## Por que o NotchUser

O notch é um espaço morto no meio da barra de menus. O NotchUser coloca ele pra trabalhar, e parece que sempre foi assim.

- **Passou o mouse, abriu.** Capa, progresso e controles saem de dentro do notch e voltam pra dentro quando o mouse sai.
- **Funciona com o que você já usa.** Spotify, Apple Music e qualquer coisa tocando no navegador (YouTube, SoundCloud, sites de streaming). Vários ao mesmo tempo? Ele segue o que começou por último, e dá pra trocar.
- **Uma prateleira pro que você está levando de um lado pro outro.** Arraste arquivos, links ou texto até o notch e depois arraste pra onde precisar: WhatsApp, Mail, Finder, AirDrop.
- **Tão leve que dá pra esquecer que está lá.** Com música tocando e o notch fechado, usa **~0% de CPU e uns 30 MB de memória**. As animações rodam no Core Animation, dentro do próprio macOS.

<p align="center">
  <img src="Assets/screens/closed.png" width="820" alt="O notch fechado mostrando a capa e uma onda na cor do álbum">
  <br><sub>Fechado, ele não atrapalha: a capa de um lado, uma onda na cor do álbum do outro.</sub>
</p>

## Três estilos

<p align="center">
  <img src="Assets/screens/styles-pt.png" width="900" alt="Os três estilos lado a lado: Básico, Elevado e Vidro">
</p>

| Estilo | Como ele é |
| --- | --- |
| **Básico** | Preto puro, como se fosse parte do hardware. |
| **Elevado** | Sombra em camadas, controles em relevo, uma luz na cor do álbum sob o notch e a capa que inclina na direção do mouse. |
| **Vidro** | O Liquid Glass da Apple (macOS 26+): painel translúcido, prateleira e controles em vidro e ondas na cor do álbum que seguem a música. |

Escolha na apresentação, nos Ajustes ou com o botão direito no notch → **Aparência**.

## Tudo o que ele faz

**Música**
- Capa, título, artista, barra de progresso (dá pra arrastar), voltar / play-pause / avançar.
- Clique na capa para abrir o app que está tocando; os ícones no canto trocam entre as fontes.
- Títulos longos deslizam quando você passa o mouse.
- Um pulinho quando a música troca, sem abrir (dá pra ligar nos Ajustes).

**Prateleira**
- Arquivos, links e texto, com miniaturas. Clique para selecionar vários e arraste todos juntos.
- Botão direito: Abrir, Mostrar no Finder, Copiar, AirDrop. Arquivos movidos ou apagados somem sozinhos.
- Enquanto você arrasta algo, uma área grande para soltar aparece sob o notch, pra você nunca bater na borda da tela sem querer.

**Complementos opcionais** (desligados até você ligar)
- **Copiar texto da tela:** aperte **⌘⇧2**, selecione qualquer área (vídeo, imagem, PDF travado, slide numa chamada) e o texto vai pra área de transferência. O reconhecimento roda no seu Mac; a imagem é apagada logo depois.
- **Espelho de câmera:** clique no notch pra se conferir antes de uma chamada. A câmera só fica ligada com o espelho aberto.
- **Fone Bluetooth em alta qualidade:** mantém o microfone do MacBook como entrada, pra o fone não cair pra "qualidade de ligação".

**E mais**
- Uma pílula no topo de telas externas, que não têm notch.
- Português, English e Español, ou o idioma do Mac.
- Uma apresentação que pede todas as permissões num lugar só, todas opcionais.

## Instalar

1. Baixe o **[NotchUser.zip](../../releases/latest/download/NotchUser.zip)**, descompacte e arraste o **NotchUser.app** para **Aplicativos**.
2. O app não é assinado por uma conta paga de desenvolvedor da Apple, então na primeira vez o macOS vai bloquear:
   - **botão direito no app → Abrir → Abrir**, ou
   - no macOS mais recente: **Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim**.

   Se aparecer que o app "está danificado", rode isto uma vez e abra de novo:
   ```bash
   xattr -dr com.apple.quarantine /Applications/NotchUser.app
   ```
3. Uma apresentação rápida deixa escolher idioma e estilo, ligar complementos e dar as permissões.

Requer **macOS 14 Sonoma ou mais novo**, Apple Silicon ou Intel.

## Como usar

| Onde | O que fazer |
| --- | --- |
| Notch | Passe o mouse para abrir · botão direito para estilos, opções, **Ajustes…** e **Sair** |
| Capa do álbum | Clique para abrir o app que está tocando |
| Ícones no canto do player | Trocar entre Spotify, navegador, Música… |
| Prateleira | Clique para selecionar · dois cliques para abrir · arraste para fora · botão direito para mais |
| Em qualquer lugar | **⌘⇧2** copia texto da tela (com o complemento ligado) |

## Privacidade

- **Sem conta, sem estatísticas, sem rastreamento.** O NotchUser não envia nada pra lugar nenhum.
- A única conexão que ele faz é baixar a capa do Spotify, dos servidores do próprio Spotify.
- O reconhecimento de texto roda no seu Mac com o Vision da Apple, e a imagem capturada é apagada na hora.
- Cada permissão (Automação para Spotify/Música, Câmera, Gravação de Tela) só é pedida pelo recurso que precisa dela.

## Desempenho

Medido num MacBook com música tocando:

| | Notch fechado | Notch aberto |
| --- | --- | --- |
| CPU | ~0,0–0,1% | só a barra de progresso atualiza enquanto você olha |
| Memória | ~30 MB | — |

As barrinhas e ondas são entregues uma vez ao Core Animation e o próprio macOS as anima. O app não se redesenha pra isso. Longe do notch, o mouse é checado só 4 vezes por segundo.

## Também para Linux e Windows

- **Ubuntu e outras distribuições com GNOME:** [NotchUser-Linux](https://github.com/Magnumja/NotchUser-Linux), uma extensão do GNOME Shell.
- **Windows 10/11:** [NotchUser-Windows](https://github.com/Magnumja/NotchUser-Windows), uma pílula no topo da tela.

## Compilar a partir do código

Só precisa das Command Line Tools do Xcode (`xcode-select --install`), não do Xcode completo.

```bash
zsh build.sh            # compila, instala em /Applications e abre
zsh build.sh release    # gera dist/NotchUser.zip para distribuir
```

| Arquivo | O que é |
| --- | --- |
| `main.swift` | O app inteiro (SwiftUI + AppKit). |
| `helper.m` | Lê o "Tocando agora" do sistema (veja abaixo). |
| `Tools/make_icon.swift` | Gera o ícone do app a partir de `Assets/logo.png`. |
| `Tools/make_gif.swift` | Transforma uma gravação de tela em GIF. |

### Como ele lê a música do navegador

Desde o macOS 15.4 a Apple só deixa os próprios apps dela lerem o "Tocando agora" do sistema (o framework privado MediaRemote). O NotchUser usa o mesmo caminho de outros apps de notch: um pequeno helper (`helper.m`) é carregado pelo `/usr/bin/perl`, que é assinado pela Apple, e repassa título, artista, tempo e capa para o app. Ele não mexe em nenhuma configuração do sistema.

**Aviso:** é um caminho não oficial e a Apple pode fechá-lo numa atualização. Se isso acontecer, o NotchUser continua funcionando com Spotify e Apple Music (via AppleScript); só a parte do navegador para.

## Contribuir

Issues e pull requests são muito bem-vindos, seja um bug, uma ideia ou uma tradução. Se o NotchUser deixou seu notch mais útil, **uma ⭐ no repositório ajuda outras pessoas a encontrarem ele.**

## Licença

[MIT](LICENSE). Use, modifique e compartilhe à vontade.
