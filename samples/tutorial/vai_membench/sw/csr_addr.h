#ifndef CSR_ADDR_H
#include "vai_timeslicing.h"
#define CSR_ADDR_H
//------------------ RO -------------------------------
// placeholder: MMIO_CSR_MEM_BASE 16'h0
// placeholder: MMIO_CSR_LEN_MASK 16'h8
// placeholder: MMIO_CSR_READ_TOTAL 16'h10
// placeholder: MMIO_CSR_WRITE_TOTAL 16'h18
// placeholder: MMIO_CSR_PROPERTIES 16'h20
// how many read requests have been issued and served
#define MMIO_CSR_READ_CNT TSCSR_USR(0x28)
// how many write requests have been issued and served
#define MMIO_CSR_WRITE_CNT TSCSR_USR(0x30)
// how many cycles have passed since write 1 to MMIO_CSR_CTL
#define MMIO_CSR_CLK_CNT TSCSR_USR(0x38)
#define MMIO_CSR_STATE TSCSR_USR(0x40)
#define MMIO_CSR_REPORT_RECCNT TSCSR_USR(0x48)
#define MMIO_CSR_RDRSP_CNT TSCSR_USR(0x50)
#define MMIO_CSR_WRRSP_CNT TSCSR_USR(0x58)
//------------------ WO -------------------------------
// The base address
#define MMIO_CSR_MEM_BASE TSCSR_USR(0x0)
// All access will be masked by this:
// offset = rand() & len_mask; base_addr[offset] = xxx.
#define MMIO_CSR_LEN_MASK TSCSR_USR(0x8)
// how many read requests will be issued in total
#define MMIO_CSR_READ_TOTAL TSCSR_USR(0x10)
// how many write requests will be issued in total
#define MMIO_CSR_WRITE_TOTAL TSCSR_USR(0x18)
// properties
// Read VA: 0:1, Write VA: 2:3
// Read Cache Hint: 4:7, Write Cache Hint 8:11
// Access pattern: 12:12, 0: sequential 1: random
// Read Len: 14:13, 0: eCL_LEN_1 1: eCL_LEN_2 2: eCL_LEN_4
#define MMIO_CSR_PROPERTIES TSCSR_USR(0x20)
#define MMIO_CSR_RAND_SEED_0 TSCSR_USR(0x28)
#define MMIO_CSR_RAND_SEED_1 TSCSR_USR(0x30)
#define MMIO_CSR_RAND_SEED_2 TSCSR_USR(0x38)
#define MMIO_CSR_REPORT_ADDR TSCSR_USR(0x40)
#define MMIO_CSR_REC_FILTER TSCSR_USR(0x48)
#define MMIO_CSR_SEQ_START_OFFSET TSCSR_USR(0x50)
#endif
