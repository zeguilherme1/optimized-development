#include <stdio.h>
#include <stdlib.h>
#define N 100

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

int main() {
	int **matrix_a = createMatrix(N, N); 
	int **matrix_b = createMatrix(N, N); 
	int **matrix_c = createMatrix(N, N);

	for (int i = 0; i < N; i++) {
		for (int j = 0; j < N; j++) {
			matrix_a[i][j] = -1;
			matrix_b[i][j] = -2;
		}
	}

	multiplyMatrix(matrix_a, matrix_b, matrix_c);		
	
	printMatrix(matrix_c);

	freeMatrix(matrix_a);
	freeMatrix(matrix_b);
	freeMatrix(matrix_c);
	return 0;
}

