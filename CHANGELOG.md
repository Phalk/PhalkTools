# PhalkTools 0.12.0

Mudanças desde a versão 0.11.0.

## Texture Bars

- Cada barra pode usar a textura global ou uma textura própria. A escolha vale para barras de vida, recurso e lançamento, além do medidor de dano.
- Adicionados controles de altura por barra e de espaçamento entre vida e recurso para jogador, alvo e foco. Os controles de Texture Bars ficam indisponíveis para os frames estilizados pelo módulo Unit Frames.
- Corrigida a reaplicação da textura em barras de lançamento desmarcadas. A textura escolhida também cobre o fundo da barra, e a barra de lançamento do jogador ganhou um seletor de cor.

## Damage Meter

- A seção independente e o comando `/pt meter` foram removidos. A troca de textura continua disponível em **Texture Bars → Damage Meter**.
- Posição, tamanho, espaçamento, borda e lista de combatentes ficam sob controle da interface nativa do WoW.

## Unit Frames e interface

- O nome do alvo foi ancorado acima da barra de vida personalizada. Os ajustes de layout nas barras protegidas aguardam o fim do combate.
- O painel de buffs mantém o espaço inferior, com a remoção da instrução de clique e arraste.
- A descrição do addon foi encurtada e o aviso do painel de configurações em combate passou a quebrar linha dentro da janela.
