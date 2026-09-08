#include <stdio.h>
#include <stdlib.h>
#include "utils.h"
#define N 1000

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

	loopUnrollingMult(matrix_a, matrix_b, matrix_c);		
	
	printMatrix(matrix_c);

	freeMatrix(matrix_a);
	freeMatrix(matrix_b);
	freeMatrix(matrix_c);
	return 0;
}

