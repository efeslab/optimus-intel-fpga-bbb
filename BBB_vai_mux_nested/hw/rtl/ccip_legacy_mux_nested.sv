import ccip_if_pkg::*;
`include "vendor_defines.vh"
module nested_mux_9
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

logic link_0_1_softreset;
logic link_0_1_error;
logic [1:0] link_0_1_pwrstate;
t_if_ccip_Rx link_0_1_rx;
t_if_ccip_Tx link_0_1_tx;
logic out_1_softreset[2:0];
logic [1:0] out_1_pwrstate[2:0];
logic out_1_error[2:0];
t_if_ccip_Rx out_1_rx[2:0];
t_if_ccip_Tx out_1_tx[2:0];
logic link_0_5_softreset;
logic link_0_5_error;
logic [1:0] link_0_5_pwrstate;
t_if_ccip_Rx link_0_5_rx;
t_if_ccip_Tx link_0_5_tx;
logic out_5_softreset[2:0];
logic [1:0] out_5_pwrstate[2:0];
logic out_5_error[2:0];
t_if_ccip_Rx out_5_rx[2:0];
t_if_ccip_Tx out_5_tx[2:0];
logic link_0_9_softreset;
logic link_0_9_error;
logic [1:0] link_0_9_pwrstate;
t_if_ccip_Rx link_0_9_rx;
t_if_ccip_Tx link_0_9_tx;
logic out_9_softreset[2:0];
logic [1:0] out_9_pwrstate[2:0];
logic out_9_error[2:0];
t_if_ccip_Rx out_9_rx[2:0];
t_if_ccip_Tx out_9_tx[2:0];
logic out_0_softreset[2:0];
logic [1:0] out_0_pwrstate[2:0];
logic out_0_error[2:0];
t_if_ccip_Rx out_0_rx[2:0];
t_if_ccip_Tx out_0_tx[2:0];
assign link_0_1_softreset = out_0_softreset[0];
assign link_0_1_error = out_0_error[0];
assign link_0_1_pwrstate = out_0_pwrstate[0];
assign link_0_1_rx = out_0_rx[0];
assign out_0_tx[0] = link_0_1_tx;
assign link_0_5_softreset = out_0_softreset[1];
assign link_0_5_error = out_0_error[1];
assign link_0_5_pwrstate = out_0_pwrstate[1];
assign link_0_5_rx = out_0_rx[1];
assign out_0_tx[1] = link_0_5_tx;
assign link_0_9_softreset = out_0_softreset[2];
assign link_0_9_error = out_0_error[2];
assign link_0_9_pwrstate = out_0_pwrstate[2];
assign link_0_9_rx = out_0_rx[2];
assign out_0_tx[2] = link_0_9_tx;
ccip_mux_legacy #(
    .NUM_SUB_AFUS(3),
    .NUM_PIPE_STAGES(0)
)
mux_1(
    .pClk(pClk),
    .pClkDiv2(pClkDiv2),
    .SoftReset(link_0_1_softreset),
    .up_Error(link_0_1_error),
    .up_PwrState(link_0_1_pwrstate),
    .up_RxPort(link_0_1_rx),
    .up_TxPort(link_0_1_tx),
    .afu_SoftReset(out_1_softreset[2:0]),
    .afu_PwrState(out_1_pwrstate[2:0]),
    .afu_Error(out_1_error[2:0]),
    .afu_RxPort(out_1_rx[2:0]),
    .afu_TxPort(out_1_tx[2:0])
    );

ccip_mux_legacy #(
    .NUM_SUB_AFUS(3),
    .NUM_PIPE_STAGES(0)
)
mux_5(
    .pClk(pClk),
    .pClkDiv2(pClkDiv2),
    .SoftReset(link_0_5_softreset),
    .up_Error(link_0_5_error),
    .up_PwrState(link_0_5_pwrstate),
    .up_RxPort(link_0_5_rx),
    .up_TxPort(link_0_5_tx),
    .afu_SoftReset(out_5_softreset[2:0]),
    .afu_PwrState(out_5_pwrstate[2:0]),
    .afu_Error(out_5_error[2:0]),
    .afu_RxPort(out_5_rx[2:0]),
    .afu_TxPort(out_5_tx[2:0])
    );

ccip_mux_legacy #(
    .NUM_SUB_AFUS(3),
    .NUM_PIPE_STAGES(0)
)
mux_9(
    .pClk(pClk),
    .pClkDiv2(pClkDiv2),
    .SoftReset(link_0_9_softreset),
    .up_Error(link_0_9_error),
    .up_PwrState(link_0_9_pwrstate),
    .up_RxPort(link_0_9_rx),
    .up_TxPort(link_0_9_tx),
    .afu_SoftReset(out_9_softreset[2:0]),
    .afu_PwrState(out_9_pwrstate[2:0]),
    .afu_Error(out_9_error[2:0]),
    .afu_RxPort(out_9_rx[2:0]),
    .afu_TxPort(out_9_tx[2:0])
    );

ccip_mux_legacy #(
    .NUM_SUB_AFUS(3),
    .NUM_PIPE_STAGES(0)
)
mux_0(
    .pClk(pClk),
    .pClkDiv2(pClkDiv2),
    .SoftReset(SoftReset),
    .up_Error(up_Error),
    .up_PwrState(up_PwrState),
    .up_RxPort(up_RxPort),
    .up_TxPort(up_TxPort),
    .afu_SoftReset(out_0_softreset[2:0]),
    .afu_PwrState(out_0_pwrstate[2:0]),
    .afu_Error(out_0_error[2:0]),
    .afu_RxPort(out_0_rx[2:0]),
    .afu_TxPort(out_0_tx[2:0])
    );

/* port0 afu1 */
assign afu_SoftReset[0] = out_1_softreset[0];
assign afu_PwrState[0] = out_1_pwrstate[0];
assign afu_Error[0] = out_1_error[0];
assign afu_RxPort[0] = out_1_rx[0];
assign out_1_tx[0] = afu_TxPort[0];

/* port1 afu2 */
assign afu_SoftReset[1] = out_1_softreset[1];
assign afu_PwrState[1] = out_1_pwrstate[1];
assign afu_Error[1] = out_1_error[1];
assign afu_RxPort[1] = out_1_rx[1];
assign out_1_tx[1] = afu_TxPort[1];

/* port2 afu3 */
assign afu_SoftReset[2] = out_1_softreset[2];
assign afu_PwrState[2] = out_1_pwrstate[2];
assign afu_Error[2] = out_1_error[2];
assign afu_RxPort[2] = out_1_rx[2];
assign out_1_tx[2] = afu_TxPort[2];

/* port3 afu4 */
assign afu_SoftReset[3] = out_5_softreset[0];
assign afu_PwrState[3] = out_5_pwrstate[0];
assign afu_Error[3] = out_5_error[0];
assign afu_RxPort[3] = out_5_rx[0];
assign out_5_tx[0] = afu_TxPort[3];

/* port4 afu5 */
assign afu_SoftReset[4] = out_5_softreset[1];
assign afu_PwrState[4] = out_5_pwrstate[1];
assign afu_Error[4] = out_5_error[1];
assign afu_RxPort[4] = out_5_rx[1];
assign out_5_tx[1] = afu_TxPort[4];

/* port5 afu6 */
assign afu_SoftReset[5] = out_5_softreset[2];
assign afu_PwrState[5] = out_5_pwrstate[2];
assign afu_Error[5] = out_5_error[2];
assign afu_RxPort[5] = out_5_rx[2];
assign out_5_tx[2] = afu_TxPort[5];

/* port6 afu7 */
assign afu_SoftReset[6] = out_9_softreset[0];
assign afu_PwrState[6] = out_9_pwrstate[0];
assign afu_Error[6] = out_9_error[0];
assign afu_RxPort[6] = out_9_rx[0];
assign out_9_tx[0] = afu_TxPort[6];

/* port7 afu8 */
assign afu_SoftReset[7] = out_9_softreset[1];
assign afu_PwrState[7] = out_9_pwrstate[1];
assign afu_Error[7] = out_9_error[1];
assign afu_RxPort[7] = out_9_rx[1];
assign out_9_tx[1] = afu_TxPort[7];

/* port8 afu9 */
assign afu_SoftReset[8] = out_9_softreset[2];
assign afu_PwrState[8] = out_9_pwrstate[2];
assign afu_Error[8] = out_9_error[2];
assign afu_RxPort[8] = out_9_rx[2];
assign out_9_tx[2] = afu_TxPort[8];

endmodule

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

logic link_0_1_softreset;
logic link_0_1_error;
logic [1:0] link_0_1_pwrstate;
t_if_ccip_Rx link_0_1_rx;
t_if_ccip_Tx link_0_1_tx;
logic out_1_softreset[1:0];
logic [1:0] out_1_pwrstate[1:0];
logic out_1_error[1:0];
t_if_ccip_Rx out_1_rx[1:0];
t_if_ccip_Tx out_1_tx[1:0];
logic link_0_4_softreset;
logic link_0_4_error;
logic [1:0] link_0_4_pwrstate;
t_if_ccip_Rx link_0_4_rx;
t_if_ccip_Tx link_0_4_tx;
logic out_4_softreset[1:0];
logic [1:0] out_4_pwrstate[1:0];
logic out_4_error[1:0];
t_if_ccip_Rx out_4_rx[1:0];
t_if_ccip_Tx out_4_tx[1:0];
logic link_0_7_softreset;
logic link_0_7_error;
logic [1:0] link_0_7_pwrstate;
t_if_ccip_Rx link_0_7_rx;
t_if_ccip_Tx link_0_7_tx;
logic out_7_softreset[1:0];
logic [1:0] out_7_pwrstate[1:0];
logic out_7_error[1:0];
t_if_ccip_Rx out_7_rx[1:0];
t_if_ccip_Tx out_7_tx[1:0];
logic link_0_10_softreset;
logic link_0_10_error;
logic [1:0] link_0_10_pwrstate;
t_if_ccip_Rx link_0_10_rx;
t_if_ccip_Tx link_0_10_tx;
logic out_10_softreset[1:0];
logic [1:0] out_10_pwrstate[1:0];
logic out_10_error[1:0];
t_if_ccip_Rx out_10_rx[1:0];
t_if_ccip_Tx out_10_tx[1:0];
logic out_0_softreset[3:0];
logic [1:0] out_0_pwrstate[3:0];
logic out_0_error[3:0];
t_if_ccip_Rx out_0_rx[3:0];
t_if_ccip_Tx out_0_tx[3:0];
assign link_0_1_softreset = out_0_softreset[0];
assign link_0_1_error = out_0_error[0];
assign link_0_1_pwrstate = out_0_pwrstate[0];
assign link_0_1_rx = out_0_rx[0];
assign out_0_tx[0] = link_0_1_tx;
assign link_0_4_softreset = out_0_softreset[1];
assign link_0_4_error = out_0_error[1];
assign link_0_4_pwrstate = out_0_pwrstate[1];
assign link_0_4_rx = out_0_rx[1];
assign out_0_tx[1] = link_0_4_tx;
assign link_0_7_softreset = out_0_softreset[2];
assign link_0_7_error = out_0_error[2];
assign link_0_7_pwrstate = out_0_pwrstate[2];
assign link_0_7_rx = out_0_rx[2];
assign out_0_tx[2] = link_0_7_tx;
assign link_0_10_softreset = out_0_softreset[3];
assign link_0_10_error = out_0_error[3];
assign link_0_10_pwrstate = out_0_pwrstate[3];
assign link_0_10_rx = out_0_rx[3];
assign out_0_tx[3] = link_0_10_tx;
ccip_mux_legacy #(
    .NUM_SUB_AFUS(2),
    .NUM_PIPE_STAGES(0)
)
mux_1(
    .pClk(pClk),
    .pClkDiv2(pClkDiv2),
    .SoftReset(link_0_1_softreset),
    .up_Error(link_0_1_error),
    .up_PwrState(link_0_1_pwrstate),
    .up_RxPort(link_0_1_rx),
    .up_TxPort(link_0_1_tx),
    .afu_SoftReset(out_1_softreset[1:0]),
    .afu_PwrState(out_1_pwrstate[1:0]),
    .afu_Error(out_1_error[1:0]),
    .afu_RxPort(out_1_rx[1:0]),
    .afu_TxPort(out_1_tx[1:0])
    );

ccip_mux_legacy #(
    .NUM_SUB_AFUS(2),
    .NUM_PIPE_STAGES(0)
)
mux_4(
    .pClk(pClk),
    .pClkDiv2(pClkDiv2),
    .SoftReset(link_0_4_softreset),
    .up_Error(link_0_4_error),
    .up_PwrState(link_0_4_pwrstate),
    .up_RxPort(link_0_4_rx),
    .up_TxPort(link_0_4_tx),
    .afu_SoftReset(out_4_softreset[1:0]),
    .afu_PwrState(out_4_pwrstate[1:0]),
    .afu_Error(out_4_error[1:0]),
    .afu_RxPort(out_4_rx[1:0]),
    .afu_TxPort(out_4_tx[1:0])
    );

ccip_mux_legacy #(
    .NUM_SUB_AFUS(2),
    .NUM_PIPE_STAGES(0)
)
mux_7(
    .pClk(pClk),
    .pClkDiv2(pClkDiv2),
    .SoftReset(link_0_7_softreset),
    .up_Error(link_0_7_error),
    .up_PwrState(link_0_7_pwrstate),
    .up_RxPort(link_0_7_rx),
    .up_TxPort(link_0_7_tx),
    .afu_SoftReset(out_7_softreset[1:0]),
    .afu_PwrState(out_7_pwrstate[1:0]),
    .afu_Error(out_7_error[1:0]),
    .afu_RxPort(out_7_rx[1:0]),
    .afu_TxPort(out_7_tx[1:0])
    );

ccip_mux_legacy #(
    .NUM_SUB_AFUS(2),
    .NUM_PIPE_STAGES(0)
)
mux_10(
    .pClk(pClk),
    .pClkDiv2(pClkDiv2),
    .SoftReset(link_0_10_softreset),
    .up_Error(link_0_10_error),
    .up_PwrState(link_0_10_pwrstate),
    .up_RxPort(link_0_10_rx),
    .up_TxPort(link_0_10_tx),
    .afu_SoftReset(out_10_softreset[1:0]),
    .afu_PwrState(out_10_pwrstate[1:0]),
    .afu_Error(out_10_error[1:0]),
    .afu_RxPort(out_10_rx[1:0]),
    .afu_TxPort(out_10_tx[1:0])
    );

ccip_mux_legacy #(
    .NUM_SUB_AFUS(4),
    .NUM_PIPE_STAGES(0)
)
mux_0(
    .pClk(pClk),
    .pClkDiv2(pClkDiv2),
    .SoftReset(SoftReset),
    .up_Error(up_Error),
    .up_PwrState(up_PwrState),
    .up_RxPort(up_RxPort),
    .up_TxPort(up_TxPort),
    .afu_SoftReset(out_0_softreset[3:0]),
    .afu_PwrState(out_0_pwrstate[3:0]),
    .afu_Error(out_0_error[3:0]),
    .afu_RxPort(out_0_rx[3:0]),
    .afu_TxPort(out_0_tx[3:0])
    );

/* port0 afu1 */
assign afu_SoftReset[0] = out_1_softreset[0];
assign afu_PwrState[0] = out_1_pwrstate[0];
assign afu_Error[0] = out_1_error[0];
assign afu_RxPort[0] = out_1_rx[0];
assign out_1_tx[0] = afu_TxPort[0];

/* port1 afu2 */
assign afu_SoftReset[1] = out_1_softreset[1];
assign afu_PwrState[1] = out_1_pwrstate[1];
assign afu_Error[1] = out_1_error[1];
assign afu_RxPort[1] = out_1_rx[1];
assign out_1_tx[1] = afu_TxPort[1];

/* port2 afu4 */
assign afu_SoftReset[2] = out_4_softreset[0];
assign afu_PwrState[2] = out_4_pwrstate[0];
assign afu_Error[2] = out_4_error[0];
assign afu_RxPort[2] = out_4_rx[0];
assign out_4_tx[0] = afu_TxPort[2];

/* port3 afu5 */
assign afu_SoftReset[3] = out_4_softreset[1];
assign afu_PwrState[3] = out_4_pwrstate[1];
assign afu_Error[3] = out_4_error[1];
assign afu_RxPort[3] = out_4_rx[1];
assign out_4_tx[1] = afu_TxPort[3];

/* port4 afu1 */
assign afu_SoftReset[4] = out_7_softreset[0];
assign afu_PwrState[4] = out_7_pwrstate[0];
assign afu_Error[4] = out_7_error[0];
assign afu_RxPort[4] = out_7_rx[0];
assign out_7_tx[0] = afu_TxPort[4];

/* port5 afu2 */
assign afu_SoftReset[5] = out_7_softreset[1];
assign afu_PwrState[5] = out_7_pwrstate[1];
assign afu_Error[5] = out_7_error[1];
assign afu_RxPort[5] = out_7_rx[1];
assign out_7_tx[1] = afu_TxPort[5];

/* port6 afu1 */
assign afu_SoftReset[6] = out_10_softreset[0];
assign afu_PwrState[6] = out_10_pwrstate[0];
assign afu_Error[6] = out_10_error[0];
assign afu_RxPort[6] = out_10_rx[0];
assign out_10_tx[0] = afu_TxPort[6];

/* port7 afu2 */
assign afu_SoftReset[7] = out_10_softreset[1];
assign afu_PwrState[7] = out_10_pwrstate[1];
assign afu_Error[7] = out_10_error[1];
assign afu_RxPort[7] = out_10_rx[1];
assign out_10_tx[1] = afu_TxPort[7];

endmodule
