`include "platform_if.vh"
`include "afu_json_info.vh"

module ccip_std_afu
    (
        input           logic             pClk,
        input           logic             pClkDiv2,
        input           logic             pClkDiv4,
        input           logic             uClk_usr,
        input           logic             uClk_usrDiv2,
        input           logic             pck_cp2af_softReset,
        input           logic [1:0]       pck_cp2af_pwrState,
        input           logic             pck_cp2af_error,

        // Interface structures
        input           t_if_ccip_Rx      pck_cp2af_sRx,
        output          t_if_ccip_Tx      pck_af2cp_sTx
    );

    // set clock and reset 
    logic clk, reset, reset_r;

    assign clk = pClk;
    assign reset = pck_cp2af_softReset;
    assign reset_r = ~pck_cp2af_softReset;

    logic [127:0] afu_id = `AFU_ACCEL_UUID;

    t_ccip_c0_ReqMmioHdr mmio_req_hdr;
    assign mmio_req_hdr = t_ccip_c0_ReqMmioHdr'(pck_cp2af_sRx.c0.hdr);

    // setup fifo and sRx and sTx
    //
    t_if_ccip_Rx sRx;
    t_if_ccip_Tx sTx;

    // Rx
    always_comb
    begin
        sRx <= pck_cp2af_sRx;
    end

    // Tx
    always_comb
    begin
        pck_af2cp_sTx.c0  <= sTx.c0;
        pck_af2cp_sTx.c2  <= sTx.c2;
    end

    // sTx.c1 buffer(fifo)
    logic fifo_c1tx_rdack, fifo_c1tx_dout_v, fifo_c1tx_full, fifo_c1tx_almFull;
    t_if_ccip_c1_Tx fifo_c1tx_dout;
    sync_C1Tx_fifo #(
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
        .T0_fifo_empty(fifo_c1tx_empty),
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
        end
        else
        begin
            fifo_c1tx_dout_v_q <= fifo_c1tx_dout_v;
            fifo_c1tx_dout_v_qq <= fifo_c1tx_dout_v_q;

            if (fifo_c1tx_dout_v_qq)
                pck_af2cp_sTx.c1 <= fifo_c1tx_dout;
            else
                pck_af2cp_sTx.c1 <= t_if_ccip_c1_Tx'(0);
        end
    end

    // mmio read and write 

    // afu mmio writes
    t_ccip_clAddr buf_addr;
    t_ccip_clAddr bufcpy_addr;
    logic [64:0] size;

    // afu state
    logic start_traversal;
    logic end_traversal;
    logic [64:0] written_size;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            buf_addr        <= 0;
            bufcpy_addr     <= 0;
            size            <= 0;
        end
        else
        begin
            sTx.c2.mmioRdValid <= 0;

            if (sRx.c0.mmioWrValid)
            begin
                case (mmio_req_hdr.address)
                    16'h22: buf_addr        <= t_ccip_clAddr'(sRx.c0.data);
                    16'h24: bufcpy_addr     <= t_ccip_clAddr'(sRx.c0.data);
                    16'h26: size            <= sRx.c0.data >> 6;
                endcase
            end

            // serve MMIO read requests
            if (sRx.c0.mmioRdValid)
            begin
                sTx.c2.hdr.tid <= mmio_req_hdr.tid; // copy TID

                case (mmio_req_hdr.address)
                    // AFU header
                    16'h0000: sTx.c2.data <=
                        {
                            4'b0001, // Feature type = AFU
                            8'b0,    // reserved
                            4'b0,    // afu minor revision = 0
                            7'b0,    // reserved
                            1'b1,    // end of DFH list = 1
                            24'b0,   // next DFH offset = 0
                            4'b0,    // afu major revision = 0
                            12'b0    // feature ID = 0
                        };
                    16'h0002: sTx.c2.data <= afu_id[63:0]; // afu id low
                    16'h0004: sTx.c2.data <= afu_id[127:64]; // afu id hi
                    16'h0006: sTx.c2.data <= 64'h0; // reserved
                    16'h0008: sTx.c2.data <= 64'h0; // reserved
                    default:  sTx.c2.data <= 64'h0;
                endcase
                sTx.c2.mmioRdValid <= 1;
            end
        end
    end

    always_comb
    begin
        start_traversal <= (buf_addr != 0) && (bufcpy_addr != 0);
        end_traversal   <= (written_size >= size) && start_traversal;
    end

    typedef enum logic[1:0] {
        STATE_IDLE,
        STATE_RUN
    } t_state;

    t_state state;

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
                    if (start_traversal && !end_traversal)
                    begin
                        state <= STATE_RUN;
                        $display("Running afu...");
                    end
                STATE_RUN:
                    if (end_traversal)
                    begin
                        state <= STATE_IDLE;
                        $display("Copying done...");
                    end
            endcase
        end
    end

    // read logic
    // this wraps at 0xffff(65535 elements this code can copy upto 4MB)
    t_ccip_mdata read_mdata;
    logic [64:0] read_size;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            sTx.c0.valid <= 0;
            sTx.c0.hdr   <= 0;
            read_size   <= 0;
            read_mdata  <= 0;
        end
        else
        begin
            sTx.c0.valid <= (buf_addr != 0 && ! sRx.c0TxAlmFull && state == STATE_RUN && !fifo_c1tx_almFull && read_size < size);

            if (buf_addr != 0 && ! sRx.c0TxAlmFull && state == STATE_RUN && !fifo_c1tx_almFull && read_size < size)
            begin
                read_size <= read_size + 1;
                read_mdata <= read_mdata + 1;
            end
            sTx.c0.hdr.vc_sel <= eVC_VA;
            sTx.c0.hdr.cl_len <= eCL_LEN_1;
            sTx.c0.hdr.mdata <= read_mdata;
            sTx.c0.hdr.address   <= buf_addr + read_mdata;
        end
    end

    // read response logic
    t_ccip_clData rd_data;
    t_ccip_mdata  write_mdata;

    logic can_send_write_req;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            rd_data <= 0;
            write_mdata <= 0;
        end
        else if (sRx.c0.rspValid)
        begin
            rd_data <= sRx.c0.data;
            write_mdata <= sRx.c0.hdr.mdata;
            can_send_write_req <= 1;
        end
        else
        begin
            can_send_write_req <= 0;
        end
    end


    // write logic

    t_ccip_c1_ReqMemHdr wr_hdr;

    always_comb
    begin
        wr_hdr <= t_ccip_c1_ReqMemHdr'(0);
        wr_hdr.sop <= 1'b1;

        wr_hdr.address <= bufcpy_addr + write_mdata;
    end

    // send write
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            sTx.c1.valid <= 0;
            sTx.c1.hdr <= 0;
        end
        else
        begin
            sTx.c1.valid <= (state == STATE_RUN  && can_send_write_req);
            sTx.c1.data <= rd_data;
            sTx.c1.hdr <= wr_hdr;
        end
    end

    // write response

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            written_size <= 0;
        end

        else if (sRx.c1.rspValid)
        begin
            written_size <= written_size + 1;
        end
    end

endmodule
