# =============================================================================
# Makefile - profiling fatorial 4x2 de multiplicacao de matrizes
#
# SSC0951 - Desenvolvimento de Codigo Otimizado
#
# Um unico CFLAGS para os oito binarios. Isso torna "os oito foram
# construidos de forma identica" um fato estrutural em vez de uma afirmacao,
# que e o que a comparabilidade das celulas do fatorial exige.
#
# -O0 e exigido pela atividade e e carga estrutural: em -O0 o gcc nao
# vetoriza nem aplica transformacao de laco, portanto as quatro variantes
# escritas a mao sao genuinamente o que se mede. Nao adicionar -march=native
# nem -funroll-loops, senao o Fator Tecnica passa a ser o compilador.
# =============================================================================

CC      := gcc
CFLAGS  := -O0 -std=c11 -Wall -Wextra -Werror
BIN     := experimento/bin
VBIN    := $(BIN)/verif

ESTATICOS := 1 3 5 7
DINAMICOS := 2 4 6 8

MEDICAO   := $(foreach i,$(ESTATICOS) $(DINAMICOS),$(BIN)/case$(i))
VERIF     := $(foreach i,$(ESTATICOS) $(DINAMICOS),$(VBIN)/case$(i))

CABECALHOS := matrix_config.h utils.h utils_static.h

.PHONY: all verif clean
all: $(MEDICAO)
verif: $(VERIF)

# Familia estatica: linka utils_static.c
$(foreach i,$(ESTATICOS),$(eval $(BIN)/case$(i): case$(i).c utils_static.c $(CABECALHOS)))
# Familia dinamica: linka utils.c
$(foreach i,$(DINAMICOS),$(eval $(BIN)/case$(i): case$(i).c utils.c $(CABECALHOS)))

$(foreach i,$(ESTATICOS),$(eval $(VBIN)/case$(i): case$(i).c utils_static.c $(CABECALHOS)))
$(foreach i,$(DINAMICOS),$(eval $(VBIN)/case$(i): case$(i).c utils.c $(CABECALHOS)))

# Nunca colocar utils.c e utils_static.c na mesma linha de link.
$(MEDICAO):
	@mkdir -p $(BIN)
	$(CC) $(CFLAGS) -o $@ $(filter %.c,$^)

$(VERIF):
	@mkdir -p $(VBIN)
	$(CC) $(CFLAGS) -DVERIFICA -o $@ $(filter %.c,$^)

clean:
	rm -rf $(BIN)
