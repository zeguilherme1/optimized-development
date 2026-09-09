#!/usr/bin/env bash
# =============================================================================
# run_experimento.sh - coleta do planejamento fatorial 4x2
#
# SSC0951 - Desenvolvimento de Codigo Otimizado
#
# Fator 1 Tecnica  : base, interchange, unrolling, tiling
# Fator 2 Alocacao : estatica, dinamica
# 8 celulas x 10 replicas = 80 medicoes em ordem randomizada.
#
# Metricas: tempo de resposta, L1-dcache-loads, L1-dcache-load-misses,
#           branch-instructions, branch-misses.
#
# Saida: dados/dados_brutos.csv, dados/ambiente.txt, dados/eventos.txt,
#        dados/ordem_execucao.txt, dados/dicionario.txt, dados/perf/*.csv
#
# PRE-REQUISITO: perf_event_paranoid precisa estar em 1 ou menos. Este script
# apenas verifica e aborta, nunca invoca sudo.
# =============================================================================

set -euo pipefail

# LC_ALL=C e obrigatorio, nao higiene. Nesta maquina LC_NUMERIC=pt_BR.UTF-8, e
# sob esse locale o printf do bash REJEITA "1234.5" e imprime "1234,00".
# Corrupcao silenciosa de dado, nao apenas troca de separador decimal.
export LC_ALL=C

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXP="$RAIZ/experimento"
BIN="$EXP/bin"
OUT="$RAIZ/dados"
CSV="$OUT/dados_brutos.csv"

# ----------------------------------------------------------------- constantes
REPLICAS=${REPLICAS:-10}
CASOS=8
SEMENTE=42
CPU_FIXA=0                 # P-core, coerente com o PMU cpu_core (cpus 0-3)
MAX_TENTATIVAS=2
PARANOID_MAX=1
PERF_SEP=';'               # nao ',': ver man perf-stat, secao CSV FORMAT
ESCALA_MIN=99.99           # % minimo de tempo de contagem, portao de multiplexacao

# Conjuntos de eventos, em ordem de preferencia. Todo evento vem qualificado
# com o PMU: a man page do perf-stat, secao INTEL HYBRID SUPPORT, diz que um
# evento disponivel nos dois PMUs "cria dois eventos automaticamente", um por
# PMU. Com taskset -c 0 o gemeo cpu_atom nunca e escalonado e retorna
# <not counted>, e um parser ingenuo leria essa linha.
EVENTOS_A="cpu_core/L1-dcache-loads/,cpu_core/L1-dcache-load-misses/,cpu_core/branch-instructions/,cpu_core/branch-misses/"
EVENTOS_B="cpu_core/mem_inst_retired.all_loads/,cpu_core/mem_load_retired.l1_miss/,cpu_core/br_inst_retired.all_branches/,cpu_core/br_misp_retired.all_branches/"
# task-clock e duration_time sao eventos de software e de ferramenta, nao
# consomem contador de proposito geral, logo nao induzem multiplexacao.
EVENTOS_AUX="task-clock,duration_time"

CFLAGS_REG="-O0 -std=c11 -Wall -Wextra -Werror"

TECNICA=( "" base base interchange interchange unrolling unrolling tiling tiling )
ALOCACAO=( "" estatica dinamica estatica dinamica estatica dinamica estatica dinamica )
T_COD=(   ""  1 1 2 2 3 3 4 4 )

# --------------------------------------------------------------------- helpers
titulo() { printf '\n[%s] %s\n' "$1" "$2"; }
morrer() { printf '\nERRO: %s\n' "$*" >&2; exit 1; }

ler_sys() { [ -r "$1" ] && cat "$1" 2>/dev/null || echo "indisponivel"; }

