#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <assert.h>
#include <uuid/uuid.h>
#include <signal.h>
#include <string>
#include <cstring>

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

int main()
{
    std::string file_input("input.png");
    std::string file_output("output.png");
    
    Image image(file_input);

    unsigned int size = image.height * image.width;

    unsigned int *image_in = image.array_in;
    unsigned int *image_out = image.array_out;


    char *src, *dst;
    struct status_cl *stat;
    int i;
    uint64_t id_lo, id_hi;

    VAI_SVC_WRAPPER fpga;

    if (!fpga.isOk())
        return -1;
   
    fpga.reset();

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

    fpga.mmioWrite64(MMIO_CSR_STATUS_ADDR, (uint64_t)stat/CL(1));
    fpga.mmioWrite64(MMIO_CSR_SRC_ADDR, (uint64_t)src/CL(1));
    fpga.mmioWrite64(MMIO_CSR_DST_ADDR, (uint64_t)dst/CL(1));
    fpga.mmioWrite64(MMIO_CSR_NUM_LINES, size*sizeof(unsigned int)/CL(1));
    fpga.mmioWrite64(MMIO_CSR_CTL, 1);

    printf("start!\n");

    while (0 == stat->completion) {
        usleep(500000);
        printf("running...\n");
    }


    uint64_t *ptr = (uint64_t*)dst;

    memcpy(image_out, dst, size*sizeof(unsigned int));

    image.map_back();
    image.write_png_file(file_output);

    //printf("everything is ok!\n");

    dst = NULL;
    stat = NULL;
    src = NULL;

    return 0;
}
