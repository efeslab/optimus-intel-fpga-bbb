#ifndef __VAI_TIMESLICING__
#define __VAI_TIMESLICING__
typedef enum { tsIDLE=0, tsRUNNING=1, tsFINISH=2, tsPAUSED=4} t_transaction_state;
typedef enum { tsctlSTART_NEW=1, tsctlSTART_RESUME=5, tsctlPAUSE=6} t_transaction_ctl;
// RO
#define MMIO_CSR_TRANSACTION_STATE 0x018
#define MMIO_CSR_STATE_SIZE_PG 0x020
// WO
#define MMIO_CSR_TRANSACTION_CTL 0x018
#define MMIO_CSR_SNAPSHOT_ADDR 0x028
#define MMIO_TSCSR_USR_BASE 0x030

#define TSCSR_USR(off) (MMIO_TSCSR_USR_BASE + off)
#endif // end of __VAI_TIMESLICING__
