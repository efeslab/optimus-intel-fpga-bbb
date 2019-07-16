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

int process_image(VAI_SVC_WRAPPER& fpga)
{
    uint64_t t1, t2, t3, t4, t5;

    t1 = __rdtsc(); // begin

    std::string file_input("input.png");
    std::string file_output("output.png");
    
    Image image(file_input);

    unsigned int size = image.height * image.width;

    unsigned int *image_in = image.array_in;
    unsigned int *image_out = image.array_out;


    char *src, *dst;
    volatile struct status_cl *stat;
    int i;
    uint64_t id_lo, id_hi;


    if (!fpga.isOk())
        return -1;
   

    src = (char *)fpga.allocBuffer(size*sizeof(unsigned int));
    dst = (char *)fpga.allocBuffer(size*sizeof(unsigned int));

    memcpy(src, image_in, size*sizeof(unsigned int));

    stat = (struct status_cl *) fpga.allocBuffer(sizeof(struct status_cl));

    printf("buf_addr: %llx\n", (uint64_t)src);

    for (i=0; i<size*sizeof(unsigned int); i++) {
        dst[i] = 0;
    }

    stat->completion = 0;
    stat->n_clk = 0;
    stat->n_read = 0;
    stat->n_write = 0;

    t2 = __rdtsc(); // file read & buffer initialization

    fpga.reset();

    fpga.mmioWrite64(MMIO_CSR_STATUS_ADDR, (uint64_t)stat/CL(1));
    fpga.mmioWrite64(MMIO_CSR_SRC_ADDR, (uint64_t)src/CL(1));
    fpga.mmioWrite64(MMIO_CSR_DST_ADDR, (uint64_t)dst/CL(1));
    fpga.mmioWrite64(MMIO_CSR_NUM_LINES, size*sizeof(unsigned int)/CL(1));
    fpga.mmioWrite64(MMIO_CSR_CTL, 1);

    t3 = __rdtsc(); // mmio

    printf("start!\n");

    while (0 == stat->completion) {
        //usleep(500);
    //    printf("running...\n");
    }

    t4 = __rdtsc(); // polling

    printf("finish!\n");

    uint64_t *ptr = (uint64_t*)dst;

    memcpy(image_out, dst, size*sizeof(unsigned int));

    image.map_back();
    image.write_png_file(file_output);

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

    for (int i = 0; i < 10; i++) {
        process_image(fpga);
    }

    return 0;
}
