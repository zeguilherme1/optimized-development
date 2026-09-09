#pragma once
#ifndef UTILS_STATIC_H
#define UTILS_STATIC_H

#include "matrix_config.h"

/* =========================================================================
 * utils_static.h - kernels e auxiliares da familia de ALOCACAO ESTATICA
 *
 * As matrizes sao arrays de tamanho fixo, contiguos, declarados em escopo de
 * arquivo (.bss) em cada case*.c. Esse e o nivel "estatica" do Fator 2.
 *
 * Escopo de arquivo e obrigatorio e nao estilistico: 3 matrizes de int a
 * N=1000 ocupam 11,44 MiB e o limite de pilha desta maquina e 8 MiB. Como
 * arrays automaticos em main, o quadro estoura, e em -O0 o gcc nao emite
 * stack probe, logo a primeira escrita alem da pagina de guarda e um SIGSEGV
 * sem diagnostico.
 *
 * O sufixo Static existe porque C nao tem sobrecarga. Com ele, linkar
 * utils.c e utils_static.c no mesmo binario gera no maximo um objeto sem uso
 * em vez de quatro erros de simbolo duplicado.
 *
 * Como em utils.h, os quatro kernels NAO zeram matrix_c. Ver a nota la.
 * ========================================================================= */

int matrixDim(void);

void fillMatrixStatic(int matrix[N][N], unsigned long long seed);

void zeroMatrixStatic(int matrix[N][N]);

void multiplyMatrixStatic(int matrix_a[N][N], int matrix_b[N][N], int matrix_c[N][N]);

void loopInterchangeMultStatic(int matrix_a[N][N], int matrix_b[N][N], int matrix_c[N][N]);

void loopUnrollingMultStatic(int matrix_a[N][N], int matrix_b[N][N], int matrix_c[N][N]);

void loopTilingMultStatic(int matrix_a[N][N], int matrix_b[N][N], int matrix_c[N][N]);

long long checksumMatrixStatic(int matrix[N][N]);

void printMatrixStatic(int matrix[N][N]);

#endif
