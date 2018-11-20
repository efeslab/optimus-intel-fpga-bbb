import ccip_if_pkg::*;
`include "vendor_defines.vh"
module vai_mux # (parameter NUM_SUB_AFUS=8, NUM_PIPE_STAGES=0)
(
    input   wire                    pClk,
    input   wire                    pClkDiv2,
    /* upstream ports */
    input   wire                    SoftReset,                          // upstream reset
    input   wire                    up_Error,
    input   wire                    up_PwrState,
    input   t_if_ccip_Rx            up_RxPort,                          // upstream Rx response port
    output  t_if_ccip_Tx            up_TxPort,                          // upstream Tx request port
    /* downstream ports */
    output  logic                   afu_SoftReset [NUM_SUB_AFUS-1:0],
    output  logic [1:0]             afu_PwrState  [NUM_SUB_AFUS-1:0],
    output  logic                   afu_Error     [NUM_SUB_AFUS-1:0],
    output  t_if_ccip_Rx            afu_RxPort    [NUM_SUB_AFUS-1:0],        // downstream Rx response AFU
    input   t_if_ccip_Tx            afu_TxPort    [NUM_SUB_AFUS-1:0]         // downstream Tx request  AFU

);

    /* forward Rx Port */

    t_if_ccip_Rx pre_afu_RxPort[NUM_SUB_AFUS-1:0];
    logic [63:0] offset_array [NUM_SUB_AFUS-1:0];

    vai_serve_rx #(
        .NUM_SUB_AFUS(NUM_SUB_AFUS)
    )
    inst_vai_serve_rx(
        .clk(pClk),
        .reset(SoftReset),
        .up_RxPort(up_RxPort),
        .afu_RxPort(pre_afu_RxPort),
        .offset_array(offset_array)
        );


    /* audit Tx port for each afu */

    t_if_ccip_Tx audit_TxPort[NUM_SUB_AFUS-1:0];
    vai_audit_tx #(
        .NUM_SUB_AFUS(NUM_SUB_AFUS)
    )
    inst_vai_audit_tx(
        .clk(pClk),
        .reset(SoftReset),
        .up_TxPort(audit_TxPort),
        .afu_TxPort(afu_TxPort),
        .offset_array(offset_array)
        );


    /* we utilize the legacy ccip_mux to send packet */

    t_if_ccip_Rx legacy_afu_RxPort[NUM_SUB_AFUS-1:0];
    ccip_mux_legacy #(
        .NUM_SUB_AFUS(NUM_SUB_AFUS),
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
        .afu_SoftReset(afu_SoftReset),
        .afu_PwrState(afu_PwrState),
        .afu_Error(afu_Error),
        .afu_RxPort(legacy_afu_RxPort),
        .afu_TxPort(audit_TxPort)
        );

    generate
        genvar n;
        for (n=0; n<NUM_SUB_AFUS; n++)
        begin
            always_comb
            begin
                afu_RxPort[n] = pre_afu_RxPort[n]; /* c0 & c1 */
                afu_RxPort[n].c0TxAlmFull = legacy_afu_RxPort[n].c0TxAlmFull;
                afu_RxPort[n].c1TxAlmFull = legacy_afu_RxPort[n].c1TxAlmFull;
            end
        end
    endgenerate

endmodule
