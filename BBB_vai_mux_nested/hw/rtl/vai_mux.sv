import ccip_if_pkg::*;
`include "vendor_defines.vh"
module vai_mux_15
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
    output  logic                   afu_SoftReset [14:0],
    output  logic [1:0]             afu_PwrState  [14:0],
    output  logic                   afu_Error     [14:0],
    output  t_if_ccip_Rx            afu_RxPort    [14:0],        // downstream Rx response AFU
    input   t_if_ccip_Tx            afu_TxPort    [14:0]         // downstream Tx request  AFU

);

    /* forward Rx Port */

    t_if_ccip_Rx pre_afu_RxPort[14:0];
    t_if_ccip_Rx mgr_RxPort;
    logic [63:0] offset_array [14:0];

    vai_serve_rx #(
        .NUM_SUB_AFUS(15)
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
        .NUM_SUB_AFUS(15)
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

    logic afu_SoftReset_ext [15:0];
    logic [1:0] afu_PwrState_ext [15:0];
    logic afu_Error_ext [15:0];

    always_ff @(posedge pClk)
    begin
        for (int i=0; i<15; i++)
        begin
            afu_SoftReset[i] <= afu_vai_reset[i] | afu_SoftReset_ext[i];
            afu_PwrState[i] <= afu_PwrState_ext[i];
            afu_Error[i] <= afu_Error_ext[i];
        end
    end

    /* audit Tx port for each afu */

    t_if_ccip_Tx audit_TxPort[15:0];
    vai_audit_tx #(
        .NUM_SUB_AFUS(15)
    )
    inst_vai_audit_tx(
        .clk(pClk),
        .reset(SoftReset),
        .up_TxPort(audit_TxPort[14:0]),
        .afu_TxPort(afu_TxPort),
        .offset_array(offset_array)
        );

    /* we utilize the legacy ccip_mux to send packet */
    assign audit_TxPort[15] = mgr_TxPort;

    t_if_ccip_Rx legacy_afu_RxPort[15:0];
    nested_mux_16 inst_ccip_mux_nested(
        .pClk(pClk),
        .pClkDiv2(pClkDiv2),
        .SoftReset(SoftReset),
        .up_Error(up_Error),
        .up_PwrState(up_PwrState),
        .up_RxPort(up_RxPort), /* we only use this to count packets */
        .up_TxPort(up_TxPort),
        .afu_SoftReset(afu_SoftReset_ext),
        .afu_PwrState(afu_PwrState_ext),
        .afu_Error(afu_Error_ext),
        .afu_RxPort(legacy_afu_RxPort),
        .afu_TxPort(audit_TxPort)
        );

    generate
        genvar n;
        for (n=0; n<15; n++)
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
