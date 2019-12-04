#include <iostream>
#include <stdlib.h>
#include <getopt.h>
#include <string.h>
using namespace std;

int main(int argc, char *argv[]) {
    int opt, num_v, factor;
    while ((opt = getopt (argc, argv, ":v:f:")) != -1) {
        switch (opt) {
            case 'v':
                num_v = atoi(optarg);
                break;
            case 'f':
                factor = atoi(optarg);
                break;
            case '?':
                printf("Unknown option: %c\n", opt);
                return -EINVAL;
        }
    }

    for (int i = 0; i < num_v; i++) {
        for (int j = 0; j < factor; j++) {
            int k = rand() % num_v;
            cout << i << " " << k << endl;
        }
    }
    return 0;
}
