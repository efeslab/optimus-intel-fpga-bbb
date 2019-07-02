`include "platform_if.vh"
`include "afu_json_info.vh"

module ccip_std_afu
    (
        input           logic             pClk,
        input           logic             pClkDiv2,
        input           logic             pClkDiv4,
        input           logic             uClk_usr,
        input           logic             uClk_usrDiv2,
        input           logic             pck_cp2af_softReset,
        input           logic [1:0]       pck_cp2af_pwrState,
        input           logic             pck_cp2af_error,

        // Interface structures
        input           t_if_ccip_Rx      pck_cp2af_sRx,
        output          t_if_ccip_Tx      pck_af2cp_sTx
    );

    // set clock and reset 
    logic clk, reset;

    assign clk = pClk;
    assign reset = pck_cp2af_softReset;

    logic [127:0] afu_id = `AFU_ACCEL_UUID;

    t_ccip_c0_ReqMmioHdr mmio_req_hdr;
    assign mmio_req_hdr = t_ccip_c0_ReqMmioHdr'(pck_cp2af_sRx.c0.hdr);

    // setup fifo and sRx and sTx
    //
    t_if_ccip_Rx sRx;
    t_if_ccip_Tx sTx, sTx_c1;

    // Rx
    always_comb
    begin
        sRx <= pck_cp2af_sRx;
    end

    // Tx
    always_comb
    begin
        pck_af2cp_sTx.c0  <= sTx.c0;
        pck_af2cp_sTx.c1  <= sTx_c1.c1;
    end


    // mmio read and write 

    // afu mmio writes
    t_ccip_clAddr buf_addr;
    t_ccip_clAddr bufcpy_addr;
    logic [64:0] size;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            buf_addr        <= 0;
            bufcpy_addr     <= 0;
            size            <= 0;
        end
        else
        begin
            pck_af2cp_sTx.c2.mmioRdValid <= 0;

            if (sRx.c0.mmioWrValid)
            begin
                case (mmio_req_hdr.address)
                    16'h22: buf_addr        <= t_ccip_clAddr'(sRx.c0.data);
                    16'h24: bufcpy_addr     <= t_ccip_clAddr'(sRx.c0.data);
                    16'h26: size            <= sRx.c0.data >> 6;
                endcase
            end

            // serve MMIO read requests
            if (sRx.c0.mmioRdValid)
            begin
                pck_af2cp_sTx.c2.hdr.tid <= mmio_req_hdr.tid; // copy TID

                case (mmio_req_hdr.address)
                    // AFU header
                    16'h0000: pck_af2cp_sTx.c2.data <=
                        {
                            4'b0001, // Feature type = AFU
                            8'b0,    // reserved
                            4'b0,    // afu minor revision = 0
                            7'b0,    // reserved
                            1'b1,    // end of DFH list = 1
                            24'b0,   // next DFH offset = 0
                            4'b0,    // afu major revision = 0
                            12'b0    // feature ID = 0
                        };
                    16'h0002: pck_af2cp_sTx.c2.data <= afu_id[63:0]; // afu id low
                    16'h0004: pck_af2cp_sTx.c2.data <= afu_id[127:64]; // afu id hi
                    16'h0006: pck_af2cp_sTx.c2.data <= 64'h0; // reserved
                    16'h0008: pck_af2cp_sTx.c2.data <= 64'h0; // reserved
                    default:  pck_af2cp_sTx.c2.data <= 64'h0;
                endcase
                pck_af2cp_sTx.c2.mmioRdValid <= 1;
            end
        end
    end

    logic finished;

    dma
    dma1(
        .clk(clk),
        .soft_reset(reset),

        .size(size),
        .buf_addr(buf_addr),
        .bufcpy_addr(bufcpy_addr),

        .sRx(sRx),
        .sTx(sTx),
        .sTx_c1(sTx_c1),

        .finished(finished)
    );

endmodule
