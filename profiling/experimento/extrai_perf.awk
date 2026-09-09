# =============================================================================
# extrai_perf.awk - parser da saida de "perf stat -x ';'"
#
# Uso: awk -v sep=';' -v esperados="ev1,ev2,ev3,ev4,task-clock,duration_time" \
#          -v escala_min=99.99 -f extrai_perf.awk arquivo_do_perf.csv
#
# Saida em caso de sucesso: uma linha com os valores na ordem canonica de
# "esperados", mais o minimo do percentual de execucao do contador.
# Em caso de falha: mensagem em stderr e codigo de saida 1.
#
# Ordem dos campos, conforme a secao CSV FORMAT de man perf-stat:
#   1 valor (ou <not counted> / <not supported>)
#   2 unidade ("" para contagem, msec para task-clock, ns para duration_time)
#   3 nome do evento            <- a chave, o parser indexa por aqui
#   4 tempo de execucao do contador
#   5 percentual do tempo de medicao com o contador ativo
#   6,7 valor e unidade de metrica, opcionais
#
# Tres regras que decorrem direto da man page e sao faceis de errar:
#
# 1. Nunca indexar pela direita ($NF, $(NF-1)). Os campos 6 e 7 existem para
#    alguns eventos e nao para outros.
# 2. Descartar linhas so de metrica. A man page: "Additional metrics may be
#    printed with all earlier fields being empty".
# 3. Com -o arquivo, o perf escreve uma linha em branco e "# started on
#    <data>" antes dos dados.
#
# Indexar pelo NOME e nao por posicao de linha e obrigatorio porque em CPU
# hibrida a ordem de saida do perf nao e contratualmente a ordem de entrada.
#
# Os valores sao carregados como STRING e nunca sofrem aritmetica antes de
# serem impressos: o CONVFMT padrao do gawk e "%.6g", que estragaria uma
# contagem de 3e9 se ela fosse coagida a numero.
# =============================================================================

function normaliza(s)
{
	gsub(/^[ \t]+|[ \t]+$/, "", s)
	sub(/^cpu_core\//, "", s)
	sub(/\/$/, "", s)
	return s
}

BEGIN {
	FS = sep
	n_esp = split(esperados, esp, ",")
	for (i = 1; i <= n_esp; i++) esp[i] = normaliza(esp[i])
	menor = 1000
	erro = 0
}

/^#/ || /^[ \t]*$/ { next }
NF < 5             { next }          # linha de metrica adicional

{
	valor = $1; nome = $3; pct = $5
	gsub(/^[ \t]+|[ \t]+$/, "", valor)
	gsub(/^[ \t]+|[ \t]+$/, "", pct)

	if (valor == "") next

	# Linha do PMU errado. Com prefixo cpu_core/ explicito isso nao deveria
	# acontecer, mas se acontecer e a assinatura classica do gemeo cpu_atom
	# nao escalonado, e ler essa linha daria zero em vez de erro.
	if (nome ~ /^[ \t]*cpu_atom\//) {
		printf("FALHA linha do PMU cpu_atom presente: %s\n", nome) > "/dev/stderr"
		erro = 1
		next
	}

	nome = normaliza(nome)

	if (valor ~ /^</) {
		printf("FALHA %s valor=%s\n", nome, valor) > "/dev/stderr"
		erro = 1
		next
	}
	if (valor !~ /^[0-9]+([.][0-9]+)?$/) {
		printf("FALHA %s valor nao numerico=%s\n", nome, valor) > "/dev/stderr"
		erro = 1
		next
	}

	# duration_time e task-clock nao consomem contador de proposito geral,
	# logo nao podem multiplexar e o percentual delas nao entra no minimo.
	if (nome != "task-clock" && nome != "duration_time") {
		if (pct == "") pct = "100.00"
		if (pct + 0 < menor) menor = pct + 0
	}

	if (nome in val) {
		printf("FALHA evento duplicado: %s\n", nome) > "/dev/stderr"
		erro = 1
		next
	}
	val[nome] = valor
}

END {
	for (i = 1; i <= n_esp; i++) {
		if (!(esp[i] in val)) {
			printf("FALHA evento ausente: %s\n", esp[i]) > "/dev/stderr"
			erro = 1
		}
	}
	if (menor < escala_min + 0) {
		printf("FALHA multiplexacao: escala minima %.2f%% abaixo de %.2f%%\n",
		       menor, escala_min + 0) > "/dev/stderr"
		erro = 1
	}
	if (erro) exit 1

	saida = ""
	for (i = 1; i <= n_esp; i++) saida = saida val[esp[i]] ","
	printf("%s%.2f\n", saida, menor)
}
