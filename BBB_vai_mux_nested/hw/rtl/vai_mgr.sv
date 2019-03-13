`include "platform_if.vh"
`include "vendor_defines.vh"
module vai_mgr # (parameter NUM_SUB_AFUS=8)
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
    output          t_if_ccip_Tx      pck_af2cp_sTx,        // CCI-P Tx Port
    output	        t_if_ccip_Rx      afu_RxPort,           // to mux rx port
    input     		t_if_ccip_Tx	  afu_TxPort,		 	// from mux tx port

    output  logic [63:0]            offset_array    [NUM_SUB_AFUS-1:0],  // to tx auditor
    output  logic [63:0]            sub_afu_reset
);

    localparam LNUM_SUB_AFUS = $clog2(NUM_SUB_AFUS);
    localparam VMID_WIDTH = LNUM_SUB_AFUS;


    logic clk;
    logic reset=1, reset_r=0;
    assign clk = pClk;

    always @(posedge clk)
    begin
        reset <= pck_cp2af_softReset;
        reset_r <= ~pck_cp2af_softReset;
    end

    /* T0: connect to ccip */
    t_if_ccip_Rx T0_Rx;
    assign T0_Rx = pck_cp2af_sRx;


    /* T1: register */
    t_ccip_clData T1_mmio_data;
    t_ccip_c0_ReqMmioHdr T1_mmio_req_hdr;
    logic T1_is_mmio_read;
    logic T1_is_mmio_write;
    t_if_ccip_Rx T1_Rx_temp;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            T1_mmio_data <= 0;
            T1_mmio_req_hdr <= 0;
            T1_is_mmio_read <= 0;
            T1_is_mmio_write <= 0;
            T1_Rx_temp <= 0;
        end
        else
        begin
            T1_mmio_data <= T0_Rx.c0.data;
            T1_mmio_req_hdr <= T0_Rx.c0.hdr;
            T1_is_mmio_read <= T0_Rx.c0.mmioRdValid;
            T1_is_mmio_write <= T0_Rx.c0.mmioWrValid;
            T1_Rx_temp <= T0_Rx;
        end
    end


    /* T2: decode */
    logic [LNUM_SUB_AFUS-1:0] T2_vmid;
    logic [63:0] T2_data;
    t_ccip_tid T2_tid;
    logic T2_is_offset;
    logic T2_is_reset;
    logic T2_is_dfh;
    logic T2_is_id_lo;
    logic T2_is_id_hi;
    logic T2_is_nafus;
    logic T2_is_read;
    logic T2_is_write;
    logic T2_is_ctl_mmio;
	t_if_ccip_Rx T2_Rx_temp;
	
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            T2_vmid <= 0;
            T2_data <= 0;
            T2_tid <= 0;
            T2_is_offset <= 0;
            T2_is_reset <= 0;
            T2_is_read <= 0;
            T2_is_write <= 0;
            T2_is_dfh <= 0;
            T2_is_id_lo <= 0;
            T2_is_id_hi <= 0;
            T2_is_nafus <= 0;
            T2_Rx_temp <= 0;
        end
        else
        begin
        	T2_is_ctl_mmio <= (T1_mmio_req_hdr.address[CCIP_MMIOADDR_WIDTH-1:10] == 0);
        	T2_Rx_temp <= T1_Rx_temp;
            T2_vmid <= (T1_mmio_req_hdr.address[7:1] - 6);
            T2_data[63:0] <= T1_mmio_data;
            T2_tid <= T1_mmio_req_hdr.tid;
            /* 0 <= vmid < NUM_SUB_AFUS */
            T2_is_offset <= (T1_mmio_req_hdr.address[7:1] >= 6 
                            && T1_mmio_req_hdr.address[7:1] < NUM_SUB_AFUS+6);

            T2_is_dfh <= (T1_mmio_req_hdr.address == 0);
            T2_is_id_lo <= (T1_mmio_req_hdr.address == 2);
            T2_is_id_hi <= (T1_mmio_req_hdr.address == 4);
            T2_is_reset <= (T1_mmio_req_hdr.address == 6);
            T2_is_nafus <= (T1_mmio_req_hdr.address == 8);

            T2_is_read <= T1_is_mmio_read;
            T2_is_write <= T1_is_mmio_write;
        end
    end

    /* T3: assign value */
    logic [2:0] user_clk_array [NUM_SUB_AFUS-1:0];
    t_if_ccip_c2_Tx T3_Tx_c2;
	logic T3_is_ctl_mmio;
	logic T3_is_read;
    logic [127:0] mgr_id;
    assign mgr_id = 128'hd1d383aaca4c4c60a0a013a421139e69;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            for (int i=0; i<NUM_SUB_AFUS; i++)
            begin
                offset_array[i] <= 0;
                user_clk_array[i] <= 0;
            end

            T3_Tx_c2 <= 0;
            sub_afu_reset <= 0;
            T3_is_ctl_mmio <= 0;
            T3_is_read <= 0;
        end
        else
        begin
        	T3_is_ctl_mmio <= T2_is_ctl_mmio;
            if (T2_is_write && T2_is_ctl_mmio)
            begin
                if (T2_is_offset)
                begin
                    offset_array[T2_vmid] <= T2_data;
                end

                if (T2_is_reset)
                begin
                    sub_afu_reset <= T2_data;
                end
            end

            if (T2_is_read && T2_is_ctl_mmio)
            begin
                T3_Tx_c2.hdr.tid <= T2_tid;
                T3_Tx_c2.mmioRdValid <= 1;

                if (T2_is_offset)
                begin
                    T3_Tx_c2.data <= offset_array[T2_vmid];
                end
                else if (T2_is_reset)
                begin
                    T3_Tx_c2.data <= sub_afu_reset;
                end
                else if (T2_is_nafus)
                begin
                    T3_Tx_c2.data <= NUM_SUB_AFUS;
                end
                else if (T2_is_dfh)
                begin
                    T3_Tx_c2.data <= t_ccip_mmioData'(0);
                    T3_Tx_c2.data[63:60] <= 4'h1;
                    T3_Tx_c2.data[40] <= 1'b1;
                end
                else if (T2_is_id_lo)
                begin
                    T3_Tx_c2.data <= mgr_id[63:0];
                end
                else if (T2_is_id_hi)
                begin
                    T3_Tx_c2.data <= mgr_id[127:64];
                end
                else
                begin
                    T3_Tx_c2.data <= 64'hffffffffffffffff;
                end
            end
            else
            begin
                T3_Tx_c2 <= 0;
            end
            T3_is_read <= T2_is_read;
        end
    end
	
    /* T4 (T2): output */
    /* we do not support read and write from mgr_afu */

    logic fifo_c0tx_rdack, fifo_c0tx_dout_v, fifo_c0tx_full, fifo_c0tx_almFull;
    t_if_ccip_c0_Tx fifo_c0tx_dout;
	logic fifo_c1tx_rdack, fifo_c1tx_dout_v, fifo_c1tx_full, fifo_c1tx_almFull;
    t_if_ccip_c1_Tx fifo_c1tx_dout;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            afu_RxPort.c0.mmioRdValid <= 0;
            afu_RxPort.c0.mmioWrValid <= 0;
            afu_RxPort.c0.rspValid <= 0;
            afu_RxPort.c1.rspValid <= 0;
        end
        else
        begin
        	if (!T2_is_ctl_mmio)
        		afu_RxPort.c0 <= T2_Rx_temp.c0;
        	else
        		afu_RxPort.c0 <= 0;

            afu_RxPort.c1 <= T2_Rx_temp.c1;
            afu_RxPort.c0TxAlmFull <= fifo_c0tx_almFull;
            afu_RxPort.c1TxAlmFull <= fifo_c1tx_almFull;
        end
    end
    
    
    //handle c0tx
    
    logic c0tx_is_ok, c0tx_is_ok_T1, c0tx_is_ok_T2;
    assign c0tx_is_ok = fifo_c0tx_dout_v && (!pck_cp2af_sRx.c0TxAlmFull);
	sync_C1Tx_fifo #(
		.DATA_WIDTH($bits(t_if_ccip_c0_Tx)),
		.CTL_WIDTH(0),
		.DEPTH_BASE2($clog2(24)),
		.GRAM_MODE(3),
		.FULL_THRESH(24-12)
	)
	inst_fifo_c0tx(
		.Resetb(reset_r),
		.Clk(clk),
		.fifo_din(afu_TxPort.c0),
		.fifo_ctlin(),
		.fifo_wen(afu_TxPort.c0.valid),
		.fifo_rdack(fifo_c0tx_rdack),
		.T2_fifo_dout(fifo_c0tx_dout),
		.T0_fifo_ctlout(),
		.T0_fifo_dout_v(fifo_c0tx_dout_v),
		.T0_fifo_empty(fifo_c0tx_empty),
		.T0_fifo_full(fifo_c0tx_full),
		.T0_fifo_count(),
		.T0_fifo_almFull(fifo_c0tx_almFull),
		.T0_fifo_underflow(),
		.T0_fifo_overflow()
		);
    assign fifo_c0tx_rdack = c0tx_is_ok;
    always_ff @(posedge clk)
    begin
    	if (c0tx_is_ok_T2) 
    		pck_af2cp_sTx.c0 <= fifo_c0tx_dout;
        else
            pck_af2cp_sTx.c0.valid <= 0;

        c0tx_is_ok_T2 <= c0tx_is_ok_T1;
        c0tx_is_ok_T1 <= c0tx_is_ok;
    end
    
    //handle c1tx
    logic c1tx_is_ok, c1tx_is_ok_T1, c1tx_is_ok_T2;
    assign c1tx_is_ok = fifo_c1tx_dout_v && (!pck_cp2af_sRx.c1TxAlmFull);
	sync_C1Tx_fifo #(
		.DATA_WIDTH($bits(t_if_ccip_c1_Tx)),
		.CTL_WIDTH(0),
		.DEPTH_BASE2($clog2(24)),
		.GRAM_MODE(3),
		.FULL_THRESH(24-12)
	)
	inst_fifo_c1tx(
		.Resetb(reset_r),
		.Clk(clk),
		.fifo_din(afu_TxPort.c1),
		.fifo_ctlin(),
		.fifo_wen(afu_TxPort.c1.valid),
		.fifo_rdack(fifo_c1tx_rdack),
		.T2_fifo_dout(fifo_c1tx_dout),
		.T0_fifo_ctlout(),
		.T0_fifo_dout_v(fifo_c1tx_dout_v),
		.T0_fifo_empty(fifo_c1tx_empty),
		.T0_fifo_full(fifo_c1tx_full),
		.T0_fifo_count(),
		.T0_fifo_almFull(fifo_c1tx_almFull),
		.T0_fifo_underflow(),
		.T0_fifo_overflow()
		);
    assign fifo_c1tx_rdack = c1tx_is_ok;
	always_ff @(posedge clk)
    begin
    	if (c1tx_is_ok_T2) 
    		pck_af2cp_sTx.c1 <= fifo_c1tx_dout;
        else
            pck_af2cp_sTx.c1.valid <= 0;

        c1tx_is_ok_T2 <= c1tx_is_ok_T1;
        c1tx_is_ok_T1 <= c1tx_is_ok;
    end
    
	logic fifo_c2tx_rdack, fifo_c2tx_dout_v, fifo_c2tx_full, fifo_c2tx_almFull;
    t_if_ccip_c2_Tx fifo_c2tx_dout;
    logic fifo_c2tx_dout_v_T1, fifo_c2tx_dout_v_T2;
	sync_C1Tx_fifo #(
		.DATA_WIDTH($bits(t_if_ccip_c2_Tx)),
		.CTL_WIDTH(0),
		.DEPTH_BASE2($clog2(24)),
		.GRAM_MODE(3),
		.FULL_THRESH(24-12)
	)
	inst_fifo_c2tx(
		.Resetb(reset_r),
		.Clk(clk),
		.fifo_din(afu_TxPort.c2),
		.fifo_ctlin(),
		.fifo_wen(afu_TxPort.c2.mmioRdValid),
		.fifo_rdack(fifo_c2tx_rdack),
		.T2_fifo_dout(fifo_c2tx_dout),
		.T0_fifo_ctlout(),
		.T0_fifo_dout_v(fifo_c2tx_dout_v),
		.T0_fifo_empty(fifo_c2tx_empty),
		.T0_fifo_full(fifo_c2tx_full),
		.T0_fifo_count(),
		.T0_fifo_almFull(fifo_c2tx_almFull),
		.T0_fifo_underflow(),
		.T0_fifo_overflow()
		);
    assign fifo_c2tx_rdack = fifo_c2tx_dout_v;
	always_ff @(posedge clk)
    begin
    	if (T3_is_read && T3_is_ctl_mmio) 
    	begin
    		pck_af2cp_sTx.c2 <= T3_Tx_c2;
    	end 
    	else 
    	begin
    		if (fifo_c2tx_dout_v_T2)
    			pck_af2cp_sTx.c2 <= fifo_c2tx_dout;
            else
                pck_af2cp_sTx.c2.mmioRdValid <= 0;
    	end 
    	
        fifo_c2tx_dout_v_T2 <= fifo_c2tx_dout_v_T1;
        fifo_c2tx_dout_v_T1 <= fifo_c2tx_dout_v;	
    end	



endmodule