# ------------------------------------------------------ 1. pre-requisitos
verificar_prerequisitos() {
	titulo "1/7" "Verificando pre-requisitos"

	for t in gcc make perf taskset awk lscpu free uname md5sum sort; do
		command -v "$t" >/dev/null || morrer "ferramenta ausente no PATH: $t"
	done

	local p
	p="$(cat /proc/sys/kernel/perf_event_paranoid)"
	if [ "$p" -gt "$PARANOID_MAX" ]; then
		cat >&2 <<EOF

ERRO: perf_event_paranoid = $p bloqueia a abertura dos contadores.

Execute o comando abaixo e repita a coleta:

    sudo sysctl -w kernel.perf_event_paranoid=1

Este script nao invoca sudo. O valor 1 libera contadores por processo e
mantem bloqueado o acesso a eventos por CPU e a tracepoints crus.
Para tornar permanente, apos o reboot:

    echo 'kernel.perf_event_paranoid=1' | sudo tee /etc/sysctl.d/99-perf.conf

EOF
		exit 1
	fi
	printf '  perf_event_paranoid = %s, ok\n' "$p"

	# CPU fixa precisa pertencer ao PMU cpu_core, senao o prefixo esta errado.
	local mask_core="/sys/bus/event_source/devices/cpu_core/cpus"
	if [ -r "$mask_core" ]; then
		HIBRIDA=1
		printf '  CPU hibrida: cpu_core = %s, cpu_atom = %s\n' \
			"$(cat "$mask_core")" "$(ler_sys /sys/bus/event_source/devices/cpu_atom/cpus)"
		grep -qE "(^|[,-])${CPU_FIXA}([,-]|$)" "$mask_core" \
			|| morrer "CPU_FIXA=$CPU_FIXA nao esta em cpu_core ($(cat "$mask_core"))"
	else
		HIBRIDA=0
		printf '  CPU nao hibrida, o prefixo cpu_core/ sera removido dos eventos\n'
		EVENTOS_A="${EVENTOS_A//cpu_core\//}"; EVENTOS_A="${EVENTOS_A//\/,/,}"; EVENTOS_A="${EVENTOS_A%/}"
		EVENTOS_B="${EVENTOS_B//cpu_core\//}"; EVENTOS_B="${EVENTOS_B//\/,/,}"; EVENTOS_B="${EVENTOS_B%/}"
	fi

	SMT_IRMAOS="$(ler_sys /sys/devices/system/cpu/cpu${CPU_FIXA}/topology/thread_siblings_list)"
	if [ "$SMT_IRMAOS" != "$CPU_FIXA" ] && [ "$SMT_IRMAOS" != "indisponivel" ]; then
		printf '  AVISO: cpu%s tem irmao SMT (%s), que compartilha a L1d de 48 KiB\n' \
			"$CPU_FIXA" "$SMT_IRMAOS"
		printf '         e o preditor de branch. Mantenha a maquina ociosa.\n'
	fi

	printf '  ulimit -s = %s KiB (3 matrizes de int a N=1000 sao 11,44 MiB, por\n' "$(ulimit -s)"
	printf '            isso a familia estatica usa .bss e nao a pilha)\n'
	printf '  carga atual: %s\n' "$(cut -d' ' -f1-3 /proc/loadavg)"

	mkdir -p "$OUT/perf" "$RAIZ/figuras" "$RAIZ/analise"
}

# --------------------------------------------------------------- 2. compilar
compilar() {
	titulo "2/7" "Compilando os 8 binarios de medicao e os 8 de verificacao"
	make -C "$RAIZ" clean >/dev/null
	make -C "$RAIZ" all verif >/dev/null || morrer "falha na compilacao"
	for i in $(seq 1 $CASOS); do
		[ -x "$BIN/case$i" ] || morrer "binario ausente: $BIN/case$i"
	done
	printf '  8 + 8 binarios prontos, CFLAGS = %s\n' "$CFLAGS_REG"
}

# -------------------------------------------------- 3. descobrir os eventos
# Sonda contra uma carga que gera loads e branches de verdade. /bin/true nao
# serve: as contagens somem no ruido de startup e a sondagem aprovaria um
# conjunto que na pratica nao conta nada.
sondar() {
	local lista="$1" arq="$2"
	taskset -c "$CPU_FIXA" perf stat --no-big-num -x"$PERF_SEP" -o "$arq" \
		-e "$lista" -- awk 'BEGIN { s = 0; for (i = 0; i < 3000000; i++) s += i % 7 }' \
		>/dev/null 2>&1
}

