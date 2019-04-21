#ifndef __VAI_TIMESLICING__
#define __VAI_TIMESLICING__
typedef enum { tsIDLE=0, tsRUNNING=1, tsFINISH=2, tsPAUSED=4} t_transaction_state;
typedef enum { tsctlSTART_NEW=1, tsctlSTART_RESUME=5, tsctlPAUSE=6} t_transaction_ctl;

#define MMIO_CSR_CNT_LIST_LENGTH 0
#define MMIO_CSR_CLK_CNT 1
#define MMIO_CSR_RESULT_ADDR 2
#define MMIO_CSR_START_ADDR 3
#define MMIO_CSR_PROPERTIES 4
#define MMIO_CSR_TRANSACTION_STATE 5
#define MMIO_CSR_STATE_SIZE_PG 6
#define MMIO_CSR_TRANSACTION_CTL 7
#define MMIO_CSR_SNAPSHOT_ADDR 8

#endif // end of __VAI_TIMESLICING__
