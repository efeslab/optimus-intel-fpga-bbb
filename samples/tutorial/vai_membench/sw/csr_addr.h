#ifndef CSR_ADDR_H
#define CSR_ADDR_H
//------------------ RO -------------------------------
//time slicing status 0 means idle, 1 means running, 2 means done
#define MMIO_CSR_TS_STATE 0x18
// placeholder: MMIO_CSR_MEM_BASE 16'h20
// placeholder: MMIO_CSR_LEN_MASK 16'h28
// placeholder: MMIO_CSR_READ_TOTAL 16'h30
// placeholder: MMIO_CSR_WRITE_TOTAL 16'h38
// placeholder: MMIO_CSR_PROPERTIES 16'h40
// how many read requests have been issued and served
#define MMIO_CSR_READ_CNT 0x48
// how many write requests have been issued and served
#define MMIO_CSR_WRITE_CNT 0x50
// how many cycles have passed since write 1 to MMIO_CSR_CTL
#define MMIO_CSR_CLK_CNT 0x58
#define MMIO_CSR_STATE 0x60
#define MMIO_CSR_REPORT_RECCNT 0x68
#define MMIO_CSR_RDRSP_CNT 0x70
#define MMIO_CSR_WRRSP_CNT 0x78
//------------------ WO -------------------------------
// write 1 to start the AFU
#define MMIO_CSR_CTL 0x018
// The base address
#define MMIO_CSR_MEM_BASE 0x20
// All access will be masked by this:
// offset = rand() & len_mask; base_addr[offset] = xxx.
#define MMIO_CSR_LEN_MASK 0x28
// how many read requests will be issued in total
#define MMIO_CSR_READ_TOTAL 0x30
// how many write requests will be issued in total
#define MMIO_CSR_WRITE_TOTAL 0x38
#define MMIO_CSR_RAND_SEED_0 0x48
#define MMIO_CSR_RAND_SEED_1 0x50
#define MMIO_CSR_RAND_SEED_2 0x58
#define MMIO_CSR_REPORT_ADDR 0x60
#define MMIO_CSR_REC_FILTER 0x68
// properties
// Read VA: 0:1, Write VA: 2:3
// Read Cache Hint: 4:7, Write Cache Hint 8:11
#define MMIO_CSR_PROPERTIES 0x40
#endif
