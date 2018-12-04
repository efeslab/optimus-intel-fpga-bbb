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
	//RW
	localparam MMIO_CSR_STATUS_ADDR = 16'h018 >> 2;
	localparam MMIO_CSR_SRC_ADDR = 16'h020 >> 2;
	localparam MMIO_CSR_DST_ADDR = 16'h028 >> 2;
	localparam MMIO_CSR_NUM_LINES = 16'h030 >> 2;
	//RO
	localparam MMIO_CSR_MEM_READ_IDX = 16'h38 >> 2;
	localparam MMIO_CSR_WRITE_REQ_CNT = 16'h40 >> 2;
	localparam MMIO_CSR_WRITE_RESP_CNT = 16'h48 >> 2;
	localparam MMIO_CSR_STATE = 16'h50 >> 2;
	localparam MMIO_CSR_CLK_CNT = 16'h58 >> 2;
	localparam MMIO_CSR_WRITE_FULL_CNT = 16'h60 >> 2;
	//WO
	localparam MMIO_CSR_CTL = 16'h070 >> 2;
	localparam MMIO_CSR_WR_THRESHOLD = 16'h078 >> 2;
	localparam MMIO_CSR_SOFT_RST = 16'h080 >> 2;
    // Memory address to which this AFU will write.
	localparam DEFAULT_CSR_STATUS_ADDR = t_ccip_clAddr'(0);
	localparam DEFAULT_CSR_SRC_ADDR = t_ccip_clAddr'(0);
	localparam DEFAULT_CSR_DST_ADDR = t_ccip_clAddr'(0);
	localparam DEFAULT_CSR_NUM_LINES = 32'h0;
	localparam DEFAULT_CSR_WR_THRESHOLD = 32'h40;
    t_ccip_clAddr csr_status_addr;
    t_ccip_clAddr csr_src_addr;
    t_ccip_clAddr csr_dst_addr;
	logic [31:0] csr_num_lines;
	logic [31:0] write_req_cnt;
	logic [31:0] write_resp_cnt;
	logic [31:0] write_full_cnt;
	logic [31:0] csr_mem_read_idx;
	logic [63:0] clk_cnt;
	logic read_req_done;
	logic can_read;
	logic read_stage_2;
	logic write_stage_2;
	logic [31:0] csr_wr_threshold;
	logic csr_soft_reset;
    typedef enum logic [1:0]
    {
        STATE_IDLE,
		STATE_REPORT,
        STATE_RUN
    }
    t_state;
    t_state state;

    logic reset;
    assign reset = csr_soft_reset;

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

			  MMIO_CSR_STATUS_ADDR: sTx.c2.data <= t_ccip_mmioData'(csr_status_addr);
			  MMIO_CSR_SRC_ADDR: sTx.c2.data <= t_ccip_mmioData'(csr_src_addr);
			  MMIO_CSR_DST_ADDR: sTx.c2.data <= t_ccip_mmioData'(csr_dst_addr);
			  MMIO_CSR_NUM_LINES: sTx.c2.data <= t_ccip_mmioData'(csr_num_lines);
			  MMIO_CSR_MEM_READ_IDX: sTx.c2.data <= t_ccip_mmioData'(csr_mem_read_idx);
			  MMIO_CSR_WRITE_REQ_CNT: sTx.c2.data <= t_ccip_mmioData'(write_req_cnt);
			  MMIO_CSR_WRITE_RESP_CNT: sTx.c2.data <= t_ccip_mmioData'(write_resp_cnt);
			  MMIO_CSR_STATE:
			  begin
			  	sTx.c2.data <= t_ccip_mmioData'(0);
				sTx.c2.data[1:0] <= state;
				sTx.c2.data[8] <= read_req_done;
				sTx.c2.data[9] <= sRx.c0TxAlmFull;
				sTx.c2.data[10] <= sRx.c1TxAlmFull;
				sTx.c2.data[16] <= can_read;
				sTx.c2.data[17] <= read_stage_2;
				sTx.c2.data[18] <= write_stage_2;
			  end
			  MMIO_CSR_CLK_CNT: sTx.c2.data <= t_ccip_mmioData'(clk_cnt);
			  MMIO_CSR_WRITE_FULL_CNT: sTx.c2.data <= t_ccip_mmioData'(write_full_cnt);

              default: sTx.c2.data <= t_ccip_mmioData'(0);
            endcase
        end
    end


    //
    // CSR write handling.  Host software must tell the AFU the memory address
    // to which it should be writing.  The address is set by writing a CSR.
    //


	logic csr_ctl_start;
    always_ff @(posedge clk)
    begin
		if (pck_cp2af_softReset)
		begin
			csr_status_addr <= DEFAULT_CSR_SRC_ADDR;
			csr_src_addr <= DEFAULT_CSR_SRC_ADDR;
			csr_dst_addr <= DEFAULT_CSR_DST_ADDR;
			csr_num_lines <= DEFAULT_CSR_NUM_LINES;
			csr_wr_threshold <= DEFAULT_CSR_WR_THRESHOLD;
			csr_ctl_start <= 1'b0;
			csr_soft_reset <= 1'b1; //only reset csr_soft_reset when afu_soft_reset
		end
        else if (is_csr_write)
        begin
			case(mmio_req_hdr.address)
				// CSR_STATUS_ADDR Start physical address for status flag. Consist of completion flag, num of cycles used.
				MMIO_CSR_STATUS_ADDR: csr_status_addr <= t_ccip_clAddr'(sRx.c0.data);
				// CSR_SRC_ADDR Start physical address for source buffer. All read requests are targetted to this region.
				MMIO_CSR_SRC_ADDR: csr_src_addr <= t_ccip_clAddr'(sRx.c0.data);
				// CSR_DST_ADDR Start physical address for destination buffer. All write requests are targetted to this region.
				MMIO_CSR_DST_ADDR: csr_dst_addr <= t_ccip_clAddr'(sRx.c0.data);
				// CSR_NUM_LINES Number of cache lines
				MMIO_CSR_NUM_LINES: csr_num_lines <= sRx.c0.data[31:0];
				// CSR_CTL Controls test flow start
				MMIO_CSR_CTL:
				begin
					if (sRx.c0.data[0] == 1'b1 &&
						csr_src_addr != DEFAULT_CSR_SRC_ADDR &&
						csr_dst_addr != DEFAULT_CSR_DST_ADDR &&
						csr_num_lines != DEFAULT_CSR_NUM_LINES)
					begin
						csr_ctl_start <= 1'b1;
					end
				end
				MMIO_CSR_WR_THRESHOLD: csr_wr_threshold <= sRx.c0.data;
				MMIO_CSR_SOFT_RST:
				begin
					csr_soft_reset <= 1'b1;
				end
				default:
				begin
					csr_ctl_start <= 1'b0;
					csr_soft_reset <= 1'b0;
				end
			endcase
        end
		else
		begin
			csr_ctl_start <= 1'b0;
			csr_soft_reset <= 1'b0;
		end
    end
    


    // =========================================================================
    //
    //   Main AFU logic
    //
    // =========================================================================

    //
    // State machine
    //
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            state <= STATE_IDLE;
			clk_cnt <= 64'h0;
        end
        else
        begin
			// Trigger the AFU when start signal is wrote to CSR_CTL. (After
			// the CPU tells us where the FPGA should read, write how much
			// cachelines.)
            if ((state == STATE_IDLE) && csr_ctl_start)
            begin
                state <= STATE_RUN;
				clk_cnt <= 64'h0;
                $display("AFU running...");
            end
			if (state == STATE_RUN)
				clk_cnt <= clk_cnt + 1;
            // The AFU completes its task by writing a single line.  When
            // the line is written return to idle.  The write will happen
            // as long as the request channel is not full.
            if ((state == STATE_RUN) && read_req_done && write_resp_cnt == csr_num_lines)
            begin
                state <= STATE_REPORT;
                $display("AFU reporting...");
            end
			if ((state == STATE_REPORT))
			begin
				state <= STATE_IDLE;
				$display("AFU done...");
			end
        end
    end
	logic [31:0] read_minus_write;
	logic can_read_stage_2;
	logic [31:0] can_read_lreg;
	logic [31:0] can_read_rreg;
	t_ccip_clAddr src_addr_buf;
	assign read_minus_write = csr_mem_read_idx - write_resp_cnt;
	assign read_req_done = csr_mem_read_idx == csr_num_lines;
	// send memory read requests
	always_ff @(posedge clk)
	begin
		if (reset)
		begin
			sTx.c0.valid <= 1'b0;
			sTx.c0.hdr <= t_ccip_c0_ReqMemHdr'(0);
			csr_mem_read_idx <= 32'hffffffff;
			can_read <= 1'b0;
			can_read_stage_2 <= 1'b0;
			read_stage_2 <= 1'b0;
		end
		if (csr_ctl_start)
			src_addr_buf <= csr_src_addr - 1;
		if (state == STATE_RUN)
		begin
			if (!sRx.c0TxAlmFull && !sRx.c1TxAlmFull)
			begin
				//can_read <= ((csr_mem_read_idx + 1 - write_resp_cnt) < csr_wr_threshold);
				can_read_stage_2 <= 1'b1;
				can_read_lreg <= csr_mem_read_idx + 1;
				can_read_rreg <= write_req_cnt + csr_wr_threshold;
			end
			else
			begin
				can_read_stage_2 <= 1'b0;
			end

			if (can_read_stage_2)
			begin
				can_read <= can_read_lreg < can_read_rreg;
			end
			else
			begin
				can_read <= 1'b0;
			end

			if (can_read && !read_req_done)
			begin
				read_stage_2 <= 1'b1;
				csr_mem_read_idx <= csr_mem_read_idx + 1;
				src_addr_buf <= src_addr_buf + 1;
			end
			else
			begin
				read_stage_2 <= 1'b0;
			end

			if (read_stage_2 && !read_req_done)
			begin
				sTx.c0.valid <= 1'b1;
				sTx.c0.hdr.vc_sel <= eVC_VL0;
				sTx.c0.hdr.cl_len <= eCL_LEN_1;
				sTx.c0.hdr.req_type <= eREQ_RDLINE_I;
				sTx.c0.hdr.address <= src_addr_buf;
				sTx.c0.hdr.mdata <= csr_mem_read_idx[15:0]; // this counter will wrap around at 0x7fff
			end
			else begin
				sTx.c0.valid <= 1'b0;
			end
		end
	end
	t_ccip_mdata stage_mdata;
	t_ccip_clData stage_data;
	t_ccip_clAddr stage_reg_addr;
	logic [15:0] stage_reg_negoff;
	// received memory read response
	always_ff @(posedge clk)
	begin
		if (reset)
		begin
			write_stage_2 <= 1'b0;
		end
		if (sRx.c0.rspValid == 1'b1 &&
				sRx.c0.hdr.resp_type == eRSP_RDLINE &&
				sRx.c0.hdr.cl_num == eCL_LEN_1)
		begin
			write_stage_2 <= 1'b1;
			stage_reg_addr <= csr_dst_addr + csr_mem_read_idx;
			stage_reg_negoff <= 16'(csr_mem_read_idx[15:0] - sRx.c0.hdr.mdata);	//explicitly let it overflow
			stage_mdata <= sRx.c0.hdr.mdata;
			stage_data <= sRx.c0.data;
		end
		else
		begin
			write_stage_2 <= 1'b0;
		end
	end
	/*
	 * handle write_stage_2
	 */
	always_ff @(posedge clk)
	begin
		if (reset)
		begin
			sTx.c1.valid <= 1'b0;
			sTx.c1.hdr.rsvd0 <= 0;
			sTx.c1.hdr.rsvd1 <= 0;
			sTx.c1.hdr <= t_ccip_c1_ReqMemHdr'(0);
			write_req_cnt <= 32'h0;
			write_full_cnt <= 32'h0;
		end
		if (write_stage_2)
		begin
			sTx.c1.valid <= 1'b1;
			sTx.c1.hdr.vc_sel <= eVC_VL0;
			sTx.c1.hdr.sop <= 1'b1;
			sTx.c1.hdr.cl_len <= eCL_LEN_1;
			sTx.c1.hdr.req_type <= eREQ_WRLINE_I;
			sTx.c1.hdr.address <= stage_reg_addr - stage_reg_negoff;
			sTx.c1.hdr.mdata <= stage_mdata;
			sTx.c1.data <= stage_data;
			write_req_cnt <= write_req_cnt + 1;
			write_full_cnt <= write_full_cnt + sRx.c1TxAlmFull;
		end
		if (state == STATE_REPORT)
		begin
			sTx.c1.valid <= 1'b1;
			sTx.c1.hdr.vc_sel <= eVC_VL0;
			sTx.c1.hdr.sop <= 1'b1;
			sTx.c1.hdr.cl_len <= eCL_LEN_1;
			sTx.c1.hdr.req_type <= eREQ_WRLINE_I;
			sTx.c1.hdr.address <= csr_status_addr;
			sTx.c1.hdr.mdata <= t_ccip_mdata'(0);
			sTx.c1.data[0] <= 1'b1;
			sTx.c1.data[127:64] <= clk_cnt;
			sTx.c1.data[159:128] <= csr_mem_read_idx;
			sTx.c1.data[191:160] <= write_resp_cnt;
		end
		if (!write_stage_2 && state != STATE_REPORT) begin
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
			write_resp_cnt <= 32'h0;
		end
		else if (state == STATE_RUN &&
				sRx.c1.rspValid == 1'b1 &&
				sRx.c1.hdr.format == 1'b0 &&
				sRx.c1.hdr.cl_num == eCL_LEN_1 &&
				sRx.c1.hdr.resp_type == eRSP_WRLINE)
		begin
			write_resp_cnt <= write_resp_cnt + 1;
		end
	end
endmodule
