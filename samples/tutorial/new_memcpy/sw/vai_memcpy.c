#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <assert.h>
#include <uuid/uuid.h>
#include <signal.h>

#include <vai/vai.h>
#include "csr_addr.h"

struct vai_afu_conn *conn;

struct status_cl {
    uint64_t completion;
    uint64_t n_clk;
    uint32_t n_read;
    uint32_t n_write;
};

void handler(int sig) {
    printf("disconnecting and exiting...\n");
    vai_afu_disconnect(conn);
    exit(-1);
}

int vai_memcpy_test(void)
{
    char *src, *dst;
    struct status_cl *stat;
    int i;
    uint64_t id_lo, id_hi;

    //vai_afu_alloc_region(conn, (void *)&src, 0, 4096*30);
    src = vai_afu_malloc(conn, 4096*30);
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

#define MMIO_VMOFF 0x000
    
    /* read afu uuid */
    vai_afu_mmio_read(conn, MMIO_VMOFF+0x0, &id_lo);
    vai_afu_mmio_read(conn, MMIO_VMOFF+0x8, &id_lo);
    vai_afu_mmio_read(conn, MMIO_VMOFF+0x10, &id_hi);
    printf("%llx%llx\n", id_lo, id_hi);

    vai_afu_mmio_write(conn, MMIO_VMOFF+MMIO_CSR_SOFT_RST, 1L);
    vai_afu_mmio_write(conn, MMIO_VMOFF+MMIO_CSR_SOFT_RST, 0L);
    vai_afu_mmio_write(conn, MMIO_VMOFF+MMIO_CSR_STATUS_ADDR, (uint64_t)stat/CL(1));
    vai_afu_mmio_write(conn, MMIO_VMOFF+MMIO_CSR_SRC_ADDR, (uint64_t)src/CL(1));
    vai_afu_mmio_write(conn, MMIO_VMOFF+MMIO_CSR_DST_ADDR, (uint64_t)dst/CL(1));
    vai_afu_mmio_write(conn, MMIO_VMOFF+MMIO_CSR_NUM_LINES, 128/CL(1));
    //vai_afu_mmio_write(conn, MMIO_VMOFF+MMIO_CSR_WR_THRESHOLD, 6);
    vai_afu_mmio_write(conn, MMIO_VMOFF+MMIO_CSR_CTL, 1);

    printf("start!\n");

    while (0 == stat->completion) {
        usleep(500000);
    }

    for (i=0; i<128; ++i) {
        if (src[i] != dst[i])
            goto error;
    }

    uint64_t *ptr = (uint64_t*)src;

    for (i=0; i<48; i++) {
        printf("%016llx\n", ptr[i]);
    }

    printf("everything is ok!\n");

    dst = NULL;
    stat = NULL;
    vai_afu_free(conn, src);
    src = NULL;

    return 0;

error:
    printf("wrong at %zu, get %u instead of %u\n", i, dst[i], src[i]);
    return -1;
}

int main(int argc, char *argv[])
{
    void *buf_addr;
    volatile char *buf;
    uint64_t id_lo, id_hi;
    time_t t;

    srand((unsigned) time(&t));

    conn = vai_afu_connect();
    signal(SIGINT, handler);

    vai_memcpy_test();

    vai_afu_disconnect(conn);

    return 0;
}
