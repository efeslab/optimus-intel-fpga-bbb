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
#include <uuid/uuid.h>
#include <time.h>

#include "afu_json_info.h"
#ifndef ORIG_ASE
#include <vai/fpga.h>
#include <vai/wrapper.h>
#else
#include <opae/fpga.h>
#endif
#include "csr_addr.h"
#include "report.h"
#include "utils.h"

#define RAND64 ((uint64_t)(rand()) | ((uint64_t)(rand()) << 32))

//
// Search for an accelerator matching the requested UUID and connect to it.
//
static fpga_handle connect_to_accel(const char *accel_uuid)
{
    fpga_properties filter = NULL;
    fpga_guid guid;
    fpga_token accel_token;
    uint32_t num_matches;
    fpga_handle accel_handle;
    fpga_result r;

    // Don't print verbose messages in ASE by default
    setenv("ASE_LOG", "0", 0);

    // Set up a filter that will search for an accelerator
    fpgaGetProperties(NULL, &filter);
    fpgaPropertiesSetObjectType(filter, FPGA_ACCELERATOR);

    // Add the desired UUID to the filter
    uuid_parse(accel_uuid, guid);
    fpgaPropertiesSetGUID(filter, guid);

    // Do the search across the available FPGA contexts
    num_matches = 1;
    fpgaEnumerate(&filter, 1, &accel_token, 1, &num_matches);

    // Not needed anymore
    fpgaDestroyProperties(&filter);

    if (num_matches < 1)
    {
        fprintf(stderr, "Accelerator %s not found!\n", accel_uuid);
        return 0;
    }

    // Open accelerator
    r = fpgaOpen(accel_token, &accel_handle, 0);
    assert(FPGA_OK == r);

    // Done with token
    fpgaDestroyToken(&accel_token);

    return accel_handle;
}


//
// Allocate a buffer in I/O memory, shared with the FPGA.
//
static volatile void* alloc_buffer(fpga_handle accel_handle,
                                   ssize_t size,
                                   uint64_t *wsid,
                                   uint64_t *io_addr)
{
    fpga_result r;
    volatile void* buf;

    r = fpgaPrepareBuffer(accel_handle, size, (void*)&buf, wsid, 0);
    if (FPGA_OK != r) return NULL;

    // Get the physical address of the buffer in the accelerator
    r = fpgaGetIOAddress(accel_handle, *wsid, io_addr);
    assert(FPGA_OK == r);

    return buf;
}

