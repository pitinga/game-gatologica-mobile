# Contrato técnico do gerador e do estoque

## Invariantes de admissão

Um tabuleiro só pode entrar no estoque quando:

- Possui `size` igual a 6, 9 ou 12, exatamente `size` regiões, cada região é conexa por lados e não há células sem cor.
- O verificador de soluções usa busca incremental com poda por coluna, região e vizinhança, sem construir um catálogo de permutações para 12×12, e encontra exatamente uma combinação válida de gatos (teste truncado assim que encontra duas soluções).
- O solucionador estritamente dedutivo completa o tabuleiro sem conhecer a solução e sem hipótese, retrocesso ou pesquisa de soluções.
- Opcionalmente há **um** gato pré-colocado e imutável; esse índice deve fazer parte da solução, ser considerado na prova, permanecer fixo ao salvar/restaurar e não entrar no histórico de desfazer.
- Seu identificador (tamanho + regiões com cores renumeradas pela primeira aparição) não está no histórico recente.

O construtor de tabuleiros escolhe uma configuração de gatos sem contato e expande regiões conexas a partir de cada gato. Algumas regiões são inicialmente limitadas a 1–2 células para que existam pistas diretas; os níveis precisam ser calibrados com usuários reais.

## Concorrência e integridade

- Há um único gerador em `Thread`. Nenhuma API da árvore de cenas é usada pelo trabalhador.
- `Mutex` protege fila, histórico, flags e preferências. `use_game` é atômico em relação ao trabalhador.
- Somente o thread principal faz escrita de arquivos e interação com o jogador.
- Após tocar, o trabalhador espera 450 ms antes de executar mais um lote. Pode concluir o lote atual; não se promete limite instantâneo de CPU.
- A interface prioriza a fila da dificuldade atual, mas abastece todas as filas até 5.
- Ao perder foco, entrar em pausa ou vencer, geração é desabilitada. O thread é encerrado de forma ordenada na saída.
- A gravação usa arquivo temporário seguido de renomeação; uma falha não é silenciosamente tratada como sucesso.

## Pendências para produção

1. Revisão real de experiência/dificuldade, contraste, acessibilidade e economia de bateria.
2. Testes em Android 7+ ARM64 e avaliação de FPS/bateria em aparelho modesto.
3. Configurar export, assinatura e publicação controlada (sem credenciais no Git).
4. Integrar compras PRO (Google Play Billing) e anúncios somente fora da partida; validar restauração em reinstalação/offline.
5. Opcional: equivalência por simetria de tabuleiros e histogramas de dificuldade baseados em telemetria anônima opt-in.

## Mudança de dificuldade e pistas iniciais (v2)

- Fácil **6×6**, Médio **9×9**, Difícil **12×12**. Os três tamanhos compartilham as quatro restrições de gatos.
- O gerador utiliza preenchimento recursivo aleatório sem contato, crescimento de regiões conexas e teste de solução única com poda. O solucionador por dedução não faz suposições.
- Aproximadamente 25% das tentativas recebem um gato pré-colocado; somente candidatos dedutíveis e de solução única entram no banco. O pacote offline contém 2/8 pistas iniciais em cada dificuldade.
- Banco/progresso `v2` em arquivos separados dos da v1; a atualização para 9×9/12×12 começa um novo banco sem apagar os arquivos antigos.
- Os 12 tons pastel têm contornos de região fortes. A revisão de acessibilidade e legibilidade em celulares pequenos ainda é necessária.