descobrir_eventos() {
	titulo "3/7" "Sondando a nomenclatura de evento do perf"

	local ev arq nome saida
	: > "$OUT/eventos.txt"
	{
		echo "Sondagem de nomenclatura de evento do perf"
		echo "Data     : $(date -Is)"
		echo "Maquina  : $(lscpu | awk -F: '/Model name/ {gsub(/^ +/,"",$2); print $2; exit}')"
		echo "perf     : $(perf --version)"
		echo
	} >> "$OUT/eventos.txt"

	EVENTOS=""
	for nome in A B; do
		[ "$nome" = A ] && ev="$EVENTOS_A" || ev="$EVENTOS_B"
		arq="$OUT/perf/sonda_$nome.csv"
		printf '  conjunto %s ... ' "$nome"
		{ echo "--- conjunto $nome ---"; echo "$ev,$EVENTOS_AUX"; } >> "$OUT/eventos.txt"

		if ! sondar "$ev,$EVENTOS_AUX" "$arq"; then
			printf 'perf falhou\n'; echo "veredito: perf retornou erro" >> "$OUT/eventos.txt"
			continue
		fi
		cat "$arq" >> "$OUT/eventos.txt"

		if ! saida="$(awk -v sep="$PERF_SEP" -v esperados="$ev,$EVENTOS_AUX" \
		              -v escala_min="$ESCALA_MIN" -f "$EXP/extrai_perf.awk" "$arq" 2>&1)"; then
			printf 'rejeitado\n'
			{ echo "veredito: rejeitado"; echo "$saida"; echo; } >> "$OUT/eventos.txt"
			continue
		fi

		# sanidade de ordem: misses <= loads, branch_misses <= branch_instructions,
		# e nenhuma contagem zerada
		if ! echo "$saida" | awk -F, '
			{ ok = ($1 > 0 && $2 > 0 && $3 > 0 && $4 > 0 && $2 <= $1 && $4 <= $3) }
			END { exit ok ? 0 : 1 }'; then
			printf 'valores incoerentes (%s)\n' "$saida"
			{ echo "veredito: valores incoerentes: $saida"; echo; } >> "$OUT/eventos.txt"
			continue
		fi

		EVENTOS="$ev"
		CONJUNTO="$nome"
		printf 'aceito (%s)\n' "$saida"
		{ echo "veredito: ACEITO"; echo "valores: $saida"; echo; } >> "$OUT/eventos.txt"
		break
	done

	[ -n "$EVENTOS" ] || morrer "nenhum conjunto de eventos abriu. Ver $OUT/eventos.txt"

	# Mapeamento resolvido, para o relatorio poder declarar QUAL evento de
	# hardware respaldou cada alias. Os aliases L1-dcache-* sao eventos legados
	# PERF_TYPE_HW_CACHE codificados pelo parser do perf, e por isso nao
	# aparecem em "perf list" nesta maquina.
	{
		echo "--- mapeamento resolvido (perf stat -vv) ---"
		taskset -c "$CPU_FIXA" perf stat -vv -x"$PERF_SEP" -e "$EVENTOS" \
			-- /bin/true 2>&1 | grep -iE "config|name|type|perf_event_attr|sys_perf" | head -60
		echo
	} >> "$OUT/eventos.txt" 2>/dev/null || true

	printf '  conjunto escolhido: %s\n  eventos: %s\n' "$CONJUNTO" "$EVENTOS"
	printf '  mapeamento e sondagem registrados em dados/eventos.txt\n'
}

