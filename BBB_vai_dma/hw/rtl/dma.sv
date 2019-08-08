`include "dma.vh"

module dma(
    input   logic           clk,
    input   logic           soft_reset,

    input   from_afu        afu_to_dma,
    output  to_afu          dma_to_afu
);
    logic reset, reset_r;

    always @(posedge clk)
    begin
        reset   <= soft_reset | afu_to_dma.d_in.begin_copy;
        reset_r <= ~soft_reset & ~afu_to_dma.d_in.begin_copy;
    end

    t_if_ccip_c1_Tx  sTx_c1_fifo;

    // sTx.c1 buffer(fifo)
    logic fifo_c1tx_rdack, fifo_c1tx_dout_v, fifo_c1tx_full, fifo_c1tx_almFull;
    t_if_ccip_c1_Tx fifo_c1tx_dout;
    fifo #(
        .DATA_WIDTH($bits(t_if_ccip_c1_Tx)),
        .CTL_WIDTH(0),
        .DEPTH_BASE2($clog2(64)),
        .GRAM_MODE(3),
        .FULL_THRESH(64-8)
    )
    inst_fifo_c1tx(
        .Resetb(reset_r),
        .Clk(clk),
        .fifo_din(sTx_c1_fifo),
        .fifo_ctlin(),
        .fifo_wen(sTx_c1_fifo.valid),
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

    assign dma_to_afu.d_out.wr_ready = !fifo_c1tx_almFull;

    logic fifo_c1tx_dout_v_q, fifo_c1tx_dout_v_qq;
    assign fifo_c1tx_rdack = fifo_c1tx_dout_v && !afu_to_dma.sRx.c1TxAlmFull; // && !fifo_c1tx_empty;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            fifo_c1tx_dout_v_q <= 0;
            fifo_c1tx_dout_v_qq <= 0;
            dma_to_afu.sTx.c1 <= 0;
        end
        else
        begin
            fifo_c1tx_dout_v_q <= fifo_c1tx_rdack;
            fifo_c1tx_dout_v_qq <= fifo_c1tx_dout_v_q;

            if (fifo_c1tx_dout_v_qq)
                dma_to_afu.sTx.c1 <= fifo_c1tx_dout;
            else
                dma_to_afu.sTx.c1 <= t_if_ccip_c1_Tx'(0);
        end
    end

    logic fifo_c0rx_rdack, fifo_c0rx_dout_v, fifo_c0rx_full, fifo_c0rx_almFull;
    t_if_ccip_c0_Rx fifo_c0Rx_dout;
    fifo #(
        .DATA_WIDTH($bits(t_ccip_clData)),
        .CTL_WIDTH(0),
        .DEPTH_BASE2($clog2(64)),
        .GRAM_MODE(3),
        .FULL_THRESH(64-8)
    )
    inst_fifo_c0rx(
        .Resetb(reset_r),
        .Clk(clk),
        .fifo_din(afu_to_dma.sRx.c0.data),
        .fifo_ctlin(),
        .fifo_wen(afu_to_dma.sRx.c0.rspValid),
        .fifo_rdack(fifo_c0rx_rdack),
        .T2_fifo_dout(fifo_c0rx_dout),
        .T0_fifo_ctlout(),
        .T0_fifo_dout_v(fifo_c0rx_dout_v),
        .T0_fifo_empty(fifo_c0rx_empty),
        .T0_fifo_full(fifo_c0rx_full),
        .T0_fifo_count(),
        .T0_fifo_almFull(fifo_c0rx_almFull),
        .T0_fifo_underflow(),
        .T0_fifo_overflow()
    );

    logic fifo_c0rx_dout_v_q, fifo_c0rx_dout_v_qq;
    assign fifo_c0rx_rdack = fifo_c0rx_dout_v && afu_to_dma.d_in.rd_ready;

    t_if_ccip_Rx sRx;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            fifo_c0rx_dout_v_q <= 0;
            fifo_c0rx_dout_v_qq <= 0;
            sRx <= 0;
        end
        else
        begin
            fifo_c0rx_dout_v_q <= fifo_c0rx_rdack;
            fifo_c0rx_dout_v_qq <= fifo_c0rx_dout_v_q;

            sRx.c0 <= fifo_c0rx_dout;

            if (fifo_c0rx_dout_v_qq)
            begin
                dma_to_afu.d_out.rd_data <= fifo_c0rx_dout;
                dma_to_afu.d_out.rd_out  <= 1;
            end
            else
            begin
                dma_to_afu.d_out.rd_data <= 0;
                dma_to_afu.d_out.rd_out  <= 0;
            end
        end
    end

    logic increment;
    t_ccip_clAddr b_buf_addr;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            b_buf_addr <= 0;
        end
        else
        begin
            if (b_buf_addr == 0)
            begin
                b_buf_addr <= afu_to_dma.d_in.rd_addr;
            end

            if (increment)
            begin
                b_buf_addr <= b_buf_addr + 1;
            end
        end
    end

    logic [64:0] written_size;
    logic start_traversal, end_traversal;

    assign dma_to_afu.d_out.finished = end_traversal;

    always_comb
    begin
        start_traversal <= (b_buf_addr != 0) && (afu_to_dma.d_in.wr_addr != 0);
        end_traversal   <= (written_size >= afu_to_dma.d_in.wr_len) && start_traversal;
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
                    end
                STATE_RUN:
                    if (end_traversal)
                    begin
                        state <= STATE_IDLE;
                    end
            endcase
        end
    end

    // read logic
    t_ccip_c0_ReqMemHdr rd_hdr;
    logic [64:0] read_size;
    logic [64:0] next_write_idx;

    logic read_valid, read_valid_q;
    assign read_valid = !afu_to_dma.sRx.c0TxAlmFull & state == STATE_RUN & read_size < afu_to_dma.d_in.rd_len & !increment & !fifo_c1tx_almFull & !afu_to_dma.sRx.c1TxAlmFull & !fifo_c0rx_almFull;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            dma_to_afu.sTx.c0.valid <= 0;
            dma_to_afu.sTx.c0.hdr   <= 0;
            read_size    <= 0;
            increment    <= 0;
        end
        else
        begin
            dma_to_afu.sTx.c0.valid <= read_valid;

            if (read_valid)
            begin
                read_size <= read_size + 1;
                increment <= 1;
            end
            else
            begin
                increment <= 0;
            end

            dma_to_afu.sTx.c0.hdr.vc_sel    <= eVC_VA;
            dma_to_afu.sTx.c0.hdr.cl_len    <= eCL_LEN_1;
            dma_to_afu.sTx.c0.hdr.address   <= b_buf_addr;
        end
    end

    // read response logic
    t_ccip_clData rd_data;

    // logic can_send_write_req;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            rd_data <= 0;
        end
        else if (afu_to_dma.sRx.c0.rspValid)
        begin
            rd_data <= afu_to_dma.sRx.c0.data;
        end
    end


    // write logic

    t_ccip_c1_ReqMemHdr wr_hdr;

    always_comb
    begin
        wr_hdr <= t_ccip_c1_ReqMemHdr'(0);
        wr_hdr.sop <= 1'b1;

        wr_hdr.address <= afu_to_dma.d_in.wr_addr + next_write_idx;
    end

    // send write
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            sTx_c1_fifo.valid <= 0;
            sTx_c1_fifo.hdr <= 0;
            next_write_idx <= 0;
        end
        else
        begin
            sTx_c1_fifo.valid <= (state == STATE_RUN  && afu_to_dma.d_in.wr_out && dma_to_afu.d_out.wr_ready);
            if (state == STATE_RUN  && afu_to_dma.d_in.wr_out && dma_to_afu.d_out.wr_ready)
            begin
                next_write_idx <= next_write_idx + 1;
            end
            sTx_c1_fifo.data <= afu_to_dma.d_in.wr_data;
            sTx_c1_fifo.hdr <= wr_hdr;
        end
    end

    // write response

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            written_size <= 0;
        end

        else if (afu_to_dma.sRx.c1.rspValid)
        begin
            written_size <= written_size + 1;
        end
    end

endmodule
