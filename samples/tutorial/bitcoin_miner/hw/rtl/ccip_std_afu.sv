`include "platform_if.vh"

import ccip_if_pkg::*;
`ifdef WITH_MUX
        `define BITCOIN_TOP_IFC_NAME `BITCOIN_WITHMUX_NAME
`else
        `define BITCOIN_TOP_IFC_NAME `BITCOIN_NOMUX_NAME
`endif
module `BITCOIN_TOP_IFC_NAME
(
  input  logic         pClk,               // 400MHz - CCI-P clock domain. Primary interface clock
  input  logic         pClkDiv2,           // 200MHz - CCI-P clock domain.
  input  logic         pClkDiv4,           // 100MHz - CCI-P clock domain.
  input  logic         uClk_usr,           // User clock domain. Refer to clock programming guide  ** Currently provides fixed 300MHz clock **
  input  logic         uClk_usrDiv2,       // User clock domain. Half the programmed frequency  ** Currently provides fixed 150MHz clock **
  input  logic         pck_cp2af_softReset,// CCI-P ACTIVE HIGH Soft Reset
  input  logic [1:0]   pck_cp2af_pwrState, // CCI-P AFU Power State
  input  logic         pck_cp2af_error,    // CCI-P Protocol Error Detected

  // Interface structures
  input  t_if_ccip_Rx  pck_cp2af_sRx,      // CCI-P Rx Port
  output t_if_ccip_Tx  pck_af2cp_sTx       // CCI-P Tx Port
);

    logic reset;
    logic resetQ;
    logic resetQQ;
    logic resetQQQ;

    always_ff @(posedge pClk)
    begin
        resetQQQ <= pck_cp2af_softReset;
        resetQQ <= resetQQQ;
        resetQ <= resetQQ;
        reset <= resetQ;
    end

    t_if_ccip_Rx sRx;
    t_if_ccip_Tx sTx;

    always_ff @(posedge pClk)
    begin
        sRx <= pck_cp2af_sRx;
        pck_af2cp_sTx <= sTx;
    end

    t_if_ccip_Rx sRx_async;
    t_if_ccip_Tx sTx_async;
    logic reset_async;

    ccip_async_shim ccip_async_shim(
        .bb_softreset(reset),
        .bb_clk(pClk),
        .bb_tx(sTx),
        .bb_rx(sRx),
        .afu_softreset(reset_async),
        .afu_clk(pClkDiv4),
        .afu_tx(sTx_async),
        .afu_rx(sRx_async)
        );

    ccip_std_afu_async bitcoin(
        .pClk(pClkDiv4),
        .pck_cp2af_softReset(reset_async),
        .pck_cp2af_sRx(sRx_async),
        .pck_af2cp_sTx(sTx_async)
        );

endmodule
