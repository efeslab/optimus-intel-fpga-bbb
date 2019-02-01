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

#include <uuid/uuid.h>
#include <opae/fpga.h>
// State from the AFU's JSON file, extracted using OPAE's afu_json_mgr script
#include "afu_json_info.h"

#define CACHELINE_BYTES 64
#define CL(x) ((x) * CACHELINE_BYTES)

//RO
#define MMIO_CSR_CNT_LIST_LENGTH 0x018
#define MMIO_CSR_CNT_DATA_ENTRIES 0x020
//WO
#define MMIO_CSR_RESULT_ADDR 0x028
#define MMIO_CSR_START_ADDR 0x030

uint64_t total = 0;
//
// A simple data structure for our example.  It contains 4 memory lines in
// which the last 3 lines hold values in the low word and the 1st line
// holds a pointer to the next entry in the list.  The pad fields are
// unused.
//
struct t_linked_list
{
    struct t_linked_list* next;
    uint64_t pad_next[7];

    uint64_t v0;
    uint64_t pad0[7];

    uint64_t v1;
    uint64_t pad1[7];

    uint64_t v2;
    uint64_t pad2[7];
};

//
// Construct a linked list of type t_linked_list in a buffer starting at
// head.  Generated the list with n_entries, separating each entry by
// spacing_bytes.
//
// Both head and spacing_bytes must be cache-line aligned.
//
struct t_linked_list* initList(struct t_linked_list* head,
                        uint64_t n_entries,
                        uint64_t spacing_bytes)
{
    struct t_linked_list* p = head;
    uint64_t v = 1;

    for (int i = 0; i < n_entries; i += 1)
    {
        p->v0 = v++;
        p->v1 = v++;
        p->v2 = v++;
		total += p->v0 + p->v1 + p->v2;

        struct t_linked_list* p_next = (struct t_linked_list*)((char*)p + spacing_bytes);
        p->next = (i+1 < n_entries) ? p_next : NULL;

        p = p_next;
    }

	__sync_synchronize();
    return head;
}

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

struct t_result {
	uint64_t done;
	uint64_t result;
	uint64_t clk_cnt;
};

int main(int argc, char *argv[])
{
	// parse command line
	uint64_t n_entries = 0;
	uint64_t unitsize = 0;
	if (argc < 3) {
		fprintf(stderr, "%s length unitsize\n", argv[0]);
		return -1;
	}
	else {
		int len = strlen(argv[2]);
		n_entries = atoi(argv[1]);
		unitsize = atoi(argv[2]);
		switch (argv[2][len-1]) {
			case 'K':
			case 'k':
				unitsize *= 1024;
				break;
			case 'M':
			case 'm':
				unitsize *= 1024*1024;
				break;
			default:
				fprintf(stderr, "wrong units\n");
				return -1;
		}
		assert(sizeof(struct t_linked_list) <= unitsize);
	}
    // Find and connect to the accelerator
	fpga_handle accel_handle;
	uint64_t result_wsid;
	accel_handle = connect_to_accel(AFU_ACCEL_UUID);
    // Allocate a memory buffer for storing the result.  Unlike the hello
    // world examples, here we do not need the physical address of the
    // buffer.  The accelerator instantiates MPF's VTP and will use
    // virtual addresses.
	uint64_t result_bufpa;
    volatile struct t_result* result_buf;
	result_buf = (volatile struct t_result*)alloc_buffer(accel_handle, getpagesize(), &result_wsid, &result_bufpa);
    assert(NULL != result_buf);

    // Set the low word of the shared buffer to 0.  The FPGA will write
    // a non-zero value to it.
    result_buf->done = 0;

    // Set the result buffer pointer
	assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_RESULT_ADDR, result_bufpa / CL(1)) == FPGA_OK &&
		  "write result addr failed");

    // Allocate a 16MB buffer and share it with the FPGA.  Because the FPGA
    // is using VTP we can allocate a virtually contiguous region.
    // OPAE_SVC_WRAPPER detects the presence of VTP and uses it for memory
    // allocation instead of calling OPAE directly.  The buffer will
    // be composed of physically discontiguous pages.  VTP will construct
    // a private TLB to map virtual addresses from this process to FPGA-side
    // physical addresses.
	uint64_t list_wsid;
	uint64_t list_bufpa;
    volatile char * list_buf;
	list_buf = (volatile char*)alloc_buffer(accel_handle, unitsize * n_entries + CL(4), &list_wsid, &list_bufpa);
	list_buf = (volatile char*)(((uint64_t)list_buf + (CL(4) - 1)) & (~0xffL));
	list_bufpa = (list_bufpa + (CL(4) - 1)) & (~0xffL);
    assert(NULL != list_buf);

    // Initialize a linked list in the buffer
    initList((struct t_linked_list*)(list_buf), n_entries, unitsize);

    // Start the FPGA, which is waiting for the list head in CSR 1.
	assert(fpgaWriteMMIO64(accel_handle, 0, MMIO_CSR_START_ADDR, list_bufpa / CL(1)) == FPGA_OK &&
			"write list addr failed");

    while (0 == result_buf->done)
    {
        usleep(500000);
    };

    // Hash is stored in result_buf[1]
    uint64_t r = result_buf->result;
	printf("Hash: %#lx, Soft: %#lx [%s]\n", r, total, (total==r)?"Correct":"ERROR");

    // Reads CSRs to get some statistics
	uint64_t cnt_list_length;
	uint64_t cnt_data_entries;
	assert(fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_CNT_LIST_LENGTH, &cnt_list_length) == FPGA_OK);
	assert(fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_CNT_DATA_ENTRIES, &cnt_data_entries) == FPGA_OK);

    printf("# List length: %lu,\n# Linked list data entries read: %lu\n", cnt_list_length, cnt_data_entries);

    // All shared buffers are automatically released and the FPGA connection
    // is closed when their destructors are invoked here.
	fpgaReleaseBuffer(accel_handle, result_wsid);
	fpgaReleaseBuffer(accel_handle, list_wsid);
	fpgaClose(accel_handle);
    return 0;
}
