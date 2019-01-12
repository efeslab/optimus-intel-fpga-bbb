import ccip_if_pkg::*;
`include "vendor_defines.vh"

module tx_mux #(parameter N_SUBAFUS=16)
(
    input wire clk,
    input wire reset,

    input t_if_ccip_Tx in [N_SUBAFUS-1:0],
    output t_if_ccip_Tx out,

    output wire c0_almFull [N_SUBAFUS-1:0],
    output wire c1_almFull [N_SUBAFUS-1:0]
);

    genvar i;

    localparam LOGN_SUBAFUS = $clog2(N_SUBAFUS);

    /* --------- reset fan-out ----------- */
    logic reset_q;
    logic reset_qq [N_SUBAFUS-1:0];
    logic reset_qq_r [N_SUBAFUS-1:0];
    always_ff @(posedge clk)
    begin
        reset_q <= reset;
        for (int i=0; i<N_SUBAFUS; i++)
        begin
            reset_qq[i] <= reset_q;
            reset_qq_r[i] <= ~reset_q;
        end
    end

    /* --------------- fifo ---------------- */
    /* c0 fifo */
    t_if_ccip_c0_Tx     fifo_c0_din         [N_SUBAFUS-1:0];
    t_if_ccip_c0_Tx     fifo_c0_dout        [N_SUBAFUS-1:0];
    logic               fifo_c0_wen         [N_SUBAFUS-1:0];
    logic               fifo_c0_rdack       [N_SUBAFUS-1:0];
    logic               fifo_c0_dout_v      [N_SUBAFUS-1:0];
    logic               fifo_c0_empty       [N_SUBAFUS-1:0];
    logic               fifo_c0_full        [N_SUBAFUS-1:0];
    logic               fifo_c0_almFull     [N_SUBAFUS-1:0];

    generate
        for (i=0; i<N_SUBAFUS; i++)
        begin: GEN_FIFO_C0
            sync_C1Tx_fifo #(
                .DATA_WIDTH($bits(t_if_ccip_c0_Tx)),
                .CTL_WIDTH(0),
                .DEPTH_BASE2($clog2(32)),
                .GRAM_MODE(3),
                .FULL_THRESH(32-8)
            )
            inst_fifo_c0(
                .Resetb(reset_qq_r[i]),
                .Clk(clk),
                .fifo_din(fifo_c0_din[i]),
                .fifo_ctlin(),
                .fifo_wen(fifo_c0_wen[i]),
                .fifo_rdack(fifo_c0_rdack[i]),
                .T2_fifo_dout(fifo_c0_dout[i]),
                .T0_fifo_ctlout(),
                .T0_fifo_dout_v(fifo_c0_dout_v[i]),
                .T0_fifo_empty(fifo_c0_empty[i]),
                .T0_fifo_full(fifo_c0_full[i]),
                .T0_fifo_count(),
                .T0_fifo_almFull(fifo_c0_almFull[i]),
                .T0_fifo_underflow(),
                .T0_fifo_overflow()
                );
        end
    endgenerate

    /* c1 fifo */
    t_if_ccip_c1_Tx     fifo_c1_din         [N_SUBAFUS-1:0];
    t_if_ccip_c1_Tx     fifo_c1_dout        [N_SUBAFUS-1:0];
    logic               fifo_c1_wen         [N_SUBAFUS-1:0];
    logic               fifo_c1_rdack       [N_SUBAFUS-1:0];
    logic               fifo_c1_dout_v      [N_SUBAFUS-1:0];
    logic               fifo_c1_empty       [N_SUBAFUS-1:0];
    logic               fifo_c1_full        [N_SUBAFUS-1:0];
    logic               fifo_c1_almFull     [N_SUBAFUS-1:0];

    generate
        for (i=0; i<N_SUBAFUS; i++)
        begin: GEN_FIFO_C1
            sync_C1Tx_fifo #(
                .DATA_WIDTH($bits(t_if_ccip_c1_Tx)),
                .CTL_WIDTH(0),
                .DEPTH_BASE2($clog2(32)),
                .GRAM_MODE(3),
                .FULL_THRESH(32-8)
            )
            inst_fifo_c1(
                .Resetb(reset_qq_r[i]),
                .Clk(clk),
                .fifo_din(fifo_c1_din[i]),
                .fifo_ctlin(),
                .fifo_wen(fifo_c1_wen[i]),
                .fifo_rdack(fifo_c1_rdack[i]),
                .T2_fifo_dout(fifo_c1_dout[i]),
                .T0_fifo_ctlout(),
                .T0_fifo_dout_v(fifo_c1_dout_v[i]),
                .T0_fifo_empty(fifo_c1_empty[i]),
                .T0_fifo_full(fifo_c1_full[i]),
                .T0_fifo_count(),
                .T0_fifo_almFull(fifo_c1_almFull[i]),
                .T0_fifo_underflow(),
                .T0_fifo_overflow()
                );
        end
    endgenerate

    /* c2 fifo */
    t_if_ccip_c2_Tx     fifo_c2_din         [N_SUBAFUS-1:0];
    t_if_ccip_c2_Tx     fifo_c2_dout        [N_SUBAFUS-1:0];
    logic               fifo_c2_wen         [N_SUBAFUS-1:0];
    logic               fifo_c2_rdack       [N_SUBAFUS-1:0];
    logic               fifo_c2_dout_v      [N_SUBAFUS-1:0];
    logic               fifo_c2_empty       [N_SUBAFUS-1:0];
    logic               fifo_c2_full        [N_SUBAFUS-1:0];
    logic               fifo_c2_almFull     [N_SUBAFUS-1:0];

    generate
        for (i=0; i<N_SUBAFUS; i++)
        begin: GEN_FIFO_C2
            sync_C1Tx_fifo #(
                .DATA_WIDTH($bits(t_if_ccip_c2_Tx)),
                .CTL_WIDTH(0),
                .DEPTH_BASE2($clog2(32)),
                .GRAM_MODE(3),
                .FULL_THRESH(32-8)
            )
            inst_fifo_c2(
                .Resetb(reset_qq_r[i]),
                .Clk(clk),
                .fifo_din(fifo_c2_din[i]),
                .fifo_ctlin(),
                .fifo_wen(fifo_c2_wen[i]),
                .fifo_rdack(fifo_c2_rdack[i]),
                .T2_fifo_dout(fifo_c2_dout[i]),
                .T0_fifo_ctlout(),
                .T0_fifo_dout_v(fifo_c2_dout_v[i]),
                .T0_fifo_empty(fifo_c2_empty[i]),
                .T0_fifo_full(fifo_c2_full[i]),
                .T0_fifo_count(),
                .T0_fifo_almFull(fifo_c2_almFull[i]),
                .T0_fifo_underflow(),
                .T0_fifo_overflow()
                );
        end
    endgenerate

    /* ------------- enqueue ---------------- */
    generate
        for (i=0; i<N_SUBAFUS; i++)
        begin: GEN_ENQ
            /* enq: T0 */
            t_if_ccip_Tx T0_Tx;
            always_ff @(posedge clk)
            begin
                if (reset_qq[i])
                begin
                    T0_Tx <= t_if_ccip_Tx'(0);
                end
                else
                begin
                    T0_Tx <= in[i];
                end
            end

            /* enq: T1 */
            t_if_ccip_c0_Tx T1_c0;
            always_ff @(posedge clk)
            begin
                if (reset_qq[i])
                begin
                    T1_c0 <= 0;
                end
                else
                begin
                    if (T0_Tx.c0.valid & ~fifo_c0_full[i])
                    begin
                        fifo_c0_din[i] <= T0_Tx.c0;
                        fifo_c0_wen[i] <= 1;
                    end
                    else
                    begin
                        fifo_c0_wen[i] <= 0;
                    end

                    if (T0_Tx.c1.valid & ~fifo_c1_full[i])
                    begin
                        fifo_c1_din[i] <= T0_Tx.c1;
                        fifo_c1_wen[i] <= 1;
                    end
                    else
                    begin
                        fifo_c1_wen[i] <= 0;
                    end

                    if (T0_Tx.c2.mmioRdValid & ~fifo_c2_full[i])
                    begin
                        fifo_c2_din[i] <= T0_Tx.c2;
                        fifo_c2_wen[i] <= 1;
                    end
                    else
                    begin
                        fifo_c2_wen[i] <= 0;
                    end
                end
            end
        end
    endgenerate

    /* ---------------- dequeue ---------------- */
    /* deq: T0 */
    logic [LOGN_SUBAFUS-1:0] T0_curr;
    logic [LOGN_SUBAFUS-1:0] T0_curr_prefetch;
    logic T0_subafu_hit [N_SUBAFUS-1:0];

    generate
        for (i=0; i<N_SUBAFUS; i++)
        begin
            assign T0_subafu_hit[i] = (T0_curr == i);
        end
    endgenerate

    assign T0_curr_prefetch = (T0_curr == (N_SUBAFUS-1)) ? 0 : (T0_curr+1);
        
    always_ff @(posedge clk)
    begin
        if (reset_q)
        begin
            T0_curr <= 0;
        end
        else
        begin
            /* make it parallel */
            T0_curr <= T0_curr_prefetch;

            for (int i=0; i<N_SUBAFUS; i++)
            begin
                /* We only send ack if the id of subafu match T0_curr,
                 * plus the output of subafu is valid.
                 * The following code can be parallized better. */
                if (fifo_c0_dout_v[i])
                    fifo_c0_rdack[i] <= T0_subafu_hit[i];
                else
                    fifo_c0_rdack[i] <= 0;

                if (fifo_c1_dout_v[i])
                    fifo_c1_rdack[i] <= T0_subafu_hit[i];
                else
                    fifo_c1_rdack[i] <= 0;

                if (fifo_c2_dout_v[i])
                    fifo_c2_rdack[i] <= T0_subafu_hit[i];
                else
                    fifo_c2_rdack[i] <= 0;
            end
        end
    end

    /* deq: T1 */
    logic [LOGN_SUBAFUS-1:0] T1_curr;
    logic T1_c0_dout_v;
    logic T1_c1_dout_v;
    logic T1_c2_dout_v;

    always_ff @(posedge clk)
    begin
        T1_curr <= T0_curr;
        T1_c0_dout_v <= fifo_c0_dout_v[T0_curr];
        T1_c1_dout_v <= fifo_c1_dout_v[T0_curr];
        T1_c2_dout_v <= fifo_c2_dout_v[T0_curr];
    end

    /* deq: T2 */
    logic [LOGN_SUBAFUS-1:0] T2_curr;
    logic T2_c0_dout_v;
    logic T2_c1_dout_v;
    logic T2_c2_dout_v;

    always_ff @(posedge clk)
    begin
        T2_curr <= T1_curr;
        T2_c0_dout_v <= T1_c0_dout_v;
        T2_c1_dout_v <= T1_c1_dout_v;
        T2_c2_dout_v <= T1_c2_dout_v;
    end

    /* deq: T3 */
    t_if_ccip_Tx T3_Tx;
    logic [LOGN_SUBAFUS-1:0] T3_curr;

    t_if_ccip_Tx T3_Tx_prefetch;

    always_comb 
    begin
        T3_Tx_prefetch.c0 = fifo_c0_dout[T2_curr];
        T3_Tx_prefetch.c1 = fifo_c1_dout[T2_curr];
        T3_Tx_prefetch.c2 = fifo_c2_dout[T2_curr];
    end

    always_ff @(posedge clk)
    begin
        T3_curr <= T2_curr;

        if (T2_c0_dout_v)
            T3_Tx.c0 <= T3_Tx_prefetch.c0;
        else
            T3_Tx.c0 <= t_if_ccip_c0_Tx'(0);

        if (T2_c1_dout_v)
            T3_Tx.c1 <= T3_Tx_prefetch.c1;
        else
            T3_Tx.c1 <= t_if_ccip_c1_Tx'(0);

        if (T2_c2_dout_v)
            T3_Tx.c2 <= T3_Tx_prefetch.c2;
        else
            T3_Tx.c2 <= t_if_ccip_c2_Tx'(0);
    end

    /* dep: T4 */
    t_if_ccip_Tx T4_Tx;

    /* It seems like that T3 is too far from the output port,
     * so we add a stage here */
    always_ff @(posedge clk)
    begin
        if (reset_q)
        begin
            T4_Tx <= t_if_ccip_Tx'(0);
        end
        else
        begin
            T4_Tx <= T3_Tx;
        end
    end

    /* connection */
    assign out = T4_Tx;
    assign c0_almFull = fifo_c0_almFull;
    assign c1_almFull = fifo_c1_almFull;

endmodule