typedef enum {DATABUF=0,STATBUF,SNAPSHOT_BUF,NUM_BUF} buf_t;
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
    fpga_handle accel_handle;
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
    volatile unsigned char *buf[NUM_BUF];
    uint64_t buf_pa[NUM_BUF];
    uint64_t wsid[NUM_BUF];
    uint64_t len_mask = (buf_size/CL(1)) - 1; // access unit in AFU is cache line
    //assert(((buf_size % getpagesize()) == 0 ) && ("buf_size should be page aligned"));
    size_t alloc_size[NUM_BUF]; {
        alloc_size[DATABUF] = buf_size + getpagesize();
        alloc_size[STATBUF] = getpagesize();
        alloc_size[SNAPSHOT_BUF] = getpagesize();
    }
    accel_handle = connect_to_accel(AFU_ACCEL_UUID);
    size_t i = 0;
    for (i=0; i < NUM_BUF; ++i) {
        buf[i] = alloc_buffer(accel_handle, alloc_size[i], &wsid[i], &buf_pa[i]);
        assert(NULL != buf[i]);
    }
    // clean status buf and report buf
    memset(buf[STATBUF], 0, alloc_size[STATBUF]);
    volatile struct status_cl *status_buf = (struct status_cl *) buf[STATBUF];
    volatile report_t *report_buf = (report_t *)(buf[STATBUF] + CL(1));
    t_transaction_ctl start = tsctlSTART_NEW;
    while(1) { //preemption loop start
        // reset to uncompleted
        status_buf->completion = 0;
        // Tell the accelerator the address of the buffer using cache line
        // addresses.  The accelerator will respond by writing to the buffer.
        uint64_t databuf = ((buf_pa[DATABUF] & (~0xfff)) + 0x1000);
        assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_REPORT_ADDR, buf_pa[STATBUF]/CL(1)) == FPGA_OK &&
                "Write Status Addr failed");
        printf("status addr is %lX\n", buf_pa[STATBUF]);
        assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_MEM_BASE, databuf/CL(1)) == FPGA_OK &&
                "Write MEM BASE failed");
        printf("MEM BASE is %lX\n", databuf);
        assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_LEN_MASK, len_mask) == FPGA_OK &&
                "Write LEN MASK failed");
        printf("%zu Cache lines , buf_size is %zu, len mask %lx\n", buf_size/CL(1), buf_size, len_mask);
        assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_READ_TOTAL, read_total) == FPGA_OK &&
                "Write READ_TOTAL failed");
        assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_WRITE_TOTAL, write_total) == FPGA_OK &&
                "Write WRITE_TOTAL failed");
        printf("Read total is %lu, Write total is %lu\n", read_total, write_total);
        //initialize RANDOM SEED AND PROPERTIES
        uint64_t rand_seed[3] = {RAND64, RAND64, RAND64};
        assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_RAND_SEED_0, rand_seed[0]) == FPGA_OK &&
                "Write RAND_SEED_0 failed");
        assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_RAND_SEED_1, rand_seed[1]) == FPGA_OK &&
                "Write RAND_SEED_1 failed");
        assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_RAND_SEED_2, rand_seed[2]) == FPGA_OK &&
                "Write RAND_SEED_2 failed");
        printf("RAND SEED \n\t%0lx\n\t%0lx\n\t%0lx\n", rand_seed[0], rand_seed[1], rand_seed[2]); 
        assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_REC_FILTER, 0) == FPGA_OK &&
                "Write REC_FILTER failed");
        assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_PROPERTIES, csr_properties) == FPGA_OK &&
                "Write PROPERTIES failed");
        printf("PROPERTIES: %s %s %s %s %s %s\n",
                GET_RD_VC_N(csr_properties), GET_WR_VC_N(csr_properties),
                GET_RD_CH_NAME(csr_properties), GET_WR_CH_NAME(csr_properties),
                GET_ACCESS_NAME(csr_properties), GET_RD_LEN_NAME(csr_properties));
        // FIXME set seq start offset according to VMID
        assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_SEQ_START_OFFSET, 32) == FPGA_OK &&
                "Write SEQ_START_OFFSET failed");
        assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_SNAPSHOT_ADDR, buf_pa[SNAPSHOT_BUF]/CL(1)) == FPGA_OK &&
                "Write snapshot addr failed");
        assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_TRANSACTION_CTL, start) == FPGA_OK &&
                "Write CSR CTL failed");
        printf("START!!!\n");
        struct debug_csr dc;
sleep:
        usleep(500000);
        if (!get_debug_csr(accel_handle, &dc))
            print_csr(&dc);
        else {
            perror("get_debug_csr error");
            break;
        }
        if (status_buf->completion)
            break;
#ifndef NO_PREEMPTION
        uint64_t tsstate;
#ifdef SIMULTAION
        assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_TRANSACTION_CTL, tsctlPAUSE) == 0);
#endif
        while (1) {
            assert(fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_TRANSACTION_STATE, &tsstate) == FPGA_OK);
            printf("state while waiting for pause: %ld\n", tsstate);
            if (!get_debug_csr(accel_handle, &dc))
                print_csr(&dc);
            if (tsstate == tsPAUSED)
                break;
            if (tsstate == tsFINISH)
                goto sleep;
            usleep(500000);
        }
        assert(fpgaReset(accel_handle) == FPGA_OK);
        usleep(5000);
        start = tsctlSTART_RESUME;
#else
        goto sleep;
#endif
    }
    struct debug_csr dc;
    printf("Done: cycle is %lu\n",
            status_buf->n_clk);
    get_debug_csr(accel_handle, &dc);
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
    // Done
    for (i=0; i < NUM_BUF; ++i) {
        fpgaReleaseBuffer(accel_handle, wsid[i]);
    }
    fpgaClose(accel_handle);

    return 0;
}
