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

    /* reset fanout */
    logic reset_q;
    logic reset_qq[N_SUBAFUS-1:0];
    always_ff @(posedge clk)
    begin
        reset_q <= reset;
        for (int i=0; i<N_SUBAFUS; i++)
            reset_qq[i] <= reset_q;
    end

    localparam LOG_N_SUBAFUS = $clog2(N_SUBAFUS);

    /* tx_to_fifo */

    logic fifo_c0_almostFull [N_SUBAFUS-1:0];
    logic fifo_c1_almostFull [N_SUBAFUS-1:0];
    logic fifo_c2_almostFull [N_SUBAFUS-1:0];

    logic fifo_c0_notEmpty [N_SUBAFUS-1:0];
    logic fifo_c1_notEmpty [N_SUBAFUS-1:0];
    logic fifo_c2_notEmpty [N_SUBAFUS-1:0];

    t_if_ccip_c0_Tx fifo_c0_first [N_SUBAFUS-1:0];
    t_if_ccip_c1_Tx fifo_c1_first [N_SUBAFUS-1:0];
    t_if_ccip_c2_Tx fifo_c2_first [N_SUBAFUS-1:0];

    logic fifo_c0_deq_en [N_SUBAFUS-1:0];
    logic fifo_c1_deq_en [N_SUBAFUS-1:0];
    logic fifo_c2_deq_en [N_SUBAFUS-1:0];

    generate
        genvar i;
        for (i=0; i<N_SUBAFUS; i++)
        begin: gen_tx_to_fifo
            tx_to_fifo #(
                .N_ENTRIES(32)
            )
            inst_tx_to_fifo(
                .clk(clk),
                .reset(reset_qq[i]),
                .afu_TxPort(in[i]),
                .out_fifo_c0_almostFull(fifo_c0_almostFull[i]),
                .out_fifo_c0_notEmpty(fifo_c0_notEmpty[i]),
                .out_fifo_c0_first(fifo_c0_first[i]),
                .in_fifo_c0_deq_en(fifo_c0_deq_en[i]),
                .out_fifo_c1_almostFull(fifo_c1_almostFull[i]),
                .out_fifo_c1_notEmpty(fifo_c1_notEmpty[i]),
                .out_fifo_c1_first(fifo_c1_first[i]),
                .in_fifo_c1_deq_en(fifo_c1_deq_en[i]),
                .out_fifo_c2_almostFull(fifo_c2_almostFull[i]),
                .out_fifo_c2_notEmpty(fifo_c2_notEmpty[i]),
                .out_fifo_c2_first(fifo_c2_first[i]),
                .in_fifo_c2_deq_en(fifo_c2_deq_en[i])
                );
        end
    endgenerate


    /* T1: maintain index */

    logic [LOG_N_SUBAFUS-1:0] T1_curr;
    logic T1_c0_valid;
    logic T1_c1_valid;
    logic T1_c2_valid;

    logic T1_c0_almFull [N_SUBAFUS-1:0];
    logic T1_c1_almFull [N_SUBAFUS-1:0];
    
    always_ff @(posedge clk)
    begin
        if (reset_q)
        begin
            T1_curr <= 0;
            T1_c0_valid <= 0;
            T1_c1_valid <= 0;
            T1_c2_valid <= 0;

            for (int i=0; i<N_SUBAFUS; i++)
            begin
                T1_c0_almFull[i] <= 0;
                T1_c1_almFull[i] <= 0;
            end
        end
        else
        begin
            if (T1_curr == N_SUBAFUS-1)
            begin
                T1_curr <= 0;
            end
            else
            begin
                T1_curr <= T1_curr + 1;
            end

            T1_c0_valid <= fifo_c0_notEmpty[T1_curr];
            T1_c1_valid <= fifo_c1_notEmpty[T1_curr];
            T1_c2_valid <= fifo_c2_notEmpty[T1_curr];

            T1_c0_almFull <= fifo_c0_almostFull;
            T1_c1_almFull <= fifo_c1_almostFull;

            for (int i=0; i<N_SUBAFUS; i++)
            begin
                if (i == T1_curr)
                begin
                    fifo_c0_deq_en[i] <= fifo_c0_notEmpty[i];
                    fifo_c1_deq_en[i] <= fifo_c1_notEmpty[i];
                    fifo_c2_deq_en[i] <= fifo_c2_notEmpty[i];
                end
                else
                begin
                    fifo_c0_deq_en[i] <= 0;
                    fifo_c1_deq_en[i] <= 0;
                    fifo_c2_deq_en[i] <= 0;
                end
            end
        end
    end


    /* T2: read out the fifo */

    logic [LOG_N_SUBAFUS-1:0] T2_curr;

    logic T2_c0_valid;
    logic T2_c1_valid;
    logic T2_c2_valid;

    logic T2_c0_almFull [N_SUBAFUS-1:0];
    logic T2_c1_almFull [N_SUBAFUS-1:0];

    t_if_ccip_c0_Tx T2_c0;
    t_if_ccip_c1_Tx T2_c1;
    t_if_ccip_c2_Tx T2_c2;

    always_ff @(posedge clk)
    begin
        T2_curr <= T1_curr;

        T2_c0_valid <= T1_c0_valid;
        T2_c1_valid <= T1_c1_valid;
        T2_c2_valid <= T1_c2_valid;

        T2_c0_almFull <= T1_c0_almFull;
        T2_c1_almFull <= T1_c1_almFull;

        if (T1_c0_valid)
        begin
            T2_c0 <= fifo_c0_first[T2_curr];
        end

        if (T1_c1_valid)
        begin
            T2_c1 <= fifo_c1_first[T2_curr];
        end

        if (T1_c2_valid)
        begin
            T2_c2 <= fifo_c2_first[T2_curr];
        end
    end

    /* T3: output */
    t_if_ccip_Tx T3_Tx;

    logic T3_c0_almFull [N_SUBAFUS-1:0];
    logic T3_c1_almFull [N_SUBAFUS-1:0];

    always_ff @(posedge clk)
    begin
        if (reset_q)
        begin
            T3_Tx <= 0;

            for (int i=0; i<N_SUBAFUS; i++)
            begin
                T3_c0_almFull[i] <= 0;
                T3_c1_almFull[i] <= 0;
            end
        end
        else 
        begin
            T3_c0_almFull <= T2_c0_almFull;
            T3_c1_almFull <= T2_c1_almFull;

            if (T2_c0_valid)
            begin
                T3_Tx.c0 <= T2_c0;
            end
            else
            begin
                T3_Tx.c0 <= 0;
            end

            if (T2_c1_valid)
            begin
                T3_Tx.c1 <= T2_c1;
            end
            else
            begin
                T3_Tx.c1 <= 0;
            end

            if (T2_c2_valid)
            begin
                T3_Tx.c2 <= T2_c2;
            end
            else
            begin
                T3_Tx.c2 <= 0;
            end
        end
    end

    assign out = T3_Tx;
    assign c0_almFull = T3_c0_almFull;
    assign c1_almFull = T3_c1_almFull;

endmodule
