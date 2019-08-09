#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <assert.h>
#include <uuid/uuid.h>
#include <signal.h>
#include <string>
#include <cstring>
#include <x86intrin.h>
#include <sys/time.h>

#include <vai/fpga.h>
#include "csr_addr.h"
#include "vai_svc_wrapper.h"
#include "image.h"

struct status_cl {
    uint64_t completion;
    uint64_t n_clk;
    uint32_t n_read;
    uint32_t n_write;
};

int process_image(VAI_SVC_WRAPPER& fpga, Image& image,
        char* src, char* dst, volatile struct status_cl *stat)
{
    uint64_t t1, t2, t3, t4, t5;

    t1 = __rdtsc(); // begin

    unsigned int *image_in = image.array_in;
    unsigned int *image_out = image.array_out;


    int i;
    uint64_t id_lo, id_hi;


    if (!fpga.isOk()) {
        printf("fpga not ok\n");
        return -1;
    }
   
    unsigned int size = image.height * image.width;

    memcpy(src, image_in, size*sizeof(unsigned int));

    //printf("buf_addr: %llx\n", (uint64_t)src);

    //for (i=0; i<size*sizeof(unsigned int); i++) {
        //dst[i] = 0;
    //}

    stat->completion = 0;
    stat->n_clk = 0;
    stat->n_read = 0;
    stat->n_write = 0;

    t2 = __rdtsc(); // file read & buffer initialization

    //fpga.reset();

    fpga.mmioWrite64(MMIO_CSR_STATUS_ADDR, (uint64_t)stat/CL(1));
    fpga.mmioWrite64(MMIO_CSR_SRC_ADDR, (uint64_t)src/CL(1));
    fpga.mmioWrite64(MMIO_CSR_DST_ADDR, (uint64_t)dst/CL(1));
    fpga.mmioWrite64(MMIO_CSR_NUM_LINES, size*sizeof(unsigned int)/CL(1));
    fpga.mmioWrite64(MMIO_CSR_CTL, 1);

    t3 = __rdtsc(); // mmio

    //printf("start!\n");

    while (0 == stat->completion) {
        //usleep(500);
    //    printf("running...\n");
    }

    t4 = __rdtsc(); // polling

    //printf("finish!\n");

    uint64_t *ptr = (uint64_t*)dst;

    memcpy(image_out, dst, size*sizeof(unsigned int));

    image.map_back();

    //printf("everything is ok!\n");

    t5 = __rdtsc(); // write file

    dst = NULL;
    stat = NULL;
    src = NULL;

    double total = t5 - t1, rd = t2 - t1, mo = t3 - t2, pl = t4 - t3, wr = t5 - t4;
    printf("read %lf, write %lf, mmio %lf, polling %lf\n", rd/total, wr/total, mo/total, pl/total);

    return 0;
}

int main() {
    VAI_SVC_WRAPPER fpga;

    std::string file_input("input.png");
    std::string file_output("output.png");
    
    Image image(file_input);
    struct timespec start, end;

    char *src, *dst;
    volatile struct status_cl *stat;
    unsigned int size = image.height * image.width;

    int k = 0;

    src = (char *)fpga.allocBuffer(size*sizeof(unsigned int));
    dst = (char *)fpga.allocBuffer(size*sizeof(unsigned int));
    stat = (struct status_cl *) fpga.allocBuffer(sizeof(struct status_cl));


    printf("allocation done.\n");

    getchar();

    clock_gettime(CLOCK_MONOTONIC_RAW, &start);

    for (int i = 0; i < 2; i++) {
        process_image(fpga, image, src, dst, stat);
        //printf("image cnt: %d\n", k++);
    }

    clock_gettime(CLOCK_MONOTONIC_RAW, &end);
    uint64_t delta_us = (end.tv_sec - start.tv_sec) * 1000 + (end.tv_nsec - start.tv_nsec) / 1000000;
    printf("t: %ld\n", delta_us);

    image.write_png_file(file_output);

    return 0;
}