# ------------------------------------------------------------- 4. ambiente
registrar_ambiente() {
	titulo "4/7" "Registrando o ambiente experimental"
	{
		echo "Ambiente experimental - profiling fatorial 4x2"
		echo "Data                 : $(date -Is)"
		echo
		echo "--- maquina ---"
		echo "Modelo de CPU        : $(lscpu | awk -F: '/Model name/ {gsub(/^ +/,"",$2); print $2; exit}')"
		echo "Nucleos / threads    : $(lscpu | awk -F: '/^Core\(s\) per socket/ {gsub(/^ +/,"",$2); n=$2} /^CPU\(s\):/ {gsub(/^ +/,"",$2); t=$2} END {printf "%s nucleos / %s threads", n, t}')"
		echo "Cache L1d            : $(ler_sys /sys/devices/system/cpu/cpu${CPU_FIXA}/cache/index0/size), $(ler_sys /sys/devices/system/cpu/cpu${CPU_FIXA}/cache/index0/ways_of_associativity) vias, linha de $(ler_sys /sys/devices/system/cpu/cpu${CPU_FIXA}/cache/index0/coherency_line_size) B"
		echo "Cache L2             : $(lscpu | awk -F: '/L2 cache/ {gsub(/^ +/,"",$2); print $2; exit}')"
		echo "Cache L3             : $(lscpu | awk -F: '/L3 cache/ {gsub(/^ +/,"",$2); print $2; exit}')"
		echo "Memoria total        : $(free -h | awk '/^Mem:/ {print $2}')"
		echo "PMU cpu_core         : $(ler_sys /sys/bus/event_source/devices/cpu_core/cpus)"
		echo "PMU cpu_atom         : $(ler_sys /sys/bus/event_source/devices/cpu_atom/cpus)"
		echo "PMU nome             : $(ler_sys /sys/bus/event_source/devices/cpu_core/caps/pmu_name)"
		echo "SMT ativo            : $(ler_sys /sys/devices/system/cpu/smt/active)"
		echo "Irmaos SMT da cpu$CPU_FIXA  : $SMT_IRMAOS"
		echo
		echo "--- software ---"
		echo "Kernel               : $(uname -sr)"
		echo "Distribuicao         : $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo indisponivel)"
		echo "gcc                  : $(gcc --version | head -1)"
		echo "perf                 : $(perf --version)"
		echo "awk                  : $(awk --version | head -1)"
		echo "LC_ALL usado         : $LC_ALL"
		echo "ulimit -s            : $(ulimit -s) KiB"
		echo
		echo "--- estado de medicao ---"
		echo "perf_event_paranoid  : $(cat /proc/sys/kernel/perf_event_paranoid)"
		echo "nmi_watchdog         : $(ler_sys /proc/sys/kernel/nmi_watchdog)"
		echo "Governor             : $(ler_sys /sys/devices/system/cpu/cpu${CPU_FIXA}/cpufreq/scaling_governor)"
		echo "Freq min / max       : $(ler_sys /sys/devices/system/cpu/cpu${CPU_FIXA}/cpufreq/scaling_min_freq) / $(ler_sys /sys/devices/system/cpu/cpu${CPU_FIXA}/cpufreq/scaling_max_freq) kHz"
		echo "EPP                  : $(ler_sys /sys/devices/system/cpu/cpu${CPU_FIXA}/cpufreq/energy_performance_preference)"
		echo "Freq antes da coleta : $(ler_sys /sys/devices/system/cpu/cpu${CPU_FIXA}/cpufreq/scaling_cur_freq) kHz"
		echo "Carga antes          : $(cut -d' ' -f1-3 /proc/loadavg)"
		echo
		echo "--- parametros do experimento ---"
		echo "N                    : $(awk '/^#define N /{print $3}' "$RAIZ/matrix_config.h")"
		echo "BLOCO                : $(awk '/^#define BLOCO /{print $3}' "$RAIZ/matrix_config.h")"
		echo "UNROLL               : $(awk '/^#define UNROLL /{print $3}' "$RAIZ/matrix_config.h")"
		echo "Replicas por celula  : $REPLICAS"
		echo "Celulas              : $CASOS"
		echo "Aquecimentos         : 1 por celula, descartado"
		echo "Semente da ordem     : $SEMENTE"
		echo "CPU fixada           : $CPU_FIXA (taskset)"
		echo "CFLAGS               : $CFLAGS_REG"
		echo "Conjunto de eventos  : $CONJUNTO"
		echo "Eventos de hardware  : $EVENTOS"
		echo "Eventos auxiliares   : $EVENTOS_AUX"
		echo
		echo "--- procedencia dos binarios ---"
		( cd "$BIN" && md5sum case* )
	} > "$OUT/ambiente.txt"
	printf '  dados/ambiente.txt escrito\n'
}

# ------------------------------------------------------------ 5. aquecimento
# Uma execucao descartada por celula, atraves do perf com o conjunto real de
# eventos, para que o caminho de setup do perf, o page cache, as paginas de
# texto do binario e a rampa de frequencia estejam quentes na primeira medida.
# Valida os rotulos e o checksum ANTES de gastar a coleta inteira: rotulo
# trocado num printf e indetectavel depois e trocaria duas celulas do desenho.
aquecer() {
	titulo "5/7" "Aquecimento e validacao dos 8 binarios"
	local i linha arq campos
	CHECKSUM_REF=""; N_REF=""

	for i in $(seq 1 $CASOS); do
		arq="$OUT/perf/aquece_$i.csv"
		printf '  case%d ... ' "$i"
		linha="$(taskset -c "$CPU_FIXA" perf stat --no-big-num -x"$PERF_SEP" \
			-o "$arq" -e "$EVENTOS,$EVENTOS_AUX" -- "$BIN/case$i")" \
			|| morrer "case$i falhou no aquecimento"

		IFS=, read -r -a campos <<< "$linha"
		[ "${#campos[@]}" -eq 8 ] || morrer "case$i imprimiu ${#campos[@]} campos, esperado 8: $linha"
		[ "${campos[0]}" = "$i" ] || morrer "case$i reporta case_id=${campos[0]}"
		[ "${campos[1]}" = "${TECNICA[$i]}" ] || morrer "case$i reporta technique=${campos[1]}, esperado ${TECNICA[$i]}"
		[ "${campos[2]}" = "${ALOCACAO[$i]}" ] || morrer "case$i reporta allocation=${campos[2]}, esperado ${ALOCACAO[$i]}"

		[ -n "$N_REF" ] || N_REF="${campos[3]}"
		[ "${campos[3]}" = "$N_REF" ] || morrer "case$i reporta n=${campos[3]}, esperado $N_REF"
		[ -n "$CHECKSUM_REF" ] || CHECKSUM_REF="${campos[7]}"
		[ "${campos[7]}" = "$CHECKSUM_REF" ] \
			|| morrer "case$i produziu checksum ${campos[7]}, esperado $CHECKSUM_REF. Os oito binarios nao calculam o mesmo produto."

		printf 'ok  tecnica=%-11s alocacao=%-8s n=%s\n' "${campos[1]}" "${campos[2]}" "${campos[3]}"
	done
	printf '  checksum de referencia: %s   n: %s\n' "$CHECKSUM_REF" "$N_REF"
}

