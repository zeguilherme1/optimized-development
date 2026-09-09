#include <stdio.h>
#include "utils_static.h"

/* =========================================================================
 * utils_static.c - kernels da familia de ALOCACAO ESTATICA
 *
 * Transliteracao mecanica de utils.c. Os quatro nests de laco sao identicos
 * caractere por caractere aos da versao dinamica: a unica diferenca e o tipo
 * do parametro, int matrix[N][N] em vez de int **matrix, e portanto o
 * enderecamento. Isso e exatamente o Fator 2 do experimento e nada mais.
 *
 * Sobre a escolha do parametro. Em -O0 uma leitura de elemento custa:
 *   int **m  na pilha  ->  carrega m, carrega m[i], carrega m[i][k]   = 3
 *   int m[N][N]        ->  carrega m, carrega m[i][k] em base+i*4000  = 2
 *   global lido direto ->  carrega m[i][k] em desloc. relativo a RIP  = 1
 * A diferenca real entre as duas alocacoes e um load de ponteiro dependente
 * mais a perda de contiguidade entre linhas. A forma de parametro, 2 contra
 * 3, captura isso. A forma global, 1 contra 3, somaria uma segunda unidade de
 * diferenca que e artefato de passagem de parametro e nao de alocacao,
 * inflando o efeito principal do Fator 2 na metrica de loads.
 * ========================================================================= */

/* Corpo desenrolado escrito a mao para fator 4. Mudar UNROLL em
 * matrix_config.h sem reescrever o corpo daria um kernel silenciosamente
 * errado, por isso o valor fica travado aqui. */
_Static_assert(UNROLL == 4, "corpo desenrolado escrito a mao para fator 4");

int matrixDim(void) {
	return N;
}

void fillMatrixStatic(int matrix[N][N], unsigned long long seed) {
	unsigned long long state = seed;

	for (int i = 0; i < N; i++) {
		for (int j = 0; j < N; j++) {
			matrix[i][j] = nextValue(&state);
		}
	}
}

void zeroMatrixStatic(int matrix[N][N]) {
	for (int i = 0; i < N; i++) {
		for (int j = 0; j < N; j++) {
			matrix[i][j] = 0;
		}
	}
}

/* Nivel base do Fator 1: ordem i-j-k, sem transformacao.
 * O laco k percorre uma linha de A e uma COLUNA de B, com passo de 4000 B,
 * o que falha em quase todo acesso a L1. */
void multiplyMatrixStatic(int matrix_a[N][N], int matrix_b[N][N], int matrix_c[N][N]) {
	for (int i = 0; i < N; i++) {
		for (int j = 0; j < N; j++) {
			for (int k = 0; k < N; k++) {
				matrix_c[i][j] += matrix_a[i][k] * matrix_b[k][j];
			}
		}
	}
}

/* Loop interchange: unica transformacao e trocar j e k, virando i-k-j.
 * Agora o laco interno percorre uma LINHA de B e uma linha de C, os dois
 * sequenciais, e a[i][k] fica invariante no laco interno. */
void loopInterchangeMultStatic(int matrix_a[N][N], int matrix_b[N][N], int matrix_c[N][N]) {
	for (int i = 0; i < N; i++) {
		for (int k = 0; k < N; k++) {
			for (int j = 0; j < N; j++) {
				matrix_c[i][j] += matrix_a[i][k] * matrix_b[k][j];
			}
		}
	}
}

/* Loop unrolling: mesma ordem i-j-k da base, unica transformacao e desenrolar
 * o laco mais interno em UNROLL = 4 copias. Corta as instrucoes de branch do
 * laco interno de cerca de 1e9 para 2,5e8 sem mudar o padrao de acesso.
 *
 * k e declarado antes do primeiro laco e o laco de resto continua dele.
 * Declarar um k novo comecando em zero e a versao classica desse bug.
 * Em N=1000 o resto tem zero iteracoes, mas a guarda existe para o kernel
 * estar correto em qualquer N, ao contrario do k += 2 sem guarda anterior,
 * que lia matrix_b[k+1][j] fora dos limites em N impar. */
void loopUnrollingMultStatic(int matrix_a[N][N], int matrix_b[N][N], int matrix_c[N][N]) {
	const int k_limit = N - (N % UNROLL);

	for (int i = 0; i < N; i++) {
		for (int j = 0; j < N; j++) {
			int k = 0;

			for (; k < k_limit; k += UNROLL) {
				matrix_c[i][j] += matrix_a[i][k]     * matrix_b[k][j];
				matrix_c[i][j] += matrix_a[i][k + 1] * matrix_b[k + 1][j];
				matrix_c[i][j] += matrix_a[i][k + 2] * matrix_b[k + 2][j];
				matrix_c[i][j] += matrix_a[i][k + 3] * matrix_b[k + 3][j];
			}

			for (; k < N; k++) {
				matrix_c[i][j] += matrix_a[i][k] * matrix_b[k][j];
			}
		}
	}
}

/* Loop tiling: unica transformacao e bloquear o espaco de iteracao em cubos
 * de lado BLOCO. A ordem interna permanece i-j-k, IDENTICA a base. Se o
 * kernel bloqueado usasse i-k-j ele carregaria blocking mais interchange, e o
 * efeito principal de Tecnica ficaria confundido com a interacao.
 *
 * matrix_c ja vem zerada de main, o que aqui e obrigatorio e nao apenas
 * conveniente: os blocos kk acumulam sobre o mesmo elemento de C, e zerar
 * dentro do nest apagaria as somas parciais dos blocos anteriores.
 *
 * As guardas i_max, j_max e k_max nao sao opcionais. 1000 % 32 = 8, logo o
 * ultimo bloco de cada dimensao tem largura 8, e um laco que fosse ate
 * ii + BLOCO escreveria 24 elementos alem do fim de todo bloco final. */
void loopTilingMultStatic(int matrix_a[N][N], int matrix_b[N][N], int matrix_c[N][N]) {
	for (int ii = 0; ii < N; ii += BLOCO) {
		const int i_max = (ii + BLOCO < N) ? ii + BLOCO : N;

		for (int jj = 0; jj < N; jj += BLOCO) {
			const int j_max = (jj + BLOCO < N) ? jj + BLOCO : N;

			for (int kk = 0; kk < N; kk += BLOCO) {
				const int k_max = (kk + BLOCO < N) ? kk + BLOCO : N;

				for (int i = ii; i < i_max; i++) {
					for (int j = jj; j < j_max; j++) {
						for (int k = kk; k < k_max; k++) {
							matrix_c[i][j] += matrix_a[i][k] * matrix_b[k][j];
						}
					}
				}
			}
		}
	}
}

/* Soma dos N^2 elementos de C, em long long. O maximo e
 * 1e6 * 65025000 = 6,5e13, cerca de 30000x alem da faixa do int.
 * Chamada FORA da regiao cronometrada. Como toda a aritmetica e inteira, os
 * oito kernels devem produzir checksums bit a bit identicos, sem tolerancia. */
long long checksumMatrixStatic(int matrix[N][N]) {
	long long soma = 0;

	for (int i = 0; i < N; i++) {
		for (int j = 0; j < N; j++) {
			soma += (long long)matrix[i][j];
		}
	}

	return soma;
}

void printMatrixStatic(int matrix[N][N]) {
	for (int i = 0; i < N; i++) {
		for (int j = 0; j < N; j++) {
			printf("%d ", matrix[i][j]);
		}
		printf("\n");
	}
}
