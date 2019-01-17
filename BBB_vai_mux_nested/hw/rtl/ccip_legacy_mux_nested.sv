import ccip_if_pkg::*;
`include "vendor_defines.vh"
module nested_mux_16
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
    output  logic                   afu_SoftReset [15:0],
    output  logic [1:0]             afu_PwrState  [15:0],
    output  logic                   afu_Error     [15:0],
    output  t_if_ccip_Rx            afu_RxPort    [15:0],        // downstream Rx response AFU
    input   t_if_ccip_Tx            afu_TxPort    [15:0]         // downstream Tx request  AFU

);

    /* L1 */

    logic           l1out_SoftReset [3:0];
    logic [1:0]     l1out_PwrState [3:0];
    logic           l1out_Error [3:0];
    t_if_ccip_Rx    l1out_RxPort [3:0];
    t_if_ccip_Tx    l1in_TxPort [3:0];

    ccip_mux_legacy #(
        .NUM_SUB_AFUS(4),
        .NUM_PIPE_STAGES(0)
    )
    inst_ccip_mux_legacy(
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
        for (n=0; n<4; n++)
        begin
            logic           l2out_SoftReset [3:0];
            logic [1:0]     l2out_PwrState [3:0];
            logic           l2out_Error [3:0];
            t_if_ccip_Rx    l2out_RxPort [3:0];
            t_if_ccip_Tx    l2in_TxPort [3:0];

            ccip_mux_legacy #(
                .NUM_SUB_AFUS(4),
                .NUM_PIPE_STAGES(0)
            )
            inst_ccip_mux_legacy(
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

            always_comb
            begin
                for (int i=0; i<4; i++)
                begin
                    afu_SoftReset[4*n+i]    =   l2out_SoftReset[i];
                    afu_PwrState[4*n+i]     =   l2out_PwrState[i];
                    afu_Error[4*n+i]        =   l2out_Error[i];
                    afu_RxPort[4*n+i]       =   l2out_RxPort[i];
                    l2in_TxPort[i]          =   afu_TxPort[4*n+i];
                end
            end
        end
    endgenerate

endmodule

module nested_mux_12 /* l1=4, l2=3 */
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
    output  logic                   afu_SoftReset [11:0],
    output  logic [1:0]             afu_PwrState  [11:0],
    output  logic                   afu_Error     [11:0],
    output  t_if_ccip_Rx            afu_RxPort    [11:0],        // downstream Rx response AFU
    input   t_if_ccip_Tx            afu_TxPort    [11:0]         // downstream Tx request  AFU

);

    /* L1 */

    logic           l1out_SoftReset [3:0];
    logic [1:0]     l1out_PwrState [3:0];
    logic           l1out_Error [3:0];
    t_if_ccip_Rx    l1out_RxPort [3:0];
    t_if_ccip_Tx    l1in_TxPort [3:0];

    ccip_mux_legacy #(
        .NUM_SUB_AFUS(4),
        .NUM_PIPE_STAGES(0)
    )
    inst_ccip_mux_legacy(
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
        for (n=0; n<4; n++)
        begin
            logic           l2out_SoftReset [2:0];
            logic [1:0]     l2out_PwrState [2:0];
            logic           l2out_Error [2:0];
            t_if_ccip_Rx    l2out_RxPort [2:0];
            t_if_ccip_Tx    l2in_TxPort [2:0];

            ccip_mux_legacy #(
                .NUM_SUB_AFUS(3),
                .NUM_PIPE_STAGES(0)
            )
            inst_ccip_mux_legacy(
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

            always_comb
            begin
                for (int i=0; i<3; i++)
                begin
                    afu_SoftReset[3*n+i]    =   l2out_SoftReset[i];
                    afu_PwrState[3*n+i]     =   l2out_PwrState[i];
                    afu_Error[3*n+i]        =   l2out_Error[i];
                    afu_RxPort[3*n+i]       =   l2out_RxPort[i];
                    l2in_TxPort[i]          =   afu_TxPort[3*n+i];
                end
            end
        end
    endgenerate

endmodule

module nested_mux_9 /* l1=3, l2=3 */
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
    output  logic                   afu_SoftReset [8:0],
    output  logic [1:0]             afu_PwrState  [8:0],
    output  logic                   afu_Error     [8:0],
    output  t_if_ccip_Rx            afu_RxPort    [8:0],        // downstream Rx response AFU
    input   t_if_ccip_Tx            afu_TxPort    [8:0]         // downstream Tx request  AFU

);

    /* L1 */

    logic           l1out_SoftReset [2:0];
    logic [1:0]     l1out_PwrState [2:0];
    logic           l1out_Error [2:0];
    t_if_ccip_Rx    l1out_RxPort [2:0];
    t_if_ccip_Tx    l1in_TxPort [2:0];

    ccip_mux_legacy #(
        .NUM_SUB_AFUS(3),
        .NUM_PIPE_STAGES(0)
    )
    inst_ccip_mux_legacy(
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
        for (n=0; n<3; n++)
        begin
            logic           l2out_SoftReset [2:0];
            logic [1:0]     l2out_PwrState [2:0];
            logic           l2out_Error [2:0];
            t_if_ccip_Rx    l2out_RxPort [2:0];
            t_if_ccip_Tx    l2in_TxPort [2:0];

            ccip_mux_legacy #(
                .NUM_SUB_AFUS(3),
                .NUM_PIPE_STAGES(0)
            )
            inst_ccip_mux_legacy(
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

            always_comb
            begin
                for (int i=0; i<3; i++)
                begin
                    afu_SoftReset[3*n+i]    =   l2out_SoftReset[i];
                    afu_PwrState[3*n+i]     =   l2out_PwrState[i];
                    afu_Error[3*n+i]        =   l2out_Error[i];
                    afu_RxPort[3*n+i]       =   l2out_RxPort[i];
                    l2in_TxPort[i]          =   afu_TxPort[3*n+i];
                end
            end
        end
    endgenerate

endmodule

module nested_mux_6 /* l1=3, l2=2 */
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
    output  logic                   afu_SoftReset [5:0],
    output  logic [1:0]             afu_PwrState  [5:0],
    output  logic                   afu_Error     [5:0],
    output  t_if_ccip_Rx            afu_RxPort    [5:0],        // downstream Rx response AFU
    input   t_if_ccip_Tx            afu_TxPort    [5:0]         // downstream Tx request  AFU

);

    /* L1 */

    logic           l1out_SoftReset [2:0];
    logic [1:0]     l1out_PwrState [2:0];
    logic           l1out_Error [2:0];
    t_if_ccip_Rx    l1out_RxPort [2:0];
    t_if_ccip_Tx    l1in_TxPort [2:0];

    ccip_mux_legacy #(
        .NUM_SUB_AFUS(3),
        .NUM_PIPE_STAGES(0)
    )
    inst_ccip_mux_legacy(
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
        for (n=0; n<3; n++)
        begin
            logic           l2out_SoftReset [1:0];
            logic [1:0]     l2out_PwrState [1:0];
            logic           l2out_Error [1:0];
            t_if_ccip_Rx    l2out_RxPort [1:0];
            t_if_ccip_Tx    l2in_TxPort [1:0];

            ccip_mux_legacy #(
                .NUM_SUB_AFUS(2),
                .NUM_PIPE_STAGES(0)
            )
            inst_ccip_mux_legacy(
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

            always_comb
            begin
                for (int i=0; i<2; i++)
                begin
                    afu_SoftReset[2*n+i]    =   l2out_SoftReset[i];
                    afu_PwrState[2*n+i]     =   l2out_PwrState[i];
                    afu_Error[2*n+i]        =   l2out_Error[i];
                    afu_RxPort[2*n+i]       =   l2out_RxPort[i];
                    l2in_TxPort[i]          =   afu_TxPort[2*n+i];
                end
            end
        end
    endgenerate

endmodule