# ---------------------------------------------------------------- 6. coleta
coletar() {
	titulo "6/7" "Coletando $((CASOS * REPLICAS)) medicoes em ordem randomizada"

	awk -v casos="$CASOS" -v r="$REPLICAS" -v s="$SEMENTE" \
		-f "$EXP/ordem.awk" > "$OUT/ordem_execucao.txt"

	local total; total="$(wc -l < "$OUT/ordem_execucao.txt")"
	printf '  ordem sorteada e persistida em dados/ordem_execucao.txt (%s execucoes)\n\n' "$total"

	echo "ordem_execucao,caso,tecnica,alocacao,n,T_tecnica,A_alocacao,B_fat1,B_fat2,replica,retentativas,tempo_kernel_ns,perf_task_clock_ms,perf_duration_ns,l1d_loads,l1d_load_misses,branch_instructions,branch_misses,checksum,perf_escala_min_pct" > "$CSV"

	local n=0 t_ini; t_ini="$(date +%s)"

	while read -r caso rep; do
		n=$((n + 1))
		local arq tentativa=0 ok=0 linha rc contadores campos
		arq="$OUT/perf/run$(printf '%04d' "$n").csv"

		while [ "$tentativa" -lt "$MAX_TENTATIVAS" ] && [ "$ok" -eq 0 ]; do
			tentativa=$((tentativa + 1))

			set +e
			linha="$(taskset -c "$CPU_FIXA" perf stat --no-big-num -x"$PERF_SEP" \
				-o "$arq" -e "$EVENTOS,$EVENTOS_AUX" -- "$BIN/case$caso" \
				2>>"$OUT/falhas.log")"
			rc=$?
			set -e

			if [ "$rc" -ne 0 ]; then
				printf 'run %d case%d rep%d: perf/binario retornou %d\n' "$n" "$caso" "$rep" "$rc" >> "$OUT/falhas.log"
				continue
			fi
			if ! [[ "$linha" =~ ^[0-9]+,[a-z]+,[a-z]+,[0-9]+,[0-9]+,[0-9]+,[0-9]+,[0-9]+$ ]]; then
				printf 'run %d case%d rep%d: stdout fora do contrato: %s\n' "$n" "$caso" "$rep" "$linha" >> "$OUT/falhas.log"
				continue
			fi
			if ! contadores="$(awk -v sep="$PERF_SEP" -v esperados="$EVENTOS,$EVENTOS_AUX" \
			                   -v escala_min="$ESCALA_MIN" -f "$EXP/extrai_perf.awk" "$arq" \
			                   2>>"$OUT/falhas.log")"; then
				printf 'run %d case%d rep%d: parser do perf rejeitou %s\n' "$n" "$caso" "$rep" "$arq" >> "$OUT/falhas.log"
				continue
			fi
			ok=1
		done

		[ "$ok" -eq 1 ] || morrer "case$caso replica $rep falhou $MAX_TENTATIVAS vezes. Ver dados/falhas.log"

		IFS=, read -r -a campos <<< "$linha"
		local tempo_ns="${campos[6]}" chk="${campos[7]}"

		# Checksum divergente nao e falha repetivel: um dos kernels esta errado.
		[ "$chk" = "$CHECKSUM_REF" ] \
			|| morrer "case$caso produziu checksum $chk, esperado $CHECKSUM_REF. Os oito binarios nao calculam o mesmo produto."

		IFS=, read -r loads misses brinst brmiss taskclock duracao escala <<< "$contadores"

		# Coerencia fisica. Pega corrupcao que o percentual de escala nao ve,
		# por exemplo uma linha de PMU errado lida como zero.
		#
		# As duas checagens de tempo usam duration_time (parede) e nao
		# task-clock (CPU). O tempo do kernel vem de CLOCK_MONOTONIC, que e
		# parede: se o processo for desescalonado durante o kernel, o relogio
		# de parede corre e o de CPU nao, portanto o tempo do kernel pode
		# legitimamente exceder o task-clock. Comparar com task-clock seria
		# premissa errada.
		#
		# A tolerancia de 2% existe porque task-clock e duration_time vem de
		# mecanismos diferentes, contabilidade do escalonador contra medicao
		# da ferramenta, e qual dos dois sai marginalmente maior e ruido de
		# arredondamento. Sem folga, uma diferenca de 0,02% aborta a coleta.
		local diag
		diag="$(awk -v a="$misses" -v b="$loads" -v c="$brmiss" -v d="$brinst" \
		    -v tc="$taskclock" -v tk="$tempo_ns" -v du="$duracao" 'BEGIN {
			tol = 0.02
			if (a > b)                          { print "misses > loads"; exit 1 }
			if (c > d)                          { print "branch_misses > branch_instructions"; exit 1 }
			if (a <= 0 || b <= 0 || c <= 0 || d <= 0) { print "contagem nao positiva"; exit 1 }
			if (tk > du * (1 + tol))            { printf "tempo do kernel (%.0f ns) acima do wall clock do processo (%.0f ns)\n", tk, du; exit 1 }
			if (du < tc * 1e6 * (1 - tol))      { printf "duration (%.0f ns) muito abaixo do task_clock (%.0f ns)\n", du, tc * 1e6; exit 1 }
			if (tc * 1e6 < tk * (1 - tol))      { printf "AVISO tempo de CPU (%.0f ns) abaixo do tempo de parede do kernel (%.0f ns), processo desescalonado\n", tc * 1e6, tk }
		}')" || morrer "run $n case$caso: contadores incoerentes ($contadores): $diag"
		[ -z "$diag" ] || printf 'run %d case%d: %s\n' "$n" "$caso" "$diag" >> "$OUT/falhas.log"

		# codificacao dos contrastes para as duas ANOVAs 2x2
		local a_cod b1 b2
		[ "${ALOCACAO[$caso]}" = dinamica ] && a_cod=1 || a_cod=-1
		case "${TECNICA[$caso]}" in
			base)        b1=-1; b2=-1 ;;
			interchange) b1=1;  b2=NA ;;
			unrolling)   b1=NA; b2=1  ;;
			*)           b1=NA; b2=NA ;;
		esac

		printf '%d,%d,%s,%s,%s,%d,%d,%s,%s,%d,%d,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
			"$n" "$caso" "${TECNICA[$caso]}" "${ALOCACAO[$caso]}" "${campos[3]}" \
			"${T_COD[$caso]}" \
			"$a_cod" "$b1" "$b2" "$rep" "$((tentativa - 1))" \
			"$tempo_ns" "$taskclock" "$duracao" \
			"$loads" "$misses" "$brinst" "$brmiss" "$chk" "$escala" >> "$CSV"

		# progresso com ETA
		local decorrido eta
		decorrido=$(( $(date +%s) - t_ini ))
		eta=$(( n > 0 ? decorrido * (total - n) / n : 0 ))
		printf '  %2d/%s  case%d %-11s %-8s rep %2d   ' \
			"$n" "$total" "$caso" "${TECNICA[$caso]}" "${ALOCACAO[$caso]}" "$rep"
		awk -v t="$tempo_ns" -v a="$misses" -v b="$loads" -v c="$brmiss" -v d="$brinst" \
		    -v e="$escala" -v eta="$eta" 'BEGIN {
			printf "%8.1f ms  L1miss %6.2f%%  brmiss %6.3f%%  escala %s%%  ETA %dm%02ds\n",
			       t/1e6, 100*a/b, 100*c/d, e, int(eta/60), eta%60
		}'
	done < "$OUT/ordem_execucao.txt"

	{
		echo
		echo "--- estado depois da coleta ---"
		echo "Freq depois          : $(ler_sys /sys/devices/system/cpu/cpu${CPU_FIXA}/cpufreq/scaling_cur_freq) kHz"
		echo "Carga depois         : $(cut -d' ' -f1-3 /proc/loadavg)"
		echo "Fim da coleta        : $(date -Is)"
	} >> "$OUT/ambiente.txt"
}

