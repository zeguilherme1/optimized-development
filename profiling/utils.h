#pragma once
#ifndef UTILS_H
#define UTILS_H

int** createMatrix(int rows, int cols); 

void multiplyMatrix(int **matrix_a, int **matrix_b, int **matrix_c);

void loopInterchangeMult(int **matrix_a, int **matrix_b, int **matrix_c);

void loopUnrollingMult(int **matrix_a, int **matrix_b, int **matrix_c);

void loopTillingMult(int **matrix_a, int **matrix_b, int **matrix_c);

void printMatrix(int **matrix);

void freeMatrix(int **matrix);

#endif


