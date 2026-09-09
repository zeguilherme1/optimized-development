#pragma once
#ifndef MATRIX_CONFIG_H
#define MATRIX_CONFIG_H

/* =========================================================================
 * matrix_config.h - parametros do experimento fatorial 4x2
 *
 * SSC0951 - Desenvolvimento de Codigo Otimizado
 *
 * Unico ponto de definicao de N, BLOCO e UNROLL no projeto inteiro. Nenhum
 * case*.c e nenhum utils*.c pode redefinir esses macros: manter os tres aqui
 * e o que garante que as duas familias de alocacao medem o mesmo problema e
 * usam o mesmo tamanho de bloco e o mesmo fator de desenrolamento.
 * ========================================================================= */

/* Ordem das matrizes quadradas. 3 matrizes de int a N=1000 ocupam 11,44 MiB,
 * acima do limite de pilha de 8 MiB desta maquina, por isso os arrays da
 * familia estatica ficam em escopo de arquivo (.bss) e nunca em main. */
#define N 1000

/* Lado do bloco do kernel com tiling.
 * L1d = 48 KiB por P-core, linha de 64 B, 12 vias, elemento int de 4 B.
 * As linhas da matriz distam 4000 B e nunca ficam alinhadas em 64 B, logo uma
 * linha de tile de T ints ocupa ceil((4T + 63)/64) linhas de cache. Para
 * T = 32 o pior caso de 3 tiles residentes e 18,0 KiB, ou 37% da L1d, com
 * folga para pilha e streaming do bloco seguinte. T = 64 chegaria a 60 KiB e
 * estouraria a L1d.
 * 1000 % 32 = 8, logo o ultimo bloco de cada dimensao tem largura 8 e as
 * guardas de resto executam em toda execucao, o que e proposital: guarda que
 * nunca roda e guarda que nunca foi testada. */
#define BLOCO 32

/* Fator de desenrolamento do laco mais interno do kernel com unrolling.
 * O corpo desenrolado e escrito a mao, por isso ha um _Static_assert em
 * utils.c e em utils_static.c travando este valor em 4. */
#define UNROLL 4

/* Sementes do preenchimento deterministico. Diferentes para que A != B. */
#define SEED_A 12345ULL
#define SEED_B 67890ULL

/* Limite superior do valor de celula gerado por nextValue.
 * |c[i][j]| <= N * VALOR_MAX^2 = 1000 * 255^2 = 65025000, cerca de 3% da
 * faixa do int, margem de 33x contra transbordo. O limite duro em N=1000
 * seria 1465. */
#define VALOR_MAX 255

/* Gerador linear congruente, mesmas constantes de atv1/experimento/matmul.c.
 * Descarta os 33 bits baixos, de qualidade ruim, e limita a [0,255].
 *
 * static inline e obrigatorio: funcao com ligacao externa definida em header
 * colide em todo binario que a inclui por duas unidades de traducao, o que
 * aqui e o caso dos oito (case*.c mais utils*.c).
 *
 * O preenchimento e nao uniforme de proposito. Com A e B constantes, um bug
 * de transposicao de indice (matrix_a[k][i] * matrix_b[j][k]) produz o mesmo
 * resultado e o checksum nao detecta nada. */
static inline int nextValue(unsigned long long *state)
{
	*state = *state * 6364136223846793005ULL + 1442695040888963407ULL;
	return (int)((*state >> 33) & VALOR_MAX);
}

#endif