# ------------------------------------------------------------- 7. validacao
validar() {
	titulo "7/7" "Validando o dataset"
	local esperado=$((CASOS * REPLICAS))

	local linhas; linhas=$(( $(wc -l < "$CSV") - 1 ))
	[ "$linhas" -eq "$esperado" ] || morrer "$CSV tem $linhas linhas de dado, esperado $esperado"
	printf '  %d linhas de dado, ok\n' "$linhas"

	local chks; chks="$(tail -n +2 "$CSV" | cut -d, -f19 | sort -u | wc -l)"
	[ "$chks" -eq 1 ] || morrer "$chks checksums distintos no dataset"
	printf '  1 checksum distinto (%s), ok\n' "$CHECKSUM_REF"

	local pares; pares="$(tail -n +2 "$CSV" | cut -d, -f2,10 | sort -u | wc -l)"
	[ "$pares" -eq "$esperado" ] || morrer "$pares pares (caso,replica) distintos, esperado $esperado"
	printf '  %d pares (caso,replica) distintos, ok\n' "$pares"

	local combos; combos="$(tail -n +2 "$CSV" | cut -d, -f2,3,4 | sort -u | wc -l)"
	[ "$combos" -eq "$CASOS" ] || morrer "$combos combinacoes (caso,tecnica,alocacao), esperado $CASOS"
	printf '  %d combinacoes (caso,tecnica,alocacao) distintas, ok\n' "$combos"

	local baixa; baixa="$(tail -n +2 "$CSV" | awk -F, '$20 + 0 < 99.99' | wc -l)"
	[ "$baixa" -eq 0 ] || morrer "$baixa linhas com escala de contador abaixo de 99,99%"
	printf '  escala de contador em 100%% nas %d linhas, ok\n' "$linhas"

	local vazios; vazios="$(tail -n +2 "$CSV" | grep -c ',,' || true)"
	[ "$vazios" -eq 0 ] || morrer "$vazios linhas com campo vazio"
	printf '  nenhum campo vazio, ok\n'

	local ret; ret="$(tail -n +2 "$CSV" | awk -F, '{s += $11} END {print s + 0}')"
	printf '  retentativas totais: %s\n' "$ret"

	# Validacao cruzada das duas nomenclaturas de evento, uma vez. Confirma
	# empiricamente a resolucao do alias nesta maquina hibrida, em vez de
	# supor, o que importa porque "perf list" nao anuncia o alias L1-dcache-*.
	printf '  validacao cruzada das nomenclaturas de evento ... '
	local arq_b saida_b saida_a
	arq_b="$OUT/perf/cruzada_B.csv"
	if sondar "$EVENTOS_B,$EVENTOS_AUX" "$arq_b" \
	   && saida_b="$(awk -v sep="$PERF_SEP" -v esperados="$EVENTOS_B,$EVENTOS_AUX" \
	                 -v escala_min="$ESCALA_MIN" -f "$EXP/extrai_perf.awk" "$arq_b" 2>/dev/null)" \
	   && sondar "$EVENTOS_A,$EVENTOS_AUX" "$OUT/perf/cruzada_A.csv" \
	   && saida_a="$(awk -v sep="$PERF_SEP" -v esperados="$EVENTOS_A,$EVENTOS_AUX" \
	                 -v escala_min="$ESCALA_MIN" -f "$EXP/extrai_perf.awk" "$OUT/perf/cruzada_A.csv" 2>/dev/null)"; then
		{
			echo "--- validacao cruzada das nomenclaturas ---"
			echo "conjunto A (aliases genericos) : $saida_a"
			echo "conjunto B (eventos nativos)   : $saida_b"
			paste -d, <(echo "$saida_a") <(echo "$saida_b") | awk -F, '{
				printf "razao loads  A/B : %.4f\n", $1 / $8
				printf "razao misses A/B : %.4f\n", $2 / $9
				printf "razao brinst A/B : %.4f\n", $3 / $10
				printf "razao brmiss A/B : %.4f\n", $4 / $11
			}'
			echo
		} >> "$OUT/eventos.txt"
		printf 'ok, razoes registradas em dados/eventos.txt\n'
	else
		printf 'nao foi possivel, registrado\n'
		echo "--- validacao cruzada: nao foi possivel abrir os dois conjuntos ---" >> "$OUT/eventos.txt"
	fi
}

