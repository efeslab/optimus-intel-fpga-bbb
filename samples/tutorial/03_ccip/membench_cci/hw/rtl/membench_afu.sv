`include "cci_mpf_if.vh"
`include "csr_mgr.vh"
`include "afu_json_info.vh"

module app_afu
   (
    input  logic clk,

    cci_mpf_if.to_fiu fiu,
    app_csrs.app csrs,

    input  logic c0NotEmpty,
    input  logic c1NotEmpty
    );

    logic reset = 1'b1;
    always @(posedge clk)
    begin
        reset <= fiu.reset;
    end

    t_if_ccip_Rx mpf2af_sRx;
    t_if_ccip_Tx af2mpf_sTx;

    always_comb
    begin
        mpf2af_sRx.c0 = fiu.c0Rx;
        mpf2af_sRx.c1 = fiu.c1Rx;

        mpf2af_sRx.c0TxAlmFull = fiu.c0TxAlmFull;
        mpf2af_sRx.c1TxAlmFull = fiu.c1TxAlmFull;

        fiu.c0Tx = cci_mpf_cvtC0TxFromBase(af2mpf_sTx.c0);
        if (cci_mpf_c0TxIsReadReq(fiu.c0Tx))
        begin
            fiu.c0Tx.hdr.ext.addrIsVirtual = 1'b1;
            fiu.c0Tx.hdr.ext.mapVAtoPhysChannel = 1'b1;
            fiu.c0Tx.hdr.ext.checkLoadStoreOrder = 1'b1;
        end

        fiu.c1Tx = cci_mpf_cvtC1TxFromBase(af2mpf_sTx.c1);
        if (cci_mpf_c1TxIsWriteReq(fiu.c1Tx))
        begin
            fiu.c1Tx.hdr.ext.addrIsVirtual = 1'b1;
            fiu.c1Tx.hdr.ext.mapVAtoPhysChannel = 1'b1;
            fiu.c1Tx.hdr.ext.checkLoadStoreOrder = 1'b1;
            fiu.c1Tx.hdr.pwrite = t_cci_mpf_c1_PartialWriteHdr'(0);
        end

        fiu.c2Tx = af2mpf_sTx.c2;
    end


    membench_top
      app_cci
       (
        .clk,
        .reset,
        .cp2af_sRx(mpf2af_sRx),
        .af2cp_sTx(af2mpf_sTx),
        .csrs,
        .c0NotEmpty,
        .c1NotEmpty
        );

endmodule // app_afu

module membench_top
   (
       input logic clk,
       input logic reset,
       input t_if_ccip_Rx cp2af_sRx,
       output t_if_ccip_Tx af2cp_sTx,
       app_csrs.app csrs,
       input logic c0NotEmpty,
       input logic c1NotEmpty
    );

    t_if_ccip_Rx sRx;
    always_ff @(posedge clk)
    begin
        sRx <= cp2af_sRx;
    end

    t_if_ccip_Tx sTx;
    always_comb
    begin
        af2cp_sTx = sTx;
        af2cp_sTx.c2.mmioRdValid = 1'b0;
    end

    //
    // Implement the device feature list by responding to MMIO reads.
    //
    //------------------ Config ---------------------------
    localparam MDATA_WIDTH = 12;

    localparam MMIO_CSR_TS_STATE = 0;
    localparam MMIO_CSR_READ_CNT = 1;
    localparam MMIO_CSR_WRITE_CNT = 2;
    localparam MMIO_CSR_CLK_CNT = 3;
    localparam MMIO_CSR_STATE = 4;
    localparam MMIO_CSR_REPORT_RECCNT = 5;
    localparam MMIO_CSR_RDRSP_CNT = 6;
    localparam MMIO_CSR_WRRSP_CNT = 7;
    localparam MMIO_CSR_CTL = 8;
    localparam MMIO_CSR_MEM_BASE = 10;
    localparam MMIO_CSR_LEN_MASK = 11;
    localparam MMIO_CSR_READ_TOTAL = 12;
    localparam MMIO_CSR_WRITE_TOTAL = 13;
    localparam MMIO_CSR_PROPERTIES = 14;
    localparam MMIO_CSR_RAND_SEED_0 = 15;
    localparam MMIO_CSR_RAND_SEED_1 = 16;
    localparam MMIO_CSR_RAND_SEED_2 = 17;
    localparam MMIO_CSR_STATUS_ADDR = 18;
    localparam MMIO_CSR_REC_FILTER = 19;
    localparam MMIO_CSR_SEQ_START_OFFSET = 20;

    //------------------ Default value--------------------
    // Memory address to which this AFU will write.
    localparam DEFAULT_CSR_MEM_BASE = t_ccip_clAddr'(0);
    localparam DEFAULT_RAND_SEED_0 = 64'h812765dd017492a3;
    localparam DEFAULT_RAND_SEED_1 = 64'hdb2042bc38c704e3;
    localparam DEFAULT_RAND_SEED_2 = 64'h39e8e59c761c69c6;
    localparam RECFILTER_WIDTH = 10;
    localparam PAGE_IDX_WIDTH = 6;
    localparam RW_CNT_WIDTH = 32;
    t_ccip_clAddr base_addr, report_addr, status_addr;
    assign report_addr = (status_addr + 1);
    logic [31:0] len_mask;
    logic [RECFILTER_WIDTH - 1:0] rec_filter;
    logic [63:0] clk_cnt;
    logic [RW_CNT_WIDTH-1:0] read_cnt,  rdrsp_cnt, read_total;
    logic [RW_CNT_WIDTH-1:0] write_cnt, wrrsp_cnt, write_total;
    logic [63:0] csr_properties;
    t_ccip_vc read_vc, write_vc;
    t_ccip_c0_req read_hint;
    t_ccip_c1_req write_hint;
    logic access_pattern; // 0: sequential 1: random
    logic [1:0]read_type;  // 0: eCL_LEN_1 1: eCL_LEN_2 2: eCL_LEN_4
    assign csr_properties = {read_type, access_pattern, write_hint[3:0], read_hint[3:0], write_vc[1:0], read_vc[1:0]};

    logic [63:0] rand_seed [0:2];
    logic next_valid;
    logic [31:0] seq_start_addr;

    localparam CSR_TS_IDLE = 2'h0;
    localparam CSR_TS_RUNNING = 2'h1;
    localparam CSR_TS_DONE = 2'h2;
    logic [1:0] csr_ts_state;
    logic csr_ctl_start;
    // explicitly use one more bit as sentinel
    logic [$clog2(RECORD_NUM):0] reccnt, report_reccnt, c0Rx_reccnt, c1Rx_reccnt;
    logic report_done, finish_done; // finish_done is set after write complete bit
    typedef enum logic [1:0]
    {
        STATE_IDLE,
        STATE_REPORT,
        STATE_FINISH,
        STATE_RUN
    }
    t_state;
    t_state state;

    // handling MMIO Read
    always_comb
    begin
        csrs.afu_id = `AFU_ACCEL_UUID;

        for (int i = 0; i < NUM_APP_CSRS; i = i + 1)
        begin
            csrs.cpu_rd_csrs[i].data = 64'(0);
        end

        csrs.cpu_rd_csrs[MMIO_CSR_TS_STATE].data = t_ccip_mmioData'({62'h0, csr_ts_state});
        csrs.cpu_rd_csrs[MMIO_CSR_MEM_BASE].data = t_ccip_mmioData'(base_addr);
        csrs.cpu_rd_csrs[MMIO_CSR_LEN_MASK].data = t_ccip_mmioData'({32'h0, len_mask});
        csrs.cpu_rd_csrs[MMIO_CSR_READ_TOTAL].data = t_ccip_mmioData'(read_total);
        csrs.cpu_rd_csrs[MMIO_CSR_WRITE_TOTAL].data = t_ccip_mmioData'(write_total);
        csrs.cpu_rd_csrs[MMIO_CSR_PROPERTIES].data = t_ccip_mmioData'(csr_properties);
        csrs.cpu_rd_csrs[MMIO_CSR_CLK_CNT].data = t_ccip_mmioData'(clk_cnt);
        csrs.cpu_rd_csrs[MMIO_CSR_READ_CNT].data = t_ccip_mmioData'(read_cnt);
        csrs.cpu_rd_csrs[MMIO_CSR_WRITE_CNT].data = t_ccip_mmioData'(write_cnt);

        csrs.cpu_rd_csrs[MMIO_CSR_STATE].data[1:0] = state;
        csrs.cpu_rd_csrs[MMIO_CSR_STATE].data[2] = report_done;
        csrs.cpu_rd_csrs[MMIO_CSR_STATE].data[63:3] = 0;

        csrs.cpu_rd_csrs[MMIO_CSR_REPORT_RECCNT].data[31:0] = reccnt;
        csrs.cpu_rd_csrs[MMIO_CSR_REPORT_RECCNT].data[63:32] = report_reccnt;

        csrs.cpu_rd_csrs[MMIO_CSR_RDRSP_CNT].data = t_ccip_mmioData'(rdrsp_cnt);
        csrs.cpu_rd_csrs[MMIO_CSR_WRRSP_CNT].data = t_ccip_mmioData'(wrrsp_cnt);
    end


    //
    // CSR write handling.  Host software must tell the AFU the memory address
    // to which it should be writing.  The address is set by writing a CSR.
    //

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            base_addr <= DEFAULT_CSR_MEM_BASE;
            len_mask <= 0;
            rec_filter <= 0;
            read_total <= 64'h0;
            write_total <= 64'h0;
            rand_seed[0] <= DEFAULT_RAND_SEED_0;
            rand_seed[1] <= DEFAULT_RAND_SEED_1;
            rand_seed[2] <= DEFAULT_RAND_SEED_2;
            csr_ctl_start <= 1'b0;
            access_pattern <= 0;
            read_type <= 0;
            seq_start_addr <= 0;
        end
        else
        begin
            if (csrs.cpu_wr_csrs[MMIO_CSR_MEM_BASE].en)
            begin
                base_addr <= t_ccip_clAddr'(csrs.cpu_wr_csrs[MMIO_CSR_MEM_BASE].data);
            end

            if (csrs.cpu_wr_csrs[MMIO_CSR_LEN_MASK].en)
            begin
                len_mask <= csrs.cpu_wr_csrs[MMIO_CSR_LEN_MASK].data[31:0];
            end

            if (csrs.cpu_wr_csrs[MMIO_CSR_REC_FILTER].en)
            begin
                rec_filter <= csrs.cpu_wr_csrs[MMIO_CSR_REC_FILTER].data[25:0];
            end

            if (csrs.cpu_wr_csrs[MMIO_CSR_READ_TOTAL].en)
            begin
                read_total <= csrs.cpu_wr_csrs[MMIO_CSR_REC_FILTER].data;
            end

            if (csrs.cpu_wr_csrs[MMIO_CSR_WRITE_TOTAL].en)
            begin
                write_total <= csrs.cpu_wr_csrs[MMIO_CSR_WRITE_TOTAL].data;
            end

            if (csrs.cpu_wr_csrs[MMIO_CSR_PROPERTIES].en)
            begin
                case (csrs.cpu_wr_csrs[MMIO_CSR_PROPERTIES].data[1:0]) // read_vc
                    2'b00: read_vc <= eVC_VA;
                    2'b01: read_vc <= eVC_VL0;
                    2'b10: read_vc <= eVC_VH0;
                    2'b11: read_vc <= eVC_VH1;
                endcase
                case (csrs.cpu_wr_csrs[MMIO_CSR_PROPERTIES].data[3:2]) // write_vc
                    2'b00: write_vc <= eVC_VA;
                    2'b01: write_vc <= eVC_VL0;
                    2'b10: write_vc <= eVC_VH0;
                    2'b11: write_vc <= eVC_VH1;
                endcase
                case (csrs.cpu_wr_csrs[MMIO_CSR_PROPERTIES].data[7:4]) // read_hint
                    4'h0: read_hint <= eREQ_RDLINE_I;
                    4'h1: read_hint <= eREQ_RDLINE_S;
                    default: read_hint <= eREQ_RDLINE_I;
                endcase
                case (csrs.cpu_wr_csrs[MMIO_CSR_PROPERTIES].data[11:8]) // write_hint
                    4'h0: write_hint <= eREQ_WRLINE_I;
                    4'h1: write_hint <= eREQ_WRLINE_M;
                    4'h2: write_hint <= eREQ_WRPUSH_I;
                    4'h4: write_hint <= eREQ_WRFENCE;
                    4'h6: write_hint <= eREQ_INTR;
                    default: write_hint <= eREQ_WRLINE_I;
                endcase
                access_pattern <= csrs.cpu_wr_csrs[MMIO_CSR_PROPERTIES].data[12];
                read_type <= csrs.cpu_wr_csrs[MMIO_CSR_PROPERTIES].data[14:13];
            end

            if (csrs.cpu_wr_csrs[MMIO_CSR_RAND_SEED_0].en)
            begin
                rand_seed[0] <= csrs.cpu_wr_csrs[MMIO_CSR_RAND_SEED_0].data;
            end

            if (csrs.cpu_wr_csrs[MMIO_CSR_RAND_SEED_1].en)
            begin
                rand_seed[1] <= csrs.cpu_wr_csrs[MMIO_CSR_RAND_SEED_1].data;
            end

            if (csrs.cpu_wr_csrs[MMIO_CSR_RAND_SEED_2].en)
            begin
                rand_seed[2] <= csrs.cpu_wr_csrs[MMIO_CSR_RAND_SEED_2].data;
            end

            if (csrs.cpu_wr_csrs[MMIO_CSR_STATUS_ADDR].en)
            begin
                status_addr <= t_ccip_clAddr'(csrs.cpu_wr_csrs[MMIO_CSR_STATUS_ADDR].data);
            end

            if (csrs.cpu_wr_csrs[MMIO_CSR_CTL].en)
            begin
                csr_ctl_start <= csrs.cpu_wr_csrs[MMIO_CSR_CTL].data[0];
            end
            else
            begin
                csr_ctl_start <= 1'b0;
            end

            if (csrs.cpu_wr_csrs[MMIO_CSR_SEQ_START_OFFSET].en)
            begin
                seq_start_addr <= csrs.cpu_wr_csrs[MMIO_CSR_SEQ_START_OFFSET].data[31:0];
            end

        end
    end
 


    // =========================================================================
    //
    //   Main AFU logic
    //
    // =========================================================================

    logic read_done, write_done, can_read, can_write, do_read, do_write, rdrsp_done, wrrsp_done;
    logic do_read_Q, do_write_Q;
    //
    // State machine
    //
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            state <= STATE_IDLE;
            clk_cnt <= 64'h0;
            csr_ts_state <= CSR_TS_IDLE;
        end
        else
        begin
            // Trigger the AFU when start signal is wrote to CSR_CTL. (After
            // the CPU tells us where the FPGA should read, write how much
            // cachelines.)
            if ((state == STATE_IDLE) && csr_ctl_start)
            begin
                state <= STATE_RUN;
                csr_ts_state <= CSR_TS_RUNNING;
                clk_cnt <= 64'h0;
                $display("AFU running...");
            end
            if (state == STATE_RUN)
                clk_cnt <= clk_cnt + 1;
            // The AFU completes its task by writing a single line.  When
            // the line is written return to idle.  The write will happen
            // as long as the request channel is not full.
            if ((state == STATE_RUN) && read_done && write_done && rdrsp_done && wrrsp_done)
            begin
                state <= STATE_REPORT;
                $display("AFU reporting...");
            end
            if (state == STATE_REPORT && report_done)
            begin
                csr_ts_state <= CSR_TS_RUNNING;
                state <= STATE_FINISH;
            end
            if (state == STATE_FINISH && finish_done)
            begin
                csr_ts_state <= CSR_TS_DONE;
                state <= STATE_IDLE;
                $display("AFU done...");
            end
        end
    end

    // rw_priority: 0 means read first, 1 means write first
    logic rw_priority;
    always_ff @(posedge clk) begin
        read_done <= (read_cnt >= read_total);
        write_done <= (write_cnt >= write_total);
        rdrsp_done <= (rdrsp_cnt >= read_cnt);
        wrrsp_done <= (wrrsp_cnt >= write_cnt);
    end
    assign can_read = (!sRx.c0TxAlmFull) && (!read_done);
    assign can_write = (!sRx.c1TxAlmFull) && (!write_done);
    assign do_read = next_valid && can_read && !(can_write && rw_priority);
    assign do_write = next_valid && can_write && !(can_read && !rw_priority);
    t_ccip_clAddr next_addr;
    logic [31:0] next_offset;
    always_ff @(posedge clk)
    begin
        if (reset) begin rw_priority <= 1'b0; end
        else begin rw_priority <= rw_priority? !do_write: do_read; end
    end
    always_ff @(posedge clk)
    begin
        if (reset) begin
            do_read_Q <= 0;
            do_write_Q <= 0;
        end
        else begin
            do_read_Q <= do_read;
            do_write_Q <= do_write;
        end
    end
    // record latenct per request
    localparam RECORD_NUM = 64;
    localparam RECORD_WIDTH = 16;
    localparam REPORT_UNIT = (CCIP_CLDATA_WIDTH/RECORD_WIDTH);
    initial begin
        assert ((RECORD_NUM%REPORT_UNIT)==0)
        else
            $error("RECORD_NUM %d should divide REPORT_UNIT %d", RECORD_NUM, REPORT_UNIT);
    end
