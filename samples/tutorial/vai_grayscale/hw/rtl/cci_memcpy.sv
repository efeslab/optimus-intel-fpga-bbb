`include "cci_mpf_if.vh"
`include "csr_mgr.vh"
`include "afu_json_info.vh"

module app_afu
(
    input logic clk,
    cci_mpf_if.to_fiu fiu,
    app_csrs.app csrs,
    input logic c0NotEmpty,
    input logic c1NotEmpty
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

	grayscale_app_top app_cci(
        .clk,
        .reset,
        .cp2af_sRx(mpf2af_sRx),
        .af2cp_sTx(af2mpf_sTx),
        .csrs,
        .c0NotEmpty,
        .c1NotEmpty
        );

endmodule

module grayscale_app_top
(
    input logic clk,
    input logic reset,
    input t_if_ccip_Rx cp2af_sRx,
    output t_if_ccip_Tx af2cp_sTx,
    app_csrs.app csrs,
    input logic c0NotEmpty,
    input logic c1NotEmpty
);

    logic reset_r;
    assign reset_r = ~reset;

    t_if_ccip_Rx sRx;
    always_ff @(posedge clk)
    begin
        sRx <= cp2af_sRx;
    end

    t_if_ccip_Tx sTx, pre_sTx;
	always_ff @(posedge clk)
    begin
        af2cp_sTx.c0 <= sTx.c0;
    end
    assign af2cp_sTx.c2.mmioRdValid = 1'b0;

    /* sTx.c1 needs a buffer */
    logic fifo_c1tx_rdack, fifo_c1tx_dout_v, fifo_c1tx_full, fifo_c1tx_almFull;
    t_if_ccip_c1_Tx fifo_c1tx_dout;
	sync_C1Tx_fifo_copy #(
		.DATA_WIDTH($bits(t_if_ccip_c1_Tx)),
		.CTL_WIDTH(0),
		.DEPTH_BASE2($clog2(64)),
		.GRAM_MODE(3),
		.FULL_THRESH(64-8)
	)
	inst_fifo_c1tx(
		.Resetb(reset_r),
		.Clk(clk),
		.fifo_din(sTx.c1),
		.fifo_ctlin(),
		.fifo_wen(sTx.c1.valid),
		.fifo_rdack(fifo_c1tx_rdack),
		.T2_fifo_dout(fifo_c1tx_dout),
		.T0_fifo_ctlout(),
		.T0_fifo_dout_v(fifo_c1tx_dout_v),
		.T0_fifo_empty(),
		.T0_fifo_full(fifo_c1tx_full),
		.T0_fifo_count(),
		.T0_fifo_almFull(fifo_c1tx_almFull),
		.T0_fifo_underflow(),
		.T0_fifo_overflow()
		);

    logic fifo_c1tx_dout_v_q, fifo_c1tx_dout_v_qq;
    assign fifo_c1tx_rdack = fifo_c1tx_dout_v;
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            fifo_c1tx_dout_v_q <= 0;
            fifo_c1tx_dout_v_qq <= 0;
            af2cp_sTx.c1.valid <= 0;
        end
        else
        begin
            fifo_c1tx_dout_v_q <= fifo_c1tx_dout_v;
            fifo_c1tx_dout_v_qq <= fifo_c1tx_dout_v_q;

            if (fifo_c1tx_dout_v_qq)
                af2cp_sTx.c1 <= fifo_c1tx_dout;
            else
                af2cp_sTx.c1 <= t_if_ccip_c1_Tx'(0);
        end
    end
        
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
	localparam MMIO_CSR_STATUS_ADDR = 0;
	localparam MMIO_CSR_SRC_ADDR = 1;
	localparam MMIO_CSR_DST_ADDR = 2;
	localparam MMIO_CSR_NUM_LINES = 3;
	//RO
	localparam MMIO_CSR_MEM_READ_IDX = 4;
	localparam MMIO_CSR_WRITE_REQ_CNT = 5;
	localparam MMIO_CSR_WRITE_RESP_CNT = 6;
	localparam MMIO_CSR_STATE = 7;
	localparam MMIO_CSR_CLK_CNT = 8;
	localparam MMIO_CSR_WRITE_FULL_CNT = 9;
	//WO
	localparam MMIO_CSR_CTL = 10;
	localparam MMIO_CSR_WR_THRESHOLD = 11;

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
	//logic [31:0] soft_reset_cnt;
    typedef enum logic [1:0]
    {
        STATE_IDLE,
		STATE_REPORT,
        STATE_RUN
    }
    t_state;
    t_state state;

    always_comb
    begin
        csrs.afu_id = `AFU_ACCEL_UUID;

        for (int i = 0; i < NUM_APP_CSRS; i = i + 1)
        begin
            csrs.cpu_rd_csrs[i].data = 64'(0);
        end

        csrs.cpu_rd_csrs[MMIO_CSR_STATUS_ADDR].data = t_ccip_mmioData'(csr_status_addr);
        csrs.cpu_rd_csrs[MMIO_CSR_SRC_ADDR].data = t_ccip_mmioData'(csr_src_addr);
		csrs.cpu_rd_csrs[MMIO_CSR_DST_ADDR].data = t_ccip_mmioData'(csr_dst_addr);
		csrs.cpu_rd_csrs[MMIO_CSR_NUM_LINES].data = t_ccip_mmioData'(csr_num_lines);
		csrs.cpu_rd_csrs[MMIO_CSR_MEM_READ_IDX].data = t_ccip_mmioData'(csr_mem_read_idx);
		csrs.cpu_rd_csrs[MMIO_CSR_WRITE_REQ_CNT].data = t_ccip_mmioData'(write_req_cnt);
		csrs.cpu_rd_csrs[MMIO_CSR_WRITE_RESP_CNT].data = t_ccip_mmioData'(write_resp_cnt);


        csrs.cpu_rd_csrs[MMIO_CSR_STATE].data = t_ccip_mmioData'(0);
        csrs.cpu_rd_csrs[MMIO_CSR_STATE].data[1:0] = state;
		csrs.cpu_rd_csrs[MMIO_CSR_STATE].data[8] = read_req_done;
        csrs.cpu_rd_csrs[MMIO_CSR_STATE].data[9] = sRx.c0TxAlmFull;
		csrs.cpu_rd_csrs[MMIO_CSR_STATE].data[10] = sRx.c1TxAlmFull;
		csrs.cpu_rd_csrs[MMIO_CSR_STATE].data[16] = can_read;
		csrs.cpu_rd_csrs[MMIO_CSR_STATE].data[17] = read_stage_2;
		csrs.cpu_rd_csrs[MMIO_CSR_STATE].data[18] = write_stage_2;

		csrs.cpu_rd_csrs[MMIO_CSR_CLK_CNT].data = t_ccip_mmioData'(clk_cnt);
		csrs.cpu_rd_csrs[MMIO_CSR_WRITE_FULL_CNT].data = t_ccip_mmioData'(write_full_cnt);

    end

    //
    // CSR write handling.  Host software must tell the AFU the memory address
    // to which it should be writing.  The address is set by writing a CSR.
    //


	logic csr_ctl_start;
    always_ff @(posedge clk)
    begin
		if (reset)
		begin
			csr_status_addr <= DEFAULT_CSR_SRC_ADDR;
			csr_src_addr <= DEFAULT_CSR_SRC_ADDR;
			csr_dst_addr <= DEFAULT_CSR_DST_ADDR;
			csr_num_lines <= DEFAULT_CSR_NUM_LINES;
			csr_ctl_start <= 1'b0;
		end
        else
        begin

            if (csrs.cpu_wr_csrs[MMIO_CSR_STATUS_ADDR].en)
            begin
                $display("CSR write: MMIO_CSR_STATUS_ADDR");
                csr_status_addr <= t_ccip_clAddr'(csrs.cpu_wr_csrs[MMIO_CSR_STATUS_ADDR].data);
            end

            if (csrs.cpu_wr_csrs[MMIO_CSR_SRC_ADDR].en)
            begin
                $display("CSR write: MMIO_CSR_SRC_ADDR");
				csr_src_addr <= t_ccip_clAddr'(csrs.cpu_wr_csrs[MMIO_CSR_SRC_ADDR].data);
            end

            if (csrs.cpu_wr_csrs[MMIO_CSR_DST_ADDR].en)
            begin
                $display("CSR write: MMIO_CSR_DST_ADDR");
                csr_dst_addr <= t_ccip_clAddr'(csrs.cpu_wr_csrs[MMIO_CSR_DST_ADDR].data);
            end

            if (csrs.cpu_wr_csrs[MMIO_CSR_NUM_LINES].en)
            begin
                $display("CSR write: MMIO_CSR_NUM_LINES");
                csr_num_lines <= csrs.cpu_wr_csrs[MMIO_CSR_NUM_LINES].data[31:0];
            end

            if (csrs.cpu_wr_csrs[MMIO_CSR_CTL].en)
			begin
                $display("CSR write: MMIO_CSR_CTL");
                if (csrs.cpu_wr_csrs[MMIO_CSR_CTL].data[0] == 1'b1 &&
                    csr_src_addr != DEFAULT_CSR_SRC_ADDR &&
                    csr_dst_addr != DEFAULT_CSR_DST_ADDR &&
                    csr_num_lines != DEFAULT_CSR_NUM_LINES)
                begin
                    csr_ctl_start <= 1'b1;
                end
			end
            else
            begin
                csr_ctl_start <= 1'b0;
            end

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

    logic [7:0] rw_balance;
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            rw_balance <= 0;
        end
        else
        begin
            case ({sTx.c0.valid, sRx.c1.rspValid})
                2'b00: rw_balance <= rw_balance;
                2'b01: rw_balance <= rw_balance - 1;
                2'b10: rw_balance <= rw_balance + 1;
                2'b11: rw_balance <= rw_balance;
            endcase
        end
    end

	logic [31:0] read_minus_write;
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
			read_stage_2 <= 1'b0;
		end
        else if (state == STATE_IDLE) begin
            csr_mem_read_idx <= 32'hffffffff;
        end
		else if (state == STATE_RUN)
		begin
			if (!sRx.c0TxAlmFull && !sRx.c1TxAlmFull && !fifo_c1tx_almFull && rw_balance<62)
				can_read <= 1'b1;
			else
				can_read <= 1'b0;

			if (can_read && !read_req_done)
			begin
				read_stage_2 <= 1'b1;
				csr_mem_read_idx <= csr_mem_read_idx + 1;
			end
			else
			begin
				read_stage_2 <= 1'b0;
			end

			if (read_stage_2 && !read_req_done)
			begin
				sTx.c0.valid <= 1'b1;
				sTx.c0.hdr.vc_sel <= eVC_VA;
				sTx.c0.hdr.cl_len <= eCL_LEN_1;
				sTx.c0.hdr.req_type <= eREQ_RDLINE_I;
				sTx.c0.hdr.address <= csr_src_addr + csr_mem_read_idx;
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
			//stage_data <= sRx.c0.data;
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
			sTx.c1.hdr.vc_sel <= eVC_VA;
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
			sTx.c1.hdr.vc_sel <= eVC_VA;
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
     * the grayscale core
     */
    grayscale grayscale_uu(
        .clk,
        .reset,
        .data_in(sRx.c0.data),
        .valid_in(sRx.c0.rspValid),
        .data_out(stage_data),
        .valid_out()
        );







	/*
	 * handle memory write response
	 */
	always_ff @(posedge clk)
	begin
		if (reset)
		begin
			write_resp_cnt <= 32'h0;
		end
        else if (state == STATE_IDLE) begin
            write_resp_cnt <= 0;
        end
		else if (state == STATE_RUN && sRx.c1.rspValid == 1'b1)
        begin
            if (sRx.c1.hdr.format == 1'b0)
			    write_resp_cnt <= write_resp_cnt + 1;
            else
            begin
                case (sRx.c1.hdr.cl_num)
                    eCL_LEN_1: write_resp_cnt <= write_resp_cnt + 1;
                    eCL_LEN_2: write_resp_cnt <= write_resp_cnt + 2;
                    eCL_LEN_4: write_resp_cnt <= write_resp_cnt + 4;
                endcase
            end
		end
	end
endmodule
