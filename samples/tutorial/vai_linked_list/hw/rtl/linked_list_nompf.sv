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
`ifdef WITH_MUX
    `define TOP_IFC_NAME `AFU_WITHMUX_NAME
`else
    `define TOP_IFC_NAME `AFU_NOMUX_NAME
`endif
module `TOP_IFC_NAME
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

	function automatic logic ccip_c0Rx_isReadRsp(input t_if_ccip_c0_Rx r);
		return r.rspValid && (r.hdr.resp_type == eRSP_RDLINE);
	endfunction
    //
    // MMIO reads.
    //

	//RO
	localparam MMIO_CSR_CNT_LIST_LENGTH = 16'h018 >> 2;
	localparam MMIO_CSR_CNT_DATA_ENTRIES = 16'h020 >> 2;
	//WO
	localparam MMIO_CSR_RESULT_ADDR = 16'h028 >> 2;
	localparam MMIO_CSR_START_ADDR = 16'h030 >> 2;

	logic [15:0] cnt_list_length;
	logic [15:0] cnt_data_entries;
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

              // DFH_RSVD0
              6: sTx.c2.data <= t_ccip_mmioData'(0);

              // DFH_RSVD1
              8: sTx.c2.data <= t_ccip_mmioData'(0);

			  MMIO_CSR_CNT_LIST_LENGTH:
				  sTx.c2.data <= t_ccip_mmioData'(cnt_list_length);
			  MMIO_CSR_CNT_DATA_ENTRIES:
				  sTx.c2.data <= t_ccip_mmioData'(cnt_data_entries);

              default: sTx.c2.data <= t_ccip_mmioData'(0);
            endcase
        end
    end


    //
    // CSR write handling.  Host software must tell the AFU the memory address
    // to which it should be writing.  The address is set by writing a CSR.
    //

    t_ccip_clAddr start_traversal_addr;
	t_ccip_clAddr result_addr;
	logic start_traversal;
	always_ff @(posedge clk)
	begin
		if (is_csr_write)
		begin
			case (mmio_req_hdr.address)
				MMIO_CSR_START_ADDR:
				begin
					start_traversal_addr <= t_ccip_clAddr'(sRx.c0.data);
					start_traversal <= 1'b1;
				end
				MMIO_CSR_RESULT_ADDR:
				begin
					result_addr <= t_ccip_clAddr'(sRx.c0.data);
				end
				default:
					start_traversal <= 1'b0;
			endcase
		end
		else
			start_traversal <= 1'b0;
	end


    // =========================================================================
    //
    //   State machine
    //
    // =========================================================================

    typedef enum logic [1:0]
    {
        STATE_IDLE,
        STATE_RUN,
        STATE_END_OF_LIST,
        STATE_WRITE_RESULT
    }
    t_state;

    t_state state;
    // Status signals that affect state changes
    logic rd_end_of_list;
    logic rd_last_beat_received;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            state <= STATE_IDLE;
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
                        $display("AFU starting traversal at 0x%x", start_traversal_addr);
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

              STATE_WRITE_RESULT:
                begin
                    // The end of the list has been reached.  The AFU must
                    // write the computed hash to result_addr.  It is the
                    // only memory write the AFU will request.  The write
                    // will be triggered as soon as the pipeline can
                    // accept requests.
                    if (! sRx.c1TxAlmFull)
                    begin
                        state <= STATE_IDLE;
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
                rd_needed <= (start_traversal || (addr_next_valid && ! rd_end_of_list));
                rd_addr <= (start_traversal ? start_traversal_addr : addr_next);
            end
        end
    end


    //
    // Emit read requests to the FIU.
    //

    // Read header defines the request to the FIU
    t_ccip_c0_ReqMemHdr rd_hdr;

    always_comb
    begin
        rd_hdr = t_ccip_c0_ReqMemHdr'(0);

        // Read request type
        rd_hdr.req_type = eREQ_RDLINE_I;
        // Virtual address (MPF virtual addressing is enabled)
        rd_hdr.address = rd_addr;
        // Let the FIU pick the channel
        rd_hdr.vc_sel = eVC_VA;
        // Read 4 lines (the size of an entry in the list)
        rd_hdr.cl_len = eCL_LEN_4;
    end

    // Send read requests to the FIU
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            sTx.c0.valid <= 1'b0;
            cnt_list_length <= 0;
        end
        else
        begin
            // Generate a read request when needed and the FIU isn't full
            sTx.c0.valid <= (rd_needed && ! sRx.c0TxAlmFull);
            sTx.c0.hdr <= rd_hdr;

            if (rd_needed && ! sRx.c0TxAlmFull)
            begin
                cnt_list_length <= cnt_list_length + 1;
                $display("  Reading from VA 0x%x", rd_addr);
            end
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
        // A read response is data if the cl_num is non-zero.  (When cl_num
        // is zero the response is a pointer to the next record.)
        hash_data_en <= (ccip_c0Rx_isReadRsp(sRx.c0) &&
                         (sRx.c0.hdr.cl_num != t_ccip_clNum'(0)));
        hash_data <= sRx.c0.data[63:0];
        hash_cl_num <= sRx.c0.hdr.cl_num;

        if (ccip_c0Rx_isReadRsp(sRx.c0) &&
            (sRx.c0.hdr.cl_num != t_ccip_clNum'(0)))
        begin
            $display("    Received entry v%0d: %0d",
                     sRx.c0.hdr.cl_num, sRx.c0.data[63:0]);
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
			total_cacheline <= 32'h4;
		else if (addr_next_valid && !rd_end_of_list)
			total_cacheline <= total_cacheline + 4;
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
		else if (hash_data_en)
			checksum <= checksum + hash_data;
	end

    //
    // Count the number of fields read and added to the hash.
    //
    always_ff @(posedge clk)
    begin
        if (reset || start_traversal)
        begin
            cnt_data_entries <= 0;
        end
        else if (hash_data_en)
        begin
            cnt_data_entries <= cnt_data_entries + 1;
        end
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

    // Data to write to memory.  The low word is a non-zero flag.  The
    // CPU-side software will spin, waiting for this flag.  The computed
    // hash is written in the 2nd 64 bit word.
    assign sTx.c1.data = t_ccip_clData'({ checksum, 64'h1 });

    // Control logic for memory writes
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            sTx.c1.valid <= 1'b0;
        end
        else
        begin
            // Request the write as long as the channel isn't full.
            sTx.c1.valid <= ((state == STATE_WRITE_RESULT) &&
                                   ! sRx.c1TxAlmFull);
        end

        sTx.c1.hdr <= wr_hdr;
    end

endmodule
