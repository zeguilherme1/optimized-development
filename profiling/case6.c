#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include "utils.h"

/* =========================================================================
 * case6.c - Tecnica: unrolling | Alocacao: dinamica
 *
 * SSC0951 - Desenvolvimento de Codigo Otimizado
 *
 * Uma celula do planejamento fatorial 4x2. Os oito casos compartilham este
 * mesmo esqueleto de main e diferem apenas no kernel chamado e na alocacao,
 * que sao exatamente os dois fatores do experimento.
 *
 * Compilar: gcc -O0 -std=c11 -Wall -Wextra -Werror -o case6 case6.c utils.c
 * Saida   : uma linha CSV, sem cabecalho
 *   case_id,technique,allocation,n,block_size,unroll_factor,tempo_kernel_ns,checksum
 * ========================================================================= */

int main(void)
{
	int **matrix_a = createMatrix(N, N);
	int **matrix_b = createMatrix(N, N);
	int **matrix_c = createMatrix(N, N);
	struct timespec t0, t1;

	if (matrix_a == NULL || matrix_b == NULL || matrix_c == NULL) {
		fprintf(stderr, "case6: falha ao alocar as matrizes\n");
		return 1;
	}

	/* Preenchimento de A e B e zeragem de C acontecem ANTES do relogio.
	 * Isso mantem fora da regiao cronometrada tanto o custo do gerador
	 * pseudoaleatorio quanto as faltas de pagina de primeiro toque, que
	 * diferem entre as duas familias de alocacao e seriam cobradas do
	 * Fator 2 pelo motivo errado. */
	fillMatrix(matrix_a, SEED_A);
	fillMatrix(matrix_b, SEED_B);
	zeroMatrix(matrix_c);

	clock_gettime(CLOCK_MONOTONIC, &t0);
	loopUnrollingMult(matrix_a, matrix_b, matrix_c);
	clock_gettime(CLOCK_MONOTONIC, &t1);

#ifdef VERIFICA
	/* Build de verificacao de equivalencia: imprime apenas a matriz, para
	 * que o md5sum da saida seja deterministico. A linha CSV carrega o
	 * tempo medido, que varia de execucao para execucao. */
	(void)t0;
	(void)t1;
	printMatrix(matrix_c);
#else
	{
		long long tempo_ns = (t1.tv_sec - t0.tv_sec) * 1000000000LL
		                   + (t1.tv_nsec - t0.tv_nsec);

		printf("%d,%s,%s,%d,%d,%d,%lld,%lld\n",
		       6, "unrolling", "dinamica", matrixDim(),
		       0, UNROLL,
		       tempo_ns, checksumMatrix(matrix_c));
	}
#endif

	freeMatrix(matrix_a);
	freeMatrix(matrix_b);
	freeMatrix(matrix_c);

	return 0;
}
