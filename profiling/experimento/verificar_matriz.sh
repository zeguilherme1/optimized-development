#!/usr/bin/env bash
# =============================================================================
# verificar_matriz.sh - prova de equivalencia dos oito kernels
#
# SSC0951 - Desenvolvimento de Codigo Otimizado
#
# Roda os oito binarios construidos com -DVERIFICA, que imprimem a matriz C
# inteira e nada mais, e compara o md5sum das saidas.
#
# Isso e mais forte que comparar o checksum de 64 bits das linhas CSV: aqui
# os 1.000.000 de elementos sao comparados um a um, nao um digest deles. Um
# checksum e uma soma, e somas podem coincidir por acidente. Custa oito
# execucoes extras uma unica vez, nao uma por medicao.
#
# Roda FORA do caminho de medicao e e portao: sem isso passar, coletar dados
# nao faz sentido, porque estatistica sobre kernels que calculam matrizes
# diferentes nao vale nada.
# =============================================================================

set -euo pipefail
export LC_ALL=C

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VBIN="$RAIZ/experimento/bin/verif"
OUT="$RAIZ/dados"
SAIDA="$OUT/verificacao_matriz.txt"

mkdir -p "$OUT"

if [ ! -x "$VBIN/case1" ]; then
	echo "ERRO: binarios de verificacao ausentes. Rode: make -C '$RAIZ' verif" >&2
	exit 1
fi

{
	echo "Verificacao de equivalencia dos oito kernels"
	echo "Data                : $(date -Is)"
	echo "Metodo              : md5sum da matriz C completa (1.000.000 de elementos)"
	echo "Binarios            : $VBIN/case1..case8, construidos com -DVERIFICA"
	echo
} > "$SAIDA"

declare -a digests=()

for i in 1 2 3 4 5 6 7 8; do
	printf '  case%d ... ' "$i"
	d="$(taskset -c 0 "$VBIN/case$i" | md5sum | cut -d' ' -f1)"
	digests+=("$d")
	printf '%s\n' "$d"
	printf 'case%-2d %s\n' "$i" "$d" >> "$SAIDA"
done

distintos="$(printf '%s\n' "${digests[@]}" | sort -u | wc -l)"

echo >> "$SAIDA"
if [ "$distintos" -ne 1 ]; then
	echo "RESULTADO: FALHA, $distintos digests distintos" >> "$SAIDA"
	echo >&2
	echo "ERRO: os oito kernels NAO produzem a mesma matriz ($distintos digests distintos)." >&2
	echo "      Suspeitos principais: as guardas de resto do tiling e o laco de" >&2
	echo "      resto do unrolling. Ver $SAIDA" >&2
	exit 1
fi

# Faixa dos elementos, contra o limite analitico do preenchimento LCG.
# Pega transbordo de int, que e a falha que checksums concordantes NAO pegam,
# porque ela corrompe os oito kernels de forma identica.
echo -n "  faixa dos elementos de C ... "
faixa="$(taskset -c 0 "$VBIN/case1" | tr ' ' '\n' | awk '
	NF { if (min == "" || $1 < min) min = $1; if (max == "" || $1 > max) max = $1 }
	END { printf "%d %d", min, max }')"
lo="${faixa% *}"; hi="${faixa#* }"
limite=$((1000 * 255 * 255))

if [ "$lo" -lt 0 ] || [ "$hi" -gt "$limite" ]; then
	echo "fora da faixa [0, $limite]: [$lo, $hi]"
	echo "RESULTADO: FALHA, elementos fora de [0, $limite]: [$lo, $hi]" >> "$SAIDA"
	echo "ERRO: transbordo de int detectado." >&2
	exit 1
fi
echo "[$lo, $hi] dentro de [0, $limite]"

{
	echo "Faixa dos elementos : [$lo, $hi], limite analitico [0, $limite]"
	echo "RESULTADO           : OK, os oito kernels produzem a mesma matriz"
} >> "$SAIDA"

echo
echo "OK: oito digests identicos (${digests[0]}), elementos dentro da faixa analitica."
echo "Registro em $SAIDA"
