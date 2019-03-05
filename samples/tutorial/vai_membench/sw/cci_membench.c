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

#include <opae/fpga.h>
#include "afu_json_info.h"
#include "csr_addr.h"
#include "report.h"
#include "utils.h"

#define CACHELINE_BYTES 64
#define CL(x) ((x) * CACHELINE_BYTES)
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

#define NUM_BUF 2
int main(int argc, char *argv[])
{
    fpga_handle accel_handle;
    uint32_t num_pages;
    uint64_t read_total;
    uint64_t write_total;
    uint64_t csr_properties = 0;
    srand(time(NULL));
    if (argc < 8) {
        printf("Usage: %s num_pages read_total(unit pages) write_total(unit pages) Properties(Channelx2 Cache_Hintx2)\n", argv[0]);
        printf("\tChannel properties:");
        for (size_t i=0; i < ARRSIZE(vc_map); ++i) {
            printf(" %s", vc_map[i].name);
        }
        putchar('\n');
        printf("\tRead Cache Hint properties:");
        for (size_t i=0; i < ARRSIZE(rd_ch_map); ++i) {
            printf(" %s", rd_ch_map[i].name);
        }
        putchar('\n');
        printf("\tWrite Cache Hint properties:");
        for (size_t i=0; i < ARRSIZE(wr_ch_map); ++i) {
            printf(" %s", wr_ch_map[i].name);
        }
        putchar('\n');
        return -1;
    }
    else {
        num_pages = atoi(argv[1]);
        read_total = atoll(argv[2]) * getpagesize() / CL(1);
        write_total = atoll(argv[3]) * getpagesize() / CL(1);
        // read properties from command line
        uint64_t vc_property = 0;
        uint64_t rd_ch_property = 0;
        uint64_t wr_ch_property = 0;
        property_entry_t *property_map[] = {vc_map, rd_ch_map, wr_ch_map};
        size_t entries_num[] = {ARRSIZE(vc_map), ARRSIZE(rd_ch_map), ARRSIZE(wr_ch_map)};
        uint64_t *properties[] = {&vc_property, &rd_ch_property, &wr_ch_property};
        for (size_t i=4; i < argc; ++i) {
            for (size_t j=0; j < ARRSIZE(property_map); ++j) {
                for (size_t k=0; k < entries_num[j]; ++k) {
                    if (strcmp(argv[i], property_map[j][k].name) == 0) {
                        *(properties[j]) |= property_map[j][k].value;
                        goto found_prop;
                    }
                }
            }
found_prop:
            ;
        }
        csr_properties = vc_property | rd_ch_property | wr_ch_property;
    }
    // buf[0] is base_addr, buf[1] is status
    volatile unsigned char *buf[NUM_BUF];
    uint64_t buf_pa[NUM_BUF];
    uint64_t wsid[NUM_BUF];
    size_t buf_size = num_pages * getpagesize();
    uint64_t len_mask = (buf_size/CL(1)) - 1; // access unit in AFU is cache line
    size_t alloc_size[] = {buf_size, getpagesize()};
    accel_handle = connect_to_accel(AFU_ACCEL_UUID);
    // Allocate a single page memory buffer
    size_t i = 0;
    for (i=0; i < NUM_BUF; ++i) {
        buf[i] = alloc_buffer(accel_handle, alloc_size[i], &wsid[i], &buf_pa[i]);
        assert(NULL != buf[i]);
    }
    volatile struct status_cl *status_buf = (struct status_cl *) buf[1];
    volatile report_t *report_buf = (report_t *)(buf[1] + CL(1));

    // reset to uncompleted
    status_buf->completion = 0;
    // Tell the accelerator the address of the buffer using cache line
    // addresses.  The accelerator will respond by writing to the buffer.
    assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_REPORT_ADDR, buf_pa[1]/CL(1)) == FPGA_OK &&
            "Write Status Addr failed");
    printf("status addr is %lX\n", buf_pa[1]);
    assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_MEM_BASE, buf_pa[0]/CL(1)) == FPGA_OK &&
            "Write MEM BASE failed");
    printf("MEM BASE is %lX\n", buf_pa[0]);
    assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_LEN_MASK, len_mask) == FPGA_OK &&
            "Write LEN MASK failed");
    printf("%zu Cache lines , buf_size is %zu, len mask %lx\n", buf_size/CL(1), buf_size, len_mask);
    assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_READ_TOTAL, read_total) == FPGA_OK &&
            "Write READ_TOTAL failed");
    assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_WRITE_TOTAL, write_total) == FPGA_OK &&
            "Write WRITE_TOTAL failed");
    printf("Read total is %lu, Write total is %lu\n", read_total, write_total);
    //TODO initialize RANDOM SEED AND PROPERTIES
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
    printf("PROPERTIES: %s %s %s %s\n",
            GET_RD_VC_N(csr_properties), GET_WR_VC_N(csr_properties),
            GET_RD_CH_NAME(csr_properties), GET_WR_CH_NAME(csr_properties));
    assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_CTL, 1) == FPGA_OK &&
            "Write CSR CTL failed");
    printf("START!!!\n");
    struct debug_csr dc;
    // Spin, waiting for the value in memory to change to something non-zero.
#ifdef TIMESLICING
    uint64_t ts_state;
    while ((fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_TS_STATE, &ts_state) == FPGA_OK)
            && ts_state!=2UL)
#else
        while (0 == status_buf->completion)
#endif
        {
            if (!get_debug_csr(accel_handle, &dc))
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
    get_debug_csr(accel_handle, &dc);
    print_csr(&dc);
    uint32_t lat_total = 0;;
    uint16_t lat_max = 0;
    uint16_t lat_min = 0xffff;
    for (size_t i=0; i < RECORD_NUM; ++i) {
        uint16_t r = report_buf->lat[i];
        uint16_t lat = r & RECORD_LAT_MASK;
        printf(" %s: lat %u\n", (r&RECORD_RW_MASK)?"WR":"RD", lat);
        if (lat_max < lat) lat_max = lat;
        if (lat_min > lat) lat_min = lat;
        lat_total += lat;
    }
    printf("lat max: %u, min %u, avg %f\n", lat_max, lat_min, (double)lat_total/RECORD_NUM);
    // Done
    for (i=0; i < NUM_BUF; ++i) {
        fpgaReleaseBuffer(accel_handle, wsid[i]);
    }
    fpgaClose(accel_handle);

    return 0;
}
