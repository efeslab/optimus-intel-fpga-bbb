#ifndef __REPORT_H__
#define __REPORT_H__

#include "utils.h"
#define PROP_MASK(name) (PROP_##name##_MASK_VAL << PROP_##name##_LOWBIT)
#define GET_PROP(p, name) ((p&PROP_MASK(name)) >> PROP_##name##_LOWBIT)
#define PROP_GET_TERNARY(p, name, val) (GET_PROP(p, name) == PROP_##name##_##val)?#val
#define PROP_PAIR(name, val) {#val, ((PROP_##name##_##val) << (PROP_##name##_LOWBIT))}
// property name is RD_VC WR_VC RD_CH WR_CH ...
// property val is RDLINE_I WRLINE_I RAND ...
// channel selection
#define PROP_VC_VA 0x0
#define PROP_VC_VL0 0x1
#define PROP_VC_VH0 0x2
#define PROP_VC_VH1 0x3
#define PROP_RD_VC_LOWBIT 0
#define PROP_RD_VC(name) PROP_VC_##name
#define PROP_WR_VC_LOWBIT 2
#define PROP_WR_VC(name) PROP_VC_##name
#define VC_MASK_RD 0x3
#define VC_MASK_WR 0xc
#define VC_N(p, RW, name) ((((p&(VC_MASK_##RW)) >> PROP_##RW##_VC_LOWBIT)) == PROP_ ## RW ## _VC(name))?#RW"_"#name
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
#define VC_PAIR(name) {"RD_"#name, (PROP_RD_VC(name) << PROP_RD_VC_LOWBIT)},{"WR_"#name, (PROP_WR_VC(name) << PROP_WR_VC_LOWBIT)}
#define VC_ENTRY_DEF VC_PAIR(VA), VC_PAIR(VL0), VC_PAIR(VH0), VC_PAIR(VH1)
// read cache hint
#define PROP_RD_CH_LOWBIT 4
#define PROP_RD_CH_MASK_VAL 0xf
#define PROP_RD_CH_RDLINE_I 0x0
#define PROP_RD_CH_RDLINE_S 0x1
#define GET_RD_CH_NAME(p) (\
        PROP_GET_TERNARY(p, RD_CH, RDLINE_I):\
        PROP_GET_TERNARY(p, RD_CH, RDLINE_S):"Unknown")
#define RD_CH_ENTRY_DEF PROP_PAIR(RD_CH, RDLINE_I), PROP_PAIR(RD_CH, RDLINE_S)
// write cache hint
#define PROP_WR_CH_LOWBIT 8
#define PROP_WR_CH_MASK_VAL 0xf
#define PROP_WR_CH_WRLINE_I 0x0
#define PROP_WR_CH_WRLINE_M 0x1
#define PROP_WR_CH_WRPUSH_I 0x2
#define PROP_WR_CH_WRFENCE  0x4
#define PROP_WR_CH_INTR     0x6
#define GET_WR_CH_NAME(p) (\
        PROP_GET_TERNARY(p, WR_CH, WRLINE_I):\
        PROP_GET_TERNARY(p, WR_CH, WRLINE_M):\
        PROP_GET_TERNARY(p, WR_CH, WRPUSH_I):\
        PROP_GET_TERNARY(p, WR_CH, WRFENCE):\
        PROP_GET_TERNARY(p, WR_CH, INTR):"Unknown")
#define WR_CH_ENTRY_DEF PROP_PAIR(WR_CH, WRLINE_I), PROP_PAIR(WR_CH, WRLINE_M),\
        PROP_PAIR(WR_CH, WRPUSH_I), PROP_PAIR(WR_CH, WRFENCE),\
        PROP_PAIR(WR_CH, INTR)
// access pattern
#define PROP_ACCESS_LOWBIT 12
#define PROP_ACCESS_MASK_VAL 0x1
#define PROP_ACCESS_RAND 0x1
#define PROP_ACCESS_SEQ 0x0
#define GET_ACCESS_NAME(p) (\
        PROP_GET_TERNARY(p, ACCESS, RAND):\
        PROP_GET_TERNARY(p, ACCESS, SEQ): "Unknown")
#define ACCESS_ENTRY_DEF PROP_PAIR(ACCESS, RAND), PROP_PAIR(ACCESS, SEQ)
// read length
#define PROP_RD_LEN_LOWBIT 13
#define PROP_RD_LEN_MASK_VAL 0x3
#define PROP_RD_LEN_RDCL1 0x0
#define PROP_RD_LEN_RDCL2 0x1
#define PROP_RD_LEN_RDCL4 0x2
#define GET_RD_LEN_NAME(p) (\
        PROP_GET_TERNARY(p, RD_LEN, RDCL1):\
        PROP_GET_TERNARY(p, RD_LEN, RDCL2):\
        PROP_GET_TERNARY(p, RD_LEN, RDCL4): "Unknown")
#define RD_LEN_ENTRY_DEF PROP_PAIR(RD_LEN, RDCL1), PROP_PAIR(RD_LEN, RDCL2),\
        PROP_PAIR(RD_LEN, RDCL4)
typedef struct {
    const char *name;
    uint32_t value;
} property_entry_t;
typedef struct {
    property_entry_t *pes;
    uint32_t pnum;
    char *help_msg;
} property_map_t;
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
    ACCESS_ENTRY_DEF
};
static property_entry_t rd_len_map[] = {
    RD_LEN_ENTRY_DEF
};
static property_map_t pmap[] = {
    {.pes=vc_map, .pnum=ARRSIZE(vc_map), .help_msg="Virtual Channel properties"},
    {.pes=rd_ch_map, .pnum=ARRSIZE(rd_ch_map), .help_msg="Read Cache Hint properties"},
    {.pes=wr_ch_map, .pnum=ARRSIZE(wr_ch_map), .help_msg="Write Cache Hint properties"},
    {.pes=acc_patt_map, .pnum=ARRSIZE(acc_patt_map), .help_msg="Access Pattern properties"},
    {.pes=rd_len_map, .pnum=ARRSIZE(rd_len_map), .help_msg="Read Length properties"}
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
            "read %lu(%lu)/%lu, write %lu(%lu)/%lu, clk %lu, state %lu, report_done %lu, reccnt %lu, report_reccnt %lu, properties: %s %s %s %s %s %s\n",
            dbgcsr->read_cnt, dbgcsr->rdrsp_cnt, dbgcsr->read_total,
            dbgcsr->write_cnt, dbgcsr->wrrsp_cnt, dbgcsr->write_total, dbgcsr->clk_cnt,
            (dbgcsr->state & 0x3), ((dbgcsr->state >> 2) & 0x1),
            (dbgcsr->report_reccnt & 0xffffffff), ((dbgcsr->report_reccnt >> 32) & 0xffffffff),
            GET_RD_VC_N(dbgcsr->properties), GET_WR_VC_N(dbgcsr->properties),
            GET_RD_CH_NAME(dbgcsr->properties), GET_WR_CH_NAME(dbgcsr->properties),
            GET_ACCESS_NAME(dbgcsr->properties), GET_RD_LEN_NAME(dbgcsr->properties));
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
