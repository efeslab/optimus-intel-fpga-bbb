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
#include <unistd.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>

#ifdef ORIG_ASE
#include <uuid/uuid.h>
#include <opae/fpga.h>
#define CL(x) (x*64)
#else
#include <vai/vai.h>
#endif //ORIG_ASE
// State from the AFU's JSON file, extracted using OPAE's afu_json_mgr script
#include "afu_json_info.h"

//RO
#define MMIO_CSR_RD_CNT 0x060
#define MMIO_CSR_RD_RSP_CNT 0x068
#define MMIO_CSR_WR_CNT 0x028
#define MMIO_CSR_RESULT_CNT 0x030
#define MMIO_CSR_FILTER_CNT 0x038
//WO
#define MMIO_CSR_INPUT_ADDR 0x040
#define MMIO_CSR_INPUT_SIZE 0x048
#define MMIO_CSR_RESULT_CNT_ADDR 0x050
#define MMIO_CSR_OUTPUT_ADDR 0x058


void initBuffer(uint64_t * head,
                        uint64_t n_entries)
{
    uint64_t* p = 0;
    uint64_t v = 1;

    for (int i = 0; i < n_entries; i += 1)
    {
    	p= &head[i*8];
    	for (int l = 0; l< 8; l += 1)
    	{
    		p[l] = i+l;
    	}
    	//p[7] = 100;
    }
}

#ifdef ORIG_ASE
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
#endif // ORIG_ASE

int main(int argc, char *argv[])
{
	static uint64_t INPUT_LINE_CNT = 64;
    // Find and connect to the accelerator
#ifdef ORIG_ASE
	fpga_handle accel_handle;
	accel_handle = connect_to_accel(AFU_ACCEL_UUID);
#else
	struct vai_afu_conn *conn = vai_afu_connect();
#endif
    // Allocate a memory buffer for storing the result.  Unlike the hello
    // world examples, here we do not need the physical address of the
    // buffer.  The accelerator instantiates MPF's VTP and will use
    // virtual addresses.
	uint64_t result_bufpa;
    volatile uint64_t* result_buf;
#ifdef ORIG_ASE
	uint64_t result_wsid;
	result_buf = (volatile uint64_t*)alloc_buffer(accel_handle, getpagesize(), &result_wsid, &result_bufpa);
#elif defined(ASE_REGION)
	vai_afu_alloc_region(conn, (void**)&result_buf, 0, getpagesize());
	result_bufpa = (uint64_t) result_buf;
#else
	result_buf = (volatile uint64_t*)vai_afu_malloc(conn, getpagesize());
	result_bufpa = (uint64_t) result_buf;
#endif
    assert(NULL != result_buf);

	uint64_t input_bufpa;
	volatile uint64_t* input_buf;
#ifdef ORIG_ASE
	uint64_t input_wsid;
	input_buf = (volatile uint64_t*)alloc_buffer(accel_handle, getpagesize(), &input_wsid, &input_bufpa);
#elif defined(ASE_REGION)
	vai_afu_alloc_region(conn, (void**)&input_buf, 0, getpagesize());
	input_bufpa = (uint64_t) input_buf;
#else
	input_buf = (volatile uint64_t*)vai_afu_malloc(conn, getpagesize());
	input_bufpa = (uint64_t) input_buf;
#endif
	assert(NULL != input_buf);
	
	uint64_t result_cnt_bufpa;
	volatile uint64_t* result_cnt_buf;
#ifdef ORIG_ASE
	uint64_t result_cnt_wsid;
	result_cnt_buf = (volatile uint64_t*)alloc_buffer(accel_handle, getpagesize(), &result_cnt_wsid, &result_cnt_bufpa);
#elif defined(ASE_REGION)
	vai_afu_alloc_region(conn, (void**)&result_cnt_buf, 0, getpagesize());
	result_cnt_bufpa = (uint64_t) result_cnt_buf;
#else
	result_cnt_buf = (volatile uint64_t*)vai_afu_malloc(conn, getpagesize());
	result_cnt_bufpa = (uint64_t) result_cnt_buf;
#endif
	assert(NULL != result_cnt_buf);

	initBuffer(input_buf, INPUT_LINE_CNT);
	result_cnt_buf[0] = INPUT_LINE_CNT + 1;
    // Set the result buffer pointer
#ifdef ORIG_ASE
	assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_OUTPUT_ADDR, result_bufpa / CL(1)) == FPGA_OK &&
		  "write result addr failed");
	assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_INPUT_ADDR, input_bufpa / CL(1)) == FPGA_OK &&
		  "write input addr failed");
	assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_INPUT_SIZE, INPUT_LINE_CNT) == FPGA_OK &&
		  "write input size failed");
	assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_RESULT_CNT_ADDR, result_cnt_bufpa / CL(1)) == FPGA_OK &&
		  "write result cnt addr failed");
