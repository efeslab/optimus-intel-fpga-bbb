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

#include <stdlib.h>
#include <unistd.h>

#include <uuid/uuid.h>
#include <iostream>
#include <algorithm>

#include "opae_svc_wrapper.h"

using namespace std;


OPAE_SVC_WRAPPER::OPAE_SVC_WRAPPER(const char *accel_uuid) :
    vai_conn(NULL),
    mpf_handle(NULL),
    is_ok(false),
    is_simulated(false)
{
    fpga_result r;

    // Don't print verbose messages in ASE by default
    setenv("ASE_LOG", "0", 0);

    // Is the hardware simulated with ASE?
    is_simulated = probeForASE();

    // Connect to an available accelerator with the requested UUID
    r = findAndOpenAccel(accel_uuid);

    is_ok = (FPGA_OK == r);
}


OPAE_SVC_WRAPPER::~OPAE_SVC_WRAPPER()
{
    mpfDisconnect(mpf_handle);
    vai_afu_disconnect(vai_conn);
}


volatile void*
OPAE_SVC_WRAPPER::allocBuffer(size_t nBytes, uint64_t* ioAddress)
{
    fpga_result r;

    volatile void* va = vai_afu_malloc(vai_conn, nBytes);
    if (ioAddress)
        *ioAddress = (uint64_t)va;

    return va;
}

void
OPAE_SVC_WRAPPER::freeBuffer(void* va)
{
    vai_afu_free(vai_conn, va);
}

fpga_result
OPAE_SVC_WRAPPER::findAndOpenAccel(const char* accel_uuid)
{
    fpga_result r;
    uint8_t guid[16];
    uint8_t guid_wanted[16];

    vai_conn = vai_afu_connect();
    if (vai_conn == NULL)
        goto error_exit;

    r = vai_afu_mmio_read(vai_conn, 0x8, (uint64_t*)(guid));
    if (r != FPGA_OK)
        goto error_close;

    r = vai_afu_mmio_read(vai_conn, 0x10, (uint64_t*)(guid+8));
    if (r != FPGA_OK)
        goto error_close;

    for (int i=0; i<8; i++) {
        uint8_t tmp = guid[i];
        guid[i] = guid[15-i];
        guid[15-i] = tmp;
    }

    printf("%llx %llx\n", *(uint64_t*)guid, *(uint64_t*)(guid+8));
    printf("%s\n", accel_uuid);

    uuid_parse(accel_uuid, guid_wanted);
    printf("%llx %llx\n", *(uint64_t*)guid_wanted, *(uint64_t*)(guid_wanted+8));

    for (int i=0; i<16; i++) {
        if (guid[i] != guid_wanted[i])
            goto error_close;
    }

    // Connect to MPF
    r = mpfConnect(vai_conn, &mpf_handle, MPF_FLAG_DEBUG);
    if (FPGA_OK != r) goto error_close;

    return FPGA_OK;

error_close:
    vai_afu_disconnect(vai_conn);
error_exit:
    return r;
}


//
// Is the FPGA real or simulated with ASE?
//
bool
OPAE_SVC_WRAPPER::probeForASE()
{
    fpga_result r = FPGA_OK;
    return true;
}
