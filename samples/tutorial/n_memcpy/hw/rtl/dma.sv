`include "platform_if.vh"

module dma(
    input   logic           clk,
    input   logic           soft_reset,

    // buffer related stuff
    input   logic [64:0]    size,
    input   t_ccip_clAddr   buf_addr,
    input   t_ccip_clAddr   bufcpy_addr,

    // Rx and Tx channels
    input   t_if_ccip_Rx    sRx,
    output  t_if_ccip_Tx    sTx,

    // fifo related
    output  t_if_ccip_Tx    sTx_c1,

    // finished copying
    output  logic           finished

);

    logic reset, reset_r;

    always @(posedge clk)
    begin
        reset   <= soft_reset;
        reset_r <= ~soft_reset;
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
            sTx_c1.c1 <= 0;
        end
        else
        begin
            fifo_c1tx_dout_v_q <= fifo_c1tx_dout_v && !sRx.c1TxAlmFull;
            fifo_c1tx_dout_v_qq <= fifo_c1tx_dout_v_q;

            if (fifo_c1tx_dout_v_qq)
                sTx_c1.c1 <= fifo_c1tx_dout;
            else
                sTx_c1.c1 <= t_if_ccip_c1_Tx'(0);
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
                b_buf_addr <= buf_addr;
            end

            if (increment)
            begin
                b_buf_addr <= b_buf_addr + 1;
            end
        end
    end

    logic [64:0] written_size;
    logic start_traversal, end_traversal;

    assign finished = end_traversal;

    always_comb
    begin
        start_traversal <= (b_buf_addr != 0) && (bufcpy_addr != 0);
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
                        $display("Running afu");
                        $display("Copying %d items", size);
                    end
                STATE_RUN:
                    if (end_traversal)
                    begin
                        state <= STATE_IDLE;
                        $display("copying done");
                    end
            endcase
        end
    end

    // read logic
    t_ccip_c0_ReqMemHdr rd_hdr;
    logic [64:0] read_size;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            sTx.c0.valid <= 0;
            sTx.c0.hdr   <= 0;
            read_size    <= 0;
            increment    <= 0;
        end
        else
        begin
            sTx.c0.valid <= (!sRx.c0TxAlmFull && state == STATE_RUN && !fifo_c1tx_almFull && read_size < size && !increment); // && read_size - written_size < 100);

            if (!sRx.c0TxAlmFull && state == STATE_RUN && !fifo_c1tx_almFull && read_size < size && !increment) // && read_size - written_size < 100)
            begin
                read_size <= read_size + 1;
                increment <= 1;
            end
            else
            begin
                increment <= 0;
            end

            sTx.c0.hdr.vc_sel    <= eVC_VA;
            sTx.c0.hdr.cl_len    <= eCL_LEN_1;
            sTx.c0.hdr.address   <= b_buf_addr;
        end
    end

    // read response logic
    t_ccip_clData rd_data;

    logic can_send_write_req;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            rd_data <= 0;
            //next_write_idx <= 0;
            can_send_write_req <= 0;
        end
        else if (sRx.c0.rspValid)
        begin
            rd_data <= sRx.c0.data;
            can_send_write_req <= 1;
        end
        else
        begin
            can_send_write_req <= 0;
        end
    end


    // write logic

    t_ccip_c1_ReqMemHdr wr_hdr;
    logic [64:0] next_write_idx;

    always_comb
    begin
        wr_hdr <= t_ccip_c1_ReqMemHdr'(0);
        wr_hdr.sop <= 1'b1;

        wr_hdr.address <= bufcpy_addr + next_write_idx;
    end

    // send write
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            sTx.c1.valid <= 0;
            sTx.c1.hdr <= 0;
            next_write_idx <= 0;
        end
        else
        begin
            sTx.c1.valid <= (state == STATE_RUN  && can_send_write_req);
            if (state == STATE_RUN  && can_send_write_req)
            begin
                next_write_idx <= next_write_idx + 1;
            end
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
            $display("Written no %d", written_size+1);
            written_size <= written_size + 1;
        end
    end

endmodule
