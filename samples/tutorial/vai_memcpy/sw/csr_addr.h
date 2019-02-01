#ifndef CSR_ADDR_H
#define CSR_ADDR_H
//RO
//time slicing status 0 means idle, 1 means running, 2 means done
#define MMIO_CSR_TS_STATE 0x018
#define MMIO_CSR_MEM_READ_IDX 0x020
#define MMIO_CSR_WRITE_REQ_CNT 0x028
#define MMIO_CSR_WRITE_RESP_CNT 0x030
#define MMIO_CSR_STATE 0x038
#define MMIO_CSR_CLK_CNT 0x040
#define MMIO_CSR_WRITE_FULL_CNT 0x048
//WO
#define MMIO_CSR_CTL 0x018
#define MMIO_CSR_WR_THRESHOLD 0x020
#define MMIO_CSR_SOFT_RST 0x028
#define MMIO_CSR_STATUS_ADDR 0x30
#define MMIO_CSR_SRC_ADDR 0x038
#define MMIO_CSR_DST_ADDR 0x040
#define MMIO_CSR_NUM_LINES 0x048
struct debug_csr {
    uint64_t mem_read_idx;
    uint64_t write_req_cnt;
    uint64_t write_resp_cnt;
    uint64_t write_full_cnt;
    uint64_t state;
    uint64_t clk_cnt;
};

// return value: 0 means ok, non-zero means something is wrong
int get_debug_csr(fpga_handle *accel_handle, struct debug_csr *dbgcsr) {
    return (fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_MEM_READ_IDX, &dbgcsr->mem_read_idx) ||
            fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_WRITE_REQ_CNT, &dbgcsr->write_req_cnt) ||
            fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_WRITE_RESP_CNT, &dbgcsr->write_resp_cnt) ||
            fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_WRITE_FULL_CNT, &dbgcsr->write_full_cnt) ||
            fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_STATE, &dbgcsr->state) ||
            fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_CLK_CNT, &dbgcsr->clk_cnt));
}
void print_csr(struct debug_csr *dbgcsr) {
    printf("mem_read_idx %lu, write_req_cnt %lu, write_resp_cnt %lu, write_full_cnt %lu, state %#lx, clk_cnt %lu\n", dbgcsr->mem_read_idx, dbgcsr->write_req_cnt, dbgcsr->write_resp_cnt, dbgcsr->write_full_cnt, dbgcsr->state, dbgcsr->clk_cnt);
}
#endif
