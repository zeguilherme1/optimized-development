#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <time.h>
#include "utils_static.h"

/* =========================================================================
 * case7.c - Tecnica: tiling | Alocacao: estatica
 *
 * SSC0951 - Desenvolvimento de Codigo Otimizado
 *
 * Uma celula do planejamento fatorial 4x2. Os oito casos compartilham este
 * mesmo esqueleto de main e diferem apenas no kernel chamado e na alocacao,
 * que sao exatamente os dois fatores do experimento.
 *
 * Compilar: gcc -O0 -std=c11 -Wall -Wextra -Werror -o case7 case7.c utils_static.c
 * Saida   : uma linha CSV, sem cabecalho
 *   case_id,technique,allocation,n,block_size,unroll_factor,tempo_kernel_ns,checksum
 * ========================================================================= */

/* Escopo de arquivo, nao dentro de main: 3 x 1000 x 1000 x 4 B = 11,44 MiB
 * contra um limite de pilha de 8 MiB. Em .bss isso nao custa nada no binario
 * em disco e e limitado pela RAM, nao por ulimit -s.
 *
 * A classe static tambem importa: desde o gcc 10 o padrao e -fno-common, e
 * uma definicao tentativa sem static em escopo de arquivo colidiria se outra
 * unidade de traducao declarasse a mesma coisa. */
static int matrix_a[N][N];
static int matrix_b[N][N];
static int matrix_c[N][N];

int main(void)
{
	struct timespec t0, t1;

	/* Preenchimento de A e B e zeragem de C acontecem ANTES do relogio.
	 * Isso mantem fora da regiao cronometrada tanto o custo do gerador
	 * pseudoaleatorio quanto as faltas de pagina de primeiro toque. As
	 * paginas de .bss sofrem demand zero fault na primeira escrita, custo
	 * diferente do heap da familia dinamica, e dentro do relogio seria
	 * cobrado do Fator 2 pelo motivo errado. */
	fillMatrixStatic(matrix_a, SEED_A);
	fillMatrixStatic(matrix_b, SEED_B);
	zeroMatrixStatic(matrix_c);

	clock_gettime(CLOCK_MONOTONIC, &t0);
	loopTilingMultStatic(matrix_a, matrix_b, matrix_c);
	clock_gettime(CLOCK_MONOTONIC, &t1);

#ifdef VERIFICA
	/* Build de verificacao de equivalencia: imprime apenas a matriz, para
	 * que o md5sum da saida seja deterministico. */
	(void)t0;
	(void)t1;
	printMatrixStatic(matrix_c);
#else
	{
		long long tempo_ns = (t1.tv_sec - t0.tv_sec) * 1000000000LL
		                   + (t1.tv_nsec - t0.tv_nsec);

		printf("%d,%s,%s,%d,%d,%d,%lld,%lld\n",
		       7, "tiling", "estatica", matrixDim(),
		       BLOCO, 1,
		       tempo_ns, checksumMatrixStatic(matrix_c));
	}
#endif

	return 0;
}
