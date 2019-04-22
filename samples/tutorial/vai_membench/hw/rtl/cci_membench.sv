//
// Copyright (c) 2017, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

`include "platform_if.vh"
`include "afu_json_info.vh"
`include "vai_timeslicing.vh"
`ifdef WITH_MUX
    `define MEMBENCH_TOP_IFC_NAME `MEMBENCH_WITHMUX_NAME
`else
    `define MEMBENCH_TOP_IFC_NAME `MEMBENCH_NOMUX_NAME
`endif
module `MEMBENCH_TOP_IFC_NAME
   (
    // CCI-P Clocks and Resets
    input           logic             pClk,              // 400MHz - CCI-P clock domain. Primary interface clock
    input           logic             pClkDiv2,          // 200MHz - CCI-P clock domain.
    input           logic             pClkDiv4,          // 100MHz - CCI-P clock domain.
    input           logic             uClk_usr,          // User clock domain. Refer to clock programming guide  ** Currently provides fixed 300MHz clock **
    input           logic             uClk_usrDiv2,      // User clock domain. Half the programmed frequency  ** Currently provides fixed 150MHz clock **
    input           logic             pck_cp2af_softReset,      // CCI-P ACTIVE HIGH Soft Reset
    input           logic [1:0]       pck_cp2af_pwrState,       // CCI-P AFU Power State
    input           logic             pck_cp2af_error,          // CCI-P Protocol Error Detected

    // Interface structures
    input           t_if_ccip_Rx      pck_cp2af_sRx,        // CCI-P Rx Port
    output          t_if_ccip_Tx      pck_af2cp_sTx         // CCI-P Tx Port
    );


    //
    // Run the entire design at the standard CCI-P frequency (400 MHz).
    //
    logic clk;
    assign clk = pClk;

    // =========================================================================
    //
    //   Register requests.
    //
    // =========================================================================

    //
    // The incoming pck_cp2af_sRx and outgoing pck_af2cp_sTx must both be
    // registered.  Here we register pck_cp2af_sRx and assign it to sRx.
    // We also assign pck_af2cp_sTx to sTx here but don't register it.
    // The code below never uses combinational logic to write sTx.
    //

    t_if_ccip_Rx sRx;
    always_ff @(posedge clk)
    begin
        sRx <= pck_cp2af_sRx;
    end

    t_if_ccip_Tx sTx;
    assign pck_af2cp_sTx = sTx;


    // =========================================================================
    //
    //   CSR (MMIO) handling.
    //
    // =========================================================================

    // The AFU ID is a unique ID for a given program.  Here we generated
    // one with the "uuidgen" program and stored it in the AFU's JSON file.
    // ASE and synthesis setup scripts automatically invoke afu_json_mgr
    // to extract the UUID into afu_json_info.vh.
    logic [127:0] afu_id = `AFU_ACCEL_UUID;

    //
    // A valid AFU must implement a device feature list, starting at MMIO
    // address 0.  Every entry in the feature list begins with 5 64-bit
    // words: a device feature header, two AFU UUID words and two reserved
    // words.
    //

    // Is a CSR read request active this cycle?
    logic is_csr_read;
    assign is_csr_read = sRx.c0.mmioRdValid;

    // Is a CSR write request active this cycle?
    logic is_csr_write;
    assign is_csr_write = sRx.c0.mmioWrValid;

    // The MMIO request header is overlayed on the normal c0 memory read
    // response data structure.  Cast the c0Rx header to an MMIO request
    // header.
    t_ccip_c0_ReqMmioHdr mmio_req_hdr;
    assign mmio_req_hdr = t_ccip_c0_ReqMmioHdr'(sRx.c0.hdr);


    //
    // Implement the device feature list by responding to MMIO reads.
    //
    //------------------ Config ---------------------------
    localparam MDATA_WIDTH = 12;
    //------------------ RO -------------------------------
    //time slicing status 0 means idle, 1 means running, 2 means done
    // placeholder: MMIO_CSR_MEM_BASE 16'h0
    // placeholder: MMIO_CSR_LEN_MASK 16'h8
    // placeholder: MMIO_CSR_READ_TOTAL 16'h10
    // placeholder: MMIO_CSR_WRITE_TOTAL 16'h18
    // placeholder: MMIO_CSR_PROPERTIES 16'h20
    // how many read requests have been issued and served
    localparam MMIO_CSR_READ_CNT = `TSCSR_USR(16'h28);
    // how many write requests have been issued and served
    localparam MMIO_CSR_WRITE_CNT = `TSCSR_USR(16'h30);
    // how many cycles have passed since write 1 to MMIO_CSR_CTL
    localparam MMIO_CSR_CLK_CNT = `TSCSR_USR(16'h38);
    localparam MMIO_CSR_STATE = `TSCSR_USR(16'h40);
    localparam MMIO_CSR_REPORT_RECCNT = `TSCSR_USR(16'h48);
    localparam MMIO_CSR_RDRSP_CNT = `TSCSR_USR(16'h50);
    localparam MMIO_CSR_WRRSP_CNT = `TSCSR_USR(16'h58);
    //------------------ WO -------------------------------
    // The base address
    localparam MMIO_CSR_MEM_BASE = `TSCSR_USR(16'h0);
    // All access will be masked by this:
    // offset = rand() & len_mask; base_addr[offset] = xxx.
    localparam MMIO_CSR_LEN_MASK = `TSCSR_USR(16'h8);
    // how many read requests will be issued in total
    localparam MMIO_CSR_READ_TOTAL = `TSCSR_USR(16'h10);
    // how many write requests will be issued in total
    localparam MMIO_CSR_WRITE_TOTAL = `TSCSR_USR(16'h18);
    // Read VA: 0:1, Write VA: 2:3
    // Read Cache Hint: 4:7, Write Cache Hint 8:11
    // Access pattern: 12:12, 0: sequential 1: random
    // Read Len: 14:13, 0: eCL_LEN_1 1: eCL_LEN_2 2: eCL_LEN_4
    localparam MMIO_CSR_PROPERTIES = `TSCSR_USR(16'h20);
    localparam MMIO_CSR_RAND_SEED_0 = `TSCSR_USR(16'h28);
    localparam MMIO_CSR_RAND_SEED_1 = `TSCSR_USR(16'h30);
    localparam MMIO_CSR_RAND_SEED_2 = `TSCSR_USR(16'h38);
    localparam MMIO_CSR_STATUS_ADDR = `TSCSR_USR(16'h40);
    // filter out the latency of accesses to which pages will be recorded
    localparam MMIO_CSR_REC_FILTER = `TSCSR_USR(16'h48);
    localparam MMIO_CSR_SEQ_START_OFFSET = `TSCSR_USR(16'h50);
    //------------------ Default value--------------------
    // Memory address to which this AFU will write.
    localparam DEFAULT_CSR_MEM_BASE = t_ccip_clAddr'(0);
    localparam DEFAULT_RAND_SEED_0 = 64'h812765dd017492a3;
    localparam DEFAULT_RAND_SEED_1 = 64'hdb2042bc38c704e3;
    localparam DEFAULT_RAND_SEED_2 = 64'h39e8e59c761c69c6;
    localparam RECFILTER_WIDTH = 10;
    localparam PAGE_IDX_WIDTH = 6;
    localparam RW_CNT_WIDTH = 64;
    localparam STATE_SIZE_PG = 1;
    t_ccip_clAddr base_addr, report_addr, status_addr, snapshot_addr;
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
    logic [31:0] seq_rd_inc;

    t_transaction_state csr_ts_state;
    logic csr_ctl_start, csr_ctl_resume, csr_ctl_pause;
    // explicitly use one more bit as sentinel
    logic [$clog2(RECORD_NUM):0] reccnt, report_reccnt, c0Rx_reccnt, c1Rx_reccnt;
    logic report_done, finish_done; // finish_done is set after write complete bit
    typedef enum logic [2:0]
    {
        STATE_IDLE,
        STATE_RESUME,
        STATE_RUN,
        STATE_REPORT,
        STATE_PAUSE,
        STATE_FINISH
    } t_state;
    t_state state;

    logic reset;
    assign reset = pck_cp2af_softReset;

    // handling MMIO Read
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            sTx.c2.mmioRdValid <= 1'b0;
        end
        else
        begin
            // Always respond with something for every read request
            sTx.c2.mmioRdValid <= is_csr_read;

            // The unique transaction ID matches responses to requests
            sTx.c2.hdr.tid <= mmio_req_hdr.tid;

            // Addresses are of 32-bit objects in MMIO space.  Addresses
            // of 64-bit objects are thus multiples of 2.
            case (mmio_req_hdr.address)
                0: // AFU DFH (device feature header)
                begin
                    // Here we define a trivial feature list.  In this
                    // example, our AFU is the only entry in this list.
                    sTx.c2.data <= t_ccip_mmioData'(0);
                    // Feature type is AFU
                    sTx.c2.data[63:60] <= 4'h1;
                    // End of list (last entry in list)
                    sTx.c2.data[40] <= 1'b1;
                end

                // AFU_ID_L
                2: sTx.c2.data <= afu_id[63:0];

                // AFU_ID_H
                4: sTx.c2.data <= afu_id[127:64];

                MMIO_CSR_TRANSACTION_STATE: sTx.c2.data <= t_ccip_mmioData'(csr_ts_state);
                MMIO_CSR_STATE_SIZE_PG: sTx.c2.data <= t_ccip_mmioData'(STATE_SIZE_PG);
                MMIO_CSR_MEM_BASE: sTx.c2.data <= t_ccip_mmioData'(base_addr);
                MMIO_CSR_LEN_MASK: sTx.c2.data <= t_ccip_mmioData'({32'h0, len_mask});
                MMIO_CSR_READ_TOTAL: sTx.c2.data <= t_ccip_mmioData'(read_total);
                MMIO_CSR_WRITE_TOTAL: sTx.c2.data <= t_ccip_mmioData'(write_total);
                MMIO_CSR_PROPERTIES: sTx.c2.data <= t_ccip_mmioData'(csr_properties);
                MMIO_CSR_CLK_CNT: sTx.c2.data <= t_ccip_mmioData'(clk_cnt);
                MMIO_CSR_READ_CNT: sTx.c2.data <= t_ccip_mmioData'(read_cnt);
                MMIO_CSR_WRITE_CNT: sTx.c2.data <= t_ccip_mmioData'(write_cnt);
                MMIO_CSR_STATE: begin
                    sTx.c2.data[1:0] <= state;
                    sTx.c2.data[2] <= report_done;
                    sTx.c2.data[63:3] <= 0;
                end
                MMIO_CSR_REPORT_RECCNT: begin
                    sTx.c2.data[31:0] <= reccnt;
                    sTx.c2.data[63:32] <= report_reccnt;
                end
                MMIO_CSR_RDRSP_CNT: begin
                    sTx.c2.data <= t_ccip_mmioData'(rdrsp_cnt);
                end
                MMIO_CSR_WRRSP_CNT: begin
                    sTx.c2.data <= t_ccip_mmioData'(wrrsp_cnt);
                end
                default: sTx.c2.data <= t_ccip_mmioData'(0);
            endcase
        end
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
            csr_ctl_start <= 1'b0;
            access_pattern <= 0;
            read_type <= 0;
            seq_start_addr <= 0;
        end
        else begin
            csr_ctl_start <= is_csr_write && (mmio_req_hdr.address == MMIO_CSR_TRANSACTION_CTL) && (t_transaction_ctl'(sRx.c0.data) == tsctlSTART_NEW);
            csr_ctl_resume <= is_csr_write && (mmio_req_hdr.address == MMIO_CSR_TRANSACTION_CTL) && (t_transaction_ctl'(sRx.c0.data) == tsctlSTART_RESUME);
            csr_ctl_pause <= is_csr_write && (mmio_req_hdr.address == MMIO_CSR_TRANSACTION_CTL) && (t_transaction_ctl'(sRx.c0.data) == tsctlPAUSE);
            if (is_csr_write)
                begin
                    case(mmio_req_hdr.address)
                        MMIO_CSR_MEM_BASE: base_addr <= t_ccip_clAddr'(sRx.c0.data);
                        MMIO_CSR_LEN_MASK: len_mask <= sRx.c0.data[31:0];
                        MMIO_CSR_REC_FILTER: rec_filter <= sRx.c0.data[25:0];
                        MMIO_CSR_READ_TOTAL: read_total <= sRx.c0.data;
                        MMIO_CSR_WRITE_TOTAL: write_total <= sRx.c0.data;
                        // Read VA: 0:1, Write VA: 2:3
                        // Read Cache Hint: 4:7, Write Cache Hint 8:11
                        // Access pattern: 12:12, 0: sequential 1: random
                        // Read Len: 14:13, 0: eCL_LEN_1 1: eCL_LEN_2 2: eCL_LEN_4
                        MMIO_CSR_PROPERTIES: begin
                            case (sRx.c0.data[1:0]) // read_vc
                                2'b00: read_vc <= eVC_VA;
                                2'b01: read_vc <= eVC_VL0;
                                2'b10: read_vc <= eVC_VH0;
                                2'b11: read_vc <= eVC_VH1;
                            endcase
                            case (sRx.c0.data[3:2]) // write_vc
                                2'b00: write_vc <= eVC_VA;
                                2'b01: write_vc <= eVC_VL0;
                                2'b10: write_vc <= eVC_VH0;
                                2'b11: write_vc <= eVC_VH1;
                            endcase
                            case (sRx.c0.data[7:4]) // read_hint
                                4'h0: read_hint <= eREQ_RDLINE_I;
                                4'h1: read_hint <= eREQ_RDLINE_S;
                                default: read_hint <= eREQ_RDLINE_I;
                            endcase
                            case (sRx.c0.data[11:8]) // write_hint
                                4'h0: write_hint <= eREQ_WRLINE_I;
                                4'h1: write_hint <= eREQ_WRLINE_M;
                                4'h2: write_hint <= eREQ_WRPUSH_I;
                                4'h4: write_hint <= eREQ_WRFENCE;
                                4'h6: write_hint <= eREQ_INTR;
                                default: write_hint <= eREQ_WRLINE_I;
                            endcase
                            access_pattern <= sRx.c0.data[12];
                            read_type <= sRx.c0.data[14:13];
                            case (sRx.c0.data[14:13])
                                    default: // eCL_LEN_1
                                        seq_rd_inc <= 1;
                                    1: // eCL_LEN_2
                                        seq_rd_inc <= 2;
                                    2: // eCL_LEN_4
                                        seq_rd_inc <= 4;
                            endcase
                        end
                        MMIO_CSR_RAND_SEED_0: rand_seed[0] <= sRx.c0.data;
                        MMIO_CSR_RAND_SEED_1: rand_seed[1] <= sRx.c0.data;
                        MMIO_CSR_RAND_SEED_2: rand_seed[2] <= sRx.c0.data;
                        MMIO_CSR_STATUS_ADDR: status_addr <= t_ccip_clAddr'(sRx.c0.data);
                        MMIO_CSR_SEQ_START_OFFSET: seq_start_addr <= sRx.c0.data[31:0];
                        MMIO_CSR_SNAPSHOT_ADDR: snapshot_addr <= t_ccip_clAddr'(sRx.c0.data);
                    endcase
                end
        end
    end
    


    // =========================================================================
    //
    //   Main AFU logic
    //
    // =========================================================================

    typedef struct packed {
        logic[63:0] clk_cnt;
        logic[RW_CNT_WIDTH-1:0] rdrsp_cnt;
        logic[RW_CNT_WIDTH-1:0] wrrsp_cnt;
    } t_snapshot;
    t_snapshot snapshot_resumed;
    t_snapshot snapshot_toresume;
    assign snapshot_toresume.clk_cnt = clk_cnt;
    assign snapshot_toresume.rdrsp_cnt = rdrsp_cnt;
    assign snapshot_toresume.wrrsp_cnt = wrrsp_cnt;
    logic read_done, write_done, can_read, can_write, do_read, do_write, rdrsp_done, wrrsp_done;
    logic pause_complete, resume_complete;
    logic resume_rdreq_sent, pause_wrreq_sent;
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
            csr_ts_state <= tsIDLE;
        end
        else
        begin
            // Trigger the AFU when start signal is wrote to CSR_CTL. (After
            // the CPU tells us where the FPGA should read, write how much
            // cachelines.)
            case (state)
                STATE_IDLE:
                begin
                    if (csr_ctl_start)
                    begin
                        state <= STATE_RUN;
                        csr_ts_state <= tsRUNNING;
                        clk_cnt <= 64'h0;
                        $display("AFU running...");
                    end
                    if (csr_ctl_resume)
                    begin
                        state <= STATE_RESUME;
                        csr_ts_state <= tsRUNNING;
                        $display("AFU resumming...");
                    end
                end
                STATE_RESUME:
                begin
                    if (resume_complete) begin
                        clk_cnt <= snapshot_resumed.clk_cnt;
                        state <= STATE_RUN;
                        $display("AFU resume complete...");
                    end
                end
                STATE_RUN:
                begin
                    // The AFU completes its task by writing a single line.  When
                    // the line is written return to idle.  The write will happen
                    // as long as the request channel is not full.
                    if (read_done && write_done && rdrsp_done && wrrsp_done)
                    begin
                        state <= STATE_REPORT;
                        $display("AFU reporting...");
                    end
                    if (csr_ctl_pause)
                    begin
                        state <= STATE_PAUSE;
                    end
                    clk_cnt <= clk_cnt + 1;
                end
                STATE_PAUSE:
                    if (pause_complete) begin
                        csr_ts_state <= tsPAUSED;
                        state <= STATE_IDLE;
                        $display("AFU Paused completely...");
                    end
                STATE_REPORT:
                    if (report_done)
                    begin
                        csr_ts_state <= tsRUNNING;
                        state <= STATE_FINISH;
                    end
                STATE_FINISH:
                    if (finish_done)
                    begin
                        csr_ts_state <= tsFINISH;
                        state <= STATE_IDLE;
                        $display("AFU done...");
                    end
            endcase
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
        else if (state == STATE_RUN) begin
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

    // for preemption
    localparam PAUSE_MDATA_MAGIC = RECORD_NUM + 1;
    localparam RESUME_MDATA_MAGIC = RECORD_NUM + 2;
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
            resume_rdreq_sent <= 0;
            pause_wrreq_sent <= 0;
        end
        else
        begin
            should_rec_Q <= (state == STATE_RUN) && (do_read_Q | do_write_Q) && should_rec;
            if (should_rec_Q) begin
                latbgn[reccnt_Q] <= latbgn_Q;
            end
            resume_rdreq_sent <= sRx.c0TxAlmFull? resume_rdreq_sent: (state == STATE_RESUME);
            pause_wrreq_sent <= sRx.c1TxAlmFull? pause_wrreq_sent: (state == STATE_PAUSE);
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
                STATE_RESUME: begin
                    sTx.c0.valid <= (!sRx.c0TxAlmFull && !resume_rdreq_sent);
                    sTx.c0.hdr.req_type <= eREQ_RDLINE_I;
                    sTx.c0.hdr.address <= snapshot_addr;
                    sTx.c0.hdr.vc_sel <= read_vc;
                    sTx.c0.hdr.cl_len <= eCL_LEN_1;
                    sTx.c0.hdr.mdata <= RESUME_MDATA_MAGIC;
                    if (resume_complete) begin
                        read_cnt <= snapshot_resumed.rdrsp_cnt;
                        write_cnt <= snapshot_resumed.wrrsp_cnt;
                    end
                end
                STATE_PAUSE: begin
                    sTx.c1.valid <= (!sRx.c1TxAlmFull && !pause_wrreq_sent);
                    sTx.c1.hdr.req_type <= eREQ_WRLINE_I;
                    sTx.c1.hdr.vc_sel <= write_vc;
                    sTx.c1.hdr.address <= snapshot_addr;
                    sTx.c1.hdr.sop <= 1'b1;
                    sTx.c1.hdr.cl_len <= eCL_LEN_1;
                    sTx.c1.hdr.mdata <= PAUSE_MDATA_MAGIC;
                    sTx.c1.data <= t_ccip_clData'(snapshot_toresume);
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
            snapshot_resumed <= 0;
            resume_complete <= 0;
            pause_complete <= 0;
        end
        else begin
            resume_complete <= sRx.c0.rspValid  && (sRx.c0.hdr.mdata == RESUME_MDATA_MAGIC) && (state == STATE_RESUME);
            pause_complete <= sRx.c1.rspValid && (sRx.c1.hdr.mdata == PAUSE_MDATA_MAGIC) && (state == STATE_PAUSE);
            case (state)
                STATE_RUN:
                begin
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
                STATE_RESUME: begin
                    if (sRx.c0.rspValid) begin
                        snapshot_resumed <= t_snapshot'(sRx.c0.data);
                    end
                    if (resume_complete) begin
                        rdrsp_cnt <= snapshot_resumed.rdrsp_cnt;
                        wrrsp_cnt <= snapshot_resumed.wrrsp_cnt;
                    end
                end
            endcase
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
                seq_addr <= seq_addr + seq_rd_inc;
            end
            else if (do_write) begin
                seq_addr <= seq_addr + 1;
            end
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
	end
    end
    always_ff @(posedge clk) begin
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
endmodule
