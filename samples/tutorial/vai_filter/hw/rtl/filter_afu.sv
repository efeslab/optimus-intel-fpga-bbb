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
	function automatic logic ccip_c1Rx_isWriteRsp(input t_if_ccip_c1_Rx r);
		return r.rspValid && (r.hdr.resp_type == eRSP_WRLINE);
	endfunction
    //
    // MMIO reads.
    //

	//RO
	localparam MMIO_CSR_RD_CNT = 16'h60 >> 2;
	localparam MMIO_CSR_RD_RSP_CNT = 16'h68 >> 2;
	localparam MMIO_CSR_WR_CNT = 16'h28 >> 2;
	localparam MMIO_CSR_RESULT_CNT = 16'h30 >> 2;
	localparam MMIO_CSR_FILTER_CNT = 16'h38 >> 2;
	//WO
	localparam MMIO_CSR_INPUT_ADDR = 16'h40 >> 2;
	localparam MMIO_CSR_INPUT_SIZE = 16'h48 >> 2;
	localparam MMIO_CSR_RESULT_CNT_ADDR = 16'h50 >> 2;
	localparam MMIO_CSR_OUTPUT_ADDR = 16'h58 >> 2;

    logic [63:0] rd_cnt, rd_rsp_cnt, wr_cnt,result_cnt, filter_cnt,wr_rsp_cnt;
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

			  MMIO_CSR_RD_CNT:
				  sTx.c2.data <= rd_cnt[63:0];
			  MMIO_CSR_RD_RSP_CNT:
				  sTx.c2.data <= t_ccip_mmioData'(rd_rsp_cnt);
			  MMIO_CSR_WR_CNT:
				  sTx.c2.data <= t_ccip_mmioData'(wr_cnt);
			  MMIO_CSR_RESULT_CNT:
				  sTx.c2.data <= t_ccip_mmioData'(result_cnt);
			  MMIO_CSR_FILTER_CNT:
				  sTx.c2.data <= t_ccip_mmioData'(filter_cnt);
              default: sTx.c2.data <= t_ccip_mmioData'(0);
            endcase
        end
    end


    //
    // CSR write handling.  Host software must tell the AFU the memory address
    // to which it should be writing.  The address is set by writing a CSR.
    //

    logic start_filter;
    t_ccip_clAddr input_addr;
    t_ccip_clAddr result_cnt_addr;
    t_ccip_clAddr output_addr;
	logic [63:0] input_size;
	always_ff @(posedge clk)
	begin
		if (is_csr_write)
		begin
			case (mmio_req_hdr.address)
				MMIO_CSR_OUTPUT_ADDR:
					output_addr <= t_ccip_clAddr'(sRx.c0.data);
				MMIO_CSR_INPUT_ADDR:
					input_addr <= t_ccip_clAddr'(sRx.c0.data);
				MMIO_CSR_INPUT_SIZE:
					input_size <= sRx.c0.data[63:0];
				MMIO_CSR_RESULT_CNT_ADDR:
				begin
					result_cnt_addr <= t_ccip_clAddr'(sRx.c0.data);
					start_filter <= 1'b1;
				end
				default:
					start_filter = 1'b0;
			endcase
		end
		else
			start_filter <= 1'b0;
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
        STATE_FINISH_INPUT,
        STATE_WRITE_RESULT
    }
    t_state;

    t_state state;
    // Status signals that affect state changes
    logic rd_end_of_input;
	logic fifo_is_empty;
	logic fifo_is_full;
	logic filter_is_over;
	logic [1:0] buf_line_idx;
	logic [4:0] buf_cnt;
	logic in_queue_data_en;
	logic filter_en;
    logic [511:0] buf_line;
	logic wr_needed;
	logic [63:0] key, c1,c2,c3,c4,c5,c6,c7;
	logic write_finished;
	


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
                 
                    if (start_filter)
                    begin
                        state <= STATE_RUN;
                        $display("AFU started at 0x%x",
                                 (input_addr));
                        //$display("Input size %d ", input_size);
                        $display("result cnt address %x ", (result_cnt_addr));
                    end
                end

              STATE_RUN:
                begin
                   
                    if (rd_end_of_input)
                    begin
                        state <= STATE_FINISH_INPUT;
                        $display("AFU requested all input data");
                    end
                end

              STATE_FINISH_INPUT:
                begin
                   
                    if (filter_is_over && fifo_is_empty && buf_line_idx==0 && in_queue_data_en == 0 && !wr_needed&&write_finished)
                    begin
                        state <= STATE_WRITE_RESULT;
                        $display("AFU finished filtering");
                    end
                end
			  STATE_WRITE_RESULT:
			  	begin
			  		if (!sRx.c1TxAlmFull )
			  		begin
			  			
			  			state <= STATE_IDLE;
			  			$display("AFU writed result cnt");
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

    
   
	localparam BUFF_SIZE = 32;
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
           
            if (rd_needed)
            begin
                rd_needed <= sRx.c0TxAlmFull;
            end
            else
            begin
                
                rd_needed <= (state==STATE_RUN)&&(rd_cnt - rd_rsp_cnt < ((BUFF_SIZE -buf_cnt )<< 2));
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
        rd_hdr.address = input_addr + rd_cnt;
        // Let the FIU pick the channel
        rd_hdr.vc_sel = eVC_VA;
        // Read 1 lines (the size of an entry in the list)
        rd_hdr.cl_len = eCL_LEN_1;
    end

    // Send read requests to the FIU
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            sTx.c0.valid <= 1'b0;
           	rd_cnt <= 0;
        end
        else
        begin
            // Generate a read request when needed and the FIU isn't full
            sTx.c0.valid <= ((!rd_end_of_input)&&rd_needed && ! sRx.c0TxAlmFull);
            sTx.c0.hdr <= rd_hdr;

            if ((!rd_end_of_input)&& rd_needed && ! sRx.c0TxAlmFull)
            begin
                rd_cnt <= rd_cnt + 1;
                $display("%0d Reading from VA 0x%x", rd_cnt,(input_addr+rd_cnt));
            end
        end
    end

	assign rd_end_of_input = input_size == rd_cnt;
    //
    // READ RESPONSE HANDLING
    //

    
    
    
    t_ccip_clNum hash_cl_num;

    //
    // Receive data (read responses).
    //
    always_ff @(posedge clk)
    begin
        
		if (reset)
		begin
			filter_en <= 0;
			rd_rsp_cnt <= 0;
		end
		else 
		begin
		    filter_en <= ccip_c0Rx_isReadRsp(sRx.c0);

		    if (ccip_c0Rx_isReadRsp(sRx.c0))
		    begin
				key <= sRx.c0.data[63:0];
				c1 <= sRx.c0.data[127:64];
				c2 <= sRx.c0.data[191:128];
				c3 <= sRx.c0.data[255:192];
				c4 <= sRx.c0.data[319:256];
				c5 <= sRx.c0.data[383:320];
				c6 <= sRx.c0.data[447:384];
				c7 <= sRx.c0.data[511:448];
				rd_rsp_cnt <= rd_rsp_cnt + 1;
			

		    end
		end
    end

	assign filter_is_over = filter_cnt == input_size;

	always_ff @(posedge clk)
	begin
		if (reset)
		begin
			buf_line <= 0;
			buf_line_idx <= 0;
			in_queue_data_en <= 0;
			result_cnt <= 0;
			filter_cnt <=0;
		end
		else
		begin
			if (filter_en) 
			begin
				filter_cnt <= filter_cnt + 1;
				if (c1+c2+c3+c4+c5+c6 > c7) 
				begin
					buf_line[buf_line_idx*2*64+:64] <= key;
					buf_line[buf_line_idx*2*64+64+:64] <= c7;
					result_cnt <= result_cnt + 1;
					if (buf_line_idx == 3) 
					begin
						buf_line_idx <= 0;
						in_queue_data_en <= 1;
						
					end
					else
					begin
						buf_line_idx <= buf_line_idx + 1;
						in_queue_data_en <= 0;
					end
				end
				else
				begin
					in_queue_data_en <= 0;
				
				end
		        $display("Filtering entry %0d: %0d %0d %0d %0d %0d %0d %0d %0d",
		                 rd_rsp_cnt, key,c1,c2,c3,c4,c5,c6,c7);
			end
			else
			begin
				if (filter_is_over && buf_line_idx != 0)
				begin
					buf_line_idx <= 0;
					in_queue_data_en <= 1;
				end
				else
					in_queue_data_en <= 0;
			end
		end
	end
   
    logic out_queue_data_en;
	logic[511:0] output_buf_line;

    
    fifo u0 (
        .data  (buf_line),  //  fifo_input.datain
        .wrreq (in_queue_data_en), //            .wrreq
        .rdreq (out_queue_data_en), //            .rdreq
        .clock (clk), //            .clk
        .q     (output_buf_line),     // fifo_output.dataout
        .usedw (buf_cnt), //            .usedw
        .full  (fifo_is_full),  //            .full
        .empty (fifo_is_empty)  //            .empty
    );

    
    


    // =========================================================================
    //
    //   Write logic.
    //
    // =========================================================================
	
	always_ff @(posedge clk)
	begin
		if (reset)
		begin
			wr_rsp_cnt <=0;
		end
		else 
		begin
			if (ccip_c1Rx_isWriteRsp(sRx.c1))
				wr_rsp_cnt <= wr_rsp_cnt + 1;
		end
	end
	assign write_finished = (wr_rsp_cnt == (result_cnt?(((result_cnt-1)>>2) +1):0))&&filter_is_over;
	
	always_ff @(posedge clk)
	begin
		if (reset) 
		begin
			
			out_queue_data_en <= 0;
			wr_needed <= 0;
		end		
		else
		begin
			if (wr_needed) 
			begin	
				out_queue_data_en <= 0;
				if (! sRx.c1TxAlmFull) 
					wr_needed <= 0;
			end
			else 
			begin
				if (! fifo_is_empty)
				begin
					out_queue_data_en <= 1;
					wr_needed <= 1;
				end
			end
		end
	end
	

    t_ccip_c1_ReqMemHdr wr_hdr;

    always_comb
    begin
        wr_hdr = t_ccip_c1_ReqMemHdr'(0);

        // Write request type
        wr_hdr.req_type = eREQ_WRLINE_I;
        // Virtual address (MPF virtual addressing is enabled)
        wr_hdr.address = (state ==STATE_WRITE_RESULT|| state==STATE_IDLE)? result_cnt_addr :(output_addr + wr_cnt);
        // Let the FIU pick the channel
        wr_hdr.vc_sel = eVC_VL0;
        // Write 1 line
        wr_hdr.cl_len = eCL_LEN_1;
        // Start of packet is true (single line write)
        wr_hdr.sop = 1'b1;
    end

    
    assign sTx.c1.data = t_ccip_clData'((state==STATE_WRITE_RESULT || state==STATE_IDLE)? result_cnt:output_buf_line);

    // Control logic for memory writes
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            sTx.c1.valid <= 1'b0;
            wr_cnt <= 0;
        end
        else
        begin

            sTx.c1.valid <= (state == STATE_WRITE_RESULT || wr_needed) && (! sRx.c1TxAlmFull);
            if (sTx.c1.valid)
            	$display("sTx.c1.data %0d: %0d %0d %0d %0d %0d %0d %0d %0d",
		                 wr_cnt, sTx.c1.data[0+:64], sTx.c1.data[64+:64], sTx.c1.data[128+:64], sTx.c1.data[192+:64], sTx.c1.data[256+:64], sTx.c1.data[320+:64], sTx.c1.data[384+:64], sTx.c1.data[448+:64]);
            if ((state == STATE_WRITE_RESULT || wr_needed) && (! sRx.c1TxAlmFull))
            begin
            	wr_cnt <= wr_cnt + 1;
            	
            	$display("%0d writing to VA 0x%x", wr_cnt,(wr_hdr.address));
            end
        end

        sTx.c1.hdr <= wr_hdr;
    end

endmodule
