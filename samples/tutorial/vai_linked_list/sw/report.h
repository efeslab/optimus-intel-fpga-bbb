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
#define VC_PAIR(name) {"RD_"#name, PROP_RD_VC(name) << PROP_RD_VC_LOWBIT}
//{"WR_"#name, (PROP_WR_VC(name) << PROP_WR_VC_LOWBIT)}
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
static property_map_t pmap[] = {
    {.pes=vc_map, .pnum=ARRSIZE(vc_map), .help_msg="Virtual Channel properties"}
};
struct debug_csr {
    uint64_t list_length;
    uint64_t properties;
    uint64_t ts_state;
    uint64_t clk_cnt;
};

// return value: 0 means ok, non-zero means something is wrong
int get_debug_csr(
        fpga_handle *accel_handle,
        struct debug_csr *dbgcsr) {
    return (
            fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_CNT_LIST_LENGTH, &dbgcsr->list_length) ||
            fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_TRANSACTION_STATE, &dbgcsr->ts_state)||
            fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_PROPERTIES, &dbgcsr->properties) ||
            fpgaReadMMIO64(accel_handle, 0, MMIO_CSR_CLK_CNT, &dbgcsr->clk_cnt)
            );
}
void print_csr(struct debug_csr *dbgcsr) {
    fprintf(stderr,
            "clk_cnt %lu, list_length %lu, ts_state %ld, properties: %s\n",
            dbgcsr->clk_cnt, dbgcsr->list_length, dbgcsr->ts_state,
            GET_RD_VC_N(dbgcsr->properties));
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
