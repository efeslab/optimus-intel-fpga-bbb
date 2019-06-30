#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <assert.h>
#include <uuid/uuid.h>
#include <signal.h>

#include <vai/fpga.h>
#include "csr_addr.h"

#include "vai_svc_wrapper.h"

struct status_cl {
    uint64_t completion;
    uint64_t n_clk;
    uint32_t n_read;
    uint32_t n_write;
};

int vai_memcpy_test(void)
{
    char *src, *dst;
    struct status_cl *stat;
    int i;
    uint64_t id_lo, id_hi;

    VAI_SVC_WRAPPER fpga;

    if (!fpga.isOk())
        return -1;
   
    fpga.reset();

    //vai_afu_alloc_region(conn, (void *)&src, 0, 4096*30);
    src = (char *) fpga.allocBuffer(4096*30, NULL);
    dst = src + 40960;
    stat = (struct status_cl *) (dst + 40960);

    printf("buf_addr: %llx\n", (uint64_t)src);

    for (i=0; i<40960; i++) {
        src[i] = rand()%256;
        dst[i] = 0;
    }

    stat->completion = 0;
    stat->n_clk = 0;
    stat->n_read = 0;
    stat->n_write = 0;

    fpga.mmioWrite64(MMIO_CSR_STATUS_ADDR, (uint64_t)stat/CL(1));
    fpga.mmioWrite64(MMIO_CSR_SRC_ADDR, (uint64_t)src/CL(1));
    fpga.mmioWrite64(MMIO_CSR_DST_ADDR, (uint64_t)dst/CL(1));
    fpga.mmioWrite64(MMIO_CSR_NUM_LINES, 128/CL(1));
    fpga.mmioWrite64(MMIO_CSR_CTL, 1);

    printf("start!\n");

    while (0 == stat->completion) {
        usleep(500000);
        printf("running...\n");
    }

    for (i=0; i<128; ++i) {
        if (src[i] != dst[i]) {
            printf("wrong at %zu, get %u instead of %u\n", i, dst[i], src[i]);
            return -1;
        }
    }

    uint64_t *ptr = (uint64_t*)src;

    for (i=0; i<48; i++) {
        printf("%016llx\n", ptr[i]);
    }

    printf("everything is ok!\n");

    dst = NULL;
    stat = NULL;
    src = NULL;

    return 0;
}

int main(int argc, char *argv[])
{
    uint64_t id_lo, id_hi;
    time_t t;

    vai_memcpy_test();

    return 0;
}
