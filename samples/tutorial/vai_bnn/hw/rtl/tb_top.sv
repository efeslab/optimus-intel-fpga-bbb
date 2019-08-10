/* Module: tb
* Author: Manuele Rusci - manuele.rusci@unibo.it
* Description: BNN net16 model testbench.
*/

`include "platform_if.vh"
`include "afu_json_info.vh"
`include "csr_mgr.vh"
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

    logic [23:0] clock_cycles_to_wait;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            a_out.rd_addr <= 0;
            a_out.rd_len <= 0;
            a_out.wr_addr <= 0;
            clock_cycles_to_wait <= 1000;
        end
        else begin
            if (csrs.cpu_wr_csrs[0].en)
            begin
                a_out.rd_addr <= t_ccip_clAddr'(csrs.cpu_wr_csrs[0].data);
            end

            if (csrs.cpu_wr_csrs[1].en)
            begin
                a_out.rd_len  <= csrs.cpu_wr_csrs[1].data >> 6;
                $display("read %d", csrs.cpu_wr_csrs[1].data >> 6);
            end

            if (csrs.cpu_wr_csrs[2].en)
            begin
                a_out.wr_addr <= t_ccip_clAddr'(csrs.cpu_wr_csrs[2].data);
            end

            if (csrs.cpu_wr_csrs[3].en)
            begin
                a_out.wr_len  <= csrs.cpu_wr_csrs[3].data >> 6;
                $display("write %d", csrs.cpu_wr_csrs[3].data >> 6);
            end

            if (csrs.cpu_wr_csrs[4].en)
            begin
                clock_cycles_to_wait <= csrs.cpu_wr_csrs[4].data;
            end
        end
    end

    logic [99:0][15:0][15:0] layer_i;
    logic [15:0][15:0] layer;
    logic [3:0][7:0] layer_o;

    logic [24:0] index;
    logic [24:0] index_out;
    logic [4:0] write_index_begin;

    logic [3:0]	 write_index;
    logic [511:0] write_data;

    logic [23:0] clock_cycle;


    always_ff @(posedge clk)
    begin
        if(reset)
        begin
            index <= 0;
            layer_i <= 0;
            a_out.rd_ready <= 0;
        end
        else begin
            if (a_out.rd_ready == 0)
            begin
                a_out.rd_ready <= 1;
            end

            if (a_in.rd_out)
            begin
                a_out.rd_ready <= 0;
                layer_i[index] <= a_in.rd_data[255:0];
                layer_i[index+1] <= a_in.rd_data[511:256];
                index <= index + 2;
            end
        end
    end

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            layer <= 0;
            layer_o <= 0;
            index_out <= 0;
            clock_cycle <= 0;
            write_index <= 0;
            write_data <= 0;
        end
        else
        begin
            if (clock_cycle >= clock_cycles_to_wait)
            begin
                if (index_out < index)
                begin
                    clock_cycle <= 0;
                end

                if (index_out < 100 & index_out < index)
                begin
                    if (index_out > 0)
                    begin
                        if (write_index == 0 )
                            write_data[31:0]<= layer_o;
                        if (write_index == 1 )
                            write_data[63:32]<= layer_o;
                        if (write_index == 2 )
                            write_data[95:64]<= layer_o;
                        if (write_index == 3 )
                            write_data[127:96]<= layer_o;
                        if (write_index == 4 )
                            write_data[159:128]<= layer_o;
                        if (write_index == 5 )
                            write_data[191:160]<= layer_o;
                        if (write_index == 6 )
                            write_data[223:192]<= layer_o;
                        if (write_index == 7 )
                            write_data[255:224]<= layer_o;
                        if (write_index == 8 )
                            write_data[287:256]<= layer_o;
                        if (write_index == 9 )
                            write_data[319:288]<= layer_o;
                        if (write_index == 10 )
                            write_data[351:320]<= layer_o;
                        if (write_index == 11 )
                            write_data[383:352]<= layer_o;
                        if (write_index == 12 )
                            write_data[415:384]<= layer_o;
                        if (write_index == 13 )
                            write_data[447:416]<= layer_o;
                        if (write_index == 14 )
                            write_data[479:448]<= layer_o;
                        if (write_index == 15 )
                            write_data[511:480]<= layer_o;


                        write_index <= write_index + 1;
                    end

                    index_out <= index_out + 1;
                    layer <= layer_i[index_out];
                end

                if (write_index == 4'b1111)
                begin
                    a_out.wr_out <= 1;
                    a_out.wr_data <= write_data;
                end
                else if (index_out >= 99) begin
                    a_out.wr_out <= 1;
                    a_out.wr_data[383:0] <= write_data;
                    a_out.wr_data[511:384] <= {128{1'b1}};
                end
            end
            else begin
                clock_cycle <= clock_cycle + 1;
            end

            if (a_out.wr_out)
            begin
                a_out.wr_out <= 0;
            end
        end
    end

    bnn_top bnn_top_i(.layer_i(layer), .layer_o(layer_o));
endmodule
