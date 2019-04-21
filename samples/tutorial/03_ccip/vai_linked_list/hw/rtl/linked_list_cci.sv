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

`include "cci_mpf_if.vh"
`include "csr_mgr.vh"
`include "afu_json_info.vh"
`include "vai_timeslicing.vh"

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

	vai_linked_list_top app_cci(
        .clk(clk),
        .reset(reset),
        .csrs,
        .cp2af_sRx(mpf2af_sRx),
        .af2cp_sTx(af2mpf_sTx)
        );

endmodule
        


module vai_linked_list_top
   (
    // CCI-P Clocks and Resets
    input           logic             clk,              // 400MHz - CCI-P clock domain. Primary interface clock
    input           logic             reset,
    app_csrs.app csrs,
    // Interface structures
    input           t_if_ccip_Rx      cp2af_sRx,        // CCI-P Rx Port
    output          t_if_ccip_Tx      af2cp_sTx         // CCI-P Tx Port
    );


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
        sRx <= cp2af_sRx;
    end

    t_if_ccip_Tx sTx;
    always_comb
    begin
        af2cp_sTx = sTx;
        af2cp_sTx.c2.mmioRdValid = 0;
    end


    // The MMIO request header is overlayed on the normal c0 memory read
    // response data structure.  Cast the c0Rx header to an MMIO request
    // header.
    t_ccip_c0_ReqMmioHdr mmio_req_hdr;
    assign mmio_req_hdr = t_ccip_c0_ReqMmioHdr'(sRx.c0.hdr);

    function automatic logic ccip_c0Rx_isReadRsp(input t_if_ccip_c0_Rx r);
        return r.rspValid && (r.hdr.resp_type == eRSP_RDLINE);
    endfunction
    //
    // MMIO reads.
    //

    localparam MMIO_CSR_CNT_LIST_LENGTH = 0;
    localparam MMIO_CSR_CLK_CNT = 1;
    localparam MMIO_CSR_RESULT_ADDR = 2;
    localparam MMIO_CSR_START_ADDR = 3;
    localparam MMIO_CSR_PROPERTIES = 4;
    localparam MMIO_CSR_TRANSACTION_STATE = 5;
    localparam MMIO_CSR_STATE_SIZE_PG = 6;
    localparam MMIO_CSR_TRANSACTION_CTL = 7;
    localparam MMIO_CSR_SNAPSHOT_ADDR = 8;

    localparam STATE_SIZE_PG = 1;

    logic [63:0] clk_cnt;
    logic [31:0] cnt_list_length;
    t_transaction_state ts_state;
    t_ccip_vc read_vc;
    t_ccip_mmioData csr_properties;
    assign csr_properties = {62'h0, read_vc};

    always_comb
    begin
        csrs.afu_id = `AFU_ACCEL_UUID;

        for (int i = 0; i < NUM_APP_CSRS; i = i + 1)
        begin
            csrs.cpu_rd_csrs[i].data = 64'(0);
        end

        csrs.cpu_rd_csrs[MMIO_CSR_TRANSACTION_STATE].data = t_ccip_mmioData'(ts_state);
        csrs.cpu_rd_csrs[MMIO_CSR_STATE_SIZE_PG].data = t_ccip_mmioData'(STATE_SIZE_PG);
        csrs.cpu_rd_csrs[MMIO_CSR_CNT_LIST_LENGTH].data = t_ccip_mmioData'(cnt_list_length);
        csrs.cpu_rd_csrs[MMIO_CSR_PROPERTIES].data = t_ccip_mmioData'(csr_properties);
        csrs.cpu_rd_csrs[MMIO_CSR_CLK_CNT].data = t_ccip_mmioData'(clk_cnt);

    end

    //
    // CSR write handling.  Host software must tell the AFU the memory address
    // to which it should be writing.  The address is set by writing a CSR.
    //
    typedef struct packed {
        logic [63:0] clk_cnt;
        t_ccip_clAddr traversal_addr;
        logic [63:0] checksum;
        logic [31:0] cnt_list_length;
    } t_snapshot;
    t_ccip_clAddr start_traversal_addr;
    t_ccip_clAddr snapshot_addr;
    t_ccip_clAddr resumed_traversal_addr;
    t_ccip_clAddr result_addr;
    t_snapshot snapshot_resumed;
    t_snapshot snapshot_toresume;
    assign resumed_traversal_addr = snapshot_resumed.traversal_addr;
    logic start_traversal;
    logic resume_traversal;
    logic pause_traversal;

    always_ff @(posedge clk)
    begin
        if (csrs.cpu_wr_csrs[MMIO_CSR_TRANSACTION_CTL].en)
        begin
            case (t_transaction_ctl'(csrs.cpu_wr_csrs[MMIO_CSR_TRANSACTION_CTL].data))
                tsctlSTART_NEW:
                    start_traversal <= 1;
                tsctlSTART_RESUME:
                    resume_traversal <= 1;
                tsctlPAUSE:
                    pause_traversal <= 1;
                default: begin
                    start_traversal <= 0;
                    resume_traversal <= 0;
                    pause_traversal <= 0;
                end
            endcase
        end
        else
        begin
            start_traversal <= 0;
            resume_traversal <= 0;
            pause_traversal <= 0;
        end

        if (csrs.cpu_wr_csrs[MMIO_CSR_SNAPSHOT_ADDR].en)
        begin
            snapshot_addr <= t_ccip_clAddr'(csrs.cpu_wr_csrs[MMIO_CSR_SNAPSHOT_ADDR].data);
        end

        if (csrs.cpu_wr_csrs[MMIO_CSR_START_ADDR].en)
        begin
            start_traversal_addr <= t_ccip_clAddr'(csrs.cpu_wr_csrs[MMIO_CSR_START_ADDR].data);
        end
 
        if (csrs.cpu_wr_csrs[MMIO_CSR_RESULT_ADDR].en)
        begin
            result_addr <= t_ccip_clAddr'(csrs.cpu_wr_csrs[MMIO_CSR_RESULT_ADDR].data);
        end

        if (csrs.cpu_wr_csrs[MMIO_CSR_PROPERTIES].en)
        begin
            case (csrs.cpu_wr_csrs[MMIO_CSR_PROPERTIES].data[1:0]) // read_vc
                2'b00: read_vc <= eVC_VA;
                2'b01: read_vc <= eVC_VL0;
                2'b10: read_vc <= eVC_VH0;
            endcase
        end
 
    end


    // =========================================================================
    //
    //   State machine
    //
    // =========================================================================

    typedef enum logic [2:0]
    {
        STATE_IDLE,
        STATE_RESUME,
        STATE_RUN,
        STATE_END_OF_LIST,
        STATE_PAUSE,
        STATE_WRITE_RESULT
    }
    t_state;

    t_state state;
    // Status signals that affect state changes
    logic rd_end_of_list;
    logic rd_last_beat_received;
    logic resume_complete, pause_complete, write_complete;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            state <= STATE_IDLE;
            ts_state <= tsIDLE;
            clk_cnt <= 0;
        end
        else
        begin
            case (state)
                STATE_IDLE:
                begin
                    // Traversal begins when CSR 1 is written
                    if (start_traversal)
                    begin
                        state <= STATE_RUN;
                        ts_state <= tsRUNNING;
                        $display("AFU starting traversal at 0x%x", start_traversal_addr);
                    end
                    else if (resume_traversal)
                    begin
                        state <= STATE_RESUME;
                        ts_state <= tsRUNNING;
                        $display("AFU resume traversal from snapshot 0x%x", snapshot_addr);
                    end
                end

                STATE_RESUME:
                begin
                    if (resume_complete)
                    begin
                        state <= STATE_RUN;
                        clk_cnt <= snapshot_resumed.clk_cnt;
                        $display("AFU resumed traversal, start from 0x%x", resumed_traversal_addr);
                    end
                end

                STATE_RUN:
                begin
                    // rd_end_of_list is set when the "next" pointer
                    // in the linked list is NULL.
                    if (rd_end_of_list)
                    begin
                        state <= STATE_END_OF_LIST;
                        $display("AFU reached end of list");
                    end
                    if (pause_traversal)
                    begin
                        state <= STATE_PAUSE;
                        $display("AFU starts pausing");
                    end
                    clk_cnt <= clk_cnt + 1;
                end

                STATE_END_OF_LIST:
                begin
                    // The NULL pointer indicating the list end has been
                    // reached.  When the remainder of the record containing
                    // the NULL pointer has been processed completely it
                    // will be time to write the response.
                    if (rd_last_beat_received)
                    begin
                        state <= STATE_WRITE_RESULT;
                        $display("AFU write result to 0x%x", result_addr);
                    end
                end
                STATE_PAUSE:
                begin
                    if (pause_complete)
                    begin
                        state <= STATE_IDLE;
                        ts_state <= tsPAUSED;
                        $display("AFU paused completely");
                    end
                end
                STATE_WRITE_RESULT:
                begin
                    // The end of the list has been reached.  The AFU must
                    // write the computed hash to result_addr.  It is the
                    // only memory write the AFU will request.  The write
                    // will be triggered as soon as the pipeline can
                    // accept requests.
                    if (write_complete)
                    begin
                        state <= STATE_IDLE;
                        ts_state <= tsFINISH;
                        $display("AFU done");
                    end
                end
            endcase
        end
    end


    // =========================================================================
    //
    //   Read logic.
    //
    // =========================================================================

    //
    // READ REQUEST
    //

    // Did a read response just arrive containing a pointer to the next entry
    // in the list?
    logic addr_next_valid;

    // When a read response contains a next pointer, this is the next address.
    t_ccip_clAddr addr_next;
    t_ccip_clAddr current_addr;
    always_ff @(posedge clk)
    begin
        if (state == STATE_RUN)
        current_addr <= (
            start_traversal ? start_traversal_addr :
            (resume_complete ? resumed_traversal_addr :
            (addr_next_valid ? addr_next :
            current_addr)));
    end

    always_ff @(posedge clk)
    begin
        // Read response from the first line in a 4 line group?  The next
        // pointer is in the first line of each 4-line object.  The read
        // response header's cl_num is 0 for the first line.
        addr_next_valid <= ccip_c0Rx_isReadRsp(sRx.c0) &&
                           (sRx.c0.hdr.cl_num == t_ccip_clNum'(0));

        // Next address is in the low word of the line
        addr_next <= t_ccip_clAddr'({6'h0, sRx.c0.data[63:6]});

        // End of list reached if the next address is NULL.  This test
        // is a combination of the same state setting addr_next_valid
        // this cycle, with the addition of a test for a NULL next address.
        rd_end_of_list <= (t_ccip_clAddr'(sRx.c0.data[63:0]) == t_ccip_clAddr'(0)) &&
                           ccip_c0Rx_isReadRsp(sRx.c0) &&
                          (sRx.c0.hdr.cl_num == t_ccip_clNum'(0));
    end


    //
    // Since back pressure may prevent an immediate read request, we must
    // record whether a read is needed and hold it until the request can
    // be sent to the FIU.
    //
    t_ccip_clAddr rd_addr;
    logic rd_needed;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            rd_needed <= 1'b0;
        end
        else
        begin
            // If reads are allowed this cycle then we can safely clear
            // any previously requested reads.  This simple AFU has only
            // one read in flight at a time since it is walking a pointer
            // chain.
            if (rd_needed)
            begin
                rd_needed <= sRx.c0TxAlmFull;
            end
            else
            begin
                // Need a read under two conditions:
                //   - Starting a new walk
                //   - A read response just arrived from a line containing
                //     a next pointer.
                rd_needed <= (start_traversal || resume_complete || (addr_next_valid && ! rd_end_of_list));
                rd_addr <= (start_traversal ? start_traversal_addr : (resume_complete ? resumed_traversal_addr : addr_next));
            end
        end
    end


    //
    // Emit read requests to the FIU.
    //

    logic resume_rdreq_sent;
    // Send read requests to the FIU
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            sTx.c0.valid <= 1'b0;
            sTx.c0.hdr <= t_ccip_c0_ReqMmioHdr'(0);
            cnt_list_length <= 0;
            resume_rdreq_sent <= 0;
        end
        else
        begin
            resume_rdreq_sent <= sRx.c0TxAlmFull? resume_complete: (state == STATE_RESUME);
            case (state)
                STATE_RUN: begin
                    // Generate a read request when needed and the FIU isn't full
                    sTx.c0.valid <= (rd_needed && !sRx.c0TxAlmFull);
                    sTx.c0.hdr.req_type <= eREQ_RDLINE_I;
                    sTx.c0.hdr.address <= rd_addr;
                    sTx.c0.hdr.vc_sel <= read_vc;
                    sTx.c0.hdr.cl_len <= eCL_LEN_1;
                    if (rd_needed && ! sRx.c0TxAlmFull)
                    begin
                        cnt_list_length <= cnt_list_length + 1;
                        $display("  Reading from VA 0x%x", rd_addr);
                    end
                end
                STATE_RESUME: begin
                    if (resume_complete) begin
                        cnt_list_length <= snapshot_resumed.cnt_list_length - 1;
                    end
                    sTx.c0.valid <= (!sRx.c0TxAlmFull && !resume_rdreq_sent);
                    sTx.c0.hdr.req_type <= eREQ_RDLINE_I;
                    sTx.c0.hdr.address <= snapshot_addr;
                    sTx.c0.hdr.vc_sel <= read_vc;
                    sTx.c0.hdr.cl_len <= eCL_LEN_1;
                end
                default: begin
                    sTx.c0.valid <= 0;
                end
            endcase
        end
    end


    //
    // READ RESPONSE HANDLING
    //

    //
    // Registers requesting the addition of read data to the hash.
    //
    logic hash_data_en;
    logic [63:0] hash_data;
    // The cache-line number of the associated data is recorded in order
    // to figure out when reading is complete.  We will have read all
    // the data when the 4th beat of the final request is read.
    t_ccip_clNum hash_cl_num;

    //
    // Receive data (read responses).
    //
    always_ff @(posedge clk)
    begin
        if (reset) begin
            resume_complete <= 0;
        end
        else begin
            resume_complete <= (state == STATE_RESUME) && ccip_c0Rx_isReadRsp(sRx.c0);
            case (state)
                STATE_RUN: begin
                    // A read response is data if the cl_num is non-zero.  (When cl_num
                    // is zero the response is a pointer to the next record.)
                    hash_data_en <= (ccip_c0Rx_isReadRsp(sRx.c0));
                    hash_data <= sRx.c0.data[127:64];

                    if (ccip_c0Rx_isReadRsp(sRx.c0))
                    begin
                        $display("    Received entry v%0d: %0d",
                            sRx.c0.hdr.cl_num, sRx.c0.data[127:64]);
                    end
                end
                STATE_RESUME: begin
                    if (ccip_c0Rx_isReadRsp(sRx.c0)) begin
                        snapshot_resumed <= t_snapshot'(sRx.c0.data);
                    end
                end
            endcase
        end
    end


    //
    // Signal completion of reading a line.  The state machine consumes this
    // to transition from END_OF_LIST to WRITE_RESULT.
    //
    logic [31:0] total_cacheline;
    always_ff @(posedge clk)
    begin
        if (reset || start_traversal)
            total_cacheline <= 32'h1;
        else if (addr_next_valid && !rd_end_of_list)
            total_cacheline <= total_cacheline + 1;
    end
    logic [31:0] total_received;
    always_ff @(posedge clk)
    begin
        if (reset || start_traversal)
            total_received <= 32'h0;
        else if (ccip_c0Rx_isReadRsp(sRx.c0))
            total_received <= total_received + 1;
    end
    assign rd_last_beat_received = (total_received == total_cacheline);
    //
    // Compute a hash of the received data.
    //
    logic [63:0] checksum;
    always_ff @(posedge clk)
    begin
        if (reset || start_traversal)
            checksum <= 64'h0;
        else if (state == STATE_RESUME && resume_complete)
            checksum <= snapshot_resumed.checksum;
        else if (hash_data_en)
            checksum <= checksum + hash_data;
    end

    // =========================================================================
    //
    //   Write logic.
    //
    // =========================================================================

    // Construct a memory write request header.  For this AFU it is always
    // the same, since we write to only one address.
    t_ccip_c1_ReqMemHdr wr_hdr;

    always_comb
    begin
        wr_hdr = t_ccip_c1_ReqMemHdr'(0);

        // Write request type
        wr_hdr.req_type = eREQ_WRLINE_I;
        // Virtual address (MPF virtual addressing is enabled)
        wr_hdr.address = result_addr;
        // Let the FIU pick the channel
        wr_hdr.vc_sel = eVC_VA;
        // Write 1 line
        wr_hdr.cl_len = eCL_LEN_1;
        // Start of packet is true (single line write)
        wr_hdr.sop = 1'b1;
    end


    assign snapshot_toresume.traversal_addr = current_addr;
    assign snapshot_toresume.checksum = checksum;
    assign snapshot_toresume.clk_cnt = clk_cnt;
    assign snapshot_toresume.cnt_list_length = cnt_list_length;
    logic pause_write_req_sent, write_result_req_sent;
    // Control logic for memory writes
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            sTx.c1.valid <= 1'b0;
            sTx.c1.hdr <= t_ccip_c1_ReqMemHdr'(0);
            pause_write_req_sent <= 0;
            write_result_req_sent <= 0;
        end
        else
        begin
            sTx.c1.hdr.req_type = eREQ_WRLINE_I;
            sTx.c1.hdr.vc_sel = eVC_VL0;
            sTx.c1.hdr.cl_len = eCL_LEN_1;
            sTx.c1.hdr.sop = 1;
            // Request the write as long as the channel isn't full.
            case (state)
                STATE_PAUSE:
                begin
                    pause_write_req_sent <= sRx.c1TxAlmFull? pause_write_req_sent: 1;
                    sTx.c1.hdr.address <= snapshot_addr;
                    sTx.c1.data <= t_ccip_clData'(snapshot_toresume);
                    sTx.c1.valid <= (!sRx.c1TxAlmFull && !pause_write_req_sent);
                end
                STATE_WRITE_RESULT:
                begin
                    write_result_req_sent <= sRx.c1TxAlmFull? write_result_req_sent: 1;
                    sTx.c1.hdr.address <= result_addr;
                    // Data to write to memory.  The low word is a non-zero flag.  The
                    // CPU-side software will spin, waiting for this flag.  The computed
                    // hash is written in the 2nd 64 bit word.
                    sTx.c1.data <= t_ccip_clData'({clk_cnt, checksum, 64'h1});
                    sTx.c1.valid <= (!sRx.c1TxAlmFull && !write_result_req_sent);
                end
                default: begin
                    pause_write_req_sent <= 0;
                    write_result_req_sent <= 0;
                    sTx.c1.valid <= 0;
                end
            endcase
        end

    end
    // handle write response
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            pause_complete <= 0;
            write_complete <= 0;
        end
        else
        begin
            pause_complete <= (state == STATE_PAUSE) && (sRx.c1.rspValid);
            write_complete <= (state == STATE_WRITE_RESULT) && (sRx.c1.rspValid);
        end
    end
endmodule
