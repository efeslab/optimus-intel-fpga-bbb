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
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <assert.h>
#include <string.h>
#include <uuid/uuid.h>
#include <time.h>

#include <string>
#include <atomic>

using namespace std;

#include "opae_svc_wrapper.h"
#include "csr_mgr.h"

using namespace opae::fpga::types;
using namespace opae::fpga::bbb::mpf::types;

#include "afu_json_info.h"
#include "report.h"
#include "csr_addr.h"
#include "utils.h"

#define CACHELINE_BYTES 64
#define CL(x) ((x) * CACHELINE_BYTES)
#define RAND64 ((uint64_t)(rand()) | ((uint64_t)(rand()) << 32))

typedef enum {DATABUF=0,STATBUF,NUM_BUF} buf_t;
size_t cmdarg_getbytes(const char *arg) {
    size_t l = strlen(arg);
    uint64_t n = atoll(arg);
    switch (arg[l - 1]) {
        default:
        case 'p':
        case 'P': // unit is page
            return n * getpagesize();
        case 'c':
        case 'C': // unit is cache line
            return CL(n);
    }
}

int main(int argc, char *argv[])
{
    OPAE_SVC_WRAPPER fpga(AFU_ACCEL_UUID);
    assert(fpga.isOk());
    CSR_MGR csrs(fpga);

    uint64_t buf_size;
    uint64_t read_total;
    uint64_t write_total;
    uint64_t csr_properties = 0;

    srand(time(NULL));

    if (argc < 10) {
        printf("Usage: %s num_pages([P]age | [C]acheline) read_total([P | C]) write_total([P | C]) Properties(Channelx2 Cache_Hintx2 Access_Pattern Read_Length)\n", argv[0]);
        for (size_t i=0; i < ARRSIZE(pmap); ++i) {
            printf("\t%s:", pmap[i].help_msg);
            for (size_t j=0; j < pmap[i].pnum; ++j) {
                printf(" %s", pmap[i].pes[j].name);
            }
            putchar('\n');
        }
        return -1;
    }
    else {
        buf_size = cmdarg_getbytes(argv[1]);
        read_total = cmdarg_getbytes(argv[2]) / CL(1);
        write_total = cmdarg_getbytes(argv[3]) / CL(1);
        // read properties from command line
        for (size_t i=4; i < argc; ++i) {
            for (size_t j=0; j < ARRSIZE(pmap); ++j) {
                for (size_t k=0; k < pmap[j].pnum; ++k) {
                    if (strcmp(argv[i], pmap[j].pes[k].name) == 0) {
                        csr_properties |= pmap[j].pes[k].value;
                        goto found_prop;
                    }
                }
            }
found_prop:
            ;
        }
    }
    // buf[0] is base_addr, buf[1] is status
    fpga::types::shared_buffer::ptr_t buf_ptr[NUM_BUF];
    volatile unsigned char *buf[NUM_BUF];
    uint64_t wsid[NUM_BUF];
    uint64_t len_mask = (buf_size/CL(1)) - 1; // access unit in AFU is cache line
    assert(((buf_size % getpagesize()) == 0 ) && ("buf_size should be page aligned"));

    size_t alloc_size[NUM_BUF]; {
        alloc_size[DATABUF] = buf_size + getpagesize();
        alloc_size[STATBUF] = getpagesize();
    }
    size_t i = 0;
    for (i=0; i < NUM_BUF; ++i) {
        buf_ptr[i] = fpga.allocBuffer(alloc_size[i]);
        buf[i] = reinterpret_cast<volatile unsigned char *>(buf_ptr[i]->c_type());
        assert(NULL != buf[i]);
    }
    // clean status buf and report buf
    memset((void*)buf[STATBUF], 0, alloc_size[STATBUF]);
    volatile struct status_cl *status_buf = (struct status_cl *) buf[STATBUF];
    volatile report_t *report_buf = (report_t *)(buf[STATBUF] + CL(1));

    // reset to uncompleted
    status_buf->completion = 0;
    // Tell the accelerator the address of the buffer using cache line
    // addresses.  The accelerator will respond by writing to the buffer.
    csrs.writeCSR(MMIO_CSR_STATUS_ADDR, (uint64_t)buf[STATBUF]/CL(1));
    printf("status addr is %lX\n", buf[STATBUF]);

    uint64_t databuf = (((uint64_t)buf[DATABUF] & (~0xfff)) + 0x1000);
    csrs.writeCSR(MMIO_CSR_MEM_BASE, databuf/CL(1));

    printf("MEM BASE is %lX\n", databuf);
    csrs.writeCSR(MMIO_CSR_LEN_MASK, len_mask);

    printf("%zu Cache lines , buf_size is %zu, len mask %lx\n", buf_size/CL(1), buf_size, len_mask);
    csrs.writeCSR(MMIO_CSR_READ_TOTAL, read_total);
    csrs.writeCSR(MMIO_CSR_WRITE_TOTAL, write_total);
    printf("Read total is %lu, Write total is %lu\n", read_total, write_total);

    //initialize RANDOM SEED AND PROPERTIES
    uint64_t rand_seed[3] = {RAND64, RAND64, RAND64};
    csrs.writeCSR(MMIO_CSR_RAND_SEED_0, rand_seed[0]);
    csrs.writeCSR(MMIO_CSR_RAND_SEED_1, rand_seed[1]);
    csrs.writeCSR(MMIO_CSR_RAND_SEED_2, rand_seed[2]);

    printf("RAND SEED \n\t%0lx\n\t%0lx\n\t%0lx\n", rand_seed[0], rand_seed[1], rand_seed[2]); 
    csrs.writeCSR(MMIO_CSR_REC_FILTER, 0);
    csrs.writeCSR(MMIO_CSR_PROPERTIES, csr_properties);
    printf("PROPERTIES: %s %s %s %s %s %s\n",
            GET_RD_VC_N(csr_properties), GET_WR_VC_N(csr_properties),
            GET_RD_CH_NAME(csr_properties), GET_WR_CH_NAME(csr_properties),
            GET_ACCESS_NAME(csr_properties), GET_RD_LEN_NAME(csr_properties));

    csrs.writeCSR(MMIO_CSR_SEQ_START_OFFSET, 32);
    csrs.writeCSR(MMIO_CSR_CTL, 1);

    printf("START!!!\n");

    struct debug_csr dc;
    // Spin, waiting for the value in memory to change to something non-zero.
#ifdef TIMESLICING
    while (csrs.readCSR(MMIO_CSR_TS_STATE) != 2UL)
#else
    while (0 == status_buf->completion)
#endif
        {
            if (!get_debug_csr(csrs, &dc))
                print_csr(&dc);
            else {
                perror("get_debug_csr error");
                break;
            }
            usleep(500000);
            // A well-behaved program would use _mm_pause(), nanosleep() or
            // equivalent to save power here.
        };
    printf("Done: cycle is %lu\n",
            status_buf->n_clk);
    get_debug_csr(csrs, &dc);
    print_csr(&dc);
    uint32_t lat_total = 0;;
    uint16_t lat_max = 0;
    uint16_t lat_min = 0xffff;
    printf("%lu lat recorded\n", status_buf->reccnt);
    for (size_t i=0; i < status_buf->reccnt; ++i) {
        uint16_t r = report_buf->lat[i];
        uint16_t lat = r & RECORD_LAT_MASK;
        printf(" %s: lat %u\n", (r&RECORD_RW_MASK)?"WR":"RD", lat);
        if (lat_max < lat) lat_max = lat;
        if (lat_min > lat) lat_min = lat;
        lat_total += lat;
    }
    printf("lat max: %u, min %u, avg %f\n", lat_max, lat_min, (double)lat_total/status_buf->reccnt);
    double elapsed_sec = (double)status_buf->n_clk / 400 / 1000000;
    printf("RD thr: %f MB/s\n", (double)(CL(read_total)) / 1024 / 1024 / elapsed_sec);
    printf("WR thr: %f MB/s\n", (double)(CL(write_total)) / 1024 / 1024 / elapsed_sec);

    return 0;
}
