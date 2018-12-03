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
#include <uuid/uuid.h>
#include <string.h>

#include <opae/fpga.h>

// State from the AFU's JSON file, extracted using OPAE's afu_json_mgr script
#include "afu_json_info.h"
#include "csr_addr.h"

#define CACHELINE_BYTES 64
#define CL(x) ((x) * CACHELINE_BYTES)


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
    fpga_handle accel_handle;
    volatile unsigned char *buf[3]; // buf[0] is src, buf[1] is dst, buf[2] is status flag

    uint64_t wsid[3];
    uint64_t buf_pa[3];
	size_t buf_size = num_pages * getpagesize();
    // Find and connect to the accelerator
    accel_handle = connect_to_accel(AFU_ACCEL_UUID);
    // Allocate a single page memory buffer
	size_t i = 0;
	for (i=0; i < 2; ++i) {
    	buf[i] = (volatile char*)alloc_buffer(accel_handle, buf_size,
				&wsid[i], &buf_pa[i]);
		assert(NULL != buf[i]);
	}
	buf[2] = (volatile char*)alloc_buffer(accel_handle, getpagesize(),
				&wsid[2], &buf_pa[2]);
    assert(NULL != buf[2]);
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
		bzero(buf[1], buf_size);
		assert(fpgaWriteMMIO32(accel_handle, 0, MMIO_CSR_SOFT_RST, 0) == FPGA_OK &&
				"CSR_Soft_Reset afu failed");
		printf("afu csr_soft reseted\n");
		// Tell the accelerator the address of the buffer using cache line
		// addresses.  The accelerator will respond by writing to the buffer.
		assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_STATUS_ADDR, buf_pa[2]/CL(1)) == FPGA_OK &&
				"Write Status Addr failed");
		printf("status addr is %lX\n", buf_pa[2]);
		assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_SRC_ADDR, buf_pa[0]/CL(1)) == FPGA_OK &&
				"Write SRC Addr failed");
		printf("SRC addr is %lX\n", buf_pa[0]);
		assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_DST_ADDR, buf_pa[1]/CL(1)) == FPGA_OK &&
				"Write DST Addr failed");
		printf("DST addr is %lX\n", buf_pa[1]);
		assert(fpgaWriteMMIO32(accel_handle, 0, MMIO_CSR_NUM_LINES, buf_size/CL(1)) == FPGA_OK &&
				"Write Num Lines failed");
		printf("NUM lines %zu, buf_size is %zu\n", buf_size/CL(1), buf_size);
		assert(fpgaWriteMMIO32(accel_handle, 0, MMIO_CSR_WR_THRESHOLD, wr_threshold) == FPGA_OK &&
				"Write WR_THRESHOLD failed");
		printf("Wr threashold is %u\n", wr_threshold);
		assert(fpgaWriteMMIO32(accel_handle, 0, MMIO_CSR_CTL, 1) == FPGA_OK &&
				"Write CSR CTL failed");
		printf("START!!!\n");
		struct debug_csr dc;
		// Spin, waiting for the value in memory to change to something non-zero.
		while (0 == status_buf->completion)
		{
			fpga_result r;
			r = get_debug_csr(accel_handle, &dc);
			if (r != FPGA_OK)
				break;
			else
				print_csr(&dc);
			usleep(500000);
			// A well-behaved program would use _mm_pause(), nanosleep() or
			// equivalent to save power here.
		};
		printf("Done: cycle is %u, read is %u, write is %u\n",
				status_buf->n_clk, status_buf->n_read, status_buf->n_write);
		get_debug_csr(accel_handle, &dc);
		print_csr(&dc);
		for (i=0; i < buf_size; ++i) {
			if (buf[1][i] != i%(256)) {
				goto error;
			}
		}
		goto correct;
	error:
		fprintf(stderr, "Wrong at %zu, get %u\n", i, (char)(buf[1][i]));
		goto done;
	correct:
		fprintf(stdout, "Everything is fine!!!\n");
	}
done:
    // Done
	for (i=0; i < 3; ++i)
	    fpgaReleaseBuffer(accel_handle, wsid[i]);
    fpgaClose(accel_handle);

    return 0;
}
