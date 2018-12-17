//
// Copyright (c) 2017, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <assert.h>
#include <string.h>

#include <vai/vai.h>
#include "csr_addr.h"

struct status_cl {
    uint64_t completion;
    uint64_t n_clk;
    uint32_t n_read;
    uint32_t n_write;
};

int main(int argc, char *argv[])
{
    uint32_t wr_threshold;
    uint32_t num_pages;
    if (argc < 3) {
        printf("Usage: %s wr_threshold num_pages\n", argv[0]);
        return -1;
    }
    else {
        wr_threshold = atoi(argv[1]);
        num_pages = atoi(argv[2]);
    }
    struct vai_afu_conn *conn = vai_afu_connect();
    // buf[0] is src, buf[1] is dst, buf[2] is status flag
    volatile unsigned char *buf[3];
    uint64_t buf_pa[3];
    size_t buf_size = num_pages * getpagesize();
    size_t alloc_size[] = {buf_size, buf_size, getpagesize()};
    // Allocate a single page memory buffer
    size_t i = 0;
    for (i=0; i < 3; ++i) {
#ifdef ASE_REGION
        vai_afu_alloc_region(conn, (void **)&buf[i], 0, alloc_size[i]);
        buf_pa[i] = buf[i];
#else
        buf[i] = (volatile unsigned char *)vai_afu_malloc(conn, alloc_size[i]);
        buf_pa[i] = (uint64_t)buf[i];
#endif
        assert(NULL != buf[i]);
    }
    volatile struct status_cl *status_buf = (struct status_cl *) buf[2];

    // Set the low byte of the shared buffer to 0.  The FPGA will write
    // a non-zero value to it.
    for (i=0; i < buf_size; ++i) {
        buf[0][i] = i%(256);
    }

    int r;
    for (r=0; r < 2; ++r) {
        status_buf->completion = 0;
        status_buf->n_clk = 0;
        status_buf->n_read = 0;
        status_buf->n_write = 0;
        bzero((void*)buf[1], buf_size);
        assert(vai_afu_mmio_write(conn, MMIO_CSR_SOFT_RST, 0) == 0 &&
                "CSR_Soft_Reset afu failed");
        printf("afu csr_soft reseted\n");
        // Tell the accelerator the address of the buffer using cache line
        // addresses.  The accelerator will respond by writing to the buffer.
        assert(vai_afu_mmio_write(conn, MMIO_CSR_STATUS_ADDR, buf_pa[2]/CL(1)) == 0 &&
                "Write Status Addr failed");
        printf("status addr is %lX\n", buf_pa[2]);
        assert(vai_afu_mmio_write(conn, MMIO_CSR_SRC_ADDR, buf_pa[0]/CL(1)) == 0 &&
                "Write SRC Addr failed");
        printf("SRC addr is %lX\n", buf_pa[0]);
        assert(vai_afu_mmio_write(conn, MMIO_CSR_DST_ADDR, buf_pa[1]/CL(1)) == 0 &&
                "Write DST Addr failed");
        printf("DST addr is %lX\n", buf_pa[1]);
        assert(vai_afu_mmio_write(conn, MMIO_CSR_NUM_LINES, buf_size/CL(1)) == 0 &&
                "Write Num Lines failed");
        printf("NUM lines %zu, buf_size is %zu\n", buf_size/CL(1), buf_size);
        assert(vai_afu_mmio_write(conn, MMIO_CSR_WR_THRESHOLD, wr_threshold) == 0 &&
                "Write WR_THRESHOLD failed");
        printf("Wr threashold is %u\n", wr_threshold);
        assert(vai_afu_mmio_write(conn, MMIO_CSR_CTL, 1) == 0 &&
                "Write CSR CTL failed");
        printf("START!!!\n");
        struct debug_csr dc;
        // Spin, waiting for the value in memory to change to something non-zero.
#ifdef TIMESLICING
        uint64_t ts_state;
        while (!vai_afu_mmio_read(conn, MMIO_CSR_TS_STATE, &ts_state) && ts_state!=2UL)
#else
        while (0 == status_buf->completion)
#endif
        {
            if (!get_debug_csr(conn, &dc))
                print_csr(&dc);
            else {
                perror("get_debug_csr error");
                break;
            }
            usleep(500000);
            // A well-behaved program would use _mm_pause(), nanosleep() or
            // equivalent to save power here.
        };
        printf("Done: cycle is %lu, read is %u, write is %u\n",
                status_buf->n_clk, status_buf->n_read, status_buf->n_write);
        get_debug_csr(conn, &dc);
        print_csr(&dc);
        for (i=0; i < buf_size; ++i) {
            if (buf[0][i] != buf[1][i]) {
                goto error;
            }
        }
        goto correct;
    error:
        fprintf(stderr, "Wrong at %zu, get %u, should be %u\n", i, (char)(buf[1][i]), (char)(buf[0][i]));
        goto done;
    correct:
        fprintf(stdout, "Everything is fine!!!\n");
    }
done:
    // Done
    for (i=0; i < 3; ++i) {
        vai_afu_free(conn, buf[i]);
    }
    vai_afu_disconnect(conn);

    return 0;
}
