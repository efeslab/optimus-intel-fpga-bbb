`include "platform_if.vh"
`include "csr_mgr.vh"
`include "afu_json_info.vh"
`include "dma.vh"

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

    from_afu f_afu;
    to_afu   t_afu;

    assign f_afu.rd_ready = 1;
    assign f_afu.wr_ready = 1;

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
            f_afu.rd_addr <= 0;
            f_afu.wr_addr <= 0;
            f_afu.rd_len <= 0;
            f_afu.wr_len <= 0;
        end
        else
        begin
            if (csrs.cpu_wr_csrs[0].en)
            begin
                f_afu.rd_addr <= t_ccip_clAddr'(csrs.cpu_wr_csrs[0].data);
            end

            if (csrs.cpu_wr_csrs[1].en)
            begin
                f_afu.wr_addr <= t_ccip_clAddr'(csrs.cpu_wr_csrs[1].data);
            end

            if (csrs.cpu_wr_csrs[2].en)
            begin
                f_afu.rd_len  <= csrs.cpu_wr_csrs[2].data >> 6;
                f_afu.wr_len  <= csrs.cpu_wr_csrs[2].data >> 6;
            end
        end
    end



    // Rx
    always_comb
    begin
        f_afu.sRx.c0 = fiu.c0Rx;
        f_afu.sRx.c1 = fiu.c1Rx;
        f_afu.sRx.c0TxAlmFull = fiu.c0TxAlmFull;
        f_afu.sRx.c1TxAlmFull = fiu.c1TxAlmFull;
    end

    // Tx
    always_comb
    begin
        fiu.c0Tx <= t_afu.sTx.c0;
        fiu.c1Tx <= t_afu.sTx_c1.c1;
    end

    assign f_afu.wr_data = t_afu.rd_data;



    dma
    dma1
    (
        .clk(clk),
        .soft_reset(reset),

        .afu_to_dma(f_afu),
        .dma_to_afu(t_afu),
        .begin_again(0)

    );

endmodule
