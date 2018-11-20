import ccip_if_pkg::*;
`include "vendor_defines.vh"

typedef enum logic [1:0] {
    READ_NORMAL,
    READ_BATCH
} p1_status_type;

module vai_serve_tx #(parameter NUM_SUB_AFUS=8)
(
    input   wire                    clk,
    input   wire                    reset,
    output  t_if_ccip_Tx            up_TxPort,
    input   t_if_ccip_Tx            afu_TxPort      [NUM_SUB_AFUS-1:0],
    input   logic [63:0]            offset_array    [NUM_SUB_AFUS-1:0]
);

    localparam LNUM_SUB_AFUS = $clog2(NUM_SUB_AFUS);
    localparam VMID_WIDTH = LNUM_SUB_AFUS;

    logic fifo_c0_read_reqs [NUM_SUB_AFUS-1:0];
    logic fifo_c1_read_reqs [NUM_SUB_AFUS-1:0];
    logic fifo_c2_read_reqs [NUM_SUB_AFUS-1:0];

    t_if_ccip_c0_Tx fifo_c0 [NUM_SUB_AFUS-1:0];
    t_if_ccip_c1_Tx fifo_c1 [NUM_SUB_AFUS-1:0];
    t_if_ccip_c2_Tx fifo_c2 [NUM_SUB_AFUS-1:0];

    logic fifo_c0_need_read [NUM_SUB_AFUS-1:0];
    logic fifo_c1_need_read [NUM_SUB_AFUS-1:0];
    logic fifo_c2_need_read [NUM_SUB_AFUS-1:0];

    logic fifo_c0_alm_full [NUM_SUB_AFUS-1:0];
    logic fifo_c1_alm_full [NUM_SUB_AFUS-1:0];
    logic fifo_c2_alm_full [NUM_SUB_AFUS-1:0];
    

    generate
        genvar n;
        for (n=0; n<NUM_SUB_AFUS; n++)
        begin: afu_tx_stages

            /* stage T0 */
            t_if_ccip_Tx T0_Tx;
            assign T0_Tx = afu_TxPort[n];

            /* stage T1 */
            t_if_ccip_c0_Tx T1_c0;
            t_if_ccip_c1_Tx T1_c1;
            t_if_ccip_c2_Tx T1_c2;

            logic [63:0] T1_offset_mem;
            logic [31:0] T1_offset_mmio;

            always_ff @(posedge clk)
            begin
                if (reset)
                begin
                    T1_c0 <= t_if_ccip_c0_Tx'(0);
                    T1_c1 <= t_if_ccip_c1_Tx'(0);
                    T1_c2 <= t_if_ccip_c2_Tx'(0);
                    T1_offset_mem <= 0;
                    T1_offset_mmio <= 0;
                end
                else
                begin
                    T1_c0 <= T0_Tx.c0;
                    T1_c1 <= T0_Tx.c1;
                    T1_c2 <= T0_Tx.c2;
                    T1_offset_mem <= offset_array[n];
                    T1_offset_mmio <= ((n+1) << 6);
                end
            end

            /* stage T2 */
            t_if_ccip_c0_Tx T2_c0;
            t_if_ccip_c1_Tx T2_c1;
            t_if_ccip_c2_Tx T2_c2;
            logic T2_enque_c0;
            logic T2_enque_c1;
            logic T2_enque_c2;

            always_ff @(posedge clk)
            begin
                if (reset)
                begin
                    T2_c0 <= t_if_ccip_c0_Tx'(0);
                    T2_c1 <= t_if_ccip_c1_Tx'(0);
                    T2_c2 <= t_if_ccip_c2_Tx'(0);
                    T2_enque_c0 <= 0;
                    T2_enque_c1 <= 0;
                    T2_enque_c2 <= 0;
                end
                else
                begin
                    /* handle c0 */
                    T2_enque_c0            <=  T1_c0.valid;
                    T2_c0.valid         <=  T1_c0.valid;
                    T2_c0.hdr.vc_sel    <=  T1_c0.hdr.vc_sel;
                    T2_c0.hdr.rsvd1     <=  T1_c0.hdr.rsvd1;
                    T2_c0.hdr.cl_len    <=  T1_c0.hdr.cl_len;
                    T2_c0.hdr.req_type  <=  T1_c0.hdr.req_type;
                    T2_c0.hdr.rsvd0     <=  T1_c0.hdr.rsvd0;
                    T2_c0.hdr.address   <=  T1_c0.hdr.address + T1_offset_mem;
                    T2_c0.hdr.mdata     <=  {LNUM_SUB_AFUS'n,T2_c0.hdr.mdata[15-LNUM_SUB_AFUS:0]};

                    /* handle c1 */
                    T2_enque_c1            <=  T1_c1.valid;
                    T2_c1.valid         <=  T1_c1.valid;
                    T2_c1.data          <=  T1_c1.data;
                    T2_c1.hdr.rsvd2     <=  T1_c1.hdr.rsvd2;
                    T2_c1.hdr.vc_sel    <=  T1_c1.hdr.vc_sel;
                    T2_c1.hdr.sop       <=  T1_c1.hdr.sop;
                    T2_c1.hdr.rsvd1     <=  T1_c1.hdr.rsvd1;
                    T2_c1.hdr.cl_len    <=  T1_c1.hdr.cl_len;
                    T2_c1.hdr.req_type  <=  T1_c1.hdr.req_type;
                    T2_c1.hdr.address   <=  (T1_c1.hdr.req_type == eREQ_WRFENCE) ? 0 : (T1_c1.hdr.address + T1_offset_mem);
                    T2_c0.hdr.mdata     <=  {LNUM_SUB_AFUS'n,T2_c1.hdr.mdata[15-LNUM_SUB_AFUS:0]};

                    /* handle c2 */
                    T2_enque_c2            <=  T1_c2.valid;
                    T2_c2.mmioRdValid   <=  T1_c2.mmioRdValid;
                    T2_c2.data          <=  T1_c2.data;
                    T2_c2.hdr.tid       <=  T1_c2.hdr.tid;
                end
            end

            vai_tx_fifo #(
                .DATA_WIDTH($bits(t_if_ccip_c0_Tx))
            )
            inst_vai_tx_fifo_c0(
                .clk(clk),
                .reset(reset),
                .data_in(T2_c0),
                .rd_req(fifo_c0_read_reqs[n]),
                .wr_req(T2_enque_c0),
                .add_block_cycle(0),
                .add_block_cycle_valid(0),
                .data_out(fifo_c0[n]),
                .need_rd(fifo_c0_need_read[n]),
                .alm_full(fifo_c0_alm_full[n])
                );

            vai_tx_fifo #(
                .DATA_WIDTH($bits(t_if_ccip_c1_Tx))
            )
            inst_vai_tx_fifo_c1(
                .clk(clk),
                .reset(reset),
                .data_in(T2_c1),
                .rd_req(fifo_c1_read_reqs[n]),
                .wr_req(T2_enque_c1),
                .add_block_cycle(0),
                .add_block_cycle_valid(0),
                .data_out(fifo_c1[n]),
                .need_rd(fifo_c1_need_read[n]),
                .alm_full(fifo_c1_alm_full[n])
                );

            vai_tex_fifo #(
                .DATA_WIDTH($bits(t_if_ccip_c2_Tx))
            )
            inst_vai_tx_fifo_c2(
                .clk(clk),
                .reset(reset),
                .data_in(T2_c2),
                .rd_req(fifo_c2_read_reqs[n]),
                .wr_req(T2_enque_c2),
                .add_block_cycle(0),
                .add_block_cycle_valid(0),
                .data_out(fifo_c2[n]),
                .need_rd(fifo_c2_need_read[n]),
                .alm_full(fifo_c2_alm_full[n])
                );

        end

    endgenerate

    /* stage P1 */
    p1_status_type P1_status;
    logic [LNUM_SUB_AFUS-1:0] P1_curr;
    logic [LNUM_SUB_AFUS-1:0] P1_next;
    logic P1_next_need_read;
    t_if_ccip_c0_Tx P1_Tx;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            P1_status <= READ_NORMAL;
            P1_curr <= 0;
            P1_next <= 0;
            P1_next_need_read <= 0;
            P1_Tx <= t_if_ccip_c0_Tx'(0);
        end
        else
        begin
            




endmodule
