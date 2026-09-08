#include <stdio.h>
#include <stdlib.h>
#include "utils.h"
#define N 1000

int** createMatrix(int rows, int cols) {
	int **matrix = (int**)malloc(rows * sizeof(int*));

	for (int i = 0; i < rows; i++) {
		matrix[i] = (int*)malloc(cols * sizeof(int));
	}

	return matrix;
}

void multiplyMatrix(int **matrix_a, int **matrix_b, int **matrix_c) {
	for (int i = 0; i < N; i++) {
		for (int j = 0; j < N; j++) {
			matrix_c[i][j] = 0;
			for (int k = 0; k < N; k++) {
				matrix_c[i][j] += matrix_a[i][k] * matrix_b[k][j];
			}
		}
	}	
}

void loopInterchangeMult(int **matrix_a, int **matrix_b, int **matrix_c) {
	for (int i = 0; i < N; i++) {
		for (int j = 0; j < N; j++) {
			matrix_c[i][j] = 0;
		}
		for (int k = 0; k < N; k++) {
			for (int j = 0; j < N; j++) {
				matrix_c[i][j] += matrix_a[i][k] * matrix_b[k][j];
			}
		}
	}
}

void loopUnrollingMult(int **matrix_a, int **matrix_b, int **matrix_c) {
	for (int i = 0; i < N; i++) {
		for (int j = 0; j < N; j++) {
			matrix_c[i][j] = 0;
		}

		for (int j = 0; j < N; j++) {
			for (int k = 0; k < N; k += 2) {
				matrix_c[i][j] += matrix_a[i][k] * matrix_b[k][j];
			   matrix_c[i][j] += matrix_a[i][k + 1] * matrix_b[k + 1][j];	
			}	
		}
	}
}

void loopTillingMult(int **matrix_a, int **matrix_b, int **matrix_c) {
	for (int i = 0; i < N; i++) {
		for (int j = 0; j < N; j++) {
			matrix_c[i][j] = 0;
		}

		for (int j = 0; j < N; j++) {
			for (int k = 0; k < N; k += 2) {
				matrix_c[i][j] += matrix_a[i][k] * matrix_b[k][j];
			   matrix_c[i][j] += matrix_a[i][k + 1] * matrix_b[k + 1][j];	
			}	
		}
	}
}

void printMatrix(int **matrix) {
	for (int i = 0; i < N; i++) {
		for (int j = 0; j < N; j++) {
			printf("%d ", matrix[i][j]);
		}
		printf("\n");
	}
}

void freeMatrix(int **matrix) {
	for (int i = 0; i < N; i++) {
		free(matrix[i]);
	}

	free(matrix);
}


