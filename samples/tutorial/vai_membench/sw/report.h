#ifndef __REPORT_H__
#define __REPORT_H__

// channel selection
#define PROP_VC_VA 0x0
#define PROP_VC_VL0 0x1
#define PROP_VC_VH0 0x2
#define PROP_VC_VH1 0x3
#define PROP_RD_VC(name) (PROP_VC_##name)
#define PROP_WR_VC(name) (PROP_VC_##name << 2)
#define VC_MASK_RD 0x3
#define VC_MASK_WR 0xc
#define VC_N(p, RW, name) ((p&(VC_MASK_##RW)) == PROP_ ## RW ## _VC(name))?#RW"_"#name
#define GET_RD_VC_N(p) (\
        VC_N(p, RD, VA):\
        VC_N(p, RD, VL0):\
        VC_N(p, RD, VH0):\
        VC_N(p, RD, VH1): "Unknown")
#define GET_WR_VC_N(p) (\
        VC_N(p, WR, VA):\
        VC_N(p, WR, VL0):\
        VC_N(p, WR, VH0):\
        VC_N(p, WR, VH1): "Unknown")
// read cache hint
#define PROP_RD_CH_RDLINE_I (0x0 << 4)
#define PROP_RD_CH_RDLINE_S (0x1 << 4)
#define RD_CH_N(p, name) ((p&0xf0) == PROP_RD_CH_##name)?#name
#define GET_RD_CH_NAME(p) (\
        RD_CH_N(p, RDLINE_I):\
        RD_CH_N(p, RDLINE_S):"Unknown")
// write cache hint
#define PROP_WR_CH_WRLINE_I (0x0 << 8)
#define PROP_WR_CH_WRLINE_M (0x1 << 8)
#define PROP_WR_CH_WRPUSH_I (0x2 << 8)
#define PROP_WR_CH_WRFENCE  (0x4 << 8)
#define PROP_WR_CH_INTR     (0x6 << 8)
#define WR_CH_N(p, name) ((p&0xf00) == PROP_WR_CH_##name)?#name
#define GET_WR_CH_NAME(p) (\
        WR_CH_N(p, WRLINE_I):\
        WR_CH_N(p, WRLINE_M):\
        WR_CH_N(p, WRPUSH_I):\
        WR_CH_N(p, WRFENCE):\
        WR_CH_N(p, INTR):"Unknown")
#define VC_PAIR(name) {"RD_"#name, PROP_RD_VC(name)},{"WR_"#name, PROP_WR_VC(name)}
#define VC_ENTRY_DEF VC_PAIR(VA), VC_PAIR(VL0), VC_PAIR(VH0), VC_PAIR(VH1)
#define RD_CH_PAIR(name) {#name, PROP_RD_CH_##name}
#define RD_CH_ENTRY_DEF RD_CH_PAIR(RDLINE_I), RD_CH_PAIR(RDLINE_S)
#define WR_CH_PAIR(name) {#name, PROP_WR_CH_##name}
#define WR_CH_ENTRY_DEF WR_CH_PAIR(WRLINE_I), WR_CH_PAIR(WRLINE_M),\
        WR_CH_PAIR(WRPUSH_I), WR_CH_PAIR(WRFENCE), WR_CH_PAIR(INTR)
// access pattern
#define PROP_RAND_ACCESS (0x1 << 12)
#define PROP_SEQ_ACCESS (0x0)
#define ACC_PATT_PAIR(name) {#name, PROP_##name##_ACCESS}
#define ACC_PATT_DEF ACC_PATT_PAIR(RAND), ACC_PATT_PAIR(SEQ)
typedef struct {
    const char *name;
    uint32_t value;
} property_entry_t;
static property_entry_t vc_map[] = {
    VC_ENTRY_DEF
};
static property_entry_t rd_ch_map[] = {
    RD_CH_ENTRY_DEF
};
static property_entry_t wr_ch_map[] = {
    WR_CH_ENTRY_DEF
};
static property_entry_t acc_patt_map[] = {
    ACC_PATT_DEF
};
struct debug_csr {
    uint64_t read_cnt;
    uint64_t rdrsp_cnt;
    uint64_t read_total;
    uint64_t write_cnt;
    uint64_t wrrsp_cnt;
    uint64_t write_total;
    uint64_t properties;
    uint64_t state;
    uint64_t report_reccnt;
    uint64_t clk_cnt;
};

// return value: 0 means ok, non-zero means something is wrong
int get_debug_csr(fpga_handle *accel_handle, struct debug_csr *dbgcsr) {
    return (fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_READ_CNT, &dbgcsr->read_cnt) ||
            fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_RDRSP_CNT, &dbgcsr->rdrsp_cnt) ||
            fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_READ_TOTAL, &dbgcsr->read_total) ||
            fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_WRITE_CNT, &dbgcsr->write_cnt) ||
            fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_WRRSP_CNT, &dbgcsr->wrrsp_cnt) ||
            fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_WRITE_TOTAL, &dbgcsr->write_total) ||
            fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_PROPERTIES, &dbgcsr->properties) ||
            fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_CLK_CNT, &dbgcsr->clk_cnt) ||
            fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_STATE, &dbgcsr->state) ||
            fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_REPORT_RECCNT, &dbgcsr->report_reccnt));
}
void print_csr(struct debug_csr *dbgcsr) {
    fprintf(stderr,
            "read %lu(%lu)/%lu, write %lu(%lu)/%lu, clk %lu, state %lu, report_done %lu, reccnt %lu, report_reccnt %lu, properties: %s %s %s %s\n",
            dbgcsr->read_cnt, dbgcsr->rdrsp_cnt, dbgcsr->read_total,
            dbgcsr->write_cnt, dbgcsr->wrrsp_cnt, dbgcsr->write_total, dbgcsr->clk_cnt,
            (dbgcsr->state & 0x3), ((dbgcsr->state >> 2) & 0x1),
            (dbgcsr->report_reccnt & 0xffffffff), ((dbgcsr->report_reccnt >> 32) & 0xffffffff),
            GET_RD_VC_N(dbgcsr->properties), GET_WR_VC_N(dbgcsr->properties),
            GET_RD_CH_NAME(dbgcsr->properties), GET_WR_CH_NAME(dbgcsr->properties));
}
struct status_cl {
    uint64_t completion;
    uint64_t n_clk;
    uint64_t reccnt;
};
#define RECORD_NUM 64
#define RECORD_WIDTH 16
#define RECORD_RW_MASK 0x8000
#define RECORD_LAT_MASK 0x7fff
typedef struct {
    uint16_t lat[RECORD_NUM];
} report_t;
#endif // __REPORT_H__