(* ramstyle = "logic" *) reg [RECORD_WIDTH-1:0] latbgn [RECORD_NUM - 1 : 0];
(* ramstyle = "logic" *) reg [RECORD_WIDTH-1:0] latrec [RECORD_NUM - 1 : 0];
    logic should_rec;
    assign should_rec = (next_offset[RECFILTER_WIDTH+PAGE_IDX_WIDTH-1:PAGE_IDX_WIDTH] == rec_filter) && (reccnt != RECORD_NUM);
    assign c0Rx_reccnt = sRx.c0.hdr.mdata[$clog2(RECORD_NUM):0];
    assign c1Rx_reccnt = sRx.c1.hdr.mdata[$clog2(RECORD_NUM):0];
    assign report_done = (report_reccnt >= reccnt);
    // queue for timing
    logic report_stage_2;
    logic should_rec_Q;
    logic [$clog2(RECORD_NUM):0] reccnt_Q, report_reccnt_Q;
    logic [RECORD_WIDTH-1:0] latbgn_Q;
    /*
     * send memory read and write requests
     */
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            read_cnt <= 0;
            write_cnt <= 0;
            sTx.c0.valid <= 0;
            reccnt <= 0;
            sTx.c1.valid <= 0;
            report_reccnt <= 0;
            should_rec_Q <= 0;
            report_stage_2 <= 0;
            finish_done <= 0;
        end
        else
        begin
            should_rec_Q <= (state == STATE_RUN) && (do_read | do_write) && should_rec;
            if (should_rec_Q) begin
                latbgn[reccnt_Q] <= latbgn_Q;
            end
            case (state)
                STATE_RUN: begin
                    if (do_read_Q) begin
                        case (read_type)
                            default: begin // eCL_LEN_1
                                read_cnt <= read_cnt + 1;
                                sTx.c0.hdr.cl_len <= eCL_LEN_1;
                                sTx.c0.hdr.address <= next_addr;
                            end
                            1: begin // eCL_LEN_2
                                read_cnt <= read_cnt + 2;
                                sTx.c0.hdr.cl_len <= eCL_LEN_2;
                                sTx.c0.hdr.address <= {next_addr[CCIP_CLADDR_WIDTH-1:1], 1'b0};
                            end
                            2: begin // eCL_LEN_4
                                read_cnt <= read_cnt + 4;
                                sTx.c0.hdr.cl_len <= eCL_LEN_4;
                                sTx.c0.hdr.address <= {next_addr[CCIP_CLADDR_WIDTH-1:2], 2'b0};
                            end
                        endcase
                        sTx.c0.valid <= 1'b1;
                        sTx.c0.hdr.vc_sel <= read_vc;
                        sTx.c0.hdr.req_type <= read_hint;
                        if (should_rec) begin
                            sTx.c0.hdr.mdata <= reccnt;
                            reccnt_Q <= reccnt;
                            latbgn_Q <= clk_cnt[RECORD_WIDTH-1:0];
                            case (read_type)
                                default:
                                    reccnt <= reccnt + 1;
                                1:
                                    reccnt <= reccnt + 2;
                                2:
                                    reccnt <= reccnt + 4;
                            endcase
                        end
                        else begin
                            sTx.c0.hdr.mdata <= RECORD_NUM;
                        end
                    end
                    else begin
                        sTx.c0.valid <= 1'b0;
                        sTx.c0.hdr <= t_ccip_c0_ReqMemHdr'(0);
                    end
                    if (do_write_Q) begin
                        write_cnt <= write_cnt + 1;
                        sTx.c1.valid <= 1'b1;
                        sTx.c1.hdr.vc_sel <= write_vc;
                        sTx.c1.hdr.sop <= 1'b1;
                        sTx.c1.hdr.cl_len <= eCL_LEN_1;
                        sTx.c1.hdr.req_type <= write_hint;
                        sTx.c1.hdr.address <= next_addr;
                        sTx.c1.data <= next_offset;
                        if (should_rec) begin
                            sTx.c1.hdr.mdata <= reccnt;
                            reccnt_Q <= reccnt;
                            latbgn_Q <= clk_cnt[RECORD_WIDTH-1:0];
                            reccnt <= reccnt + 1;
                        end
                        else begin
                            sTx.c1.hdr.mdata <= RECORD_NUM;
                        end
                    end
                    else begin
                        sTx.c1.valid <= 1'b0;
                        sTx.c1.hdr <= t_ccip_c1_ReqMemHdr'(0);
                    end
                end
                STATE_REPORT: begin
                    if (!sRx.c1TxAlmFull && !report_done) begin
                        report_reccnt_Q <= report_reccnt;
                        report_stage_2 <= 1;
                        report_reccnt <= report_reccnt + REPORT_UNIT;
                    end
                    else begin
                        report_stage_2 <= 0;
                    end
                    if (report_stage_2) begin
                        sTx.c1.valid <= 1'b1;
                        sTx.c1.hdr.vc_sel <= eVC_VL0;
                        sTx.c1.hdr.sop <= 1'b1;
                        sTx.c1.hdr.cl_len <= eCL_LEN_1;
                        sTx.c1.hdr.req_type <= eREQ_WRLINE_I;
                        sTx.c1.hdr.address <= report_addr + report_reccnt_Q[$clog2(RECORD_NUM):$clog2(REPORT_UNIT)];
                        sTx.c1.hdr.mdata <= RECORD_NUM;
                        sTx.c1.data <= t_ccip_clData'(latrec[report_reccnt_Q+:REPORT_UNIT]);
                    end
                    else begin
                        sTx.c1.valid <= 1'b0;
                    end
                end
                STATE_FINISH: begin
                    if (!sRx.c1TxAlmFull && !finish_done) begin
                        sTx.c1.valid <= 1'b1;
                        sTx.c1.hdr.vc_sel <= eVC_VL0;
                        sTx.c1.hdr.sop <= 1'b1;
                        sTx.c1.hdr.cl_len <= eCL_LEN_1;
                        sTx.c1.hdr.req_type <= eREQ_WRLINE_I;
                        sTx.c1.hdr.address <= status_addr;
                        sTx.c1.hdr.mdata <= RECORD_NUM;
                        sTx.c1.data[0] <= 1'b1;
                        sTx.c1.data[63:1] <= 0;
                        sTx.c1.data[127:64] <= clk_cnt;
                        sTx.c1.data[191:128] <= reccnt;
                        sTx.c1.data[511:192] <= 0;
                        finish_done <= 1;
                    end
                    else begin
                        sTx.c1.valid <= 1'b0;
                        finish_done <= 0;
                    end
                end
                default: begin
                    sTx.c0.valid <= 1'b0;
                    sTx.c1.valid <= 1'b0;
                end
            endcase
        end
    end
    /*
     * handle memory read and write response
     */
    logic [$clog2(RECORD_NUM):0] c0Rx_reccnt_Q, c0Rx_reccnt_QQ, c0Rx_reccnt_QQQ, c1Rx_reccnt_Q, c1Rx_reccnt_QQ, c1Rx_reccnt_QQQ, c0Rx_base_reccnt_Q;
    logic rdrsp_stage2, rdrsp_stage3, rdrsp_stage4;
    logic wrrsp_stage2, wrrsp_stage3, wrrsp_stage4;
    logic [RECORD_WIDTH-1:0] rdlat, wrlat, rdlatbgn, wrlatbgn;
    integer i;
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            rdrsp_cnt <= 0;
            wrrsp_cnt <= 0;
            rdrsp_stage2 <= 0;
            wrrsp_stage2 <= 0;
            rdrsp_stage3 <= 0;
            wrrsp_stage3 <= 0;
            rdrsp_stage4 <= 0;
            wrrsp_stage4 <= 0;
            for (i=0; i < RECORD_NUM; ++i) begin
                latrec[i] <= 0;
            end
        end
        else begin
            if (sRx.c1.rspValid == 1'b1)
            begin
                wrrsp_cnt <= wrrsp_cnt + 1;
                if (c1Rx_reccnt != RECORD_NUM)
                begin
                    wrrsp_stage2 <= 1;
                    c1Rx_reccnt_Q <= c1Rx_reccnt;
                end
                else
                begin
                    wrrsp_stage2 <= 0;
                end
            end
            if (wrrsp_stage2) begin
                wrlatbgn <= latbgn[c1Rx_reccnt_Q];
                c1Rx_reccnt_QQ <= c1Rx_reccnt_Q;
                wrrsp_stage3 <= 1;
            end
            else begin
                wrrsp_stage3 <= 0;
            end
            if (wrrsp_stage3) begin
                wrlat <= clk_cnt[RECORD_WIDTH-1:0] - wrlatbgn;
                c1Rx_reccnt_QQQ <= c1Rx_reccnt_QQ;
                wrrsp_stage4 <= 1;
            end
            else
            begin
                wrrsp_stage4 <= 0;
            end
            if (wrrsp_stage4) begin
                latrec[c1Rx_reccnt_QQQ][RECORD_WIDTH-2:0] <= wrlat;
                latrec[c1Rx_reccnt_QQQ][RECORD_WIDTH-1] <= 1'b1; // last bit == 1: write request
            end
            if (sRx.c0.rspValid == 1'b1)
            begin
                rdrsp_cnt <= rdrsp_cnt + 1;
                if (c0Rx_reccnt != RECORD_NUM)
                begin
                    rdrsp_stage2 <= 1;
                    c0Rx_reccnt_Q <= c0Rx_reccnt + sRx.c0.hdr.cl_num;
                    c0Rx_base_reccnt_Q <= c0Rx_reccnt;
                end
                else
                begin
                    rdrsp_stage2 <= 0;
                end
            end
            else
            begin
                rdrsp_stage2 <= 0;
            end
            if (rdrsp_stage2) begin
                rdlatbgn <= latbgn[c0Rx_base_reccnt_Q];
                c0Rx_reccnt_QQ <= c0Rx_reccnt_Q;
                rdrsp_stage3 <= 1;
            end
            else begin
                rdrsp_stage3 <= 0;
            end
            if (rdrsp_stage3) begin
                rdlat <= clk_cnt[RECORD_WIDTH-1:0] - rdlatbgn; // intended overflow here
                c0Rx_reccnt_QQQ <= c0Rx_reccnt_QQ;
                rdrsp_stage4 <= 1;
            end
            else
            begin
                rdrsp_stage4 <= 0;
            end
            if (rdrsp_stage4) begin
                latrec[c0Rx_reccnt_QQQ][RECORD_WIDTH-2:0] <= rdlat;
                latrec[c0Rx_reccnt_QQQ][RECORD_WIDTH-1] <= 1'b0; // last bit == 0: read request
            end
        end
    end
    /*
     * next_addr generator
     */
    /*
     * random number generator
     */

    logic [31:0] init_state[0:4];
    assign init_state[0] = rand_seed[0][31:0];
    assign init_state[1] = rand_seed[0][63:32];
    assign init_state[2] = rand_seed[1][31:0];
    assign init_state[3] = rand_seed[1][63:32];
    assign init_state[4] = rand_seed[2][31:0];
    logic [31:0] random32_Q;
    logic next_valid_Q;
    logic xor_reset;
    xorwow #(.WIDTH(32)) xw(
        .clk(clk),
        .reset(xor_reset),
        .init_state(init_state),
        .random(random32_Q),
        .valid(next_valid_Q)
    );
    // bookkeeping sequential access next addr
    logic [31:0] seq_addr;
    always_ff @(posedge clk) begin
        if (state == STATE_IDLE)
            seq_addr <= seq_start_addr;
        else if (state == STATE_RUN) begin
            if (do_read) begin
                case (read_type)
                    default: begin // eCL_LEN_1
                        seq_addr <= seq_addr + 1;
                    end
                    1: begin // eCL_LEN_2
                        seq_addr <= seq_addr + 2;
                    end
                    2: begin // eCL_LEN_4
                        seq_addr <= seq_addr + 4;
                    end
                endcase
            end
            else if (do_write) begin
                seq_addr <= seq_addr + 1;
            end
        end
        else begin
            seq_addr <= seq_addr;
        end
    end
    always_ff @(posedge clk) begin
        if (reset) begin
            xor_reset <= 1;
        end
        else begin
            if ((state == STATE_IDLE) && csr_ctl_start) begin
                xor_reset <= 0;
            end
            case (access_pattern)
                0: begin // sequential
                    next_offset <= seq_addr & len_mask;
                    next_addr <= base_addr + (seq_addr & len_mask);
                    next_valid <= (state == STATE_RUN);
                end
                1: begin // random
                    next_offset <= random32_Q & len_mask;
                    next_addr <= base_addr + (random32_Q & len_mask);
                    next_valid <= next_valid_Q;
                end
            endcase
        end
    end

endmodule
