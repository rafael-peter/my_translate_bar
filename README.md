# My Translate Bar

Tradutor nativo para macOS 15+, inteiramente no popover da barra de menus. Usa SwiftUI, AppKit, o dicionário FreeDict e o framework Translation da Apple.

## Executar

```sh
chmod +x ./Resources/FreeDict/scripts/fetch_and_convert.py
```

Com Xcode instalado:

```sh
./script/build_and_run.sh
```

Compila em modo otimizado, gera `dist/TranslateBar.app` e abre o popover. O botão **Run** do Codex usa esse script. O aplicativo original em `/Applications/Translate Bar.app` não é alterado. Para depurar, use `./script/build_and_run.sh --debug`; para executar os testes, `swift test`.

## Usar

- Digite: a tradução começa após 350 ms sem alterações.
- Cole: a tradução começa imediatamente, sem botão.
- O editor cresce de 65 até 200 pontos; depois disso, permite rolagem. O resultado também é rolável, sem truncar frases.
- O botão central **↔** inverte a direção manualmente.
- A detecção de inglês/português ajusta a direção ao colar ou após a pausa na digitação. Textos curtos ou ambíguos mantêm a direção atual. É possível desligar a detecção nas preferências.
- O relógio abre o histórico dentro do popover. A engrenagem abre as preferências no mesmo lugar.
- Limpar fica dentro do campo de entrada, com espaço reservado para não cobrir o texto. Copiar fica ao lado do resultado e confirma a cópia no próprio ícone.
- Os controles usam Liquid Glass nativo no macOS 26 ou posterior; macOS 15–25 usa os botões nativos compatíveis. O texto fica em superfícies adaptativas de leitura, sem camadas extras de vidro.

Atalhos padrão, configuráveis na engrenagem:

| Ação | Atalho |
| --- | --- |
| Abrir e focar o editor | ⌘⇧Espaço |
| Abrir e traduzir seleção ou texto copiado | ⌃⌥V |

Para alterar, clique no atalho e pressione a combinação desejada. Esc cancela. Cada atalho pode ser desligado individualmente, mantendo sua combinação salva. O segundo atalho tenta ler a seleção no aplicativo ativo quando houver permissão de Acessibilidade e suporte do aplicativo. Caso contrário, usa a área de transferência. Ele substitui todo o texto anterior e inicia a nova tradução. O Cmd+V usado diretamente no editor mantém a inserção normal no cursor. O atalho não simula copiar nem altera o clipboard. A permissão pode ser solicitada nas preferências; não é necessária para importar o texto já copiado. Enquanto as preferências estão abertas, o estado dessa permissão é atualizado automaticamente.

O popover pode abrir sobre apps em tela cheia e permanece aberto até um clique fora, Escape ou um clique no ícone da barra. Durante a gravação de atalho, Escape cancela apenas a gravação.

Não há janela expandida nem ícone no Dock. Use **Encerrar Translate Bar** nas preferências para sair.

## Permissão durante desenvolvimento

O script assina e verifica o bundle completo. Por padrão, usa assinatura local ad hoc. Essa assinatura muda quando o código muda, e o macOS pode exigir que a permissão de Acessibilidade seja concedida novamente após recompilar. A interface consulta a autorização real do processo; ela não considera uma autorização antiga como válida.

Para manter a identidade entre versões, use um certificado existente no Keychain:

```sh
TRANSLATEBAR_SIGNING_IDENTITY='Apple Development: seu certificado' ./script/build_and_run.sh
```

O script não cria certificados nem altera permissões do macOS. A Apple explica a relação entre assinatura ad hoc, identidade instável e TCC em [Developer Technical Support](https://developer.apple.com/forums/thread/751658) e [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

## Tradução e dados

O dicionário responde a correspondências exatas e apresenta outros sentidos quando disponíveis. Frases livres usam Apple Translation, processada no dispositivo. Na primeira utilização contextual, o macOS pode solicitar os modelos de idioma. Em macOS 26+, modelos já instalados usam sessões diretas; versões anteriores e downloads usam uma sessão vinculada ao popover.

O histórico é armazenado localmente em UserDefaults e pode ser apagado na interface. O cache em memória tem limite de 256 entradas.

Os dicionários FreeDict English–Portuguese 0.3 e Portuguese–English 0.2 estão sob GPL-2.0 ou posterior. Usam português genérico, sem garantia de que cada entrada seja especificamente brasileira. As fontes, checksums, conversor e cópias da licença estão em [Resources/FreeDict](Resources/FreeDict/README.md). Preserve as obrigações dessa licença ao redistribuir os dados.

## Investigação e validação

[REVERSE_ENGINEERING_FINDINGS.md](docs/reverse-engineering/REVERSE_ENGINEERING_FINDINGS.md) e [REA_EVIDENCE_BUNDLE.json](docs/reverse-engineering/REA_EVIDENCE_BUNDLE.json) registram a análise estática do aplicativo original e seus limites. Não há benchmark comparativo entre os aplicativos.

A interface foi verificada neste Mac, incluindo colagem automática, inversão automática, texto longo com rolagem, ativação individual dos atalhos e cancelamento/troca dos gravadores com Escape. Os controles Liquid Glass e a posição de Limpar/Copiar também foram inspecionados com uma tradução real. Os 25 testes automatizados passaram; um teste integrado com `NSHostingView` e `NSTextView` confirma substituição imediata pelo comando de importação, descarte de callbacks antigos e isolamento entre editores. Em 30/10/2026, o usuário confirmou pelo teclado físico que ambos os atalhos funcionam sobre apps em tela cheia e que o popover permanece aberto. O fluxo de download em um Mac sem modelos e a execução em macOS 15–25 ainda precisam de validação em ambientes correspondentes. Não há áudio nem transliteração nesta versão.
