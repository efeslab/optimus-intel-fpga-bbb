`include "platform_if.vh"
`include "csr_mgr.vh"
`include "afu_json_info.vh"
`include "dma.vh"

module app_afu
    (
        input  logic clk,
        input  logic reset,

        // MMIO Read and write
        app_csrs.app      csrs,

        output dma_in     a_out,
        input  dma_out    a_in,

        // MPF tracks outstanding requests.  These will be true as long as
        // reads or unacknowledged writes are still in flight.
        input  logic c0NotEmpty,
        input  logic c1NotEmpty
    );

    always_comb
    begin
        csrs.afu_id = `AFU_ACCEL_UUID;

        for (int i = 0; i < NUM_APP_CSRS; i = i + 1)
        begin
            csrs.cpu_rd_csrs[i].data = 64'(0);
        end
    end

    logic [3:0] mmio_read_done;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            a_out.rd_addr <= 0;
            a_out.wr_addr <= 0;
            a_out.rd_len <= 0;
            a_out.wr_len <= 0;
        end
        else
        begin
            if (csrs.cpu_wr_csrs[0].en)
            begin
                a_out.rd_addr <= t_ccip_clAddr'(csrs.cpu_wr_csrs[0].data);
                mmio_read_done[0] <= 1'b1;
            end

            if (csrs.cpu_wr_csrs[1].en)
            begin
                a_out.wr_addr <= t_ccip_clAddr'(csrs.cpu_wr_csrs[1].data);
                mmio_read_done[1] <= 1'b1;
            end

            if (csrs.cpu_wr_csrs[2].en)
            begin
                a_out.rd_len  <= csrs.cpu_wr_csrs[2].data >> 6;
                a_out.wr_len  <= csrs.cpu_wr_csrs[2].data >> 6;
                mmio_read_done[2] <= 1'b1;
            end
        end
    end

    always_comb
    begin
        a_out.begin_copy <= (mmio_read_done == 'b111);
    end

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            a_out.wr_out <= 0;
            //a_out.rd_ready <= 0;
        end
        else
        begin
            a_out.wr_out  <= a_in.wr_ready;
            //a_out.rd_ready <= a_in.rd_out;
        end
    end

    assign a_out.wr_data = a_in.rd_data;
    assign a_out.rd_ready = 1;

endmodule
