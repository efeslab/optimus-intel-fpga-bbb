typedef enum logic [2:0] {
    tsIDLE = 3'h0,
    tsRUNNING = 3'h1,
    tsFINISH = 3'h2,
    tsPAUSED = 3'h4
} t_transaction_state;

typedef enum logic [2:0] {
    tsctlSTART_NEW = 3'h1,
    tsctlSTART_RESUME = 3'h5,
    tsctlPAUSE = 3'h6
} t_transaction_ctl;
// RO
parameter MMIO_CSR_TRANSACTION_STATE = 16'h018 >> 2;
parameter MMIO_CSR_STATE_SIZE_PG = 16'h020 >> 2;
// WO
parameter MMIO_CSR_TRANSACTION_CTL = 16'h018 >> 2;
parameter MMIO_CSR_SNAPSHOT_ADDR = 16'h028 >> 2;
// the MMIO addr where user CSRs start
parameter MMIO_TSCSR_USR_BASE = 16'h30;
`define TSCSR_USR(off) ((MMIO_TSCSR_USR_BASE+off) >> 2);
`define AFU_IMAGE_VAI_MAGIC 12'hbde;
