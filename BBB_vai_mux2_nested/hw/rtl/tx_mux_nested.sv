import ccip_if_pkg::*;
`include "vendor_defines.vh"

module tx_mux_nested_9
(
    input wire clk,
    input wire reset,

    input t_if_ccip_Tx in [8:0],
    output t_if_ccip_Tx out,

    input logic in_c0_almFull,
    input logic in_c1_almFull,

    output logic out_c0_almFull [8:0],
    output logic out_c1_almFull [8:0]
);

    t_if_ccip_Tx l1up;
    t_if_ccip_Tx l1down [2:0];
    logic l1up_c0_almFull;
    logic l1up_c1_almFull;
    logic l1down_c0_almFull [2:0];
    logic l1down_c1_almFull [2:0];

    always_comb
    begin
        out = l1up;
        l1up_c0_almFull = in_c0_almFull;
        l1up_c1_almFull = in_c1_almFull;
    end

    tx_mux #(
        .N_SUBAFUS(3)
    )
    inst_tx_mux_l1(
        .clk(clk),
        .reset(reset),
        .in(l1down),
        .out(l1up),
        .in_c0_almFull(l1up_c0_almFull),
        .in_c1_almFull(l1up_c0_almFull),
        .out_c0_almFull(l1down_c0_almFull),
        .out_c1_almFull(l1down_c1_almFull)
        );

    generate
        genvar i;
        for (i=0; i<3; i++)
        begin
            t_if_ccip_Tx l2up;
            t_if_ccip_Tx l2down [2:0];
            logic l2up_c0_almFull;
            logic l2up_c1_almFull;
            logic l2down_c0_almFull [2:0];
            logic l2down_c1_almFull [2:0];

            always_comb
            begin
                l1down[i] = l2up;
                l2up_c0_almFull = l1down_c0_almFull[i];
                l2up_c1_almFull = l1down_c1_almFull[i];
            end

            tx_mux #(
                .N_SUBAFUS(3)
            )
            inst_tx_mux_l2(
                .clk(clk),
                .reset(reset),
                .in(l2down),
                .out(l2up),
                .in_c0_almFull(l2up_c0_almFull),
                .in_c1_almFull(l2up_c0_almFull),
                .out_c0_almFull(l2down_c0_almFull),
                .out_c1_almFull(l2down_c1_almFull)
                );

            always_comb
            begin
                for (int j=0; j<3; j++)
                begin
                    l2down[j] = in[3*i+j];
                    out_c0_almFull[3*i+j] = l2down_c0_almFull[j];
                    out_c1_almFull[3*i+j] = l2down_c1_almFull[j];
                end
            end
        end
    endgenerate

endmodule
