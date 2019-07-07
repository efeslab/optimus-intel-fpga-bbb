`include "platform_if.vh"
`include "csr_mgr.vh"
`include "afu_json_info.vh"

module app_afu
    (
        input  logic clk,

        // Connection toward the host.  Reset comes in here.
        cci_mpf_if.to_fiu fiu,
        app_csrs.app      csrs,

        // MPF tracks outstanding requests.  These will be true as long as
        // reads or unacknowledged writes are still in flight.
        input  logic c0NotEmpty,
        input  logic c1NotEmpty
    );

    logic reset = 1'b1;
    always @(posedge clk)
    begin
        reset <= fiu.reset;
    end

    // buffer
    t_ccip_clAddr buf_addr;
    t_ccip_clAddr bufcpy_addr;
    logic [64:0]  size;

    always_comb
    begin
        csrs.afu_id = `AFU_ACCEL_UUID;

        for (int i = 0; i < NUM_APP_CSRS; i = i + 1)
        begin
            csrs.cpu_rd_csrs[i].data = 64'(0);
        end
    end

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            buf_addr <= 0;
            bufcpy_addr <= 0;
            size <= 0;
        end
        else
        begin
            if (csrs.cpu_wr_csrs[0].en)
            begin
                buf_addr <= t_ccip_clAddr'(csrs.cpu_wr_csrs[0].data);
            end

            if (csrs.cpu_wr_csrs[1].en)
            begin
                bufcpy_addr <= t_ccip_clAddr'(csrs.cpu_wr_csrs[1].data);
            end

            if (csrs.cpu_wr_csrs[2].en)
            begin
                size  <= csrs.cpu_wr_csrs[2].data >> 6;
            end
        end
    end


    // convert mpf to cci
    t_if_ccip_Rx sRx;
    t_if_ccip_Tx sTx, sTx_c1;

    // Rx
    always_comb
    begin
        sRx.c0 = fiu.c0Rx;
        sRx.c1 = fiu.c1Rx;
        sRx.c0TxAlmFull = fiu.c0TxAlmFull;
        sRx.c1TxAlmFull = fiu.c1TxAlmFull;
    end

    // Tx
    always_comb
    begin
        fiu.c0Tx <= sTx.c0;
        fiu.c1Tx <= sTx_c1.c1;
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
