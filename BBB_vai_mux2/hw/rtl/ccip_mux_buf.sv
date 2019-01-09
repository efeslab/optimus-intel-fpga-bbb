import ccip_if_pkg::*;
`include "vendor_defines.vh"
module ccip_mux_buf # (parameter NUM_SUB_AFUS=8, NUM_PIPE_STAGES=0)
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
    output  logic                   afu_SoftReset [NUM_SUB_AFUS-1:0],
    output  logic [1:0]             afu_PwrState  [NUM_SUB_AFUS-1:0],
    output  logic                   afu_Error     [NUM_SUB_AFUS-1:0],
    output  t_if_ccip_Rx            afu_RxPort    [NUM_SUB_AFUS-1:0],        // downstream Rx response AFU
    input   t_if_ccip_Tx            afu_TxPort    [NUM_SUB_AFUS-1:0]         // downstream Tx request  AFU

);

    localparam LNUM_SUB_AFUS = $clog2(NUM_SUB_AFUS);

    logic ireg_SoftReset;
    logic ireg_up_Error;
    logic [1:0] ireg_up_PwrState;
    t_if_ccip_Rx ireg_up_RxPort;
    t_if_ccip_Tx ireg_afu_TxPort [NUM_SUB_AFUS-1:0];         // downstream Tx request  AFU

    always_ff @(posedge pClk)
    begin
        ireg_SoftReset <= SoftReset;
        ireg_up_Error <= up_Error;
        ireg_up_PwrState <= up_PwrState;
        ireg_up_RxPort <= up_RxPort;
        ireg_afu_TxPort <= afu_TxPort;
    end

    t_if_ccip_Tx oreg_up_TxPort;                          // upstream Tx request port
    logic oreg_afu_SoftReset [NUM_SUB_AFUS-1:0];
    logic [1:0] oreg_afu_PwrState  [NUM_SUB_AFUS-1:0];
    logic oreg_afu_Error     [NUM_SUB_AFUS-1:0];
    t_if_ccip_Rx oreg_afu_RxPort    [NUM_SUB_AFUS-1:0];        // downstream Rx response AFU

    always_ff @(posedge pClk)
    begin
        up_TxPort <= oreg_up_TxPort;
        afu_SoftReset <= oreg_afu_SoftReset;
        afu_PwrState <= oreg_afu_PwrState;
        afu_Error <= oreg_afu_Error;
        afu_RxPort <= oreg_afu_RxPort;
    end

    ccip_mux_legacy #(
        .NUM_SUB_AFUS(NUM_SUB_AFUS),
        .NUM_PIPE_STAGES(NUM_PIPE_STAGES)
    )
    inst_ccip_mux_legacy(
        .pClk(pClk),
        .pClkDiv2(pClkDiv2),
        .SoftReset(ireg_SoftReset),
        .up_Error(ireg_up_Error),
        .up_PwrState(ireg_up_PwrState),
        .up_RxPort(ireg_up_RxPort),
        .up_TxPort(oreg_up_TxPort),
        .afu_SoftReset(oreg_afu_SoftReset),
        .afu_PwrState(oreg_afu_PwrState),
        .afu_Error(oreg_afu_Error),
        .afu_RxPort(oreg_afu_RxPort),
        .afu_TxPort(ireg_afu_TxPort)
        );
endmodule