#else
	assert(vai_afu_mmio_write(conn, MMIO_CSR_OUTPUT_ADDR, result_bufpa / CL(1)) == 0);
	assert(vai_afu_mmio_write(conn, MMIO_CSR_INPUT_ADDR, input_bufpa / CL(1)) == 0);
	assert(vai_afu_mmio_write(conn, MMIO_CSR_INPUT_SIZE, INPUT_LINE_CNT) == 0);
	assert(vai_afu_mmio_write(conn, MMIO_CSR_RESULT_CNT_ADDR, result_cnt_bufpa/CL(1)) == 0);
#endif

    while (INPUT_LINE_CNT + 1 == result_cnt_buf[0])
    {
        usleep(500000);
    };

	printf("%lu\n", result_cnt_buf[0]);
	int i;
	for (i=0; i < result_cnt_buf[0]; ++i)
		printf("%d %lu %lu\n", i+1, result_buf[2*i], result_buf[2*i+1]);

    // Reads CSRs to get some statistics
	uint64_t read_cnt, response, write_cnt, result;
#ifdef ORIG_ASE
	assert(fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_RD_CNT, &read_cnt) == FPGA_OK);
	assert(fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_RD_RSP_CNT, &response) == FPGA_OK);
	assert(fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_WR_CNT, &write_cnt) == FPGA_OK);
	assert(fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_RESULT_CNT, &result) == FPGA_OK);
#else
	assert(vai_afu_mmio_read(conn, MMIO_CSR_RD_CNT, &read_cnt) == 0);
	assert(vai_afu_mmio_read(conn, MMIO_CSR_RD_RSP_CNT, &response) == 0);
	assert(vai_afu_mmio_read(conn, MMIO_CSR_WR_CNT, &write_cnt) == 0);
	assert(vai_afu_mmio_read(conn, MMIO_CSR_RESULT_CNT, &result) == 0);
#endif

	printf("# read: %lu\n# response: %lu\n# write: %lu\n# result: %lu\n",
			read_cnt, response, write_cnt, result);

    // All shared buffers are automatically released and the FPGA connection
    // is closed when their destructors are invoked here.
#ifdef ORIG_ASE
	fpgaReleaseBuffer(accel_handle, result_wsid);
	fpgaReleaseBuffer(accel_handle, input_wsid);
	fpgaReleaseBuffer(accel_handle, result_cnt_wsid);
	fpgaClose(accel_handle);
#elif defined(ASE_REGION)
	vai_afu_free_region(conn, result_buf);
	vai_afu_free_region(conn, input_buf);
	vai_afu_free_region(conn, result_cnt_buf);
	vai_afu_disconnect(conn);
#else
	vai_afu_free(conn, result_buf);
	vai_afu_free(conn, input_buf);
	vai_afu_free(conn, result_cnt_buf);
	vai_afu_disconnect(conn);
#endif
    return 0;
}
