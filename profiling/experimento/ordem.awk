# =============================================================================
# ordem.awk - gera a ordem de execucao randomizada
#
# Uso: awk -v casos=8 -v r=10 -v s=42 -f ordem.awk
# Saida: uma linha "caso replica" por execucao, na ordem sorteada.
#
# Randomizar a ordem entre as celulas protege os efeitos de Tecnica e
# Alocacao de se confundirem com deriva temporal, como aquecimento termico
# progressivo. Importa aqui porque cada kernel roda alguns segundos numa
# maquina U-series de 15 W com boost dinamico.
#
# A ordem gerada e persistida em dados/ordem_execucao.txt pelo coletor: a
# sequencia de srand() do gawk nao e garantidamente estavel entre versoes,
# portanto a semente sozinha nao reproduz a ordem, o arquivo reproduz.
# =============================================================================

BEGIN {
	srand(s)
	n = 0

	for (caso = 1; caso <= casos; caso++) {
		for (rep = 1; rep <= r; rep++) {
			n++
			linha[n] = caso " " rep
			chave[n] = rand()
		}
	}

	# ordenacao por chave aleatoria, insercao, n = 80
	for (i = 2; i <= n; i++) {
		k = chave[i]; l = linha[i]; j = i - 1
		while (j >= 1 && chave[j] > k) {
			chave[j+1] = chave[j]; linha[j+1] = linha[j]; j--
		}
		chave[j+1] = k; linha[j+1] = l
	}

	for (i = 1; i <= n; i++) print linha[i]
}
