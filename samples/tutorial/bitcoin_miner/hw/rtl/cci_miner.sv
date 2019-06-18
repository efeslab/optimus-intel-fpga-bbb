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


module ccip_std_afu_async
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

    logic reset;
    assign reset = pck_cp2af_softReset;


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

    localparam BITCOIN_CSR_D1 = 6;
    localparam BITCOIN_CSR_D2 = 8;
    localparam BITCOIN_CSR_D3 = 10;
    localparam BITCOIN_CSR_D4 = 12;
    localparam BITCOIN_CSR_MD1 = 14;
    localparam BITCOIN_CSR_MD2 = 16;
    localparam BITCOIN_CSR_MD3 = 18;
    localparam BITCOIN_CSR_MD4 = 20;
    localparam BITCOIN_CSR_RESULT_ADDR = 22;

    localparam BITCOIN_CSR_CONTROL = 24;
    localparam BITCOIN_CSR_CURR_NONCE = 26;

    logic [31:0] nonce;
    logic [31:0] golden_nonce;
    logic [31:0] golden_nonce_buf;
    logic [31:0] cnt;
    logic golden_valid, golden_valid_q;
    logic miner_reset;

    //
    // Implement the device feature list by responding to MMIO reads.
    //

    logic [255:0] data, middata;
    logic [63:0] d1, d2, d3, d4, md1, md2, md3, md4;
    t_ccip_clAddr result_addr;

    assign data = {d1,d2,d3,d4};
    assign middata = {md1,md2,md3,md4};

    typedef enum logic [1:0] {
        STATE_IDLE,
        STATE_RUN,
        STATE_WRITE_RESULT
    } t_state;
    t_state state;

    // csr read
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            sTx.c2.mmioRdValid <= 1'b0;
        end
        else
        begin
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
                
                BITCOIN_CSR_D1: sTx.c2.data <= d1;
                BITCOIN_CSR_D2: sTx.c2.data <= d2;
                BITCOIN_CSR_D3: sTx.c2.data <= d3;
                BITCOIN_CSR_D4: sTx.c2.data <= d4;
                BITCOIN_CSR_MD1: sTx.c2.data <= md1;
                BITCOIN_CSR_MD2: sTx.c2.data <= md2;
                BITCOIN_CSR_MD3: sTx.c2.data <= md3;
                BITCOIN_CSR_MD4: sTx.c2.data <= md4;
                BITCOIN_CSR_RESULT_ADDR: sTx.c2.data <= result_addr;
                BITCOIN_CSR_CONTROL: sTx.c2.data <= state;
                BITCOIN_CSR_CURR_NONCE: sTx.c2.data <= {cnt,nonce};
  
                default: sTx.c2.data <= t_ccip_mmioData'(0);
            endcase
        end
    end

    logic csr_control_start;
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            d1 <= 0;
            d2 <= 0;
            d3 <= 0;
            d4 <= 0;
            md1 <= 0;
            md2 <= 0;
            md3 <= 0;
            md4 <= 0;
            result_addr <= 0;
        end
        else
        begin
            if (is_csr_write)
            begin
                case(mmio_req_hdr.address)
                    BITCOIN_CSR_D1: d1 <= sRx.c0.data;
                    BITCOIN_CSR_D2: d2 <= sRx.c0.data;
                    BITCOIN_CSR_D3: d3 <= sRx.c0.data;
                    BITCOIN_CSR_D4: d4 <= sRx.c0.data;
                    BITCOIN_CSR_MD1: md1 <= sRx.c0.data;
                    BITCOIN_CSR_MD2: md2 <= sRx.c0.data;
                    BITCOIN_CSR_MD3: md3 <= sRx.c0.data;
                    BITCOIN_CSR_MD4: md4 <= sRx.c0.data;
                    BITCOIN_CSR_RESULT_ADDR: result_addr <= sRx.c0.data;
                    BITCOIN_CSR_CONTROL: begin
                        if (sRx.c0.data == STATE_RUN)
                            csr_control_start <= 1;
                        else if (sRx.c0.data == STATE_IDLE)
                            csr_control_start <= 0;
                    end
                endcase
            end
            else begin
                csr_control_start <= 0;
            end
        end
    end

    fpgaminer_top miner(clk, miner_reset, data, middata, nonce, golden_nonce, golden_valid);

    always_ff @(posedge clk)
    begin
        if (reset) begin
            golden_nonce_buf <= 0;
            state <= STATE_IDLE;
            cnt <= 0;
            miner_reset <= 1;
        end
        else begin
            golden_valid_q <= golden_valid;

            case (state)
                STATE_IDLE: begin
                    if (csr_control_start) begin
                        state <= STATE_RUN;
                        miner_reset <= 0;
                    end
                end
                STATE_RUN: begin
                    if (golden_valid_q) begin
                        $display("golden_nonce: %8x\n", golden_nonce);
                        golden_nonce_buf <= golden_nonce;
                        cnt <= cnt + 1;
                        state <= STATE_WRITE_RESULT;
                    end
                end
                STATE_WRITE_RESULT: begin
                    if (!sRx.c1TxAlmFull) begin
                        miner_reset <= 1;
                        state <= STATE_IDLE;
                    end
                end
            endcase
        end
    end

    t_ccip_c1_ReqMemHdr wr_hdr;

    always_comb
    begin
        wr_hdr = t_ccip_c1_ReqMemHdr'(0);

        wr_hdr.req_type = eREQ_WRLINE_I;
        wr_hdr.address = result_addr;
        wr_hdr.vc_sel = eVC_VA;
        wr_hdr.cl_len = eCL_LEN_1;
        wr_hdr.sop = 1'b1;
    end

    assign sTx.c1.data = t_ccip_clData'({64'(golden_nonce_buf), 64'(cnt)});

    always_ff @(posedge clk)
    begin
        if (reset) begin
            sTx.c1.valid <= 0;
        end
        else begin
            sTx.c1.valid <= ((state == STATE_WRITE_RESULT) && !sRx.c1TxAlmFull);
        end

        sTx.c1.hdr <= wr_hdr;
    end

    //
    // This AFU never makes a read request.
    //
    assign sTx.c0.valid = 1'b0;

endmodule
