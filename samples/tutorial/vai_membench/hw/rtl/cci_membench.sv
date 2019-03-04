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


module ccip_std_afu
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
    localparam MMIO_CSR_TS_STATE = 16'h18 >> 2;
    // placeholder: MMIO_CSR_MEM_BASE 16'h20
    // placeholder: MMIO_CSR_LEN_MASK 16'h28
    // placeholder: MMIO_CSR_READ_TOTAL 16'h30
    // placeholder: MMIO_CSR_WRITE_TOTAL 16'h38
    // placeholder: MMIO_CSR_PROPERTIES 16'h40
    // how many read requests have been issued and served
    localparam MMIO_CSR_READ_CNT = 16'h48 >> 2;
    // how many write requests have been issued and served
    localparam MMIO_CSR_WRITE_CNT = 16'h50 >> 2;
    // how many cycles have passed since write 1 to MMIO_CSR_CTL
    localparam MMIO_CSR_CLK_CNT = 16'h58 >> 2;
    //------------------ WO -------------------------------
    // write 1 to start the AFU
    localparam MMIO_CSR_CTL = 16'h018 >> 2;
    // The base address
    localparam MMIO_CSR_MEM_BASE = 16'h20 >> 2;
    // All access will be masked by this:
    // offset = rand() & len_mask; base_addr[offset] = xxx.
    localparam MMIO_CSR_LEN_MASK = 16'h28 >> 2;
    // how many read requests will be issued in total
    localparam MMIO_CSR_READ_TOTAL = 16'h30 >> 2;
    // how many write requests will be issued in total
    localparam MMIO_CSR_WRITE_TOTAL = 16'h38 >> 2;
    // Read VA: 0:1, Write VA: 2:3
    // Read Cache Hint: 4:7, Write Cache Hint 8:11
    localparam MMIO_CSR_PROPERTIES = 16'h40 >> 2;
    localparam MMIO_CSR_RAND_SEED_0 = 16'h48 >> 2;
    localparam MMIO_CSR_RAND_SEED_1 = 16'h50 >> 2;
    localparam MMIO_CSR_RAND_SEED_2 = 16'h58 >> 2;
    localparam MMIO_CSR_REPORT_ADDR = 16'h60 >> 2;
    //------------------ Default value--------------------
    // Memory address to which this AFU will write.
    localparam DEFAULT_CSR_MEM_BASE = t_ccip_clAddr'(0);
    localparam DEFAULT_LEN_MASK = 32'h0;
    localparam DEFAULT_RAND_SEED_0 = 64'h812765dd017492a3;
    localparam DEFAULT_RAND_SEED_1 = 64'hdb2042bc38c704e3;
    localparam DEFAULT_RAND_SEED_2 = 64'h39e8e59c761c69c6;
    t_ccip_clAddr base_addr, report_addr;
    logic [31:0] len_mask;
    logic [63:0] clk_cnt;
    logic [63:0] read_cnt,  read_total;
    logic [63:0] write_cnt, write_total;
    logic [63:0] csr_properties;
    t_ccip_vc read_vc, write_vc;
    t_ccip_c0_req read_hint;
    t_ccip_c1_req write_hint;
    assign csr_properties = {write_hint[3:0], read_hint[3:0], write_vc[1:0], read_vc[1:0]};

    logic [63:0] rand_seed [0:2];
    logic [31:0] random32;
    logic random_valid;

    localparam CSR_TS_IDLE = 2'h0;
    localparam CSR_TS_RUNNING = 2'h1;
    localparam CSR_TS_DONE = 2'h2;
    logic [1:0] csr_ts_state;
    logic csr_ctl_start;
    logic xor_reset;
    typedef enum logic [1:0]
    {
        STATE_IDLE,
        STATE_REPORT,
        STATE_RUN
    }
    t_state;
    t_state state;

    logic reset;
    assign reset = pck_cp2af_softReset;

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
                    sTx.c2.data[11:0] <= `AFU_IMAGE_VAI_MAGIC;
                end

                // AFU_ID_L
                2: sTx.c2.data <= afu_id[63:0];

                // AFU_ID_H
                4: sTx.c2.data <= afu_id[127:64];

                MMIO_CSR_TS_STATE: sTx.c2.data <= t_ccip_mmioData'({62'h0, csr_ts_state});
                MMIO_CSR_MEM_BASE: sTx.c2.data <= t_ccip_mmioData'(base_addr);
                MMIO_CSR_LEN_MASK: sTx.c2.data <= t_ccip_mmioData'({32'h0, len_mask});
                MMIO_CSR_READ_TOTAL: sTx.c2.data <= t_ccip_mmioData'(read_total);
                MMIO_CSR_WRITE_TOTAL: sTx.c2.data <= t_ccip_mmioData'(write_total);
                MMIO_CSR_PROPERTIES: sTx.c2.data <= t_ccip_mmioData'(csr_properties);
                MMIO_CSR_CLK_CNT: sTx.c2.data <= t_ccip_mmioData'(clk_cnt);
                MMIO_CSR_READ_CNT: sTx.c2.data <= t_ccip_mmioData'(read_cnt);
                MMIO_CSR_WRITE_CNT: sTx.c2.data <= t_ccip_mmioData'(write_cnt);

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
            len_mask <= DEFAULT_LEN_MASK;
            read_total <= 64'h0;
            write_total <= 64'h0;
            rand_seed[0] <= DEFAULT_RAND_SEED_0;
            rand_seed[1] <= DEFAULT_RAND_SEED_1;
            rand_seed[2] <= DEFAULT_RAND_SEED_2;
            csr_ctl_start <= 1'b0;
        end
        else if (is_csr_write)
        begin
            case(mmio_req_hdr.address)
                MMIO_CSR_MEM_BASE: base_addr <= t_ccip_clAddr'(sRx.c0.data);
                MMIO_CSR_LEN_MASK: len_mask <= sRx.c0.data[31:0];
                MMIO_CSR_READ_TOTAL: read_total <= sRx.c0.data;
                MMIO_CSR_WRITE_TOTAL: write_total <= sRx.c0.data;
                // Read VA: 0:1, Write VA: 2:3
                // Read Cache Hint: 4:7, Write Cache Hint 8:11
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
                end
                MMIO_CSR_RAND_SEED_0: rand_seed[0] <= sRx.c0.data;
                MMIO_CSR_RAND_SEED_1: rand_seed[1] <= sRx.c0.data;
                MMIO_CSR_RAND_SEED_2: rand_seed[2] <= sRx.c0.data;
                MMIO_CSR_REPORT_ADDR: report_addr <= t_ccip_clAddr'(sRx.c0.data);
                MMIO_CSR_CTL: csr_ctl_start <= sRx.c0.data[0];
                default:
                begin
                    csr_ctl_start <= 1'b0;
                end
            endcase
        end
        else
        begin
            csr_ctl_start <= 1'b0;
        end
    end
    


    // =========================================================================
    //
    //   Main AFU logic
    //
    // =========================================================================

    logic read_done, write_done, can_read, can_write, do_read, do_write;
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
            xor_reset <= 1'b1;
        end
        else
        begin
            // Trigger the AFU when start signal is wrote to CSR_CTL. (After
            // the CPU tells us where the FPGA should read, write how much
            // cachelines.)
            if ((state == STATE_IDLE) && csr_ctl_start)
            begin
                state <= STATE_RUN;
                xor_reset <= 1'b0;
                csr_ts_state <= CSR_TS_RUNNING;
                clk_cnt <= 64'h0;
                $display("AFU running...");
            end
            if (state == STATE_RUN)
                clk_cnt <= clk_cnt + 1;
            // The AFU completes its task by writing a single line.  When
            // the line is written return to idle.  The write will happen
            // as long as the request channel is not full.
            if ((state == STATE_RUN) && read_done && write_done)
            begin
                state <= STATE_REPORT;
                $display("AFU reporting...");
            end
            if ((state == STATE_REPORT))
            begin
                csr_ts_state <= CSR_TS_DONE;
                state <= STATE_IDLE;
                $display("AFU done...");
            end
        end
    end

    // rw_priority: 0 means read first, 1 means write first
    logic rw_priority;
    assign read_done = (read_cnt >= read_total);
    assign write_done = (write_cnt >= write_total);
    assign can_read = (!sRx.c0TxAlmFull) && (!read_done);
    assign can_write = (!sRx.c1TxAlmFull) && (!write_done);
    assign do_read = random_valid && can_read && !(can_write && rw_priority);
    assign do_write = random_valid && can_write && !(can_read && !rw_priority);
    t_ccip_clAddr next_addr;
    logic [31:0] random_offset;
    assign random_offset = (random32 & len_mask);
    assign next_addr = base_addr + random_offset;
    always_ff @(posedge clk)
    begin
        if (reset) begin rw_priority <= 1'b0; end
        else begin rw_priority <= rw_priority? !do_write: do_read; end
    end
    /*
     * send memory read requests
     */
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            sTx.c0.valid <= 1'b0;
            sTx.c0.hdr <= t_ccip_c0_ReqMemHdr'(0);
        end
        if (state == STATE_RUN && do_read)
        begin
            sTx.c0.valid <= 1'b1;
            sTx.c0.hdr.vc_sel <= read_vc;
            sTx.c0.hdr.cl_len <= eCL_LEN_1;
            sTx.c0.hdr.req_type <= read_hint;
            sTx.c0.hdr.address <= next_addr;
            sTx.c0.hdr.mdata <= random_offset[MDATA_WIDTH-1:0]; // this counter will wrap around at 0x7fff
        end
        else begin
            sTx.c0.valid <= 1'b0;
            sTx.c0.hdr <= t_ccip_c0_ReqMemHdr'(0);
        end
    end
    // received memory read response
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            read_cnt <= 64'h0;
        end
        if (sRx.c0.rspValid == 1'b1)
        begin
            read_cnt <= read_cnt + 1;
        end
    end
    /*
     * send memory write requests
     */
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            sTx.c1.valid <= 1'b0;
            sTx.c1.hdr <= t_ccip_c1_ReqMemHdr'(0);
            sTx.c1.data <= 0;
        end
        if (state == STATE_RUN && do_write)
        begin
            sTx.c1.valid <= 1'b1;
            sTx.c1.hdr.vc_sel <= write_vc;
            sTx.c1.hdr.sop <= 1'b1;
            sTx.c1.hdr.cl_len <= eCL_LEN_1;
            sTx.c1.hdr.req_type <= write_hint;
            sTx.c1.hdr.address <= next_addr;
            sTx.c1.hdr.mdata <= random_offset[MDATA_WIDTH-1:0];
            sTx.c1.data <= random_offset;
        end
        // TODO record latency per request
        else if (state == STATE_REPORT)
        begin
            sTx.c1.valid <= 1'b1;
            sTx.c1.hdr.vc_sel <= eVC_VL0;
            sTx.c1.hdr.sop <= 1'b1;
            sTx.c1.hdr.cl_len <= eCL_LEN_1;
            sTx.c1.hdr.req_type <= eREQ_WRLINE_I;
            sTx.c1.hdr.address <= report_addr;
            sTx.c1.hdr.mdata <= t_ccip_mdata'(0);
            sTx.c1.data[0] <= 1'b1;
            sTx.c1.data[127:64] <= clk_cnt;
        end
        else begin
            sTx.c1.valid <= 1'b0;
        end
    end
    /*
     * handle memory write response
     */
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            write_cnt <= 64'h0;
        end
        else if ( sRx.c1.rspValid == 1'b1)
        begin
            write_cnt <= write_cnt + 1;
        end
    end
    /*
     * random number generator
     */

    logic [31:0] init_state[0:4];
    assign init_state[0] = rand_seed[0][31:0];
    assign init_state[1] = rand_seed[0][63:32];
    assign init_state[2] = rand_seed[1][31:0];
    assign init_state[3] = rand_seed[1][63:32];
    assign init_state[4] = rand_seed[2][31:0];
    xorwow #(.WIDTH(32)) xw(
        .clk(clk),
        .reset(xor_reset),
        .init_state(init_state),
        .random(random32),
        .valid(random_valid)
    );
endmodule