# ------------------------------------------------------------- dicionario
escrever_dicionario() {
	cat > "$OUT/dicionario.txt" <<EOF
Dicionario de colunas de dados_brutos.csv

 1 ordem_execucao       int 1..$((CASOS * REPLICAS))  posicao na ordem randomizada. Base dos
                        diagnosticos de independencia dos residuos.
 2 caso                 int 1..8       identidade do binario.
 3 tecnica              texto          Fator 1: base, interchange, unrolling, tiling.
 4 alocacao             texto          Fator 2: estatica, dinamica.
 5 n                    int            ordem da matriz, REPORTADA PELA BIBLIOTECA via
                        matrixDim(), nao pelo macro N visto por main. Assim o
                        valor registrado nao pode mentir se alguma unidade de
                        traducao tiver sido compilada com um N diferente.
 6 T_tecnica            int 1..4       codigo do fator de 4 niveis.
 7 A_alocacao           int -1 ou +1   contraste: -1 estatica, +1 dinamica.
 8 B_fat1               -1, +1 ou NA   -1 base, +1 interchange, NA fora.
                        Define o subconjunto do Fatorial 1 (cache).
 9 B_fat2               -1, +1 ou NA   -1 base, +1 unrolling, NA fora.
                        Define o subconjunto do Fatorial 2 (branch).
10 replica              int 1..$REPLICAS
11 retentativas         int            tentativas descartadas nesta medicao.
12 tempo_kernel_ns      ns, inteiro    clock_gettime(CLOCK_MONOTONIC) apenas em volta
                        do kernel. RESPOSTA PRIMARIA. Inteiro e nao float de
                        proposito: sob LC_NUMERIC=pt_BR qualquer %f no caminho
                        de dados e risco de virgula decimal.
13 perf_task_clock_ms   ms             task-clock do processo inteiro, incluindo malloc,
                        preenchimento, checksum e, nos casos dinamicos, mil
                        chamadas de free. Secundaria.
14 perf_duration_ns     ns             duration_time, wall clock do processo. Secundaria.
15 l1d_loads            contagem       loads de L1d.
16 l1d_load_misses      contagem       misses de load de L1d.
17 branch_instructions  contagem       instrucoes de branch.
18 branch_misses        contagem       branches mal preditos.
19 checksum             int64          soma dos N^2 elementos de C. Identico nas
                        $((CASOS * REPLICAS)) linhas, prova que os oito kernels calculam o mesmo produto.
20 perf_escala_min_pct  %              minimo do percentual de tempo com contador ativo
                        entre os quatro eventos de hardware. Deve ser 100,00.
                        Valor abaixo disso significa multiplexacao, e um valor
                        multiplexado e extrapolacao e nao medicao.

Taxas derivadas NAO ficam neste arquivo. Sao calculadas em analise/analise.R:
  taxa_l1d_miss    = l1d_load_misses / l1d_loads
  taxa_branch_miss = branch_misses / branch_instructions
O arquivo bruto guarda apenas medicao. Mudar a definicao de uma taxa passa a
ser uma linha no R em vez de uma recoleta.

Conjunto de eventos usado: $CONJUNTO
Eventos de hardware       : $EVENTOS
EOF
}

# -------------------------------------------------------------------- main
printf '=== Coleta do planejamento fatorial 4x2, %s celulas x %s replicas ===\n' "$CASOS" "$REPLICAS"
: > "$OUT/falhas.log" 2>/dev/null || true
verificar_prerequisitos
compilar
descobrir_eventos
registrar_ambiente
aquecer
coletar
validar
escrever_dicionario
[ -s "$OUT/falhas.log" ] || rm -f "$OUT/falhas.log"

printf '\n=== Coleta concluida ===\n'
printf '  dados/dados_brutos.csv    %s linhas de dado\n' "$((CASOS * REPLICAS))"
printf '  dados/ambiente.txt        ambiente e procedencia dos binarios\n'
printf '  dados/eventos.txt         sondagem, mapeamento e validacao cruzada\n'
printf '  dados/ordem_execucao.txt  ordem sorteada\n'
printf '  dados/dicionario.txt      dicionario de colunas\n'
printf '  dados/perf/               trilha de auditoria, uma saida de perf por execucao\n'
printf '\nProximo passo: Rscript analise/analise.R\n'
