#include <stdio.h>
#include <stdlib.h>
#define N 100
int main() {

	int matrix_a[N][N];
	int matrix_b[N][N];
	int matrix_c[N][N];

	for (int i = 0; i < N; i++) {
		for (int j = 0; j < N; j++) {
			matrix_a[i][j] = -1;
			matrix_b[i][j] = -1;
			matrix_c[i][j] = 0;
		}
	}

	for (int i = 0; i < N; i++) {
		for (int j = 0; j < N; j++) {
			for (int k = 0; k < N; k++) {
				matrix_c[i][j] += matrix_a[i][k] * matrix_b[k][j];
			}
		}
	}
	
	return 0;
}
