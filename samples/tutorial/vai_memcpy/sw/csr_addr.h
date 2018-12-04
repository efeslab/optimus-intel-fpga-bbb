#ifndef CSR_ADDR_H
#define CSR_ADDR_H
//RW
#define MMIO_CSR_STATUS_ADDR 0x18
#define MMIO_CSR_SRC_ADDR 0x020
#define MMIO_CSR_DST_ADDR 0x028
#define MMIO_CSR_NUM_LINES 0x030
//RO
#define MMIO_CSR_MEM_READ_IDX 0x038
#define MMIO_CSR_WRITE_REQ_CNT 0x040
#define MMIO_CSR_WRITE_RESP_CNT 0x048
#define MMIO_CSR_STATE 0x050
#define MMIO_CSR_CLK_CNT 0x058
#define MMIO_CSR_WRITE_FULL_CNT 0x060
//WO
#define MMIO_CSR_CTL 0x070
#define MMIO_CSR_WR_THRESHOLD 0x078
#define MMIO_CSR_SOFT_RST 0x080
struct debug_csr {
	uint32_t num_lines;
	uint32_t mem_read_idx;
	uint32_t write_req_cnt;
	uint32_t write_resp_cnt;
	uint32_t write_full_cnt;
	uint32_t state;
	uint64_t clk_cnt;
};
fpga_result get_debug_csr(fpga_handle handle, struct debug_csr *dbgcsr) {
	fpga_result r;
	r = fpgaReadMMIO32(handle, 0, MMIO_CSR_NUM_LINES, &dbgcsr->num_lines);
	if (r != FPGA_OK)
		return r;
	r = fpgaReadMMIO32(handle, 0, MMIO_CSR_MEM_READ_IDX, &dbgcsr->mem_read_idx);
	if (r != FPGA_OK)
		return r;
	r = fpgaReadMMIO32(handle, 0, MMIO_CSR_WRITE_REQ_CNT, &dbgcsr->write_req_cnt);
	if (r != FPGA_OK)
		return r;
	r = fpgaReadMMIO32(handle, 0, MMIO_CSR_WRITE_RESP_CNT, &dbgcsr->write_resp_cnt);
	if (r != FPGA_OK)
		return r;
	r = fpgaReadMMIO32(handle, 0, MMIO_CSR_WRITE_FULL_CNT, &dbgcsr->write_full_cnt);
	if (r != FPGA_OK)
		return r;
	r = fpgaReadMMIO32(handle, 0, MMIO_CSR_STATE, &dbgcsr->state);
	if (r != FPGA_OK)
		return r;
	r = fpgaReadMMIO64(handle, 0, MMIO_CSR_CLK_CNT, &dbgcsr->clk_cnt);
	if (r != FPGA_OK)
		return r;
	return FPGA_OK;
}
void print_csr(struct debug_csr *dbgcsr) {
	printf("num_lines %u, mem_read_idx %u, write_req_cnt %u, write_resp_cnt %u, write_full_cnt %u, state %#x, clk_cnt %lu\n", dbgcsr->num_lines, dbgcsr->mem_read_idx, dbgcsr->write_req_cnt, dbgcsr->write_resp_cnt, dbgcsr->write_full_cnt, dbgcsr->state, dbgcsr->clk_cnt);
}
#endif
