#ifndef __CSR_ADDR_H__
#define __CSR_ADDR_H__
#include "vai_timeslicing.h"
// RO
#define MMIO_CSR_CNT_LIST_LENGTH TSCSR_USR(0x0)
#define MMIO_CSR_CLK_CNT TSCSR_USR(0x8)
// WO
#define MMIO_CSR_RESULT_ADDR TSCSR_USR(0x18)
#define MMIO_CSR_START_ADDR TSCSR_USR(0x20)
// RW
#define MMIO_CSR_PROPERTIES TSCSR_USR(0x28)
#endif // end of __CSR_ADDR_H__
