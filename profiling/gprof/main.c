#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>

const int size = 50000;


#define KB (1024)
#define MB (1024 * KB)
#define GB (1024 * MB)
#define LARGEST_CACHE_SZ (8 * MB)
static unsigned char dummy_buffer[LARGEST_CACHE_SZ];

void clean_cache() {
	unsigned long long i;
	for (i = 0; i < LARGEST_CACHE_SZ; i++)
		dummy_buffer[i] += 1;
}

void swap(int *a, int *b) {
	int temp = *a;
	
	*a = *b;
	*b = temp;
}

void bubbleSort(int array[], int size) {
	
	for (int i = 0; i < size - 1; i++) {
		for (int j = 0; j < size - i - 1; j++) {
			if (array[j] > array[j + 1]) {
				swap(&array[j], &array[j + 1]);	
			}	
		}
	}	
}

int qsPartition(int array[], int low, int high) {
	int p = array[low];
	int i = low;
	int j = high;
	

	while (i < j) {
		while (array[i] <= p && i <= high - 1) {
			i++;
		}

		while (array[j] > p && j >= low + 1) {
			j--;
		}

		if (i < j) {
			swap(&array[i], &array[j]);
		}
	}

	swap(&array[low], &array[j]);

	return j;
}

void quickSort(int array[], int low, int high) {
	if (low < high) {
		int pi = qsPartition(array, low, high);

		quickSort(array, low, pi - 1);
		quickSort(array, pi + 1, high);
	}
}

void insertionSort(int array[], int size) {

	for (int i = 1; i < size; i++) {
		int key = array[i];
		int j = i - 1;

		while (j >= 0 && array[j] > key) {
			array[j + 1] = array[j];
			j = j - 1;
		}

		array[j + 1] = key;
	}	

}

int main() {
	
	int *array = malloc(size * sizeof(int));
	int *tmp_array = malloc(size * sizeof(int));

	for (int i = 0; i < size; i++) {
		// populate our array with random values between 0 and 10000
		array[i] = rand() % 10000; 
	}

	for (int i = 0; i < 10; i++) {
		
		// Bubble Sort test
		memcpy(tmp_array, array, size * sizeof(int));
		clean_cache();
		bubbleSort(tmp_array, size);
 
		// Insertion Sort test
		memcpy(tmp_array, array, size * sizeof(int));
		clean_cache();
		insertionSort(tmp_array, size);
 
		// Quick Sort test
		memcpy(tmp_array, array, size * sizeof(int));
		clean_cache();
		quickSort(tmp_array, 0, size - 1);		
	}
	
	free(array);
	free(tmp_array);

	return 0;
}
