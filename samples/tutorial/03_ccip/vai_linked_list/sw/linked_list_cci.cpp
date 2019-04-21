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
#include <time.h>

#include <uuid/uuid.h>
#include <opae/fpga.h>

using namespace std;

#include "opae_svc_wrapper.h"
#include "csr_mgr.h"

using namespace opae::fpga::types;
using namespace opae::fpga::bbb::mpf::types;

#include "afu_json_info.h"
#include "csr_addr.h"
#include "report.h"
#include "utils.h"

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
    uint64_t v;
    uint64_t pad_next[6];
};

//
// Construct a linked list of type t_linked_list in a buffer starting at
// head.  Generated the list with n_entries, separating each entry by
// spacing_bytes.
//
// Both head and spacing_bytes must be cache-line aligned.
//
struct t_linked_list* initList(struct t_linked_list* head,
                        uint64_t n_entries)
{
    struct t_linked_list* p = head;
    uint64_t v = 1;
    uint64_t *shuffle = (uint64_t*)malloc(n_entries * sizeof(uint64_t));
    for (uint64_t i = 0; i < n_entries; ++i) shuffle[i] = i;
    for (int i = 1; i < n_entries; i += 1)
    {
        uint64_t next_shuffle_idx = i + (rand() % (n_entries - i));
        uint64_t tmp = shuffle[i];
        shuffle[i] = shuffle[next_shuffle_idx];
        shuffle[next_shuffle_idx] = tmp;
        struct t_linked_list* p_next = head + shuffle[i];
        p->v = v++;
        total += p->v;

        p->next = p_next;

        p = p_next;
    }
    p->v = v++;
    total += p->v;
    p->next = NULL;

    __sync_synchronize();
    return head;
}

struct t_result {
    uint64_t done;
    uint64_t result;
    uint64_t clk_cnt;
};

int main(int argc, char *argv[])
{
    OPAE_SVC_WRAPPER fpga(AFU_ACCEL_UUID);
    assert(fpga.isOk());
    CSR_MGR csrs(fpga);

    // randomize
    struct timespec tp;
    clock_gettime(CLOCK_MONOTONIC_RAW, &tp);
    srand(tp.tv_nsec);
    // parse command line
    uint64_t n_entries = 0;
    uint64_t totalsize = 0;
    uint64_t csr_properties = 0;
    if (argc < 3) {
        fprintf(stderr, "%s totalsize READ_VC\n", argv[0]);
        for (size_t i=0; i < ARRSIZE(pmap); ++i) {
            fprintf(stderr, "\t%s:", pmap[i].help_msg);
            for (size_t j=0; j < pmap[i].pnum; ++j) {
                fprintf(stderr, " %s", pmap[i].pes[j].name);
            }
            fputc('\n', stderr);
        }
        return -1;
    }
    else {
        int len = strlen(argv[1]);
        totalsize = atoll(argv[1]);
        switch (argv[1][len-1]) {
            case 'K':
            case 'k':
                totalsize *= 1024;
                break;
            case 'M':
            case 'm':
                totalsize *= 1024*1024;
                break;
            default:
                fprintf(stderr, "wrong units\n");
                return -1;
        }
        n_entries = totalsize / sizeof(struct t_linked_list);
        for (size_t i=2; i < argc; ++i) {
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



    fpga::types::shared_buffer::ptr_t result_buf_ptr;
    volatile struct t_result* result_buf;
    result_buf_ptr = fpga.allocBuffer(getpagesize());
    result_buf = reinterpret_cast<volatile struct t_result *>(result_buf_ptr->c_type());
    assert(NULL != result_buf);

    result_buf->done = 0;

    // Set the result buffer pointer
    csrs.writeCSR(MMIO_CSR_RESULT_ADDR, (uint64_t)result_buf / CL(1));

    fpga::types::shared_buffer::ptr_t list_buf_ptr;
    volatile char *list_buf;
    list_buf_ptr = fpga.allocBuffer(totalsize);
    list_buf = reinterpret_cast<volatile char *>(list_buf_ptr->c_type());
    assert(NULL != list_buf);

    // Initialize a linked list in the buffer
    initList((struct t_linked_list*)(list_buf), n_entries);

    // allocate pages for snapshot
    fpga::types::shared_buffer::ptr_t snpst_buf_ptr;
    volatile char *snpst_buf;
    uint64_t state_szpgs;
    state_szpgs = csrs.readCSR(MMIO_CSR_STATE_SIZE_PG);
    snpst_buf_ptr = fpga.allocBuffer(state_szpgs * getpagesize());
    snpst_buf = reinterpret_cast<volatile char *>(snpst_buf_ptr->c_type());
    csrs.writeCSR(MMIO_CSR_SNAPSHOT_ADDR, (uint64_t)snpst_buf / CL(1));

    // Start the FPGA, which is waiting for the list head in CSR 1.
    csrs.writeCSR(MMIO_CSR_PROPERTIES, csr_properties);
    csrs.writeCSR(MMIO_CSR_START_ADDR, (uint64_t)list_buf / CL(1));
    csrs.writeCSR(MMIO_CSR_TRANSACTION_CTL, tsctlSTART_NEW);

    // try pause
    struct debug_csr dc;
    while (1)
    {
        usleep(500000);
        assert(get_debug_csr(csrs, &dc) == 0);
        print_csr(&dc);
        if (result_buf->done) // if job finished, quit
            break;
    }

    // Hash is stored in result_buf[1]
    uint64_t r = result_buf->result;
    printf("Hash: %#lx, Soft: %#lx [%s]\n", r, total, (total==r)?"Correct":"ERROR");

    // Reads CSRs to get some statistics
    uint64_t cnt_list_length;
    cnt_list_length = csrs.readCSR(MMIO_CSR_CNT_LIST_LENGTH);

    printf("# List length: %lu\n", cnt_list_length);
    printf("# total clk_cnt: %lu\n", result_buf->clk_cnt);

    return 0;
}
