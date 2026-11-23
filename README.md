# GatoLógica — Puzzle de Cores 🐱

Jogo de lógica **original**, inspirado na mecânica de um gato por linha, coluna e região colorida, sem contato lateral ou diagonal entre gatos. Interface mobile em **Godot 4.4+ / GDScript**, com desenhos vetoriais próprios e sem necessidade de internet.

## Como jogar

- Selecione **Fácil (6×6)**, **Médio (7×7)** ou **Difícil (8×8)** e toque em **NOVO JOGO**.
- Escolha **GATO** ou **X BLOQUEAR** acima do tabuleiro; o primeiro toque marca e o segundo remove.
- Pressionar uma casa por pelo menos 450 ms (ou clicar com o botão direito do mouse) coloca/remove um X independentemente do modo atual.
- **X automático** é opcional, vem desligado e nunca substitui uma marca manual. Os X automáticos são recalculados quando um gato é removido.
- **DICA** destaca uma casa logicamente obrigatória, mas não a marca automaticamente. **DESFAZER** recupera até 100 alterações anteriores.
- Uma vitória exige uma única posição de gato por linha, coluna e região colorida, sem gatos encostando (inclusive diagonais).

## Geração sem necessidade de adivinhar

Cada partida é validada por dois sistemas **independentes**:

1. Um enumerador verifica que existe **exatamente uma solução completa**.
2. Um solucionador **sem backtracking, palpites ou acesso à resposta**, usando apenas exclusões por gato, candidatos únicos em linhas/colunas/regiões e consistência entre linhas adjacentes, precisa conseguir **deduzir todas as posições**.

Um tabuleiro com solução única que não pode ser concluído pelo solucionador lógico é descartado. O gerador pode tentar muitas vezes até conseguir uma configuração aprovada; existem limites de tentativa e um estoque de emergência. Os níveis inicialmente combinam tamanho e esforço de dedução, mas a calibração de dificuldade para jogadores humanos ainda depende de testes de uso.

## Reserva de partidas pronta antes do Novo Jogo

| Dificuldade | Reserva ativa | Emergência incluída | Dimensões |
| --- | ---: | ---: | --- |
| Fácil | 5 | 3 | 6×6 |
| Médio | 5 | 3 | 7×7 |
| Difícil | 5 | 3 | 8×8 |

O app inclui **24 tabuleiros certificados** (15 na fila ativa, 9 de emergência). Novo Jogo consome um tabuleiro da fila, sem precisar executar geração na interface. Enquanto o jogador pensa durante a partida, um único `Thread` faz a geração e validação de novos tabuleiros em pequenos lotes. O trabalho é suspenso por cerca de 450 ms após um toque, enquanto ajuda/modal estiver aberto, ou quando o app perde foco. A geração para automaticamente quando as três reservas atingem 5/5. **Não executa geração contínua com a fila cheia**.

As filas e o histórico de até 2.000 identificadores são salvos em `user://gatologica_bank_v1.json`, usando arquivo temporário e renomeação para reduzir risco de corrupção. A partida atual, cronômetro e marcas são salvos separadamente para restauração após reiniciar. Se as reservas e a emergência forem esgotadas mais rápido do que a reposição, a interface sinaliza que está preparando um desafio, sem gerar no thread principal. A geração não depende de acesso à rede.

**Garantia importante:** o certificado lógico comprova resolubilidade pelas regras programadas, não a dificuldade percebida por todos os jogadores. Colisões de tabuleiros são evitadas pelo identificador normalizado das regiões dentro do histórico retido; variantes rotacionadas/espelhadas ainda podem ocorrer.

## Executar

```bash
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/test_puzzles.gd
godot --headless --path . --script res://tests/test_ui.gd
godot --path .
```

O CI em `.github/workflows/tests.yml` executa os testes headless. **Ainda é necessário validar manualmente** o desenho, o toque prolongado e o desempenho da geração em aparelhos Android de diferentes categorias.

## Monetização e distribuição

Será **um único app** na Google Play, Free com anúncios somente nas pausas naturais da experiência (nunca durante o tabuleiro) e compra não consumível PRO para remover anúncios. Os SDKs de publicidade, Play Billing e IDs de produção **não estão integrados nesta versão**. Não simular vendas ou restaurações de compra; integrar e testar o Billing antes do lançamento.

Android 7+ (API 24) e ARM64 são as metas. Este projeto ainda não inclui export Android assinado ou um APK/AAB validado. Chaves e artefatos de distribuição devem permanecer privados no repositório `pitinga/game-mobile-builds`. O jogo não utiliza imagens de terceiros nem segredos.
