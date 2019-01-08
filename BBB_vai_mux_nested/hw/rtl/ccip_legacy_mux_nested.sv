import ccip_if_pkg::*;
`include "vendor_defines.vh"
module nested_mux_8
(
    input   wire                    pClk,
    input   wire                    pClkDiv2,
    /* upstream ports */
    input   wire                    SoftReset,                          // upstream reset
    input   wire                    up_Error,
    input   wire [1:0]              up_PwrState,
    input   t_if_ccip_Rx            up_RxPort,                          // upstream Rx response port
    output  t_if_ccip_Tx            up_TxPort,                          // upstream Tx request port
    /* downstream ports */
    output  logic                   afu_SoftReset [7:0],
    output  logic [1:0]             afu_PwrState  [7:0],
    output  logic                   afu_Error     [7:0],
    output  t_if_ccip_Rx            afu_RxPort    [7:0],        // downstream Rx response AFU
    input   t_if_ccip_Tx            afu_TxPort    [7:0]         // downstream Tx request  AFU

);

    /* L1 */

    logic           l1out_SoftReset [1:0];
    logic [1:0]     l1out_PwrState [1:0];
    logic           l1out_Error [1:0];
    t_if_ccip_Rx    l1out_RxPort [1:0];
    t_if_ccip_Tx    l1in_TxPort [1:0];

    ccip_mux_legacy #(
        .NUM_SUB_AFUS(2),
        .NUM_PIPE_STAGES(1)
    )
    inst_ccip_mux_legacy_l1(
        .pClk(pClk),
        .pClkDiv2(pClkDiv2),
        .SoftReset(SoftReset),
        .up_Error(up_Error),
        .up_PwrState(up_PwrState),
        .up_RxPort(up_RxPort), /* we only use this to count packets */
        .up_TxPort(up_TxPort),
        .afu_SoftReset(l1out_SoftReset),
        .afu_PwrState(l1out_PwrState),
        .afu_Error(l1out_Error),
        .afu_RxPort(l1out_RxPort),
        .afu_TxPort(l1in_TxPort)
        );

    /* L2 */
    generate
        genvar n;
        genvar k;
        for (n=0; n<2; n++)
        begin
            logic           l2out_SoftReset [1:0];
            logic [1:0]     l2out_PwrState [1:0];
            logic           l2out_Error [1:0];
            t_if_ccip_Rx    l2out_RxPort [1:0];
            t_if_ccip_Tx    l2in_TxPort [1:0];

            ccip_mux_legacy #(
                .NUM_SUB_AFUS(2),
                .NUM_PIPE_STAGES(1)
            )
            inst_ccip_mux_legacy_l2(
                .pClk(pClk),
                .pClkDiv2(pClkDiv2),
                .SoftReset(l1out_SoftReset[n]),
                .up_Error(l1out_Error[n]),
                .up_PwrState(l1out_PwrState[n]),
                .up_RxPort(l1out_RxPort[n]), /* we only use this to count packets */
                .up_TxPort(l1in_TxPort[n]),
                .afu_SoftReset(l2out_SoftReset),
                .afu_PwrState(l2out_PwrState),
                .afu_Error(l2out_Error),
                .afu_RxPort(l2out_RxPort),
                .afu_TxPort(l2in_TxPort)
                );

            for (k=0; k<2; k++)
            begin
                logic           l3out_SoftReset [1:0];
                logic [1:0]     l3out_PwrState [1:0];
                logic           l3out_Error [1:0];
                t_if_ccip_Rx    l3out_RxPort [1:0];
                t_if_ccip_Tx    l3in_TxPort [1:0];

                ccip_mux_legacy #(
                    .NUM_SUB_AFUS(2),
                    .NUM_PIPE_STAGES(1)
                )
                inst_ccip_mux_legacy_l3(
                    .pClk(pClk),
                    .pClkDiv2(pClkDiv2),
                    .SoftReset(l2out_SoftReset[k]),
                    .up_Error(l2out_Error[k]),
                    .up_PwrState(l2out_PwrState[k]),
                    .up_RxPort(l2out_RxPort[k]),
                    .up_TxPort(l2in_TxPort[k]),
                    .afu_SoftReset(l3out_SoftReset),
                    .afu_PwrState(l3out_PwrState),
                    .afu_Error(l3out_Error),
                    .afu_RxPort(l3out_RxPort),
                    .afu_TxPort(l3in_TxPort)
                    );

                always_comb
                begin
                    for (int i=0; i<2; i++)
                    begin
                        afu_SoftReset[4*n+2*k+i]    =   l3out_SoftReset[i];
                        afu_PwrState[4*n+2*k+i]     =   l3out_PwrState[i];
                        afu_Error[4*n+2*k+i]        =   l3out_Error[i];
                        afu_RxPort[4*n+2*k+i]       =   l3out_RxPort[i];
                        l3in_TxPort[i]          =   afu_TxPort[4*n+2*k+i];
                    end
                end
            end
        end
    endgenerate

endmodule

