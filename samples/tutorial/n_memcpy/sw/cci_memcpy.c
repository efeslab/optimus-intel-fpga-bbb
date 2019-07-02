#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdatomic.h>
#include <time.h>

#include <uuid/uuid.h>
#include <opae/fpga.h>

#include "afu_json_info.h"

#define BUFFER_SIZE (8096)
#define USER_CSR_BASE  32

#define CACHELINE_BYTES 64
#define CL(x) ((x) * CACHELINE_BYTES)

void print_err(const char *s, fpga_result res)
{
    fprintf(stderr, "Error %s: %s\n", s, fpgaErrStr(res));
}

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

void mmio_write_64(fpga_handle afc_handle, uint64_t addr, uint64_t data, const char *reg_name)
{
    fpga_result res = fpgaWriteMMIO64(afc_handle, 0, addr, data);
    if (res != FPGA_OK)
    {
        print_err("mmio_write_64 failure", res);
        exit(1);
    }
    printf("MMIO Write to %s (Byte Offset=0x%lx) = %08lx\n", reg_name, addr, data);
}

int main()
{
    fpga_handle handle;
    volatile uint64_t *buf, *bufcpy;

    uint64_t size = BUFFER_SIZE;

    uint64_t wsid;
    uint64_t buf_pa, bufcpy_pa;

    handle = connect_to_accel(AFU_ACCEL_UUID);

    buf = alloc_buffer(handle, size * sizeof(uint64_t),  &wsid, &buf_pa);
    bufcpy = alloc_buffer(handle, size * sizeof(uint64_t), &wsid, &bufcpy_pa);

    assert(buf != NULL && bufcpy != NULL);

    for(size_t i = 0; i < size;++i){
        buf[i] = i + 1;
        bufcpy[i] = 0;
    }

    mmio_write_64(handle, 0x26*4, (uintptr_t)(size * sizeof(uint64_t)),     "BUF size");
    mmio_write_64(handle, 0x22*4, buf_pa / CL(1),      "BUF address");
    mmio_write_64(handle, 0x24*4, bufcpy_pa / CL(1),   "BUF CPY address");

    struct timespec tim2, tim = { 0, 250000000L };
    uint64_t count = 0;

    while(buf[size-1] != bufcpy[size-1])
    {
        nanosleep(&tim, &tim2);
        count += 1;

        if (count >= 24) {
            break;
        }
    }

    int equal = 1;
    for(size_t i = 0; i < size; ++i)
        if (buf[i] != bufcpy[i]) {
            printf("Not equal at index %lu\n", i);
            equal = 0;
            break;
        }


    if (equal)
        printf("Copied successfully\n");

    fpgaReleaseBuffer(handle, wsid);
    fpgaClose(handle);
    return 0;
}
