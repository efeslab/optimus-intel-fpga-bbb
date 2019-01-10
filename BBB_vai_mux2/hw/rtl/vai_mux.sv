import ccip_if_pkg::*;
`include "vendor_defines.vh"
module vai_mux # (parameter NUM_SUB_AFUS=8, NUM_PIPE_STAGES=0)
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

    /* forward Rx Port */

    t_if_ccip_Rx pre_afu_RxPort[NUM_SUB_AFUS-1:0];
    t_if_ccip_Rx mgr_RxPort;
    logic [63:0] offset_array [NUM_SUB_AFUS-1:0];

    vai_serve_rx #(
        .NUM_SUB_AFUS(NUM_SUB_AFUS)
    )
    inst_vai_serve_rx(
        .clk(pClk),
        .reset(SoftReset),
        .up_RxPort(up_RxPort),
        .afu_RxPort(pre_afu_RxPort),
        .mgr_RxPort(mgr_RxPort)
        );

    t_if_ccip_Tx mgr_TxPort;

    logic [63:0] afu_vai_reset;
    vai_mgr_afu #(
        .NUM_SUB_AFUS(NUM_SUB_AFUS)
    )
    inst_vai_mgr_afu(
        .pClk(pClk),
        .pClkDiv2(pClkDiv2),
        .pClkDiv4(),
        .uClk_usr(),
        .uClk_usrDiv2(),
        .pck_cp2af_softReset(SoftReset),
        .pck_cp2af_pwrState(up_PwrState),
        .pck_cp2af_error(up_Error),
        .pck_cp2af_sRx(mgr_RxPort),
        .pck_af2cp_sTx(mgr_TxPort),
        .offset_array(offset_array),
        .sub_afu_reset(afu_vai_reset)
        );

    logic afu_SoftReset_ext [NUM_SUB_AFUS:0];
    logic [1:0] afu_PwrState_ext [NUM_SUB_AFUS:0];
    logic afu_Error_ext [NUM_SUB_AFUS:0];

    always_ff @(posedge pClk)
    begin
        for (int i=0; i<NUM_SUB_AFUS; i++)
        begin
            afu_SoftReset[i] <= afu_vai_reset[i] | afu_SoftReset_ext[i];
            afu_PwrState[i] <= afu_PwrState_ext[i];
            afu_Error[i] <= afu_Error_ext[i];
        end
    end

    /* audit Tx port for each afu */

    t_if_ccip_Tx audit_TxPort[NUM_SUB_AFUS:0];
    vai_audit_tx #(
        .NUM_SUB_AFUS(NUM_SUB_AFUS)
    )
    inst_vai_audit_tx(
        .clk(pClk),
        .reset(SoftReset),
        .up_TxPort(audit_TxPort[NUM_SUB_AFUS-1:0]),
        .afu_TxPort(afu_TxPort),
        .offset_array(offset_array)
        );


    /* we utilize the legacy ccip_mux to send packet */
    assign audit_TxPort[NUM_SUB_AFUS] = mgr_TxPort;

    logic c0_almFull [NUM_SUB_AFUS:0];
    logic c1_almFull [NUM_SUB_AFUS:0];

    tx_mux #(
        .N_SUBAFUS(NUM_SUB_AFUS+1)
    )
    inst_tx_mux(
        .clk(pClk),
        .reset(SoftReset),
        .in(audit_TxPort),
        .out(up_TxPort),
        .c0_almFull(c0_almFull),
        .c1_almFull(c1_almFull)
        );


    generate
        genvar n;
        for (n=0; n<NUM_SUB_AFUS; n++)
        begin
            always_comb
            begin
                afu_RxPort[n] = pre_afu_RxPort[n]; /* c0 & c1 */
                afu_RxPort[n].c0TxAlmFull = c0_almFull[n];
                afu_RxPort[n].c1TxAlmFull = c1_almFull[n];
            end
        end
    endgenerate

endmodule
