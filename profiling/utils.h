#pragma once
#ifndef UTILS_H
#define UTILS_H

#include "matrix_config.h"

/* =========================================================================
 * utils.h - kernels e auxiliares da familia de ALOCACAO DINAMICA
 *
 * As matrizes sao int** com uma chamada de malloc por linha, portanto as
 * linhas nao sao contiguas. Esse e o nivel "dinamica" do Fator 2.
 *
 * Os quatro kernels NAO zeram matrix_c. A zeragem e responsabilidade de main
 * e acontece antes do relogio comecar, por dois motivos:
 *   1. comparabilidade, os quatro kernels executam exatamente o mesmo
 *      conjunto de multiplicacoes e acumulacoes, diferindo so na ordem de
 *      acesso, e nao um deles com um passe extra de N^2 stores;
 *   2. falha de pagina de primeiro toque, as paginas de C precisam estar
 *      mapeadas antes da regiao cronometrada, senao cerca de mil faltas de
 *      pagina entram na medicao e sao cobradas do fator errado.
 * ========================================================================= */

int matrixDim(void);

int** createMatrix(int rows, int cols);

void fillMatrix(int **matrix, unsigned long long seed);

void zeroMatrix(int **matrix);

void multiplyMatrix(int **matrix_a, int **matrix_b, int **matrix_c);

void loopInterchangeMult(int **matrix_a, int **matrix_b, int **matrix_c);

void loopUnrollingMult(int **matrix_a, int **matrix_b, int **matrix_c);

void loopTilingMult(int **matrix_a, int **matrix_b, int **matrix_c);

long long checksumMatrix(int **matrix);

void printMatrix(int **matrix);

void freeMatrix(int **matrix);

#endif
