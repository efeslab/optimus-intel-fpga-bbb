import ccip_if_pkg::*;
`include "vendor_defines.vh"

module tx_to_fifo #(parameter N_ENTRIES=32)
(
    input wire clk,
    input wire reset,
    input t_if_ccip_Tx afu_TxPort,

    output wire out_fifo_c0_almostFull,
    output t_if_ccip_c0_Tx out_fifo_c0_first,
    input wire in_fifo_c0_deq_en,

    output wire out_fifo_c1_almostFull,
    output t_if_ccip_c1_Tx out_fifo_c1_first,
    input wire in_fifo_c1_deq_en,

    output wire out_fifo_c2_almostFull,
    output t_if_ccip_c2_Tx out_fifo_c2_first,
    input wire in_fifo_c2_deq_en
);

    /* fifo */
    t_if_ccip_c0_Tx fifo_c0_enq_data;
    t_if_ccip_c0_Tx fifo_c0_first;
    logic fifo_c0_enq_en;
    logic fifo_c0_notFull;
    logic fifo_c0_almostFull;
    logic fifo_c0_deq_en;
    logic fifo_c0_notEmpty;
    fifo_bram #(
        .N_DATA_BITS($bits(t_if_ccip_c0_Tx)),
        .N_ENTRIES(N_ENTRIES),
        .THRESHOLD(2)
    )
    fifo_c0(
        .clk(clk),
        .reset(reset),
        .enq_data(fifo_c0_enq_data),
        .enq_en(fifo_c0_enq_en),
        .notFull(fifo_c0_notFull),
        .almostFull(fifo_c0_almostFull),
        .first(fifo_c0_first),
        .deq_en(fifo_c0_deq_en),
        .notEmpty(fifo_c0_notEmpty)
        );

    t_if_ccip_c1_Tx fifo_c1_enq_data;
    t_if_ccip_c1_Tx fifo_c1_first;
    logic fifo_c1_enq_en;
    logic fifo_c1_notFull;
    logic fifo_c1_almostFull;
    logic fifo_c1_deq_en;
    logic fifo_c1_notEmpty;
    fifo_bram #(
        .N_DATA_BITS($bits(t_if_ccip_c1_Tx)),
        .N_ENTRIES(N_ENTRIES),
        .THRESHOLD(2)
    )
    fifo_c1(
        .clk(clk),
        .reset(reset),
        .enq_data(fifo_c1_enq_data),
        .enq_en(fifo_c1_enq_en),
        .notFull(fifo_c1_notFull),
        .almostFull(fifo_c1_almostFull),
        .first(fifo_c1_first),
        .deq_en(fifo_c1_deq_en),
        .notEmpty(fifo_c1_notEmpty)
        );

    t_if_ccip_c2_Tx fifo_c2_enq_data;
    t_if_ccip_c2_Tx fifo_c2_first;
    logic fifo_c2_enq_en;
    logic fifo_c2_notFull;
    logic fifo_c2_almostFull;
    logic fifo_c2_deq_en;
    logic fifo_c2_notEmpty;
    fifo_bram #(
        .N_DATA_BITS($bits(t_if_ccip_c2_Tx)),
        .N_ENTRIES(N_ENTRIES),
        .THRESHOLD(2)
    )
    fifo_c2(
        .clk(clk),
        .reset(reset),
        .enq_data(fifo_c2_enq_data),
        .enq_en(fifo_c2_enq_en),
        .notFull(fifo_c2_notFull),
        .almostFull(fifo_c2_almostFull),
        .first(fifo_c2_first),
        .deq_en(fifo_c2_deq_en),
        .notEmpty(fifo_c2_notEmpty)
        );


    /* T0 */
    t_if_ccip_Tx T0_Tx;
    assign T0_Tx = afu_TxPort;

    /* T1: register the input */
    t_if_ccip_c0_Tx T1_c0;
    t_if_ccip_c1_Tx T1_c1;
    t_if_ccip_c2_Tx T1_c2;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            T1_c0 <= t_if_ccip_c0_Tx'(0);
            T1_c1 <= t_if_ccip_c1_Tx'(0);
            T1_c2 <= t_if_ccip_c2_Tx'(0);
        end
        else
        begin
            T1_c0 <= T0_Tx.c0;
            T1_c1 <= T0_Tx.c1;
            T1_c2 <= T0_Tx.c2;
        end
    end

    /* T2: enque */
    t_if_ccip_c0_Tx T2_c0;
    t_if_ccip_c1_Tx T2_c1;
    t_if_ccip_c2_Tx T2_c2;

    always_ff @(posedge)
    begin
        if (reset)
        begin
            T2_c0 <= t_if_ccip_c0_Tx'(0);
            T2_c1 <= t_if_ccip_c1_Tx'(0);
            T2_c2 <= t_if_ccip_c2_Tx'(0);
        end
        else
        begin
            if (T1_c0.valid & fifo_c0_notFull)
            begin
                fifo_c0_enq_data <= T1_c0;
                fifo_c0_enq_en <= 1;
            end
            else
            begin
                fifo_c0_enq_data <= t_if_ccip_c0_Tx'(0);
                fifo_c0_enq_en <= 0;
            end

            if (T1_c1.valid & fifo_c1_notFull)
            begin
                fifo_c1_enq_data <= T1_c1;
                fifo_c1_enq_en <= 1;
            end
            else
            begin
                fifo_c1_enq_data <= t_if_ccip_c1_Tx'(0);
                fifo_c1_enq_en <= 0;
            end

            if (T1_c2.valid & fifo_c2_notFull)
            begin
                fifo_c2_enq_data <= T1_c2;
                fifo_c2_enq_en <= 1;
            end
            else
            begin
                fifo_c2_enq_data <= t_if_ccip_c2_Tx'(0);
                fifo_c2_enq_en <= 0;
            end
        end
    end

    /* fifo signal output and input */
    always_comb
    begin
        out_fifo_c0_almostFull = fifo_c0_almostFull;
        out_fifo_c0_first = fifo_c0_first;
        fifo_c0_deq_en = in_fifo_c0_deq_en;

        out_fifo_c1_almostFull = fifo_c1_almostFull;
        out_fifo_c1_first = fifo_c1_first;
        fifo_c1_deq_en = in_fifo_c1_deq_en;

        out_fifo_c2_almostFull = fifo_c2_almostFull;
        out_fifo_c2_first = fifo_c2_first;
        fifo_c2_deq_en = in_fifo_c2_deq_en;
    end

endmodule
